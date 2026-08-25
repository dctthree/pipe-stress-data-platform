function export_simple_feature_profiles(configFile)
%EXPORT_SIMPLE_FEATURE_PROFILES Export the verified profile cache to v7 MAT.
% The export contains no strain/stress truth.  It only exposes the already
% registered profiles so simple-feature experiments can be reproduced in
% Python without reading the large raw CSV packets again.

root = fileparts(mfilename('fullpath'));
addpath(root);
if nargin < 1 || strlength(string(configFile)) == 0
    configFile = fullfile(fileparts(root),'config','406_release.example.json');
end
cfg = blind406.loadConfig(configFile);
cacheFile = char(cfg.cacheFile);
outDir = fullfile(fileparts(char(cfg.outputRoot)),'406_simple_features');
if ~isfolder(outDir), mkdir(outDir); end
assert(isfile(cacheFile),'Blind406:MissingCache', ...
    'Run run_blind406_demo first; profile cache not found: %s',cacheFile);

s = load(cacheFile,'profiles','stageQC','cacheMeta');
profiles = s.profiles;
n = numel(profiles);
magGrid = profiles(1).mag.grid(:);
etpGrid = profiles(1).etpGrid(:);
nMag = numel(magGrid); nEtp = numel(etpGrid);

remXQ90 = nan(nMag,n);
remXMedian = nan(nMag,n);
memZStd = nan(nMag,n);
remColumnMedian = nan(nMag,size(profiles(1).mag.remColumnMedian,2),n);
remCircMedian = nan(nMag,size(profiles(1).mag.remCircMedian,2),n);
etpComplex = complex(nan(nEtp,size(profiles(1).etpComplex,2),n));
etpAmplitude = nan(nEtp,size(profiles(1).etpAmplitude,2),n);
cycle_id = strings(n,1); stage_id = strings(n,1); stage_ordinal = nan(n,1);
mag_qc_status = strings(n,1); etp_qc_status = strings(n,1);
mag_repeatability_eligible = false(n,1); mag_feature_eligible = false(n,1);
mem_temperature_C = nan(n,1); remanence_temperature_C = nan(n,1);
etp_temperature0_C = nan(n,1); etp_temperature1_C = nan(n,1);

for i = 1:n
    cycle_id(i) = string(profiles(i).cycle_id);
    stage_id(i) = string(profiles(i).stage_id);
    stage_ordinal(i) = double(profiles(i).stage_ordinal);
    mag_qc_status(i) = string(profiles(i).magQC.status);
    etp_qc_status(i) = string(profiles(i).etpQC.status);
    mag_repeatability_eligible(i) = logical(profiles(i).mag.repeatabilityEligible);
    mag_feature_eligible(i) = logical(profiles(i).mag.featureEligible);
    mem_temperature_C(i) = double(profiles(i).magQC.mem_temperature_C);
    remanence_temperature_C(i) = double(profiles(i).magQC.remanence_temperature_C);
    etp_temperature0_C(i) = double(profiles(i).etpQC.temperature0_C);
    etp_temperature1_C(i) = double(profiles(i).etpQC.temperature1_C);
    remXQ90(:,i) = profiles(i).mag.remXQ90;
    remXMedian(:,i) = profiles(i).mag.remXMedian;
    memZStd(:,i) = profiles(i).mag.memZStd;
    remColumnMedian(:,:,i) = profiles(i).mag.remColumnMedian;
    remCircMedian(:,:,i) = profiles(i).mag.remCircMedian;
    etpComplex(:,:,i) = profiles(i).etpComplex;
    etpAmplitude(:,:,i) = profiles(i).etpAmplitude;
end

manifest = table(cycle_id,stage_id,stage_ordinal,mag_qc_status,etp_qc_status, ...
    mag_feature_eligible,mag_repeatability_eligible,mem_temperature_C, ...
    remanence_temperature_C,etp_temperature0_C,etp_temperature1_C);
writetable(manifest,fullfile(outDir,'simple_profile_manifest.csv'));

processing_note = [ ...
    "Profiles are copied from the fingerprinted runtime profile cache; " + ...
    "three-landmark registration and source QC were not recomputed; no current truth is exported."];
cacheMeta = s.cacheMeta;
save(fullfile(outDir,'simple_profiles_v7.mat'),'magGrid','etpGrid','remXQ90', ...
    'remXMedian','memZStd','remColumnMedian','remCircMedian','etpComplex', ...
    'etpAmplitude','manifest','cacheMeta','processing_note','-v7');
fprintf('Exported %d packets: %s\n',n,fullfile(outDir,'simple_profiles_v7.mat'));
end
