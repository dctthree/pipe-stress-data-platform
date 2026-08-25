function figureFiles = generateFigures(profiles, stageFeatures, f2Physical, f2Circ, windowFeatures, evaluation, cfg)
%GENERATEFIGURES Produce the direct-run engineering evaluation figure set.

figDir=fullfile(cfg.outputRoot,'figures');if ~isfolder(figDir),mkdir(figDir);end
figureFiles=strings(0,1); colors=lines(3); cycles=["C1","C2","C3"];
set(groot,'defaultAxesFontName','Microsoft YaHei','defaultTextFontName','Microsoft YaHei');

% 01 Repeat matrix: missing stages remain missing.
f=newFigure([1100 430]); M=zeros(3,7);
for c=1:3,for s=0:6,M(c,s+1)=sum(stageFeatures.cycle_id==cycles(c)&stageFeatures.stage_ordinal==s);end,end
imagesc(0:6,1:3,M);colormap(f,[0.92 0.92 0.92;0.18 0.55 0.75]);caxis([0 1]);
set(gca,'YTick',1:3,'YTickLabel',cycles);xlabel('载荷阶段');ylabel('重复周期');
title('实际数据结构：2个完整周期 + 1个部分周期（缺失不插补）');
for c=1:3,for s=0:6,text(s,c,string(M(c,s+1)),'HorizontalAlignment','center','FontWeight','bold');end,end
figureFiles(end+1)=saveFigure(f,figDir,'01_repeat_design_matrix');

% 02 Magnetic event landmarks.
f=newFigure([1500 950]); tl=tiledlayout(4,5,'TileSpacing','compact','Padding','compact');
for i=1:numel(profiles)
    nexttile; y=profiles(i).mag.eventScoreRaw; plot(y,'Color',[.12 .35 .68]);hold on
    lm=profiles(i).mag.landmark;xline(lm.entry,'g--');xline(lm.weld,'r--');xline(lm.exit,'m--');
    title(profiles(i).cycle_id+"/"+profiles(i).stage_id+" "+profiles(i).magQC.status);
    xlim([1 numel(y)]);grid(gca,'on')
end
title(tl,'磁数据进管—焊缝—出管三地标QC（C2/S2源告警且最终REJECT）');
figureFiles(end+1)=saveFigure(f,figDir,'02_magnetic_landmark_qc');

% 03 ETP event landmarks.
f=newFigure([1500 950]);tl=tiledlayout(4,5,'TileSpacing','compact','Padding','compact');
for i=1:numel(profiles)
    nexttile;y=profiles(i).etpEventScore;plot(y,'Color',[.75 .28 .10]);hold on
    ev=profiles(i).etpEvent;xline(ev.entryBlock,'g--');xline(ev.weldBlock,'r--');xline(ev.exitBlock,'m--');
    title(profiles(i).cycle_id+"/"+profiles(i).stage_id+" "+profiles(i).etpQC.status);
    xlim([1 numel(y)]);grid(gca,'on')
end
title(tl,'ETP进管—焊缝—出管三地标QC');
figureFiles(end+1)=saveFigure(f,figDir,'03_etp_landmark_qc');

% 04 Registered remanence q90 profiles.
f=newFigure([1500 480]);tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
for c=1:3
    nexttile;hold on;idx=find(string({profiles.cycle_id})==cycles(c));
    for j=idx,plot(profiles(j).mag.grid,profiles(j).mag.remXQ90,'DisplayName',profiles(j).stage_id);end
    fixtureLines(cfg);title(cycles(c));xlabel('焊缝归一坐标');ylabel('Rem-X q90');grid(gca,'on')
    legend('Location','best','NumColumns',2);
end
title(tl,'剩磁X q90配准剖面（焊缝已排除于主特征中央统计）');
figureFiles(end+1)=saveFigure(f,figDir,'04_registered_remanence_q90_profiles');

% 05 F1 raw and S0 delta.
f=newFigure([1250 500]);tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;hold on
for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.MAG_F1_DW_Q90,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
rej=stageFeatures(stageFeatures.cycle_id=="C2"&stageFeatures.stage_id=="S2",:);
plot(rej.stage_ordinal,rej.MAG_F1_DW_Q90,'rx','MarkerSize',13,'LineWidth',2.2,'HandleVisibility','off');
text(rej.stage_ordinal,rej.MAG_F1_DW_Q90,'  REJECT','Color','r','FontWeight','bold');
xlabel('阶段序号');ylabel('F1原始特征单位');title('MAG-F1-DW-Q90-v1 原始值');grid(gca,'on');legend
nexttile;hold on
for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.MAG_F1_delta_S0,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
plot(rej.stage_ordinal,rej.MAG_F1_delta_S0,'rx','MarkerSize',13,'LineWidth',2.2,'HandleVisibility','off');
text(rej.stage_ordinal,rej.MAG_F1_delta_S0,'  REJECT','Color','r','FontWeight','bold');
yline(0,'k:','HandleVisibility','off');xlabel('阶段序号');ylabel('\DeltaF1=F1-F1(S0)');title('零载差值（不做终点归一）');grid(gca,'on');legend
title(tl,'剩磁主相对特征三周期轨迹');
figureFiles(end+1)=saveFigure(f,figDir,'05_F1_three_cycle_trajectories');

% 06 F1 agreement and frozen-full-scale dispersion.
f=newFigure([1250 500]);tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
A=cycleTable(stageFeatures,"C1");B=cycleTable(stageFeatures,"C2");
nexttile;scatter(A.MAG_F1_DW_Q90,B.MAG_F1_DW_Q90,70,A.stage_ordinal,'filled');hold on
lo=min([A.MAG_F1_DW_Q90;B.MAG_F1_DW_Q90]);hi=max([A.MAG_F1_DW_Q90;B.MAG_F1_DW_Q90]);plot([lo hi],[lo hi],'k--');
for i=1:height(A),text(A.MAG_F1_DW_Q90(i),B.MAG_F1_DW_Q90(i)," S"+A.stage_ordinal(i));end
xlabel('C1 F1');ylabel('C2 F1');title('C1/C2配对敏感性（C2/S2=REJECT）');axis equal;grid(gca,'on')
nexttile;r=evaluation.stageRepeatability(evaluation.stageRepeatability.feature_id=="MAG_F1_DW_Q90",:);
bar(0:6,r.sd_percent_frozen_F1_full_scale);yline(cfg.quality.maximumF1FullScaleCVPercent,'r--','5%门');
xlabel('阶段序号');ylabel('跨周期SD / 先验冻结FS_F (%)');title('重复离散度：S3–S6仅2次');grid(gca,'on')
title(tl,'F1跨周期一致性与离散度（不是本轮MPa精度）');
figureFiles(end+1)=saveFigure(f,figDir,'06_F1_cross_cycle_agreement');

% 07 Frozen 27-window robustness.
f=newFigure([1500 480]);tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
for c=1:3
    nexttile;hold on;w=windowFeatures(windowFeatures.feature_id=="MAG_F1_DW_Q90"&windowFeatures.cycle_id==cycles(c),:);
    for k=unique(w.configuration).',q=w(w.configuration==k,:);[~,o]=sort(q.stage_ordinal);q=q(o,:);plot(q.stage_ordinal,q.feature_value,'Color',[.72 .79 .88]);end
    base=w(abs(w.left_shift)<eps&abs(w.right_shift)<eps&abs(w.half_width-.033)<eps,:);[~,o]=sort(base.stage_ordinal);base=base(o,:);
    plot(base.stage_ordinal,base.feature_value,'ko-','LineWidth',1.8);title(cycles(c));xlabel('阶段');ylabel('F1');grid(gca,'on')
end
title(tl,'MAG-F1 27组冻结窗口扰动（±0.025，half=0.026/0.033/0.042）');
figureFiles(end+1)=saveFigure(f,figDir,'07_F1_window_robustness_27');

% 08 F2 array consistency heatmaps.
f=newFigure([1450 780]);tl=tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
for c=1:3
    nexttile;matrix=featureMatrix(f2Physical,cycles(c),'physical_column_within_remanence',16);
    imagesc(0:size(matrix,1)-1,1:16,matrix.');colorbar;title(cycles(c)+" 16物理列");xlabel('阶段');ylabel('剩磁物理列');
end
for c=1:3
    nexttile;matrix=featureMatrix(f2Circ,cycles(c),'circumferential_position',10);
    imagesc(0:size(matrix,1)-1,1:10,matrix.');colorbar;title(cycles(c)+" 10环向位置");xlabel('阶段');ylabel('环向位置');
end
title(tl,'MAG-F2阵列一致性QC：中央—外参考对比（非独立应力票）');
figureFiles(end+1)=saveFigure(f,figDir,'08_F2_array_consistency');

% 09 F3 shape versus mechanics template.
f=newFigure([1500 480]);tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
for c=1:3
    nexttile;idx=find(string({profiles.cycle_id})==cycles(c));ord=[profiles(idx).stage_ordinal].';
    if numel(idx)>=4
        stack=vertcatProfiles(profiles(idx),'remXQ90');oc=ord-mean(ord);slope=(oc.'*(stack-mean(stack,1)))/sum(oc.^2);slope=movmean(slope,31);
        xgrid=profiles(idx(1)).mag.grid;moment=blind406.fourPointMoment(xgrid,cfg);scale=max(abs(slope));plot(xgrid,slope,'b');hold on;plot(xgrid,moment*scale,'k--');
        legend('阶段斜率','四点弯矩模板');grid(gca,'on')
    else,text(.1,.5,'阶段不足，仅展示不判定','Units','normalized');end
    title(cycles(c));xlabel('归一坐标');ylabel('响应斜率');
end
title(tl,'MAG-F3形态QC：弯矩模板必须与二次漂移竞争');
figureFiles(end+1)=saveFigure(f,figDir,'09_F3_spatial_mechanics_qc');

% 10 MEM F4 and directional F5.
f=newFigure([1250 500]);tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
nexttile;hold on;for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.MEM_F4_ZSD,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
xlabel('阶段');ylabel('F4 RMS');title('MEM-F4-ZSD-v1（必须同周期S0）');grid(gca,'on');legend
nexttile;hold on;for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.MAG_F5_H1,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
xlabel('阶段');ylabel('F5一阶谐波对比');title('MAG-F5-H1-v1（方向辅助）');grid(gca,'on');legend
title(tl,'MEM辅助与剩磁方向诊断');
figureFiles(end+1)=saveFigure(f,figDir,'10_MEM_F4_and_MAG_F5');

% 11 ETP primary/candidates.
f=newFigure([1500 480]);tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
vars=["ETP_E1_CDIFF","ETP_E2_MOMENT","ETP_EDirect"];names=["E1复双差","E2弯矩投影","E-direct候选"];
for v=1:3,nexttile;hold on;for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.(vars(v)),'o-','Color',colors(c,:),'DisplayName',cycles(c));end
    xlabel('阶段');ylabel('归一响应');title(names(v));grid(gca,'on');legend
end
title(tl,'ETP候选复现：E-direct较好但尚未通过负对照特异性门');
figureFiles(end+1)=saveFigure(f,figDir,'11_ETP_candidate_trajectories');

% 12 ETP negative controls and temperature.
f=newFigure([1500 480]);tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
nexttile;hold on;for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.ETP_E5_WELD,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
title('E5焊缝负对照');xlabel('阶段');grid(gca,'on');legend
nexttile;hold on;for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.ETP_E6_OUT,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
title('E6外参考全局负对照');xlabel('阶段');grid(gca,'on');legend
nexttile;hold on;for c=1:3,q=cycleTable(stageFeatures,cycles(c));plot(q.stage_ordinal,q.ETP_temperature0_C,'o-','Color',colors(c,:),'DisplayName',cycles(c));end
title('ETP温度0');xlabel('阶段');ylabel('°C');grid(gca,'on');legend
title(tl,'ETP混杂诊断：负对照强于目标响应时必须降级');
figureFiles(end+1)=saveFigure(f,figDir,'12_ETP_negative_controls_temperature');

% 13 Decision-level multimodal dashboard.
f=newFigure([1350 560]);D=evaluation.decisionTable;
yyaxis left;hold on;for c=1:3,q=D(D.cycle_id==cycles(c),:);plot(q.stage_ordinal,q.relative_index_frozen_prior_scale,'o-','Color',colors(c,:),'DisplayName',cycles(c)+" 磁");end
ylabel('\DeltaF1 / 先验冻结FS_F');yyaxis right;hold on
for c=1:3,q=D(D.cycle_id==cycles(c),:);plot(q.stage_ordinal,q.ETP_EDirect,'s--','Color',colors(c,:),'HandleVisibility','off');end
ylabel('ETP E-direct（QC候选）');xlabel('阶段');grid(gca,'on');legend('Location','northwest');
title('模态资格/QC并列输出：ETP未过门，保持仅磁相对量；未实现逐阶段冲突评分');
figureFiles(end+1)=saveFigure(f,figDir,'13_multimodal_gated_dashboard');
end

function f=newFigure(position)
f=figure('Visible','off','Color','w','Position',[50 50 position]);
end
function path=saveFigure(f,folder,name)
path=string(fullfile(folder,name+".png"));exportgraphics(f,path,'Resolution',180);savefig(f,fullfile(folder,name+".fig"));close(f);
end
function q=cycleTable(T,cycle)
q=T(string(T.cycle_id)==string(cycle),:);[~,o]=sort(q.stage_ordinal);q=q(o,:);
end
function fixtureLines(cfg)
xline(cfg.spatial.leftSupport,'k:');xline(cfg.spatial.leftHead,'k--');xline(0,'r:');xline(cfg.spatial.rightHead,'k--');xline(cfg.spatial.rightSupport,'k:');
end
function M=featureMatrix(T,cycle,idVar,nChannel)
q=T(string(T.cycle_id)==cycle,:);stages=unique(q.stage_ordinal);M=nan(numel(stages),nChannel);
for i=1:numel(stages),for j=1:nChannel,r=q(q.stage_ordinal==stages(i)&q.(idVar)==j,:);if ~isempty(r),M(i,j)=r.contrast;end,end,end
base=M(1,:);M=M-base;
end
function S=vertcatProfiles(p,field)
S=zeros(numel(p),numel(p(1).mag.(field)));for i=1:numel(p),S(i,:)=p(i).mag.(field);end
end
