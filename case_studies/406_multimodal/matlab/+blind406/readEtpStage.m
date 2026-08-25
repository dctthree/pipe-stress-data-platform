function [stage, qc] = readEtpStage(stageDir, cfg)
%READETPSTAGE Read and register one 406-pipe ETP pull.
%
%   [STAGE, QC] = blind406.readEtpStage(STAGEDIR, CFG) reads all numeric
%   CSV chunks in one pressure-stage directory. Chunks are concatenated in
%   ascending numeric-filename order. The function validates the 67 named
%   columns, tolerates the known trailing empty CSV field, constructs the 20
%   complex ETP channels Z=A*exp(1i*phase), applies a 50-row complex-plane
%   median, and detects entry/weld/exit without using the pressure-stage
%   label. It deliberately does not calculate any stress feature.
%
%   Important output fields:
%     stage.grid             - normalized coordinate, entry=-1, weld=0,
%                              exit=+1 (default 1001-by-1)
%     stage.complexProfile   - registered complex profile (grid-by-20)
%     stage.amplitudeProfile - registered block-median amplitude
%     stage.eventScore       - multichannel event score before registration
%     stage.event            - entry/weld/exit block and approximate raw row
%     qc                     - file, schema, clipping, temperature, encoder,
%                              boundary-continuity and landmark diagnostics
%
%   CFG is optional. Supported fields and defaults are listed in
%   localDefaults(). This implementation uses only base MATLAB functions.

if nargin < 2 || isempty(cfg)
    cfg = struct();
end
cfg = localApplyDefaults(cfg, localDefaults());

stageDir = string(stageDir);
if ~isscalar(stageDir) || ~isfolder(stageDir)
    error('blind406:readEtpStage:MissingDirectory', ...
        'ETP stage directory does not exist: %s', stageDir);
end

files = dir(fullfile(stageDir, '*.csv'));
if isempty(files)
    error('blind406:readEtpStage:NoCsv', ...
        'No ETP CSV chunks were found in: %s', stageDir);
end

fileNames = string({files.name})';
stems = str2double(erase(fileNames, '.csv'));
if any(~isfinite(stems))
    bad = strjoin(fileNames(~isfinite(stems)), ', ');
    error('blind406:readEtpStage:NonNumericChunkName', ...
        'ETP CSV chunk names must be numeric. Invalid: %s', bad);
end
[stems, order] = sort(stems);
files = files(order);
fileNames = fileNames(order);

expectedHeader = localExpectedHeader(cfg.SignalChannels);
amplitudeParts = cell(numel(files), 1);
phaseParts = cell(numel(files), 1);
coderParts = cell(numel(files), 1);
temperatureParts = cell(numel(files), 1);
rowsByFile = zeros(numel(files), 1);
rawColumnsByFile = zeros(numel(files), 1);
firstComplex = complex(zeros(numel(files), cfg.SignalChannels));
lastComplex = complex(zeros(numel(files), cfg.SignalChannels));

for k = 1:numel(files)
    filePath = fullfile(string(files(k).folder), string(files(k).name));
    header = localReadHeader(filePath);
    if numel(header) ~= cfg.NamedColumns
        error('blind406:readEtpStage:NamedColumnCount', ...
            '%s has %d named columns; expected %d.', ...
            filePath, numel(header), cfg.NamedColumns);
    end
    if ~isequal(header(1:(2 * cfg.SignalChannels)), expectedHeader)
        error('blind406:readEtpStage:SignalColumnOrder', ...
            'Unexpected Amplitude/Phase column order in %s.', filePath);
    end

    raw = readmatrix(filePath, 'Delimiter', ',', 'NumHeaderLines', 1);
    if isempty(raw) || size(raw, 2) < cfg.NamedColumns
        error('blind406:readEtpStage:ParsedShape', ...
            '%s parsed as %d-by-%d; at least %d columns are required.', ...
            filePath, size(raw, 1), size(raw, 2), cfg.NamedColumns);
    end
    rawColumnsByFile(k) = size(raw, 2);
    named = raw(:, 1:cfg.NamedColumns);
    if any(~isfinite(named), 'all')
        error('blind406:readEtpStage:NonFiniteNamedValue', ...
            'A non-finite value was found in the first %d named fields of %s.', ...
            cfg.NamedColumns, filePath);
    end

    amplitude = named(:, 1:2:(2 * cfg.SignalChannels));
    phase = named(:, 2:2:(2 * cfg.SignalChannels));
    coder2 = named(:, cfg.Coder2Column);
    temperature = named(:, [cfg.Temperature0Column, cfg.Temperature1Column]);
    z = amplitude .* exp(1i .* phase);

    amplitudeParts{k} = amplitude;
    phaseParts{k} = phase;
    coderParts{k} = coder2;
    temperatureParts{k} = temperature;
    rowsByFile(k) = size(named, 1);
    firstComplex(k, :) = z(1, :);
    lastComplex(k, :) = z(end, :);
end

amplitude = vertcat(amplitudeParts{:});
phase = vertcat(phaseParts{:});
coder2 = vertcat(coderParts{:});
temperature = vertcat(temperatureParts{:});
zRaw = amplitude .* exp(1i .* phase);
totalRows = size(amplitude, 1);

if totalRows < 3 * cfg.BlockRows
    error('blind406:readEtpStage:TooFewRows', ...
        'Only %d rows are available; event registration is not possible.', totalRows);
end

blockCount = floor(totalRows / cfg.BlockRows);
usedRows = blockCount * cfg.BlockRows;
[realBlock, imagBlock, amplitudeBlock] = localBlockComplexMedian( ...
    amplitude(1:usedRows, :), phase(1:usedRows, :), cfg.BlockRows);
coderBlock = reshape(median(reshape(coder2(1:usedRows), ...
    cfg.BlockRows, blockCount), 1), blockCount, 1);

eventScore = localEventScore(realBlock, imagBlock);
[entryBlock, weldBlock, exitBlock, eventDetails] = ...
    localChooseLandmarkTriplet(eventScore, cfg);
coordinate = localNormalizedCoordinate(blockCount, entryBlock, weldBlock, exitBlock);
grid = linspace(-1, 1, cfg.GridPoints)';

realProfile = localInterpolateProfile(realBlock, coordinate, grid);
imagProfile = localInterpolateProfile(imagBlock, coordinate, grid);
amplitudeProfile = localInterpolateProfile(amplitudeBlock, coordinate, grid);

rawRowCenters = ((0:(blockCount - 1))' .* cfg.BlockRows) + cfg.BlockRows / 2;
entryRawRow = (entryBlock - 1) * cfg.BlockRows + cfg.BlockRows / 2;
weldRawRow = (weldBlock - 1) * cfg.BlockRows + cfg.BlockRows / 2;
exitRawRow = (exitBlock - 1) * cfg.BlockRows + cfg.BlockRows / 2;

event = eventDetails;
event.entryBlock = entryBlock;
event.weldBlock = weldBlock;
event.exitBlock = exitBlock;
event.entryRawRowApprox = entryRawRow;
event.weldRawRowApprox = weldRawRow;
event.exitRawRowApprox = exitRawRow;
event.inPipeBlockSpan = exitBlock - entryBlock + 1;
event.inPipeRawRowSpanApprox = (exitBlock - entryBlock) * cfg.BlockRows;

% File-boundary continuity is normalized by the median POSITIVE complex
% step. These ETP streams are quantized and the median over all steps is
% exactly zero, which made the earlier diagnostic explode to roughly 1e9.
complexStep = abs(diff(zRaw, 1, 1));
allStepMedian = median(complexStep, 'all');
positiveSteps = complexStep(complexStep > 0 & isfinite(complexStep));
if isempty(positiveSteps)
    positiveStepMedian = NaN;
else
    positiveStepMedian = median(positiveSteps);
end
boundaryJumpQ90 = zeros(max(numel(files) - 1, 0), 1);
for k = 2:numel(files)
    boundaryJumpQ90(k - 1) = quantile(abs(firstComplex(k, :) - lastComplex(k - 1, :)), 0.90);
end
if isfinite(positiveStepMedian) && positiveStepMedian > 0
    boundaryJumpNormalized = boundaryJumpQ90 ./ positiveStepMedian;
else
    boundaryJumpNormalized = NaN(size(boundaryJumpQ90));
end

amplitudeMinimum = min(amplitude, [], 1);
amplitudeMaximum = max(amplitude, [], 1);
amplitudeClipFraction = mean((amplitude <= cfg.AmplitudeLowClip) | ...
    (amplitude >= cfg.AmplitudeHighClip), 'all');
phaseWrapFraction = mean(abs(phase) >= cfg.PhaseWrapThreshold, 'all');
coderDifference = diff(coder2);

chunkStepOk = numel(stems) <= 1 || all(diff(stems) == cfg.ExpectedChunkStemStep);
rowCountOk = all(rowsByFile == cfg.ExpectedRowsPerChunk);
amplitudeClipWarning = amplitudeClipFraction >= cfg.AmplitudeClipWarnFraction;
amplitudeClipFailure = amplitudeClipFraction >= cfg.AmplitudeClipFailFraction;
phaseWrapWarning = phaseWrapFraction >= cfg.PhaseWrapWarnFraction;
if isempty(boundaryJumpNormalized)
    boundaryJumpMaximum = 0;
else
    boundaryJumpMaximum = max(boundaryJumpNormalized, [], 'omitnan');
end
boundaryJumpWarning = boundaryJumpMaximum >= cfg.BoundaryJumpWarnRatio;

stage = struct();
stage.stageDir = stageDir;
stage.profileKind = "ETP complex profile; no pressure/stress feature computed";
stage.signalChannels = cfg.SignalChannels;
stage.channelIndexZeroBased = 0:(cfg.SignalChannels - 1);
stage.grid = grid;
stage.complexProfile = complex(realProfile, imagProfile);
stage.realProfile = realProfile;
stage.imagProfile = imagProfile;
stage.amplitudeProfile = amplitudeProfile;
stage.eventScore = eventScore;
stage.eventScoreRawRowCenters = rawRowCenters;
stage.blockAmplitudeMedianAcrossChannels = median(amplitudeBlock, 2);
stage.blockAmplitudeQ10AcrossChannels = quantile(amplitudeBlock, 0.10, 2);
stage.blockAmplitudeQ90AcrossChannels = quantile(amplitudeBlock, 0.90, 2);
stage.coder2BlockMedian = coderBlock;
stage.event = event;
stage.config = cfg;

qc = struct();
qc.stageDir = stageDir;
qc.csvFiles = fileNames;
qc.numericFileStems = stems;
qc.csvFileCount = numel(files);
qc.rowsByFile = rowsByFile;
qc.totalRows = totalRows;
qc.usedRows = usedRows;
qc.discardedTailRows = totalRows - usedRows;
qc.expectedRowsPerChunk = cfg.ExpectedRowsPerChunk;
qc.allChunksHaveExpectedRows = rowCountOk;
qc.expectedChunkStemStep = cfg.ExpectedChunkStemStep;
qc.numericChunkStemsAreContiguous = chunkStepOk;
qc.namedColumns = cfg.NamedColumns;
qc.rawColumnsReturnedByReadmatrix = rawColumnsByFile;
qc.trailingEmptyCsvFieldTolerated = true;
qc.headerSignalColumnsValidated = true;
qc.amplitudeMinimumByChannel = amplitudeMinimum;
qc.amplitudeMaximumByChannel = amplitudeMaximum;
qc.constantAmplitudeChannels = sum((amplitudeMaximum - amplitudeMinimum) <= eps);
qc.amplitudeClipFractionGlobal = amplitudeClipFraction;
qc.phaseWrapFractionGlobal = phaseWrapFraction;
qc.temperatureMedianC = median(temperature, 1);
qc.temperatureMinimumC = min(temperature, [], 1);
qc.temperatureMaximumC = max(temperature, [], 1);
qc.coder2Start = coder2(1);
qc.coder2End = coder2(end);
qc.coder2Minimum = min(coder2);
qc.coder2Maximum = max(coder2);
qc.coder2TotalAbsoluteTravel = sum(abs(coderDifference));
qc.coder2NonzeroStepFraction = mean(coderDifference ~= 0);
qc.complexStepMedianAll = allStepMedian;
qc.complexStepMedianPositive = positiveStepMedian;
qc.fileBoundaryComplexJumpQ90Absolute = boundaryJumpQ90;
qc.fileBoundaryComplexJumpOverPositiveStepMedian = boundaryJumpNormalized;
qc.fileBoundaryComplexJumpRatioMaximum = boundaryJumpMaximum;
qc.blockRows = cfg.BlockRows;
qc.blockCount = blockCount;
qc.event = event;
qc.warningFlags = struct( ...
    'nonstandardChunkRowCount', ~rowCountOk, ...
    'noncontiguousNumericChunkStems', ~chunkStepOk, ...
    'globalAmplitudeClip', amplitudeClipWarning, ...
    'globalPhaseWrap', phaseWrapWarning, ...
    'fileBoundaryJump', boundaryJumpWarning);
qc.failureFlags = struct( ...
    'globalAmplitudeClip', amplitudeClipFailure, ...
    'noVariableAmplitudeChannel', qc.constantAmplitudeChannels >= cfg.SignalChannels, ...
    'invalidLandmarkOrder', ~(entryBlock < weldBlock && weldBlock < exitBlock));
qc.passStructural = ~qc.failureFlags.noVariableAmplitudeChannel && ...
    ~qc.failureFlags.invalidLandmarkOrder;
qc.passGlobalSignal = qc.passStructural && ~qc.failureFlags.globalAmplitudeClip;
qc.interpretation = [ ...
    "Global clipping includes entry/weld/exit impulses; compute a separate registered " + ...
    "in-pipe target/reference clipping gate before rejecting a stage. " + ...
    "Stage feature extraction and stress inference are intentionally outside this reader."];
end


function defaults = localDefaults()
defaults = struct();
defaults.SignalChannels = 20;
defaults.NamedColumns = 67;
defaults.Coder2Column = 43;
defaults.Temperature0Column = 45;
defaults.Temperature1Column = 56;
defaults.BlockRows = 50;
defaults.GridPoints = 1001;
defaults.MaxCandidatePeaks = 45;
defaults.ExpectedRowsPerChunk = 15000;
defaults.ExpectedChunkStemStep = 15000;
defaults.AmplitudeLowClip = 1.0;
defaults.AmplitudeHighClip = 254.0;
defaults.AmplitudeClipWarnFraction = 0.01;
defaults.AmplitudeClipFailFraction = 0.05;
defaults.PhaseWrapThreshold = 3.10;
defaults.PhaseWrapWarnFraction = 0.01;
defaults.BoundaryJumpWarnRatio = 4.0;
end


function cfg = localApplyDefaults(cfg, defaults)
if ~isstruct(cfg) || ~isscalar(cfg)
    error('blind406:readEtpStage:InvalidConfig', 'CFG must be a scalar struct.');
end
names = fieldnames(defaults);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(cfg, name) || isempty(cfg.(name))
        cfg.(name) = defaults.(name);
    end
end
mustBePositive(cfg.SignalChannels);
mustBeInteger(cfg.SignalChannels);
mustBePositive(cfg.NamedColumns);
mustBeInteger(cfg.NamedColumns);
mustBePositive(cfg.BlockRows);
mustBeInteger(cfg.BlockRows);
mustBePositive(cfg.GridPoints);
mustBeInteger(cfg.GridPoints);
end


function expected = localExpectedHeader(channels)
expected = strings(1, 2 * channels);
for channel = 0:(channels - 1)
    expected(2 * channel + 1) = "Amplitude-" + channel;
    expected(2 * channel + 2) = "Phase-" + channel;
end
end


function header = localReadHeader(filePath)
fid = fopen(filePath, 'r', 'n', 'UTF-8');
if fid < 0
    error('blind406:readEtpStage:CannotOpen', 'Cannot open %s.', filePath);
end
cleanup = onCleanup(@() fclose(fid));
line = fgetl(fid);
if ~ischar(line)
    error('blind406:readEtpStage:EmptyCsv', 'CSV file is empty: %s', filePath);
end
if ~isempty(line) && double(line(1)) == 65279
    line = line(2:end);
end
header = string(strsplit(line, ',', 'CollapseDelimiters', false));
clear cleanup;
end


function [realBlock, imagBlock, amplitudeBlock] = ...
        localBlockComplexMedian(amplitude, phase, blockRows)
[rows, channels] = size(amplitude);
blocks = floor(rows / blockRows);
rows = blocks * blockRows;
amplitude = amplitude(1:rows, :);
phase = phase(1:rows, :);
realRaw = amplitude .* cos(phase);
imagRaw = amplitude .* sin(phase);
realBlock = reshape(median(reshape(realRaw, blockRows, blocks, channels), 1), ...
    blocks, channels);
imagBlock = reshape(median(reshape(imagRaw, blockRows, blocks, channels), 1), ...
    blocks, channels);
amplitudeBlock = reshape(median(reshape(amplitude, blockRows, blocks, channels), 1), ...
    blocks, channels);
end


function score = localEventScore(realBlock, imagBlock)
amplitude = hypot(realBlock, imagBlock);
phase = unwrap(angle(complex(realBlock, imagBlock)), [], 1);
features = [log(max(amplitude, 1e-6)), phase];
center = median(features, 1);
scale = 1.4826 .* median(abs(features - center), 1);
positive = scale(isfinite(scale) & scale > 1e-9);
if isempty(positive)
    floorValue = 1.0;
else
    floorValue = median(positive) * 0.1;
end
scale = max(scale, max(floorValue, 1e-6));
scaled = (features - center) ./ scale;

narrow = localGaussianSmooth(scaled, 1.5);
narrowDerivative = abs(localGradientRows(narrow));
narrowScore = quantile(narrowDerivative, 0.80, 2);

broad = localGaussianSmooth(scaled, 5.0);
broadDerivative = abs(localGradientRows(broad));
broadScore = quantile(broadDerivative, 0.80, 2);

score = localGaussianSmooth(narrowScore + 0.65 .* broadScore, 1.0);
score = score(:);
end


function smoothed = localGaussianSmooth(values, sigma)
radius = max(1, ceil(4 * sigma));
x = (-radius:radius)';
kernel = exp(-0.5 .* (x ./ sigma).^2);
kernel = kernel ./ sum(kernel);
padded = [repmat(values(1, :), radius, 1); values; ...
    repmat(values(end, :), radius, 1)];
smoothed = conv2(padded, kernel, 'valid');
end


function derivative = localGradientRows(values)
derivative = zeros(size(values), 'like', values);
if size(values, 1) == 1
    return;
elseif size(values, 1) == 2
    derivative(1, :) = values(2, :) - values(1, :);
    derivative(2, :) = derivative(1, :);
    return;
end
derivative(1, :) = values(2, :) - values(1, :);
derivative(end, :) = values(end, :) - values(end - 1, :);
derivative(2:(end - 1), :) = ...
    (values(3:end, :) - values(1:(end - 2), :)) ./ 2;
end


function peaks = localCandidatePeaks(score, cfg)
n = numel(score);
raw = find(score(2:(end - 1)) >= score(1:(end - 2)) & ...
    score(2:(end - 1)) > score(3:end)) + 1;
minimumDistance = max(10, round(0.025 * n));
[~, rank] = sort(score(raw), 'descend');
accepted = zeros(0, 1);
for k = 1:numel(rank)
    candidate = raw(rank(k));
    if isempty(accepted) || all(abs(candidate - accepted) >= minimumDistance)
        accepted(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
boundary = [round(0.015 * n) + 1; round(0.985 * n) + 1];
peaks = unique(max(2, min(n - 1, [accepted; boundary])));
[~, rank] = sort(score(peaks), 'descend');
peaks = peaks(rank(1:min(cfg.MaxCandidatePeaks, numel(rank))));
peaks = sort(peaks);
end


function [entry, weld, exitBlock, details] = ...
        localChooseLandmarkTriplet(score, cfg)
n = numel(score);
peaks = localCandidatePeaks(score, cfg);
normalizer = max(quantile(score, 0.90), 1e-9);
bestObjective = -Inf;
best = [NaN, NaN, NaN];

for entryCandidate = reshape(peaks, 1, [])
    entry0 = entryCandidate - 1;
    entryFraction = entry0 / (n - 1);
    if entryFraction < 0.02 || entryFraction > 0.40
        continue;
    end
    for weldCandidate = reshape(peaks, 1, [])
        weld0 = weldCandidate - 1;
        weldFraction = weld0 / (n - 1);
        if weldFraction < 0.28 || weldFraction > 0.74 || ...
                (weld0 - entry0) < 0.16 * n
            continue;
        end
        for exitCandidate = reshape(peaks, 1, [])
            exit0 = exitCandidate - 1;
            exitFraction = exit0 / (n - 1);
            if exitFraction < 0.62 || exitFraction > 0.995 || ...
                    (exit0 - weld0) < 0.16 * n
                continue;
            end
            leftSpan = weld0 - entry0;
            rightSpan = exit0 - weld0;
            ratio = leftSpan / rightSpan;
            if ratio < 0.45 || ratio > 2.20
                continue;
            end
            strengths = (score(entryCandidate) + score(weldCandidate) + ...
                score(exitCandidate)) / normalizer;
            symmetryPenalty = 1.30 * abs(log(ratio));
            coveragePenalty = 0.25 * abs( ...
                (entry0 + exit0) / (2 * (n - 1)) - 0.5);
            boundaryPenalty = 0.20 * (abs(entryFraction - 0.18) + ...
                abs(exitFraction - 0.90));
            objective = strengths - symmetryPenalty - coveragePenalty - boundaryPenalty;
            if objective > bestObjective
                bestObjective = objective;
                best = [entryCandidate, weldCandidate, exitCandidate];
            end
        end
    end
end

if any(~isfinite(best))
    error('blind406:readEtpStage:NoLandmarkTriplet', ...
        'No physically plausible entry/weld/exit triplet was found.');
end
entry = best(1);
weld = best(2);
exitBlock = best(3);

[~, strengthRank] = sort(score(peaks), 'descend');
rankedPeaks = peaks(strengthRank);
details = struct();
details.objective = bestObjective;
details.candidatePeakCount = numel(peaks);
details.scoreQ50 = quantile(score, 0.50);
details.scoreQ90 = quantile(score, 0.90);
details.scoreQ99 = quantile(score, 0.99);
details.entryScore = score(entry);
details.weldScore = score(weld);
details.exitScore = score(exitBlock);
details.entryPeakRank = find(rankedPeaks == entry, 1);
details.weldPeakRank = find(rankedPeaks == weld, 1);
details.exitPeakRank = find(rankedPeaks == exitBlock, 1);
details.leftRightSpanRatio = (weld - entry) / (exitBlock - weld);
end


function coordinate = localNormalizedCoordinate(n, entry, weld, exitBlock)
index = (1:n)';
coordinate = NaN(n, 1);
left = index >= entry & index <= weld;
right = index >= weld & index <= exitBlock;
coordinate(left) = (index(left) - entry) ./ (weld - entry) - 1;
coordinate(right) = (index(right) - weld) ./ (exitBlock - weld);
end


function profile = localInterpolateProfile(values, coordinate, grid)
valid = isfinite(coordinate);
profile = zeros(numel(grid), size(values, 2));
for channel = 1:size(values, 2)
    profile(:, channel) = interp1(coordinate(valid), values(valid, channel), ...
        grid, 'linear');
end
end
