function stage = readMagneticStage(stageInput, options)
%READMAGNETICSTAGE Stream one 406 magnetic stage into frozen aggregates.
%
% stage = blind406.readMagneticStage(stageFolder)
% stage = blind406.readMagneticStage(manifestRow)
% stage = blind406.readMagneticStage(..., Verbose=false)
%
% A numeric-stem CSV fragment is read, reduced and cleared before the next
% fragment is opened.  The full 1307-column raw stage is therefore never
% assembled in memory.  Any number of contiguous fragments is accepted and
% the final fragment may contain fewer rows than the other fragments.
%
% Returned aggregates are the sufficient inputs for the frozen magnetic
% features and landmark detector:
%   - remanence-X q90/median, 16 physical-column medians and 10
%     circumferential-position medians (F1/F2/F3),
%   - MEM-Z spatial standard deviation (F4),
%   - MEM/remanence Z q10/q90 and absolute-difference q90/max (events),
%   - sensor temperature, XYZ saturation fractions, Ticker and Coder.
%
% Mapping is fixed by 1-based physical-column parity: odd columns are
% remanence and even columns are MEM.  X/Y/Z remain data-field names; this
% function does not claim a pipe-coordinate interpretation.

    arguments
        stageInput
        options.Verbose (1, 1) logical = true
        options.SaturationThreshold (1, 1) double {mustBePositive} = 99.5
    end

    stageFolder = resolveStageFolder(stageInput);
    if ~isfolder(stageFolder)
        error("blind406:readMagneticStage:MissingFolder", ...
            "Magnetic stage folder does not exist: %s", stageFolder);
    end

    [fragmentFiles, fragmentNames, stems, ignoredCsvCount] = ...
        numericFragments(stageFolder);
    if isempty(fragmentFiles)
        error("blind406:readMagneticStage:NoNumericFragments", ...
            "No numeric-stem CSV fragments were found in: %s", stageFolder);
    end
    if any(diff(stems) <= 0)
        error("blind406:readMagneticStage:DuplicateStem", ...
            "Numeric CSV stems must be unique and strictly increasing in: %s", stageFolder);
    end

    expectedColumns = 1307;
    signalColumns = 1280;
    physicalColumns = 32;
    circumferentialPositions = 10;
    remanencePhysical = 1:2:physicalColumns;
    memPhysical = 2:2:physicalColumns;

    % CSV signal order has four adjacent fields (X,Y,Z,T), followed by the
    % next circumferential position, then the next physical column.
    xIndex = reshape(1:4:signalColumns, circumferentialPositions, physicalColumns).';
    yIndex = xIndex + 1;
    zIndex = xIndex + 2;
    temperatureIndex = xIndex + 3;
    axisIndex = {xIndex, yIndex, zIndex};

    nFragments = numel(fragmentFiles);
    aggregate = initializeAggregateCells(nFragments);
    qcRecords = repmat(emptyQcRecord(), nFragments, 1);
    previousMemZ = [];
    previousRemanenceZ = [];
    expectedStem = NaN;

    for fragmentIndex = 1:nFragments
        file = fragmentFiles(fragmentIndex);
        stem = stems(fragmentIndex);
        fileInfo = dir(file);
        header = inspectCsvTextContract(file);
        if ~header.ContractPass
            error("blind406:readMagneticStage:HeaderContract", ...
                ["CSV does not satisfy the 1307-field magnetic contract " ...
                 "(Coder-0..3 and Ticker-0): %s"], file);
        end
        if options.Verbose
            fprintf("[blind406] magnetic fragment %d/%d: %s\n", ...
                fragmentIndex, nFragments, file);
        end

        raw = readmatrix(file, ...
            "Delimiter", ",", ...
            "NumHeaderLines", 1, ...
            "OutputType", "double");
        if isempty(raw) || size(raw, 2) < expectedColumns
            error("blind406:readMagneticStage:NumericColumnCount", ...
                "Expected at least %d numeric columns in %s; observed %d.", ...
                expectedColumns, file, size(raw, 2));
        end
        columnsDetected = size(raw, 2);
        values = single(raw(:, 1:expectedColumns));
        clear raw
        nRows = size(values, 1);
        if nRows < 1
            error("blind406:readMagneticStage:EmptyFragment", ...
                "No numeric data rows were found in %s.", file);
        end
        finiteFraction = nnz(isfinite(values)) / numel(values);
        if finiteFraction < 1
            error("blind406:readMagneticStage:NonFiniteRequiredField", ...
                "The first 1307 fields contain non-finite values in %s (finite fraction %.9f).", ...
                file, finiteFraction);
        end

        if fragmentIndex == 1
            continuousFromPrevious = true;
            gapOrOverlapRows = 0;
            expectedAtStart = NaN;
        else
            expectedAtStart = expectedStem;
            gapOrOverlapRows = stem - expectedStem;
            continuousFromPrevious = gapOrOverlapRows == 0;
            if ~continuousFromPrevious
                % Never turn a missing/overlapping file boundary into a
                % false pipe event.  The stage remains QC-failed, while the
                % first difference in this fragment is reset to zero.
                previousMemZ = [];
                previousRemanenceZ = [];
            end
        end
        expectedStem = stem + nRows;

        aggregate.sampleIndex{fragmentIndex} = ...
            stem + (0:nRows - 1).';
        aggregate.coder{fragmentIndex} = values(:, 1281:1284);
        aggregate.ticker{fragmentIndex} = double(values(:, 1307));

        % Frozen remanence-X profile and F2 array summaries.
        remanenceX = values(:, reshape(xIndex(remanencePhysical, :), 1, []));
        aggregate.remanenceXQ90{fragmentIndex} = rowLinearQuantile(remanenceX, 0.90);
        aggregate.remanenceXMedian{fragmentIndex} = median(remanenceX, 2);
        physicalMedian = zeros(nRows, numel(remanencePhysical), "single");
        for physicalIndex = 1:numel(remanencePhysical)
            physicalMedian(:, physicalIndex) = median( ...
                values(:, xIndex(remanencePhysical(physicalIndex), :)), 2);
        end
        circumferentialMedian = zeros(nRows, circumferentialPositions, "single");
        for positionIndex = 1:circumferentialPositions
            circumferentialMedian(:, positionIndex) = median( ...
                values(:, xIndex(remanencePhysical, positionIndex)), 2);
        end
        aggregate.remanenceXPhysicalColumnMedian{fragmentIndex} = physicalMedian;
        aggregate.remanenceXCircumferentialMedian{fragmentIndex} = circumferentialMedian;
        clear remanenceX physicalMedian circumferentialMedian

        % Z aggregates for F4 and for the multi-modality event detector.
        memZ = values(:, reshape(zIndex(memPhysical, :), 1, []));
        remanenceZ = values(:, reshape(zIndex(remanencePhysical, :), 1, []));
        aggregate.memZSpatialStd{fragmentIndex} = std(memZ, 1, 2);

        [memDiffQ90, memDiffMax, previousMemZ] = ...
            differenceStatistics(memZ, previousMemZ);
        [remDiffQ90, remDiffMax, previousRemanenceZ] = ...
            differenceStatistics(remanenceZ, previousRemanenceZ);
        aggregate.eventZQ10{fragmentIndex} = [ ...
            rowLinearQuantile(memZ, 0.10), ...
            rowLinearQuantile(remanenceZ, 0.10)];
        aggregate.eventZQ90{fragmentIndex} = [ ...
            rowLinearQuantile(memZ, 0.90), ...
            rowLinearQuantile(remanenceZ, 0.90)];
        aggregate.eventZAbsDiffQ90{fragmentIndex} = [memDiffQ90, remDiffQ90];
        aggregate.eventZAbsDiffMax{fragmentIndex} = [memDiffMax, remDiffMax];
        clear memZ remanenceZ memDiffQ90 memDiffMax remDiffQ90 remDiffMax

        % Per-sample sensor-temperature summaries, modality order [MEM, remanence].
        memTemperature = values(:, reshape(temperatureIndex(memPhysical, :), 1, []));
        remTemperature = values(:, reshape(temperatureIndex(remanencePhysical, :), 1, []));
        aggregate.temperatureMean{fragmentIndex} = [ ...
            mean(memTemperature, 2), mean(remTemperature, 2)];
        aggregate.temperatureStd{fragmentIndex} = [ ...
            std(memTemperature, 1, 2), std(remTemperature, 1, 2)];
        clear memTemperature remTemperature

        % Per-sample saturation fractions, dimensions rows x modality x axis.
        saturation = zeros(nRows, 2, 3, "single");
        for axis = 1:3
            memAxis = values(:, reshape(axisIndex{axis}(memPhysical, :), 1, []));
            remAxis = values(:, reshape(axisIndex{axis}(remanencePhysical, :), 1, []));
            saturation(:, 1, axis) = mean(abs(memAxis) >= options.SaturationThreshold, 2);
            saturation(:, 2, axis) = mean(abs(remAxis) >= options.SaturationThreshold, 2);
            clear memAxis remAxis
        end
        aggregate.saturationFraction{fragmentIndex} = saturation;

        qcRecords(fragmentIndex).FragmentIndex = fragmentIndex;
        qcRecords(fragmentIndex).Name = fragmentNames(fragmentIndex);
        qcRecords(fragmentIndex).Path = file;
        qcRecords(fragmentIndex).Stem = stem;
        qcRecords(fragmentIndex).ExpectedStemFromPrevious = expectedAtStart;
        qcRecords(fragmentIndex).Rows = nRows;
        qcRecords(fragmentIndex).ColumnsDetectedByReadmatrix = columnsDetected;
        qcRecords(fragmentIndex).HeaderFieldCount = header.HeaderFieldCount;
        qcRecords(fragmentIndex).FirstDataFieldCount = header.FirstDataFieldCount;
        qcRecords(fragmentIndex).DataLineHasTrailingDelimiter = header.DataLineHasTrailingDelimiter;
        qcRecords(fragmentIndex).HeaderContractPass = header.ContractPass;
        qcRecords(fragmentIndex).First1307FiniteFraction = finiteFraction;
        qcRecords(fragmentIndex).ContinuousFromPrevious = continuousFromPrevious;
        qcRecords(fragmentIndex).GapOrOverlapRows = gapOrOverlapRows;
        qcRecords(fragmentIndex).FileBytes = fileInfo.bytes;
        clear values saturation
    end

    fragmentQC = struct2table(qcRecords, "AsArray", true);
    rowCounts = fragmentQC.Rows;
    if nFragments == 1
        nominalRows = rowCounts(1);
    else
        nominalRows = mode(rowCounts(1:end - 1));
        if ~isfinite(nominalRows) || nominalRows <= 0
            nominalRows = max(rowCounts);
        end
    end
    fragmentQC.NominalFragmentRows(:) = nominalRows;
    fragmentQC.IsShortFragment = fragmentQC.Rows < nominalRows;
    fragmentQC.IsFinalFragment = false(height(fragmentQC), 1);
    fragmentQC.IsFinalFragment(end) = true;
    fragmentQC.AllowedShortFinalFragment = ...
        fragmentQC.IsShortFragment & fragmentQC.IsFinalFragment;

    stage = struct();
    stage.schemaVersion = "blind406_magnetic_stage_aggregate_v1";
    stage.stageFolder = stageFolder;
    stage.fragmentFiles = fragmentFiles;
    stage.fragmentStems = stems;
    stage.fragmentQC = fragmentQC;
    stage.sampleIndex = vertcat(aggregate.sampleIndex{:});
    stage.remanenceX = struct( ...
        "q90", vertcat(aggregate.remanenceXQ90{:}), ...
        "median", vertcat(aggregate.remanenceXMedian{:}), ...
        "physicalColumnMedian", vertcat(aggregate.remanenceXPhysicalColumnMedian{:}), ...
        "circumferentialMedian", vertcat(aggregate.remanenceXCircumferentialMedian{:}));
    stage.memZSpatialStd = vertcat(aggregate.memZSpatialStd{:});
    stage.event = struct( ...
        "modalityOrder", ["MEM", "remanence"], ...
        "zQ10", vertcat(aggregate.eventZQ10{:}), ...
        "zQ90", vertcat(aggregate.eventZQ90{:}), ...
        "zAbsDiffQ90", vertcat(aggregate.eventZAbsDiffQ90{:}), ...
        "zAbsDiffMax", vertcat(aggregate.eventZAbsDiffMax{:}));
    stage.temperature = struct( ...
        "modalityOrder", ["MEM", "remanence"], ...
        "mean", vertcat(aggregate.temperatureMean{:}), ...
        "std", vertcat(aggregate.temperatureStd{:}));
    stage.saturationFraction = vertcat(aggregate.saturationFraction{:});
    stage.saturationModalityOrder = ["MEM", "remanence"];
    stage.saturationAxisOrder = ["X", "Y", "Z"];
    stage.coder = vertcat(aggregate.coder{:});
    stage.ticker = vertcat(aggregate.ticker{:});

    % Flat aliases are the pipeline contract consumed by
    % alignMagneticStage.  The nested fields above remain available so the
    % provenance of each aggregate is explicit to callers inspecting a
    % stage directly.
    stage.remXQ90 = stage.remanenceX.q90;
    stage.remXMedian = stage.remanenceX.median;
    stage.remColumnMedian = stage.remanenceX.physicalColumnMedian;
    stage.remCircMedian = stage.remanenceX.circumferentialMedian;
    stage.memZStd = stage.memZSpatialStd;
    stage.eventScore = magneticEventScore(stage.event);
    stage.remXSaturationFraction = mean( ...
        stage.saturationFraction(:, 2, 1), "all");
    stage.memTemperatureMedian = median(stage.temperature.mean(:, 1));
    stage.remTemperatureMedian = median(stage.temperature.mean(:, 2));
    stage.mapping = struct( ...
        "physicalColumns", physicalColumns, ...
        "circumferentialPositions", circumferentialPositions, ...
        "remanenceOneBasedPhysicalColumns", remanencePhysical, ...
        "memOneBasedPhysicalColumns", memPhysical, ...
        "fieldOrder", ["X", "Y", "Z", "T"], ...
        "pipeAxisCalibrationApplied", false);

    tickerDifference = diff(stage.ticker);
    stage.qc = struct( ...
        "fragmentCount", nFragments, ...
        "ignoredNonNumericCsvCount", ignoredCsvCount, ...
        "totalRows", numel(stage.sampleIndex), ...
        "allFragmentsContinuous", all(fragmentQC.ContinuousFromPrevious), ...
        "hasAllowedShortFinalFragment", any(fragmentQC.AllowedShortFinalFragment), ...
        "hasNonFinalShortFragment", any(fragmentQC.IsShortFragment & ~fragmentQC.IsFinalFragment), ...
        "allHeadersPass", all(fragmentQC.HeaderContractPass), ...
        "allRequiredValuesFinite", all(fragmentQC.First1307FiniteFraction == 1), ...
        "sampleIndexExactlyContinuous", all(diff(stage.sampleIndex) == 1), ...
        "tickerNonpositiveDifferenceFraction", ...
            safeFraction(tickerDifference <= 0), ...
        "saturationThreshold", options.SaturationThreshold);
end


function stageFolder = resolveStageFolder(stageInput)
    if istable(stageInput)
        if height(stageInput) ~= 1 || ~ismember("StageFolder", string(stageInput.Properties.VariableNames))
            error("blind406:readMagneticStage:ManifestRow", ...
                "A manifest input must be a one-row table containing StageFolder.");
        end
        if ismember("Modality", string(stageInput.Properties.VariableNames)) && ...
                string(stageInput.Modality(1)) ~= "MAGNETIC"
            error("blind406:readMagneticStage:WrongModality", ...
                "readMagneticStage accepts only a MAGNETIC manifest row.");
        end
        stageFolder = string(stageInput.StageFolder(1));
    else
        stageFolder = string(stageInput);
    end
    if ~isscalar(stageFolder) || ismissing(stageFolder) || strlength(stageFolder) == 0
        error("blind406:readMagneticStage:StageFolder", ...
            "stageInput must resolve to one nonempty folder path.");
    end
end


function [files, names, stems, ignoredCount] = numericFragments(folder)
    listing = dir(fullfile(folder, "*.csv"));
    files = strings(0, 1);
    names = strings(0, 1);
    stems = zeros(0, 1);
    ignoredCount = 0;
    for index = 1:numel(listing)
        [~, stemText] = fileparts(listing(index).name);
        if isempty(regexp(stemText, "^\d+$", "once")) %#ok<RGXP1>
            ignoredCount = ignoredCount + 1;
            continue
        end
        stem = str2double(stemText);
        if ~isfinite(stem) || stem < 0 || stem ~= fix(stem)
            ignoredCount = ignoredCount + 1;
            continue
        end
        names(end + 1, 1) = string(listing(index).name); %#ok<AGROW>
        files(end + 1, 1) = string(fullfile(listing(index).folder, listing(index).name)); %#ok<AGROW>
        stems(end + 1, 1) = stem; %#ok<AGROW>
    end
    [stems, order] = sort(stems, "ascend");
    files = files(order);
    names = names(order);
end


function header = inspectCsvTextContract(file)
    fileId = fopen(file, "rt", "n", "UTF-8");
    if fileId < 0
        error("blind406:readMagneticStage:OpenFailed", "Cannot open %s.", file);
    end
    cleaner = onCleanup(@() fclose(fileId)); %#ok<NASGU>
    headerLine = fgetl(fileId);
    firstDataLine = fgetl(fileId);
    if ~ischar(headerLine) || ~ischar(firstDataLine)
        error("blind406:readMagneticStage:CsvPreamble", ...
            "CSV needs one header and at least one data row: %s", file);
    end
    headerFields = string(strsplit(headerLine, ",", "CollapseDelimiters", false));
    dataFieldCount = count(string(firstDataLine), ",") + 1;
    hasTrailing = endsWith(strtrim(string(firstDataLine)), ",");
    requiredNamesPass = numel(headerFields) >= 1307 && ...
        headerFields(1281) == "Coder-0" && ...
        headerFields(1284) == "Coder-3" && ...
        headerFields(1307) == "Ticker-0";
    header = struct( ...
        "HeaderFieldCount", numel(headerFields), ...
        "FirstDataFieldCount", double(dataFieldCount), ...
        "DataLineHasTrailingDelimiter", hasTrailing, ...
        "ContractPass", requiredNamesPass && dataFieldCount >= 1307);
end


function aggregate = initializeAggregateCells(n)
    names = [ ...
        "sampleIndex", "coder", "ticker", ...
        "remanenceXQ90", "remanenceXMedian", ...
        "remanenceXPhysicalColumnMedian", ...
        "remanenceXCircumferentialMedian", ...
        "memZSpatialStd", ...
        "eventZQ10", "eventZQ90", ...
        "eventZAbsDiffQ90", "eventZAbsDiffMax", ...
        "temperatureMean", "temperatureStd", ...
        "saturationFraction"];
    aggregate = struct();
    for index = 1:numel(names)
        aggregate.(names(index)) = cell(n, 1);
    end
end


function record = emptyQcRecord()
    record = struct( ...
        "FragmentIndex", NaN, ...
        "Name", "", ...
        "Path", "", ...
        "Stem", NaN, ...
        "ExpectedStemFromPrevious", NaN, ...
        "Rows", NaN, ...
        "ColumnsDetectedByReadmatrix", NaN, ...
        "HeaderFieldCount", NaN, ...
        "FirstDataFieldCount", NaN, ...
        "DataLineHasTrailingDelimiter", false, ...
        "HeaderContractPass", false, ...
        "First1307FiniteFraction", NaN, ...
        "ContinuousFromPrevious", false, ...
        "GapOrOverlapRows", NaN, ...
        "FileBytes", NaN);
end


function q = rowLinearQuantile(values, probability)
% Match NumPy's default linear interpolation for finite row data.
    sorted = sort(values, 2, "ascend");
    count = size(sorted, 2);
    position = 1 + (count - 1) * probability;
    lower = floor(position);
    upper = ceil(position);
    fraction = single(position - lower);
    if lower == upper
        q = sorted(:, lower);
    else
        q = (1 - fraction) .* sorted(:, lower) + fraction .* sorted(:, upper);
    end
end


function [q90, maximum, previousLast] = differenceStatistics(values, previousLast)
    difference = zeros(size(values), "single");
    if ~isempty(previousLast)
        difference(1, :) = abs(values(1, :) - previousLast);
    end
    if size(values, 1) > 1
        difference(2:end, :) = abs(diff(values, 1, 1));
    end
    q90 = rowLinearQuantile(difference, 0.90);
    maximum = max(difference, [], 2);
    previousLast = values(end, :);
end


function fraction = safeFraction(condition)
    if isempty(condition)
        fraction = NaN;
    else
        fraction = nnz(condition) / numel(condition);
    end
end


function score = magneticEventScore(event)
% Frozen event score used by the previous blind-cycle implementation.
    q10 = double(event.zQ10);
    q90 = double(event.zQ90);
    q90Difference = double(event.zAbsDiffQ90);
    maximumDifference = double(event.zAbsDiffMax);
    score = zeros(size(q10, 1), 1);
    for modality = 1:2
        span = q90(:, modality) - q10(:, modality);
        spanHighPass = span - centeredMovingAverage(span, 1201);
        score = score + ...
            min(max(robustZ(log1p(q90Difference(:, modality))), 0), 15) + ...
            0.35 .* min(max(robustZ(log1p(maximumDifference(:, modality))), 0), 15) + ...
            0.45 .* min(max(robustZ(abs(spanHighPass)), 0), 15);
    end
    score = centeredMovingAverage(score, 41);
end


function result = centeredMovingAverage(values, width)
% Match numpy.convolve(values, ones(width)/width, mode="same").
    width = max(1, fix(width));
    values = double(values(:));
    if width == 1
        result = values;
    else
        result = conv(values, ones(width, 1) ./ width, "same");
    end
end


function result = robustZ(values)
    values = double(values(:));
    center = median(values, "omitmissing");
    scale = 1.4826 * median(abs(values - center), "omitmissing");
    if ~isfinite(scale) || scale < 1e-12
        scale = std(values, 0, "omitmissing");
    end
    if ~isfinite(scale) || scale < 1e-12
        result = zeros(size(values));
    else
        result = (values - center) ./ scale;
    end
end
