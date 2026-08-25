function data = loadStressDataset(indexPath, scanId)
%LOADSTRESSDATASET Read the versioned stress dataset without hard-coded paths.
%
% data = loadStressDataset(indexPath)
% data = loadStressDataset(indexPath, scanId)
%
% The first form loads catalog tables and the AI feature matrix. The second
% form additionally loads one standardized pull signal by scan_id.

arguments
    indexPath (1,1) string
    scanId (1,1) string = ""
end

if ~isfile(indexPath)
    error('StressData:IndexMissing', '数据集索引不存在：%s', indexPath);
end
rootDir = fileparts(indexPath);
index = jsondecode(fileread(indexPath));

data = struct();
data.index = index;
data.rootDir = string(rootDir);
data.scans = parquetread(resolveTable(index, rootDir, 'scans'));
data.qc = parquetread(resolveTable(index, rootDir, 'qc_checks'));
data.events = parquetread(resolveTable(index, rootDir, 'events'));
data.channels = parquetread(resolveTable(index, rootDir, 'channels'));
data.probes = parquetread(resolveTable(index, rootDir, 'probes'));
data.strainFiles = parquetread(resolveTable(index, rootDir, 'strain_files'));
data.channelFeatures = parquetread(resolveTable(index, rootDir, 'channel_features'));
data.mlFeatures = parquetread(resolveTable(index, rootDir, 'ml_feature_matrix'));
data.featureDefinitions = parquetread(resolveTable(index, rootDir, 'feature_definitions'));
data.signal = table();

if strlength(scanId) > 0
    matches = string(data.scans.scan_id) == scanId;
    if nnz(matches) ~= 1
        error('StressData:ScanId', 'scan_id应唯一匹配，实际匹配%d条：%s', nnz(matches), scanId);
    end
    relativePath = string(data.scans.silver_signal_path(matches));
    signalPath = fullfile(rootDir, replace(relativePath, '/', filesep));
    if ~isfile(signalPath)
        error('StressData:SignalMissing', '标准信号不存在：%s', signalPath);
    end
    data.signal = parquetread(signalPath);
end
end

function path = resolveTable(index, rootDir, tableName)
if ~isfield(index.tables, tableName)
    error('StressData:TableMissing', '索引未声明表：%s', tableName);
end
entry = index.tables.(tableName);
path = fullfile(rootDir, replace(string(entry.parquet), '/', filesep));
if ~isfile(path)
    error('StressData:TableFileMissing', '表文件不存在：%s', path);
end
end
