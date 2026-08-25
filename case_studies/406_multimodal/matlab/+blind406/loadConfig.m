function cfg = loadConfig(configFile)
%LOADCONFIG Read and validate the frozen 406 blind-test configuration.

configFile = char(configFile);
assert(isfile(configFile), 'Blind406:MissingConfig', 'Missing config: %s', configFile);
cfg = jsondecode(fileread(configFile));
root = string(fileparts(fileparts(configFile)));
cfg.projectRoot = root;
cfg.configFile = string(configFile);
cfg.magneticRoot = resolvePath(root, string(cfg.magneticRoot));
cfg.etpRoot = resolvePath(root, string(cfg.etpRoot));
cfg.outputRoot = resolvePath(root, string(cfg.outputRoot));
cfg.cacheFile = resolvePath(root, string(cfg.cacheFile));

assert(cfg.layout.physicalColumns == 32 && cfg.layout.circumferentialPositions == 10, ...
    'Blind406:Layout', 'Frozen layout must remain 32 physical columns x 10 positions.');
assert(strcmp(cfg.layout.oneBasedOddPhysicalColumns, 'remanence') && ...
    strcmp(cfg.layout.oneBasedEvenPhysicalColumns, 'MEM'), ...
    'Blind406:Parity', 'Frozen parity is odd physical columns=remanence, even=MEM.');
assert(numel(cfg.cycles) == 3 && numel(cfg.stages) == 7, ...
    'Blind406:Design', 'Expected three cycle definitions and seven possible stages.');
assert(abs(cfg.spatial.weld) < eps && cfg.spatial.magneticGridPoints == 2001 && ...
    cfg.spatial.etpGridPoints == 1001, 'Blind406:Spatial', ...
    'Frozen weld coordinate/grid sizes changed.');
assert(contains(string(cfg.features.etpPhaseUnit), "assumption"), ...
    'Blind406:PhaseUnit', 'ETP phase unit must remain an explicit assumption.');
end

function path = resolvePath(root, configured)
if strlength(configured) == 0
    path = "";
elseif ~isempty(regexp(char(configured), '^[A-Za-z]:[\\/]', 'once')) || startsWith(configured, "\\\\")
    path = configured;
else
    path = string(fullfile(root, configured));
end
end
