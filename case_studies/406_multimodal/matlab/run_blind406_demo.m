function results = run_blind406_demo(configFile)
%RUN_BLIND406_DEMO End-to-end 406 three-cycle MEM/remanence/ETP audit.
%   Default output is relative/QC evidence only. No current strain/stress
%   truth is read and no absolute MPa value is produced.

root=fileparts(mfilename('fullpath'));addpath(root);
if nargin<1||strlength(string(configFile))==0
    configFile=fullfile(fileparts(root),'config','406_release.example.json');
end
cfg=blind406.loadConfig(configFile);rng(cfg.randomSeed,'twister');
if ~isfolder(cfg.outputRoot),mkdir(cfg.outputRoot);end

fprintf('[1/7] Building fixed 3-cycle x 7-stage x 2-modality manifest...\n');
manifest=blind406.buildManifest(cfg.magneticRoot,cfg.etpRoot,cfg.cycles);
flatManifest=flattenManifest(manifest);
writetable(flatManifest,fullfile(cfg.outputRoot,'source_stage_manifest.csv'),'Encoding','UTF-8');

fprintf('[2/7] Reading/cache-validating and registering 17 matched pull packets...\n');
[profiles,stageQC,fragmentQC,cacheMeta]=blind406.prepareProfiles(manifest,cfg);
writetable(stageQC.magnetic,fullfile(cfg.outputRoot,'magnetic_stage_qc.csv'),'Encoding','UTF-8');
writetable(stageQC.etp,fullfile(cfg.outputRoot,'etp_stage_qc.csv'),'Encoding','UTF-8');
writetable(fragmentQC.magnetic,fullfile(cfg.outputRoot,'magnetic_fragment_qc.csv'),'Encoding','UTF-8');
writetable(fragmentQC.etp,fullfile(cfg.outputRoot,'etp_fragment_qc.csv'),'Encoding','UTF-8');

fprintf('[3/7] Extracting frozen F1/F2/F3/F4/F5 and ETP E1-E6/E-direct...\n');
[stageFeatures,f2Physical,f2Circ,windowFeatures,etpChannels,shapeQC]= ...
    blind406.extractFeatures(profiles,cfg);
writetable(stageFeatures,fullfile(cfg.outputRoot,'stage_features.csv'),'Encoding','UTF-8');
writetable(f2Physical,fullfile(cfg.outputRoot,'F2_physical_column_features.csv'),'Encoding','UTF-8');
writetable(f2Circ,fullfile(cfg.outputRoot,'F2_circumferential_features.csv'),'Encoding','UTF-8');
writetable(windowFeatures,fullfile(cfg.outputRoot,'window_sensitivity_27.csv'),'Encoding','UTF-8');
writetable(etpChannels,fullfile(cfg.outputRoot,'etp_channel_features.csv'),'Encoding','UTF-8');
writetable(shapeQC,fullfile(cfg.outputRoot,'F3_shape_qc.csv'),'Encoding','UTF-8');

fprintf('[4/7] Evaluating complete, partial and QC-filtered repeatability separately...\n');
evaluation=blind406.evaluateRepeatability(stageFeatures,f2Physical,f2Circ, ...
    windowFeatures,etpChannels,shapeQC,cfg);
names={'cycleMetrics','crossCycleMetrics','stageRepeatability','windowMetrics', ...
    'f2Metrics','etpGates','featureStatus','decisionTable'};
files={'cycle_metrics.csv','cross_cycle_metrics.csv','stage_repeatability.csv', ...
    'window_metrics.csv','F2_repeat_metrics.csv','etp_gates.csv','feature_status.csv', ...
    'multimodal_decision_table.csv'};
for i=1:numel(names)
    writetable(evaluation.(names{i}),fullfile(cfg.outputRoot,files{i}),'Encoding','UTF-8');
end

fprintf('[5/7] Generating engineering evaluation figures...\n');
figureFiles=blind406.generateFigures(profiles,stageFeatures,f2Physical,f2Circ, ...
    windowFeatures,evaluation,cfg);

fprintf('[6/7] Writing machine-readable summary and Chinese conclusion report...\n');
summary=blind406.writeSummary(manifest,stageQC,stageFeatures,evaluation,figureFiles,cacheMeta,cfg);

results=struct('config',cfg,'manifest',manifest,'profiles',profiles,'stageQC',stageQC, ...
    'fragmentQC',fragmentQC,'stageFeatures',stageFeatures,'f2Physical',f2Physical, ...
    'f2Circ',f2Circ,'windowFeatures',windowFeatures,'etpChannels',etpChannels, ...
    'shapeQC',shapeQC,'evaluation',evaluation,'figureFiles',figureFiles,'summary',summary);
save(fullfile(cfg.outputRoot,'blind406_matlab_results.mat'),'results','-v7.3');
fprintf('[7/7] Complete: %s\n',cfg.outputRoot);
end

function T=flattenManifest(M)
T=M(:,{'Modality','CycleID','CycleOrdinal','StageID','StageOrdinal','StageName', ...
    'StageFolder','SourceNote','FragmentCount','Available','AvailableStagesInCycle', ...
    'CycleComplete','CyclePartial'});
fragmentNames=strings(height(M),1);fragmentStems=strings(height(M),1);
for i=1:height(M)
    fragmentNames(i)=strjoin(M.FragmentNames{i},";");
    fragmentStems(i)=strjoin(string(M.FragmentStems{i}),";");
end
T.FragmentNames=fragmentNames;T.FragmentStems=fragmentStems;
end
