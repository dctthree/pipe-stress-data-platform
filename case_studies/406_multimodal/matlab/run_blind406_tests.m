function testSummary = run_blind406_tests(configFile)
%RUN_BLIND406_TESTS Contract, regression and end-to-end tests.

root=fileparts(mfilename('fullpath'));addpath(root);
if nargin<1,configFile=fullfile(fileparts(root),'config','406_release.example.json');end
cfg=blind406.loadConfig(configFile);passed=strings(0,1);

assert(strcmp(cfg.layout.oneBasedOddPhysicalColumns,'remanence')&&strcmp(cfg.layout.oneBasedEvenPhysicalColumns,'MEM'));
passed(end+1)="frozen_physical_column_parity";
manifest=blind406.buildManifest(cfg.magneticRoot,cfg.etpRoot,cfg.cycles);
assert(height(manifest)==42&&sum(manifest.Available&manifest.Modality=="MAGNETIC")==17&&sum(manifest.Available&manifest.Modality=="ETP")==17);
assert(all(manifest.AvailableStagesInCycle(manifest.CycleID=="C3")==3));
passed(end+1)="manifest_42_expected_34_available_17_pairs";
warn=manifest(manifest.Modality=="MAGNETIC"&manifest.CycleID=="C2"&manifest.StageID=="S2",:);
assert(warn.FragmentCount==10&&contains(warn.SourceNote,"焊缝")&&~contains(warn.StageFolder,"未处理数据"));
passed(end+1)="C2_S2_operator_warning_and_10_fragments";

grid=linspace(-1,1,2001).';m=blind406.regionMasks(grid,cfg);q=blind406.profileContrast(grid,grid,m);
assert(abs(q.weightLeft-0.5279649595687331)<5e-4&&abs(q.weightRight-0.47203504043126693)<5e-4);
passed(end+1)="distance_weighted_reference_geometry";

resultFile=fullfile(cfg.outputRoot,'blind406_matlab_results.mat');
if ~isfile(resultFile),results=run_blind406_demo(configFile);else,L=load(resultFile,'results');results=L.results;end
assert(height(results.stageFeatures)==17&&numel(results.profiles)==17);
counts=sort(groupcounts(results.stageFeatures.cycle_id));
assert(isequal(counts,[3;7;7]));
passed(end+1)="unbalanced_7_7_3_preserved";

c1=results.stageFeatures(results.stageFeatures.cycle_id=="C1",:);[~,o]=sort(c1.stage_ordinal);c1=c1(o,:);
expected=double(cfg.features.cycle1RegressionF1(:));
assert(max(abs(c1.MAG_F1_DW_Q90-expected))<2e-3,'Cycle-1 F1 MATLAB/Python regression mismatch.');
passed(end+1)="cycle1_F1_frozen_regression";
expectedE1=[0;-0.01041606098233673;0.017786228811382553;-0.045149115380981444; ...
    0.017699769661187387;0.0491526124823336;0.034421304596982866];
assert(max(abs(c1.ETP_E1_CDIFF-expectedE1))<1e-2,'Cycle-1 ETP E1 regression mismatch.');
passed(end+1)="cycle1_ETP_E1_frozen_regression";

c2s2=results.stageFeatures(results.stageFeatures.cycle_id=="C2"&results.stageFeatures.stage_id=="S2",:);
assert(c2s2.mag_qc_status=="REJECT"&&~c2s2.mag_repeatability_eligible);
assert(results.evaluation.etpStatus=="QC_ONLY_NOT_STRESS_QUANTITY");
assert(results.evaluation.absoluteStressStatus=="NOT_VALIDATED_NO_CURRENT_TRUTH");
assert(~results.evaluation.f1LowStageScalePass);
assert(all(isnan(results.evaluation.decisionTable.fusion_value)));
passed(end+1)="QC_warning_ETP_downgrade_no_numeric_fusion";

assert(numel(results.figureFiles)>=13&&all(isfile(results.figureFiles)));
assert(isfile(fullfile(cfg.outputRoot,'analysis_summary.json'))&&isfile(fullfile(cfg.outputRoot,'结论说明.md')));
passed(end+1)="figures_tables_and_summary_exist";
testSummary=table(passed(:),'VariableNames',{'passed_test'});
writetable(testSummary,fullfile(cfg.outputRoot,'test_results.csv'),'Encoding','UTF-8');
fprintf('Blind406 MATLAB tests passed: %d\n',height(testSummary));disp(testSummary);
end
