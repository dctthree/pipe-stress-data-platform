function manifest = buildManifest(dataRoot, etpRoot, cycles)
%BUILDMANIFEST Build the frozen 406 blind-test cycle/stage manifest.
%
% manifest = blind406.buildManifest(dataRoot, etpRoot, cycles)
%
% Only the three cycle/modality folders declared by the release config are
% inspected. In particular, no unregistered source tree is traversed. One
% row is returned for every expected modality/cycle/stage combination,
% including missing stages. This makes a partial cycle explicit instead of
% silently dropping it.

    if nargin < 1 || strlength(string(dataRoot)) == 0
        projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        dataRoot = fullfile(projectRoot, "raw", "blind");
    end
    if nargin < 2 || strlength(string(etpRoot)) == 0
        projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        etpRoot = fullfile(projectRoot, "raw", "blind");
    end
    if nargin < 3 || isempty(cycles)
        cycles = struct( ...
            "id", {"C1", "C2", "C3"}, ...
            "magneticFolder", {"C1/magnetic", "C2/magnetic", "C3/magnetic"}, ...
            "etpFolder", {"C1/etp", "C2/etp", "C3/etp"});
    end

    dataRoot = string(dataRoot);
    etpRoot = string(etpRoot);
    if ~isscalar(dataRoot) || ~isscalar(etpRoot)
        error("blind406:buildManifest:ScalarRootRequired", ...
            "dataRoot and etpRoot must each be one path.");
    end
    if numel(cycles) ~= 3
        error("blind406:buildManifest:CycleContract", ...
            "Exactly three configured cycles are required.");
    end
    if ~isfolder(dataRoot)
        error("blind406:buildManifest:MissingMagneticRoot", ...
            "Magnetic data root does not exist: %s", dataRoot);
    end
    if ~isfolder(etpRoot)
        error("blind406:buildManifest:MissingEtpRoot", ...
            "ETP data root does not exist: %s", etpRoot);
    end

    stageNames = [ ...
        "零压力测试"; ...
        "第一次加压"; ...
        "第二次加压"; ...
        "第三次加压"; ...
        "第四次加压"; ...
        "第五次加压"; ...
        "第六次加压"];
    stageIds = "S" + string((0:6).');

    magneticFolders = strings(3,1); etpFolders = strings(3,1); cycleIds = strings(3,1);
    for cycleIndex = 1:3
        cycleIds(cycleIndex) = string(cycles(cycleIndex).id);
        magneticFolders(cycleIndex) = string(cycles(cycleIndex).magneticFolder);
        etpFolders(cycleIndex) = string(cycles(cycleIndex).etpFolder);
    end
    if ~isequal(cycleIds,["C1";"C2";"C3"])
        error("blind406:buildManifest:CycleIDs", ...
            "Configured cycle IDs must be C1, C2 and C3 in order.");
    end

    definitions = struct( ...
        "modality", {"MAGNETIC", "ETP"}, ...
        "modalityOrder", {1, 2}, ...
        "root", {dataRoot, etpRoot}, ...
        "cycleNames", {magneticFolders, etpFolders});

    emptyRecord = struct( ...
        "Modality", "", ...
        "ModalityOrder", NaN, ...
        "CycleID", "", ...
        "CycleOrdinal", NaN, ...
        "CycleName", "", ...
        "StageID", "", ...
        "StageOrdinal", NaN, ...
        "StageName", "", ...
        "SourceRoot", "", ...
        "CycleFolder", "", ...
        "StageFolder", "", ...
        "CycleFolderExists", false, ...
        "StageFolderExists", false, ...
        "ReadmePath", "", ...
        "SourceNote", "", ...
        "FragmentCount", 0, ...
        "FragmentNames", {strings(0, 1)}, ...
        "FragmentFiles", {strings(0, 1)}, ...
        "FragmentStems", {zeros(0, 1)}, ...
        "StemOrderStrictlyIncreasing", true, ...
        "IgnoredNonNumericCsvCount", 0, ...
        "HasNumericFragments", false, ...
        "Available", false, ...
        "AvailableStagesInCycle", 0, ...
        "CycleComplete", false, ...
        "CyclePartial", false);
    records = repmat(emptyRecord, 2 * 3 * numel(stageNames), 1);

    row = 0;
    for modalityIndex = 1:numel(definitions)
        definition = definitions(modalityIndex);
        for cycleIndex = 1:3
            cycleName = definition.cycleNames(cycleIndex);
            cycleFolder = fullfile(definition.root, cycleName);
            cycleExists = isfolder(cycleFolder);
            for stageIndex = 1:numel(stageNames)
                row = row + 1;
                stageFolder = fullfile(cycleFolder, stageNames(stageIndex));
                stageExists = cycleExists && isfolder(stageFolder);
                fragmentNames = strings(0, 1);
                fragmentFiles = strings(0, 1);
                stems = zeros(0, 1);
                ignoredCount = 0;
                readmePath = fullfile(stageFolder, "Readme.txt");
                sourceNote = "";

                if stageExists
                    if isfile(readmePath)
                        sourceNote = strtrim(string(fileread(readmePath)));
                    end
                    listing = dir(fullfile(stageFolder, "*.csv"));
                    for fileIndex = 1:numel(listing)
                        [~, stemText] = fileparts(listing(fileIndex).name);
                        if ~isempty(regexp(stemText, "^\d+$", "once")) %#ok<RGXP1>
                            stemValue = str2double(stemText);
                            if isfinite(stemValue) && stemValue >= 0 && stemValue == fix(stemValue)
                                stems(end + 1, 1) = stemValue; %#ok<AGROW>
                                fragmentNames(end + 1, 1) = string(listing(fileIndex).name); %#ok<AGROW>
                                fragmentFiles(end + 1, 1) = string(fullfile(listing(fileIndex).folder, listing(fileIndex).name)); %#ok<AGROW>
                            else
                                ignoredCount = ignoredCount + 1;
                            end
                        else
                            ignoredCount = ignoredCount + 1;
                        end
                    end
                    if ~isempty(stems)
                        [stems, order] = sort(stems, "ascend");
                        fragmentNames = fragmentNames(order);
                        fragmentFiles = fragmentFiles(order);
                    end
                end

                records(row).Modality = string(definition.modality);
                records(row).ModalityOrder = definition.modalityOrder;
                records(row).CycleID = cycleIds(cycleIndex);
                records(row).CycleOrdinal = cycleIndex;
                records(row).CycleName = cycleName;
                records(row).StageID = stageIds(stageIndex);
                records(row).StageOrdinal = stageIndex - 1;
                records(row).StageName = stageNames(stageIndex);
                records(row).SourceRoot = definition.root;
                records(row).CycleFolder = cycleFolder;
                records(row).StageFolder = stageFolder;
                records(row).CycleFolderExists = cycleExists;
                records(row).StageFolderExists = stageExists;
                records(row).ReadmePath = string(readmePath);
                records(row).SourceNote = sourceNote;
                records(row).FragmentCount = numel(stems);
                records(row).FragmentNames = fragmentNames;
                records(row).FragmentFiles = fragmentFiles;
                records(row).FragmentStems = stems;
                records(row).StemOrderStrictlyIncreasing = isempty(stems) || all(diff(stems) > 0);
                records(row).IgnoredNonNumericCsvCount = ignoredCount;
                records(row).HasNumericFragments = ~isempty(stems);
                records(row).Available = stageExists && ~isempty(stems);
            end
        end
    end

    manifest = struct2table(records, "AsArray", true);
    for modalityIndex = 1:2
        for cycleIndex = 1:3
            inCycle = manifest.ModalityOrder == modalityIndex & ...
                manifest.CycleOrdinal == cycleIndex;
            availableStages = sum(manifest.Available(inCycle));
            manifest.AvailableStagesInCycle(inCycle) = availableStages;
            manifest.CycleComplete(inCycle) = availableStages == numel(stageNames);
            manifest.CyclePartial(inCycle) = availableStages > 0 && ...
                availableStages < numel(stageNames);
        end
    end
    manifest = sortrows(manifest, ...
        ["ModalityOrder", "CycleOrdinal", "StageOrdinal"]);
    manifest.Properties.Description = ...
        "Frozen 406 blind-test manifest; missing stages retained; 未处理数据 excluded.";
    manifest.Properties.UserData = struct( ...
        "schemaVersion", "blind406_manifest_v2_canonical_release_paths", ...
        "stageNames", stageNames, ...
        "excludedMagneticTrees", "未处理数据", ...
        "generatedAt", datetime("now", "TimeZone", "local"));
end
