function evaluation = evaluateRepeatability(stageFeatures, f2Physical, f2Circ, windowFeatures, etpChannels, shapeQC, cfg)
%EVALUATEREPEATABILITY Unbalanced three-cycle audit and decision-level gating.

featureVars=["MAG_F1_DW_Q90","MAG_F1_delta_S0","MEM_F4_ZSD", ...
    "ETP_E1_CDIFF","ETP_E2_MOMENT","ETP_EDirect","ETP_E5_WELD","ETP_E6_OUT"];
cycles=unique(string(stageFeatures.cycle_id),'stable');
cycleRows=cell(0,12);
for ci=1:numel(cycles)
    cycle=cycles(ci); inCycle=string(stageFeatures.cycle_id)==cycle;
    for fv=featureVars
        magnetic=startsWith(fv,"MAG_")||startsWith(fv,"MEM_");
        inclusive=inCycle; strict=inCycle;
        if magnetic
            inclusive=inclusive&stageFeatures.mag_feature_eligible;
            strict=strict&stageFeatures.mag_repeatability_eligible;
        else
            inclusive=inclusive&string(stageFeatures.etp_qc_status)~="REJECT";
            strict=inclusive;
        end
        if startsWith(fv,"ETP_E1")||startsWith(fv,"ETP_E2")
            primary=inclusive&stageFeatures.stage_ordinal>0;
            strictPrimary=strict&stageFeatures.stage_ordinal>0;
        else
            primary=inclusive; strictPrimary=strict;
        end
        [rho,tau,inc]=trajectory(stageFeatures.(fv)(primary),stageFeatures.stage_ordinal(primary));
        [rhoS,tauS,incS]=trajectory(stageFeatures.(fv)(strictPrimary),stageFeatures.stage_ordinal(strictPrimary));
        cycleRows(end+1,:)={cycle,fv,sum(inCycle),sum(primary),rho,tau,inc, ...
            sum(strictPrimary),rhoS,tauS,incS,sum(inCycle)<7}; %#ok<AGROW>
    end
end
cycleMetrics=cell2table(cycleRows,'VariableNames',{'cycle_id','feature_id','provided_stage_count', ...
    'inclusive_n','inclusive_spearman','inclusive_kendall','inclusive_adjacent_increases', ...
    'strict_n','strict_spearman','strict_kendall','strict_adjacent_increases','partial_cycle'});

crossRows=cell(0,12);
for fv=featureVars
    [x,y,ord,strictMask]=matchedCurves(stageFeatures,"C1","C2",fv);
    inclusive=agreement(x,y,double(cfg.features.priorF1FullScale));
    strict=agreement(x(strictMask),y(strictMask),double(cfg.features.priorF1FullScale));
    crossRows(end+1,:)={fv,numel(x),inclusive.spearman,inclusive.ccc,inclusive.slope, ...
        inclusive.intercept,inclusive.nrmse,sum(strictMask),strict.spearman,strict.ccc, ...
        strict.nrmse,strjoin("S"+string(ord(~strictMask)),",")}; %#ok<AGROW>
end
crossCycleMetrics=cell2table(crossRows,'VariableNames',{'feature_id','inclusive_n', ...
    'inclusive_spearman','inclusive_lin_ccc','inclusive_affine_slope','inclusive_affine_intercept', ...
    'inclusive_normalized_rmse','strict_n','strict_spearman','strict_lin_ccc', ...
    'strict_normalized_rmse','excluded_stage_ids'});

repeatRows=cell(0,9);
for fv=featureVars
    for s=0:6
        use=stageFeatures.stage_ordinal==s;
        if startsWith(fv,"MAG_")||startsWith(fv,"MEM_")
            use=use&stageFeatures.mag_feature_eligible;
        else
            use=use&string(stageFeatures.etp_qc_status)~="REJECT";
        end
        values=stageFeatures.(fv)(use); values=values(isfinite(values));
        if isempty(values), mu=NaN; sd=NaN; else, mu=mean(values); sd=std(values,0); end
        cvFrozen=NaN;
        if fv=="MAG_F1_DW_Q90"||fv=="MAG_F1_delta_S0"
            cvFrozen=100*sd/double(cfg.features.priorF1FullScale);
        end
        repeatRows(end+1,:)={fv,"S"+s,numel(values),mu,sd,minOrNaN(values),maxOrNaN(values), ...
            cvFrozen,numel(values)<3}; %#ok<AGROW>
    end
end
stageRepeatability=cell2table(repeatRows,'VariableNames',{'feature_id','stage_id','n_repeats', ...
    'mean','sd','minimum','maximum','sd_percent_frozen_F1_full_scale','fewer_than_three_repeats'});

windowMetrics=evaluateWindows(windowFeatures,stageFeatures);
f2Metrics=evaluateF2(f2Physical,f2Circ);
etpGates=evaluateEtpGates(stageFeatures,etpChannels,windowMetrics,cfg);

f1Cycles=cycleMetrics(cycleMetrics.feature_id=="MAG_F1_DW_Q90"&~cycleMetrics.partial_cycle,:);
f1Cross=crossCycleMetrics(crossCycleMetrics.feature_id=="MAG_F1_DW_Q90",:);
f1Win=windowMetrics(windowMetrics.feature_id=="MAG_F1_DW_Q90"&~windowMetrics.partial_cycle,:);
f1OrdinalPass=all(f1Cycles.inclusive_spearman>=cfg.quality.minimumCompleteCycleSpearman);
f1CrossPass=f1Cross.inclusive_spearman>=cfg.quality.minimumCrossCycleSpearman && ...
    f1Cross.inclusive_lin_ccc>=cfg.quality.minimumProvisionalCCC && ...
    f1Cross.inclusive_normalized_rmse<=cfg.quality.maximumNormalizedRMSE;
f1WindowPass=all(f1Win.rho_vs_base_median>=cfg.quality.minimumWindowMedianSpearman & ...
    f1Win.rho_vs_base_minimum>=cfg.quality.minimumWindowWorstSpearman);
hasWarn=any(string(stageFeatures.mag_qc_status)~="PASS");
lowRepeat=stageRepeatability(stageRepeatability.feature_id=="MAG_F1_DW_Q90" & ...
    stageRepeatability.n_repeats>=3 & stageRepeatability.stage_id~="S0",:);
lowStageScalePass=~isempty(lowRepeat) && all(lowRepeat.sd_percent_frozen_F1_full_scale<= ...
    cfg.quality.maximumF1FullScaleCVPercent);
if f1OrdinalPass&&f1CrossPass&&f1WindowPass&&lowStageScalePass&&~hasWarn
    f1Status="B_RELATIVE_REPRODUCED_PROVISIONAL";
elseif f1OrdinalPass&&f1CrossPass&&f1WindowPass
    f1Status="B_RELATIVE_ORDER_ONLY_SCALE_DRIFT_OR_QC_EXCLUSION";
else
    f1Status="C_RESEARCH_SIGNAL_REPEAT_REQUIRED";
end

f4Cycles=cycleMetrics(cycleMetrics.feature_id=="MEM_F4_ZSD"&~cycleMetrics.partial_cycle,:);
f4Cross=crossCycleMetrics(crossCycleMetrics.feature_id=="MEM_F4_ZSD",:);
f4Pass=all(f4Cycles.inclusive_spearman>=cfg.quality.minimumCompleteCycleSpearman)&& ...
    f4Cross.inclusive_lin_ccc>=cfg.quality.minimumProvisionalCCC;
if f4Pass, f4Status="CONDITIONAL_S0_AUXILIARY_SCALE_NOT_QUALIFIED"; else, f4Status="C_AUXILIARY_UNSTABLE"; end

etpPromoted=all(etpGates.all_required_gates_pass(etpGates.complete_cycle));
if etpPromoted, etpStatus="PROVISIONAL_CANDIDATE_PENDING_TRUTH"; else, etpStatus="QC_ONLY_NOT_STRESS_QUANTITY"; end
featureStatus=table(["MAG-F1-DW-Q90-v1";"MEM-F4-ZSD-v1";"MAG-F2-ARRAY-v1"; ...
    "MAG-F3-SHAPE-v1";"MAG-F5-H1-v1";"ETP-E1-CDIFF-v1";"ETP-E2-MOMENT-v1"; ...
    "ETP-EDIRECT-v1";"ETP-E5/E6-QC";"MULTIMODAL-GATED-v1"], ...
    [f1Status;f4Status;"ARRAY_QC_ONLY";"SHAPE_QC_ONLY";"DIRECTION_AUXILIARY_ONLY"; ...
    etpStatus;"SHAPE_AUXILIARY_ONLY";"RESEARCH_CANDIDATE_QC_ONLY"; ...
    "NEGATIVE_CONTROL_QC";"DECISION_GATING_NO_NUMERIC_FUSION"], ...
    ["同管相对排序/目标-参考变化";"同周期S0复核";"异常列与环向一致性"; ...
    "弯矩形态与漂移竞争诊断";"偏心/滚转方向辅助";"候选/QC";"形态辅助"; ...
    "候选/QC";"焊缝、温漂、提离告警";"模态资格/QC门控；逐阶段冲突评分未实现"], ...
    repmat("禁止输出本轮绝对MPa",10,1), ...
    'VariableNames',{'feature_id','status','allowed_use','claim_limit'});

decisionTable=makeDecisionTable(stageFeatures,etpGates,cfg);
evaluation=struct('cycleMetrics',cycleMetrics,'crossCycleMetrics',crossCycleMetrics, ...
    'stageRepeatability',stageRepeatability,'windowMetrics',windowMetrics, ...
    'f2Metrics',f2Metrics,'shapeQC',shapeQC,'etpGates',etpGates, ...
    'featureStatus',featureStatus,'decisionTable',decisionTable, ...
    'f1Status',f1Status,'f4Status',f4Status,'etpStatus',etpStatus, ...
    'formalG1Status',"G1_INSUFFICIENT_REPLICATION_TWO_COMPLETE_PLUS_ONE_PARTIAL", ...
    'absoluteStressStatus',"NOT_VALIDATED_NO_CURRENT_TRUTH", ...
    'f1LowStageScalePass',lowStageScalePass, ...
    'f1LowStageMaximumFrozenFSDispersionPercent',max(lowRepeat.sd_percent_frozen_F1_full_scale,[],'omitnan'));
end

function T=evaluateWindows(W,F)
features=unique(string(W.feature_id),'stable'); cycles=unique(string(W.cycle_id),'stable'); rows=cell(0,9);
for fv=features.'
    for cycle=cycles.'
        part=W(string(W.feature_id)==fv&string(W.cycle_id)==cycle,:);
        if isempty(part), continue; end
        configs=unique(part.configuration); rBase=nan(numel(configs),1); rOrd=rBase;
        base=part(abs(part.left_shift)<1e-12&abs(part.right_shift)<1e-12&abs(part.half_width-0.033)<1e-12,:);
        [~,o]=sort(base.stage_ordinal); base=base(o,:);
        for k=1:numel(configs)
            q=part(part.configuration==configs(k),:); [~,o]=sort(q.stage_ordinal); q=q(o,:);
            if fv=="ETP_E1_CDIFF", use=q.stage_ordinal>0; else, use=true(height(q),1); end
            rBase(k)=spearman(q.feature_value(use),base.feature_value(use));
            rOrd(k)=spearman(q.feature_value(use),q.stage_ordinal(use));
        end
        provided=sum(string(F.cycle_id)==cycle);
        rows(end+1,:)={fv,cycle,provided,median(rBase,'omitnan'),min(rBase), ...
            median(rOrd,'omitnan'),min(rOrd),numel(configs),provided<7}; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'feature_id','cycle_id','provided_stage_count', ...
    'rho_vs_base_median','rho_vs_base_minimum','rho_vs_ordinal_median', ...
    'rho_vs_ordinal_minimum','configurations','partial_cycle'});
end

function T=evaluateF2(P,C)
cycles=unique(string(P.cycle_id),'stable'); refP=slopes(P,string(P.cycle_id)=="C1",16,'physical_column_within_remanence');
refC=slopes(C,string(C.cycle_id)=="C1",10,'circumferential_position'); rows=cell(0,8);
for cycle=cycles.'
    p=slopes(P,string(P.cycle_id)==cycle,16,'physical_column_within_remanence');
    c=slopes(C,string(C.cycle_id)==cycle,10,'circumferential_position');
    rows(end+1,:)={cycle,sum(sign(p)==sign(refP)),16,sum(sign(c)==sign(refC)),10, ...
        safePearson(p,refP),safePearson(c,refC),sum(string(P.cycle_id)==cycle& P.stage_id=="S0")>0}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'cycle_id','physical_columns_same_sign_as_C1','physical_columns_total', ...
    'circumferential_positions_same_sign_as_C1','circumferential_positions_total', ...
    'physical_slope_vector_pearson','circumferential_slope_vector_pearson','has_baseline'});
end

function s=slopes(T,use,n,idVar)
s=nan(n,1); T=T(use,:);
for j=1:n
    q=T(T.(idVar)==j,:); if height(q)>=3, p=polyfit(q.stage_ordinal,q.contrast,1); s(j)=p(1); end
end
end

function gates=evaluateEtpGates(F,C,W,cfg)
cycles=unique(string(F.cycle_id),'stable'); rows=cell(0,17);
for cycle=cycles.'
    q=F(string(F.cycle_id)==cycle,:); [~,o]=sort(q.stage_ordinal); q=q(o,:); loaded=q.stage_ordinal>0;
    rho=spearman(q.ETP_E1_CDIFF(loaded),q.stage_ordinal(loaded));
    tau=kendall(q.ETP_E1_CDIFF(loaded),q.stage_ordinal(loaded));
    adjacent=sum(diff(q.ETP_E1_CDIFF(loaded))>0); expected=max(sum(loaded)-1,0);
    p=exactPermutationP(q.ETP_E1_CDIFF(loaded),q.stage_ordinal(loaded));
    w=W(string(W.feature_id)=="ETP_E1_CDIFF"&string(W.cycle_id)==cycle,:);
    ch=C(string(C.cycle_id)==cycle&C.good_from_S0,:); ids=unique(ch.channel); slopesCh=nan(numel(ids),1); loo=nan(numel(ids),1);
    stageIDs=unique(ch.stage_ordinal); stageIDs=sort(stageIDs); matrix=nan(numel(stageIDs),numel(ids));
    for k=1:numel(ids)
        cq=ch(ch.channel==ids(k),:); [~,oo]=sort(cq.stage_ordinal); cq=cq(oo,:); matrix(:,k)=cq.E1_channel;
        ld=cq.stage_ordinal>0; slopesCh(k)=spearman(cq.E1_channel(ld),cq.stage_ordinal(ld));
    end
    for k=1:numel(ids)
        aggregate=median(matrix(:,setdiff(1:numel(ids),k)),2,'omitnan');
        loo(k)=spearman(aggregate(stageIDs>0),stageIDs(stageIDs>0));
    end
    bootstrapP=pairedChannelBootstrap(matrix,stageIDs,cfg.randomSeed+sum(double(char(cycle))));
    ratio=rangeSafe(q.ETP_E1_CDIFF)/max([rangeSafe(q.ETP_E5_WELD),rangeSafe(q.ETP_E6_OUT),eps]);
    tempRho=spearman(q.ETP_temperature0_C,q.stage_ordinal);
    goodCount=min(q.ETP_good_channels);
    windowMedian=NaN; windowMinimum=NaN;
    if ~isempty(w), windowMedian=w.rho_vs_ordinal_median; windowMinimum=w.rho_vs_ordinal_minimum; end
    gateVector=[rho>=cfg.quality.minimumETPLoadedSpearman, ...
        tau>=cfg.quality.minimumETPLoadedKendall,adjacent==5,p<=0.05, ...
        windowMedian>=0.90,windowMinimum>=0.80,min(loo)>=0.80, ...
        mean(slopesCh>0)>=cfg.quality.minimumETPPositiveChannelFraction,bootstrapP>=0.80, ...
        max(abs([spearman(q.ETP_E2_MOMENT(loaded),q.stage_ordinal(loaded)), ...
        spearman(q.ETP_E3_HEADSUP(loaded),q.stage_ordinal(loaded))]))>=0.60, ...
        ratio>=cfg.quality.minimumETPTargetNegativeControlRatio,goodCount>=18, ...
        abs(tempRho)<cfg.quality.maximumTemperatureOrdinalAbsSpearman];
    complete=height(q)==7;
    rows(end+1,:)={cycle,height(q),complete,rho,tau,adjacent,expected,p,min(loo), ...
        mean(slopesCh>0),bootstrapP,ratio,tempRho,goodCount,sum(gateVector),numel(gateVector), ...
        complete&&all(gateVector)}; %#ok<AGROW>
end
gates=cell2table(rows,'VariableNames',{'cycle_id','stage_count','complete_cycle','loaded_spearman', ...
    'loaded_kendall','loaded_adjacent_increases','loaded_adjacent_expected','exact_one_sided_p', ...
    'leave_one_channel_rho_minimum','positive_channel_fraction','channel_bootstrap_P_S1_gt_S0', ...
    'target_to_E5E6_negative_control_range_ratio','temperature_ordinal_spearman','good_channels', ...
    'passed_gate_count','total_gate_count','all_required_gates_pass'});
end

function D=makeDecisionTable(F,gates,cfg)
D=F(:,{'cycle_id','stage_id','stage_ordinal','mag_qc_status','etp_qc_status', ...
    'MAG_F1_DW_Q90','MAG_F1_delta_S0','MEM_F4_ZSD','ETP_E1_CDIFF','ETP_EDirect','ETP_E5_WELD','ETP_E6_OUT'});
D.relative_index_frozen_prior_scale=D.MAG_F1_delta_S0/double(cfg.features.priorF1FullScale);
D.etp_role=repmat("QC_ONLY",height(D),1); D.fusion_value=nan(height(D),1); D.decision=strings(height(D),1);
for i=1:height(D)
    gate=gates(string(gates.cycle_id)==string(D.cycle_id(i)),:);
    if string(D.mag_qc_status(i))=="REJECT"
        D.decision(i)="NO_MAGNETIC_DECISION";
    elseif string(D.mag_qc_status(i))=="WARN"
        D.decision(i)="MAGNETIC_RELATIVE_QC_WARNING_RETEST";
    elseif ~isempty(gate)&&~gate.all_required_gates_pass
        D.decision(i)="MAGNETIC_RELATIVE_ONLY_ETP_QC";
    else
        D.decision(i)="HOLD_ETP_ELIGIBLE_EXPLICIT_CONFLICT_GATE_NOT_IMPLEMENTED";
    end
end
end

function [x,y,ord,strict]=matchedCurves(F,a,b,fv)
A=F(string(F.cycle_id)==a,:); B=F(string(F.cycle_id)==b,:); ord=intersect(A.stage_ordinal,B.stage_ordinal);
x=nan(numel(ord),1);y=x;strict=false(numel(ord),1);
for i=1:numel(ord)
    aa=A(A.stage_ordinal==ord(i),:);bb=B(B.stage_ordinal==ord(i),:);x(i)=aa.(fv);y(i)=bb.(fv);
    if startsWith(fv,"MAG_")||startsWith(fv,"MEM_")
        strict(i)=aa.mag_repeatability_eligible&&bb.mag_repeatability_eligible;
    else
        strict(i)=string(aa.etp_qc_status)~="REJECT"&&string(bb.etp_qc_status)~="REJECT";
    end
end
end
function a=agreement(x,y,frozenFS)
valid=isfinite(x)&isfinite(y);x=x(valid);y=y(valid);
if numel(x)<2, a=struct('spearman',NaN,'ccc',NaN,'slope',NaN,'intercept',NaN,'nrmse',NaN);return;end
p=polyfit(x,y,1);rmse=sqrt(mean((x-y).^2));den=max(rangeSafe(x),eps);
a=struct('spearman',spearman(x,y),'ccc',ccc(x,y),'slope',p(1),'intercept',p(2), ...
    'nrmse',rmse/den,'frozen_fs_rmse',rmse/max(frozenFS,eps));
end
function [rho,tau,increases]=trajectory(v,o)
valid=isfinite(v)&isfinite(o);v=v(valid);o=o(valid);[o,ix]=sort(o);v=v(ix);
rho=spearman(v,o);tau=kendall(v,o);increases=sum(diff(v)>0);
end
function r=spearman(x,y)
valid=isfinite(x)&isfinite(y);x=x(valid);y=y(valid);if numel(x)<2||std(x)<eps||std(y)<eps,r=NaN;return;end
r=safePearson(tiedRank(x),tiedRank(y));
end
function r=kendall(x,y)
valid=isfinite(x)&isfinite(y);x=x(valid);y=y(valid);n=numel(x);if n<2,r=NaN;return;end
c=0;d=0;for i=1:n-1,for j=i+1:n,s=sign((x(j)-x(i))*(y(j)-y(i)));c=c+(s>0);d=d+(s<0);end,end
r=(c-d)/max(n*(n-1)/2,1);
end
function r=tiedRank(x)
[s,order]=sort(x);r=zeros(size(x));i=1;while i<=numel(x),j=i;while j<numel(x)&&s(j+1)==s(i),j=j+1;end;r(order(i:j))=(i+j)/2;i=j+1;end
end
function r=safePearson(x,y)
valid=isfinite(x)&isfinite(y);x=x(valid);y=y(valid);
if numel(x)<2||std(x)<eps||std(y)<eps,r=NaN;else,c=corrcoef(x,y);r=c(1,2);end
end
function value=ccc(x,y)
x=x(:);y=y(:);value=2*mean((x-mean(x)).*(y-mean(y)))/(var(x,1)+var(y,1)+(mean(x)-mean(y))^2);
end
function p=exactPermutationP(v,o)
if numel(v)<3||numel(v)>8,p=NaN;return;end;obs=spearman(v,o);P=perms(o(:).');null=nan(size(P,1),1);
for i=1:size(P,1),null(i)=spearman(v,P(i,:).');end;p=mean(null>=obs-1e-12);
end
function p=pairedChannelBootstrap(matrix,stageIDs,seed)
if size(matrix,2)<2||~any(stageIDs==0)||~any(stageIDs==1),p=NaN;return;end
rng(seed,'twister');B=1000;count=0;i0=find(stageIDs==0,1);i1=find(stageIDs==1,1);m=size(matrix,2);
for b=1:B,ix=randi(m,m,1);a=median(matrix(i0,ix),'omitnan');c=median(matrix(i1,ix),'omitnan');count=count+(c>a);end;p=count/B;
end
function r=rangeSafe(x)
x=x(isfinite(x));if isempty(x),r=NaN;else,r=max(x)-min(x);end
end
function v=minOrNaN(x)
if isempty(x),v=NaN;else,v=min(x);end
end
function v=maxOrNaN(x)
if isempty(x),v=NaN;else,v=max(x);end
end
