function summary = writeSummary(manifest, stageQC, F, evaluation, figureFiles, cacheMeta, cfg) %#ok<INUSD>
%WRITESUMMARY Persist the evidence boundaries and main numerical findings.

summary=struct();
summary.system=string(cfg.systemName);summary.version=string(cfg.version);
summary.generated_at=string(datetime('now','TimeZone','local'));
summary.current_strain_or_stress_truth_used=false;
summary.available_stage_packets=height(F);
summary.cycle_stage_counts=struct('C1',sum(F.cycle_id=="C1"),'C2',sum(F.cycle_id=="C2"),'C3',sum(F.cycle_id=="C3"));
summary.repeat_design="C1/C2=S0-S6; C3=S0-S2 only; missing S3-S6 remain missing";
summary.public_raw_identity="release/raw_file_manifest.csv per-file SHA-256";
summary.frozen_path_layout="canonical_release_paths_mechanical_provenance_migration_only";
summary.magnetic_feature_status=evaluation.f1Status;
summary.mem_feature_status=evaluation.f4Status;
summary.etp_status=evaluation.etpStatus;
summary.formal_engineering_repeatability=evaluation.formalG1Status;
summary.absolute_stress_status=evaluation.absoluteStressStatus;
summary.numeric_fusion_performed=false;
summary.f1_low_stage_scale_gate_pass=evaluation.f1LowStageScalePass;
summary.f1_low_stage_maximum_dispersion_percent_frozen_full_scale= ...
    evaluation.f1LowStageMaximumFrozenFSDispersionPercent;
summary.fusion_policy="Fail-closed modality/QC eligibility gating only; ETP fails cohort gates; explicit stagewise cross-modality conflict score is not implemented";
summary.known_warning=struct('cycle',"C2",'stage',"S2", ...
    'operator_note',"本次数据有问题，焊缝的数据并不在中间位置", ...
    'final_qc_status',"REJECT",'included_in_feature_plots',true, ...
    'included_in_primary_repeatability',false);
summary.cycle_metrics=table2struct(evaluation.cycleMetrics);
summary.cross_cycle_metrics=table2struct(evaluation.crossCycleMetrics);
summary.etp_gates=table2struct(evaluation.etpGates);
summary.feature_status=table2struct(evaluation.featureStatus);
summary.cache=cacheMeta;
summary.cache.sourceFingerprint_scope="pre-release local cache key; not a public raw-data integrity identifier";
relativeFigures=replace(string(figureFiles),string(cfg.outputRoot)+filesep,"");
summary.figure_files=cellstr(replace(relativeFigures,filesep,"/"));
summary.claim_limits={ ...
    'No current-cycle strain/stress truth was read.', ...
    'MAG-F1 is a same-pipe local target/reference relative feature, not absolute total stress.', ...
    'MEM-F4 is unsigned and requires same-cycle S0.', ...
    'ETP has not passed the prespecified stress-quantity gates.', ...
    'Two complete plus one partial cycle cannot qualify formal three-repeat G1.', ...
    'No numeric multimodal fusion or current-cycle MPa output is allowed.', ...
    'Explicit stagewise cross-modality conflict scoring is not implemented.'};
json=normaliseJson(summary);
fid=fopen(fullfile(cfg.outputRoot,'analysis_summary.json'),'w','n','UTF-8');
assert(fid>=0);cleaner=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',json);clear cleaner

f1c=evaluation.cycleMetrics(evaluation.cycleMetrics.feature_id=="MAG_F1_DW_Q90",:);
f4c=evaluation.cycleMetrics(evaluation.cycleMetrics.feature_id=="MEM_F4_ZSD",:);
e1=evaluation.etpGates;
cross=evaluation.crossCycleMetrics(evaluation.crossCycleMetrics.feature_id=="MAG_F1_DW_Q90",:);
warn=stageQC.magnetic(stageQC.magnetic.cycle_id=="C2"&stageQC.magnetic.stage_id=="S2",:);
rep=evaluation.stageRepeatability(evaluation.stageRepeatability.feature_id=="MAG_F1_DW_Q90",:);
s1rep=rep(rep.stage_id=="S1",:);s2rep=rep(rep.stage_id=="S2",:);
c3=F(F.cycle_id=="C3",:);[~,oo]=sort(c3.stage_ordinal);c3=c3(oo,:);
lines=[ ...
    "# 406管道三周期MEM—剩磁—ETP盲评结论";"";
    "## 数据与边界";"";
    "- 实际数据为17次阶段牵拉：C1、C2各7阶段，C3仅S0–S2；不是完整3×7。";
    "- 本程序未读取本轮应变片或应力真值，不能报告本轮MAE/RMSE或绝对MPa精度。";
    "- MEM与剩磁由同一磁CSV按物理列奇偶拆分；磁与ETP只按周期+阶段配对，并分别完成三地标空间配准。";"";
    "## 主要结果";"";
    sprintf("- 剩磁F1状态：%s。C1的7个合格点/C2排除S2后的6个合格点，阶段Spearman分别 %.3f / %.3f；C1—C2含C2/S2敏感性点时Spearman %.3f、CCC %.3f、nRMSE %.3f。", ...
        evaluation.f1Status,f1c.inclusive_spearman(1),f1c.inclusive_spearman(2), ...
        cross.inclusive_spearman,cross.inclusive_lin_ccc,cross.inclusive_normalized_rmse);
    sprintf("- 但跨三轮尺度不稳定：S1的SD/冻结FS_F=%.2f%%（门限5%%）；S2因C2/S2拒收只剩2次，离散度=%.2f%%。C3的F1(S0/S1/S2)=%.3f/%.3f/%.3f。", ...
        s1rep.sd_percent_frozen_F1_full_scale,s2rep.sd_percent_frozen_F1_full_scale, ...
        c3.MAG_F1_DW_Q90(1),c3.MAG_F1_DW_Q90(2),c3.MAG_F1_DW_Q90(3));
    sprintf("- MEM-F4状态：%s。C1/C2合格点阶段Spearman分别 %.3f / %.3f（C2排除S2）；它无符号且必须使用同周期S0。", ...
        evaluation.f4Status,f4c.inclusive_spearman(1),f4c.inclusive_spearman(2));
    sprintf("- ETP状态：%s。C1/C2 E1加载Spearman分别 %.3f / %.3f，通过门槛数分别 %d/%d、%d/%d。", ...
        evaluation.etpStatus,e1.loaded_spearman(1),e1.loaded_spearman(2), ...
        e1.passed_gate_count(1),e1.total_gate_count(1),e1.passed_gate_count(2),e1.total_gate_count(2));
    "- E-direct是目前较值得继续验证的ETP候选，但E5/E6负对照动态范围更强，尚不能归因于应力。";
    "- 当前程序仅做模态资格/QC门控：ETP未过整轮门限，保持仅磁相对量；逐阶段跨模态冲突评分尚未实现，也没有生成数值融合值。";"";
    "## 关键QC";"";
    sprintf("- C2/S2：%d行、进管/焊缝/出管=%d/%d/%d、左右跨度比=%.3f，状态=%s。该点计算并画图，但默认不进入主重复性汇总。", ...
        warn.rows,warn.entry,warn.weld,warn.exit,warn.left_right_ratio,warn.status);
    "- C3缺少S3–S6，所有完整轨迹门槛只对C1/C2评估；共同低载S0–S2另按3次重复描述。";
    "- 正式G1状态："+evaluation.formalG1Status+"。";"";
    "## 工程使用建议";"";
    "1. 主输出保留F1原始值和ΔF1=F1−F1(S0)，只用先验冻结满量程统一尺度，禁止按本轮S6归一。";
    "2. F2/F3负责阵列/形态QC；F4仅作同管S0复核；ETP用E5/E6/温度识别全局扰动，E1/E2/E-direct只作候选。";
    "3. 再补至少一个完整、随机化加载顺序、同步应变真值的干净周期，并独立验证管段/跨管道迁移后，才评估绝对MPa与融合收益。";"";
    "## 产物";"";
    "- stage_features.csv：17包全部特征。";
    "- magnetic_stage_qc.csv、etp_stage_qc.csv：逐牵拉QC。";
    "- feature_status.csv、multimodal_decision_table.csv：工程判级与模态资格/QC门控。";
    "- figures/：13类PNG及可编辑FIG。"];
fid=fopen(fullfile(cfg.outputRoot,'结论说明.md'),'w','n','UTF-8');assert(fid>=0);
cleaner=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',strjoin(lines,newline));clear cleaner
end

function json=normaliseJson(value)
try
    json=jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true);
catch
    json=jsonencode(value,'PrettyPrint',true);
end
end
