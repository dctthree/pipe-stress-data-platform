function [stageFeatures, f2Physical, f2Circ, windowFeatures, etpChannels, shapeQC] = extractFeatures(profiles, cfg)
%EXTRACTFEATURES Frozen magnetic features and prespecified ETP candidates/QC.
%   No current strain or stress value is accepted by this interface.

n = numel(profiles);
cycle = strings(n,1); stage = strings(n,1); ordinal = zeros(n,1);
F1 = nan(n,1); F1equal = nan(n,1); F1delta = nan(n,1);
F4 = nan(n,1); F5 = nan(n,1); magEligible=false(n,1); magRepeat=false(n,1);
magStatus=strings(n,1); etpStatus=strings(n,1);
E1=nan(n,1); E2=nan(n,1); E3=nan(n,1); E4=nan(n,1); E5=nan(n,1);
E6=nan(n,1); EStatic=nan(n,1); EAmplitude=nan(n,1); EPhase=nan(n,1);
EDirect=nan(n,1); goodETP=nan(n,1); temp0=nan(n,1); temp1=nan(n,1);
magTempMEM=nan(n,1); magTempRem=nan(n,1);

physicalRows = cell(0,6); circRows=cell(0,6); windowRows=cell(0,9);
etpRows=cell(0,8); shapeRows=cell(0,10);

for i=1:n
    cycle(i)=string(profiles(i).cycle_id); stage(i)=string(profiles(i).stage_id);
    ordinal(i)=double(profiles(i).stage_ordinal);
    magStatus(i)=string(profiles(i).magQC.status);
    etpStatus(i)=string(profiles(i).etpQC.status);
    magTempMEM(i)=double(profiles(i).magQC.mem_temperature_C);
    magTempRem(i)=double(profiles(i).magQC.remanence_temperature_C);
    magEligible(i)=logical(profiles(i).mag.featureEligible);
    magRepeat(i)=logical(profiles(i).mag.repeatabilityEligible);
    grid=profiles(i).mag.grid;
    masks=blind406.regionMasks(grid,cfg);
    contrast=blind406.profileContrast(profiles(i).mag.remXQ90,grid,masks);
    F1(i)=contrast.distanceWeighted; F1equal(i)=contrast.equalWeight;
    for c=1:size(profiles(i).mag.remColumnMedian,2)
        q=blind406.profileContrast(profiles(i).mag.remColumnMedian(:,c),grid,masks);
        physicalRows(end+1,:)={cycle(i),stage(i),ordinal(i),c,q.distanceWeighted,magRepeat(i)}; %#ok<AGROW>
    end
    for c=1:size(profiles(i).mag.remCircMedian,2)
        q=blind406.profileContrast(profiles(i).mag.remCircMedian(:,c),grid,masks);
        circRows(end+1,:)={cycle(i),stage(i),ordinal(i),c,q.distanceWeighted,magRepeat(i)}; %#ok<AGROW>
    end
    harmonic=firstHarmonic(profiles(i).mag.remCircMedian);
    q=blind406.profileContrast(harmonic,grid,masks); F5(i)=q.distanceWeighted;
    configuration=0;
    for ls=reshape(double(cfg.features.windowShifts),1,[])
        for rs=reshape(double(cfg.features.windowShifts),1,[])
            for hw=reshape(double(cfg.features.windowHalfWidths),1,[])
                vm=blind406.regionMasks(grid,cfg,ls,rs,hw);
                q=blind406.profileContrast(profiles(i).mag.remXQ90,grid,vm);
                windowRows(end+1,:)={"MAG_F1_DW_Q90",cycle(i),stage(i),ordinal(i),configuration,ls,rs,hw,q.distanceWeighted}; %#ok<AGROW>
                configuration=configuration+1;
            end
        end
    end
end

% Same-cycle S0 is mandatory for both delta-F1 and MEM-F4.
cycles=unique(cycle,'stable');
for ci=1:numel(cycles)
    idx=find(cycle==cycles(ci));
    base=idx(stage(idx)=="S0");
    assert(numel(base)==1,'Blind406:Baseline','Cycle %s does not have exactly one S0.',cycles(ci));
    F1delta(idx)=F1(idx)-F1(base);
    masks=blind406.regionMasks(profiles(base).mag.grid,cfg);
    baseMem=profiles(base).mag.memZStd;
    for ii=idx.'
        delta=profiles(ii).mag.memZStd-baseMem;
        F4(ii)=sqrt(mean(delta(masks.rightSupport).^2,'omitnan'));
    end
end

% ETP definitions are S0-referenced and must be evaluated cycle by cycle.
for ci=1:numel(cycles)
    idx=find(cycle==cycles(ci)); [~,order]=sort(ordinal(idx)); idx=idx(order);
    z=cat(3,profiles(idx).etpComplex); z=permute(z,[3 1 2]);
    amp=cat(3,profiles(idx).etpAmplitude); amp=permute(amp,[3 1 2]);
    grid=profiles(idx(1)).etpGrid;
    masks=blind406.regionMasks(grid,cfg);
    [good,goodQC]=goodEtpChannels(squeeze(z(1,:,:)),squeeze(amp(1,:,:)),grid,masks);
    bundle=computeEtpBundle(z,amp,grid,masks,good,cfg);
    E1(idx)=bundle.E1; E2(idx)=bundle.E2; E3(idx)=bundle.E3; E4(idx)=bundle.E4;
    E5(idx)=bundle.E5; E6(idx)=bundle.E6; EStatic(idx)=bundle.EStatic;
    EAmplitude(idx)=bundle.EAmplitude; EPhase(idx)=bundle.EPhase; EDirect(idx)=bundle.EDirect;
    goodETP(idx)=sum(good);
    for jj=1:numel(idx)
        temp0(idx(jj))=double(profiles(idx(jj)).etpQC.temperature0_C);
        temp1(idx(jj))=double(profiles(idx(jj)).etpQC.temperature1_C);
        for ch=1:numel(good)
            etpRows(end+1,:)={cycle(idx(jj)),stage(idx(jj)),ordinal(idx(jj)),ch, ...
                good(ch),bundle.E1Channels(jj,ch),bundle.EDirectChannels(jj,ch),goodQC.scale(ch)}; %#ok<AGROW>
        end
    end
    configuration=0;
    for ls=reshape(double(cfg.features.windowShifts),1,[])
        for rs=reshape(double(cfg.features.windowShifts),1,[])
            for hw=reshape(double(cfg.features.windowHalfWidths),1,[])
                vm=blind406.regionMasks(grid,cfg,ls,rs,hw);
                candidate=computeEtpBundle(z,amp,grid,vm,good,cfg);
                for jj=1:numel(idx)
                    windowRows(end+1,:)={"ETP_E1_CDIFF",cycle(idx(jj)),stage(idx(jj)),ordinal(idx(jj)), ...
                        configuration,ls,rs,hw,candidate.E1(jj)}; %#ok<AGROW>
                end
                configuration=configuration+1;
            end
        end
    end
end

% F3 spatial-mechanics diagnostic; never promoted to an independent stress value.
for ci=1:numel(cycles)
    idx=find(cycle==cycles(ci) & magEligible); [~,order]=sort(ordinal(idx)); idx=idx(order);
    if numel(idx)<4
        shapeRows(end+1,:)={cycles(ci),numel(idx),NaN,NaN,NaN,NaN,NaN, ...
            "INSUFFICIENT_STAGES",false,false}; %#ok<AGROW>
        continue
    end
    stack=zeros(numel(idx),numel(profiles(idx(1)).mag.grid));
    for j=1:numel(idx), stack(j,:)=profiles(idx(j)).mag.remXQ90; end
    ord=ordinal(idx); oc=ord-mean(ord); slope=(oc.'*(stack-mean(stack,1)))/sum(oc.^2);
    slope=movmean(slope,31); grid=profiles(idx(1)).mag.grid;
    masks=blind406.regionMasks(grid,cfg); use=masks.analysis;
    moment=blind406.fourPointMoment(grid,cfg);
    x=grid(use); y=slope(use).'; m=moment(use);
    rMoment=safePearson(y,m); r2Linear=fitR2([ones(numel(x),1),x],y);
    r2Moment=fitR2([ones(numel(x),1),x,m],y);
    r2Quadratic=fitR2([ones(numel(x),1),x,x.^2],y);
    momentWins=r2Moment>r2Quadratic;
    status="WARN_DRIFT_COMPETES"; if momentWins, status="SUPPORTIVE_ONLY"; end
    shapeRows(end+1,:)={cycles(ci),numel(idx),rMoment,r2Linear,r2Moment,r2Quadratic, ...
        r2Moment-r2Linear,status,momentWins,all(arrayfun(@(p) p.mag.repeatabilityEligible,profiles(idx)))}; %#ok<AGROW>
end

stageFeatures=table(cycle,stage,ordinal,magStatus,etpStatus,magEligible,magRepeat, ...
    F1,F1delta,F1equal,F4,F5,E1,E2,E3,E4,E5,E6,EStatic,EAmplitude,EPhase,EDirect, ...
    goodETP,temp0,temp1,'VariableNames',{'cycle_id','stage_id','stage_ordinal', ...
    'mag_qc_status','etp_qc_status','mag_feature_eligible','mag_repeatability_eligible', ...
    'MAG_F1_DW_Q90','MAG_F1_delta_S0','MAG_F1_equal_legacy','MEM_F4_ZSD', ...
    'MAG_F5_H1','ETP_E1_CDIFF','ETP_E2_MOMENT','ETP_E3_HEADSUP','ETP_E4_CHROUGH', ...
    'ETP_E5_WELD','ETP_E6_OUT','ETP_ESTATIC','ETP_EAmplitude','ETP_EPhase', ...
    'ETP_EDirect','ETP_good_channels','ETP_temperature0_C','ETP_temperature1_C'});
stageFeatures.MEM_temperature_C=magTempMEM;
stageFeatures.remanence_temperature_C=magTempRem;
f2Physical=cell2table(physicalRows,'VariableNames',{'cycle_id','stage_id','stage_ordinal', ...
    'physical_column_within_remanence','contrast','repeatability_eligible'});
f2Circ=cell2table(circRows,'VariableNames',{'cycle_id','stage_id','stage_ordinal', ...
    'circumferential_position','contrast','repeatability_eligible'});
windowFeatures=cell2table(windowRows,'VariableNames',{'feature_id','cycle_id','stage_id','stage_ordinal', ...
    'configuration','left_shift','right_shift','half_width','feature_value'});
etpChannels=cell2table(etpRows,'VariableNames',{'cycle_id','stage_id','stage_ordinal', ...
    'channel','good_from_S0','E1_channel','EDirect_channel','S0_reference_MAD'});
shapeQC=cell2table(shapeRows,'VariableNames',{'cycle_id','stage_count','slope_vs_moment_r', ...
    'linear_R2','moment_R2','quadratic_R2','moment_incremental_R2','status', ...
    'moment_beats_quadratic','all_stages_repeatability_eligible'});
end

function harmonic=firstHarmonic(circ)
theta=2*pi*(0:9)/10; centered=circ-mean(circ,2,'omitnan');
co=0.2*(centered*cos(theta(:))); si=0.2*(centered*sin(theta(:)));
harmonic=hypot(co,si);
end

function [good,qc]=goodEtpChannels(z0,amp0,grid,masks)
reference=masks.leftReference|masks.rightReference;
residual=z0-complexReferenceBaseline(z0,grid,masks);
center=complexMedian(residual(reference,:),1);
scale=1.4826*median(abs(residual(reference,:)-center),1,'omitnan');
ampMedian=median(amp0(masks.analysis,:),1,'omitnan');
ampRange=max(amp0(masks.analysis,:),[],1)-min(amp0(masks.analysis,:),[],1);
good=all(isfinite(z0),1)&ampMedian>1e-6&scale>1e-9&ampMedian<5000&ampRange>1e-6;
qc=struct('scale',scale,'amplitudeMedian',ampMedian,'amplitudeRange',ampRange);
end

function bundle=computeEtpBundle(z,amp,grid,masks,good,cfg)
[nStage,nGrid,nChannel]=size(z);
residual=complex(zeros(size(z))); ampResidual=zeros(size(amp)); phaseResidual=zeros(size(amp));
for s=1:nStage
    zs=squeeze(z(s,:,:)); as=squeeze(amp(s,:,:));
    residual(s,:,:)=zs-complexReferenceBaseline(zs,grid,masks);
    ampResidual(s,:,:)=as-realReferenceBaseline(as,grid,masks);
    ph=unwrap(angle(zs),[],1); phaseResidual(s,:,:)=ph-realReferenceBaseline(ph,grid,masks);
end
reference=masks.leftReference|masks.rightReference;
r0=squeeze(residual(1,reference,:)); r0center=complexMedian(r0,1);
sigmaC=scaleFloor(1.4826*median(abs(r0-r0center),1,'omitnan'));
a0=squeeze(ampResidual(1,reference,:)); sigmaA=scaleFloor(1.4826*median(abs(a0-median(a0,1,'omitnan')),1,'omitnan'));
p0=squeeze(phaseResidual(1,reference,:)); sigmaP=scaleFloor(1.4826*median(abs(p0-median(p0,1,'omitnan')),1,'omitnan'));
qC=abs(residual-residual(1,:,:))./reshape(sigmaC,1,1,[]);
qA=abs(ampResidual-ampResidual(1,:,:))./reshape(sigmaA,1,1,[]);
qP=abs(phaseResidual-phaseResidual(1,:,:))./reshape(sigmaP,1,1,[]);
e1c=zeros(nStage,nChannel); eac=e1c; epc=e1c;
for s=1:nStage
    e1c(s,:)=channelContrast(squeeze(qC(s,:,:)),grid,masks);
    eac(s,:)=channelContrast(squeeze(qA(s,:,:)),grid,masks);
    epc(s,:)=channelContrast(squeeze(qP(s,:,:)),grid,masks);
end
moment=blind406.fourPointMoment(grid,cfg); analysis=masks.analysis&abs(grid)>cfg.spatial.weldExclusionHalfWidth;
mv=moment(analysis)-mean(moment(analysis)); denom=sum(mv.^2); e2c=zeros(nStage,nChannel);
e3c=zeros(nStage,nChannel); head=masks.leftHead|masks.rightHead; support=masks.leftSupport|masks.rightSupport;
for s=1:nStage
    q=squeeze(qC(s,analysis,:)); q=q-mean(q,1,'omitnan'); e2c(s,:)=(mv.'*q)/denom;
    qs=squeeze(qC(s,:,:)); e3c(s,:)=median(qs(head,:),1,'omitnan')-median(qs(support,:),1,'omitnan');
end
rough=sqrt(mean(diff(amp,1,3).^2,3)); [wL,wR]=referenceWeights(grid,masks);
e4=median(rough(:,masks.target),2,'omitnan')-wL*median(rough(:,masks.leftReference),2,'omitnan')-wR*median(rough(:,masks.rightReference),2,'omitnan');
e4=e4-e4(1);
weldResponse=squeeze(median(median(qC(:,masks.weld,good),2,'omitnan'),3,'omitnan'));
outside=wL*squeeze(median(median(qC(:,masks.leftReference,good),2,'omitnan'),3,'omitnan'))+ ...
    wR*squeeze(median(median(qC(:,masks.rightReference,good),2,'omitnan'),3,'omitnan'));
e5=weldResponse-outside; e6=outside;
static=abs(residual)./reshape(sigmaC,1,1,[]); esc=zeros(nStage,nChannel);
direct=complex(zeros(nStage,nChannel));
for s=1:nStage
    esc(s,:)=channelContrast(squeeze(static(s,:,:)),grid,masks);
    zs=squeeze(z(s,:,:)); L=complexMedian(zs(masks.leftReference,:),1); R=complexMedian(zs(masks.rightReference,:),1);
    C=complexMedian(zs(masks.target,:),1); direct(s,:)=C-wL*L-wR*R;
end
directDelta=abs(direct-direct(1,:))./sigmaC;
bundle=struct('E1',median(e1c(:,good),2,'omitnan'),'E2',median(e2c(:,good),2,'omitnan'), ...
    'E3',median(e3c(:,good),2,'omitnan'),'E4',e4,'E5',e5,'E6',e6, ...
    'EStatic',median(esc(:,good),2,'omitnan'),'EAmplitude',median(eac(:,good),2,'omitnan'), ...
    'EPhase',median(epc(:,good),2,'omitnan'),'EDirect',median(directDelta(:,good),2,'omitnan'), ...
    'E1Channels',e1c,'EDirectChannels',directDelta,'qComplex',qC);
end

function baseline=complexReferenceBaseline(z,grid,masks)
L=complexMedian(z(masks.leftReference,:),1); R=complexMedian(z(masks.rightReference,:),1);
xL=median(grid(masks.leftReference)); xR=median(grid(masks.rightReference)); f=(grid-xL)/(xR-xL);
baseline=L+f.*(R-L);
end
function baseline=realReferenceBaseline(z,grid,masks)
L=median(z(masks.leftReference,:),1,'omitnan'); R=median(z(masks.rightReference,:),1,'omitnan');
xL=median(grid(masks.leftReference)); xR=median(grid(masks.rightReference)); f=(grid-xL)/(xR-xL);
baseline=L+f.*(R-L);
end
function value=complexMedian(z,dim)
value=median(real(z),dim,'omitnan')+1i*median(imag(z),dim,'omitnan');
end
function s=scaleFloor(s)
positive=s(isfinite(s)&s>1e-9); if isempty(positive), floorValue=1; else, floorValue=median(positive)/10; end
s=max(s,max(floorValue,1e-9));
end
function c=channelContrast(q,grid,masks)
[wL,wR]=referenceWeights(grid,masks);
c=median(q(masks.target,:),1,'omitnan')-wL*median(q(masks.leftReference,:),1,'omitnan')-wR*median(q(masks.rightReference,:),1,'omitnan');
end
function [wL,wR]=referenceWeights(grid,masks)
xL=median(grid(masks.leftReference)); xC=median(grid(masks.target)); xR=median(grid(masks.rightReference));
wL=(xR-xC)/(xR-xL); wR=1-wL;
end
function r=safePearson(x,y)
if numel(x)<2||std(x)<1e-12||std(y)<1e-12, r=NaN; else, C=corrcoef(x,y); r=C(1,2); end
end
function r2=fitR2(X,y)
b=X\y; pred=X*b; den=sum((y-mean(y)).^2); if den<1e-12, r2=NaN; else, r2=1-sum((y-pred).^2)/den; end
end
