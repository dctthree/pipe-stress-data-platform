function [profiles, stageQC, fragmentQC, cacheMeta] = prepareProfiles(manifest, cfg)
%PREPAREPROFILES Build or load compact registered profiles for all 17 pulls.

fingerprint=sourceFingerprint(manifest,cfg);
cacheFile=char(cfg.cacheFile);
if isfile(cacheFile) && ~logical(cfg.forceRebuildCache)
    loaded=load(cacheFile,'profiles','stageQC','fragmentQC','cacheMeta');
    if isfield(loaded,'cacheMeta') && string(loaded.cacheMeta.sourceFingerprint)==fingerprint && ...
            string(loaded.cacheMeta.schemaVersion)=="blind406_profile_cache_v2_code_bound"
        profiles=loaded.profiles;stageQC=loaded.stageQC;fragmentQC=loaded.fragmentQC;cacheMeta=loaded.cacheMeta;
        fprintf('[blind406] Reused verified profile cache: %s\n',cacheFile);
        return
    end
end

mag=manifest(manifest.Modality=="MAGNETIC"&manifest.Available,:);
etp=manifest(manifest.Modality=="ETP"&manifest.Available,:);
keys=intersect(mag.CycleID+"_"+mag.StageID,etp.CycleID+"_"+etp.StageID,'stable');
assert(numel(keys)==17,'Blind406:StagePairing','Expected 17 matched magnetic/ETP stage packets, got %d.',numel(keys));

empty=struct('cycle_id',"",'stage_id',"",'stage_ordinal',NaN,'source_note',"", ...
    'mag',struct(),'magQC',struct(),'etpComplex',[],'etpAmplitude',[],'etpGrid',[], ...
    'etpEventScore',[],'etpEvent',struct(),'etpQC',struct());
profiles=repmat(empty,numel(keys),1);
magQcRows=cell(0,22); etpQcRows=cell(0,22); magFrag=table(); etpFragRows=cell(0,12);

for i=1:numel(keys)
    parts=split(keys(i),"_"); cycle=parts(1); stage=parts(2);
    mr=mag(mag.CycleID==cycle&mag.StageID==stage,:);
    er=etp(etp.CycleID==cycle&etp.StageID==stage,:);
    fprintf('[blind406] [%d/%d] %s/%s magnetic\n',i,numel(keys),cycle,stage);
    raw=blind406.readMagneticStage(mr,Verbose=false);
    [aligned,mqc]=blind406.alignMagneticStage(raw,cfg,cycle,stage,mr.SourceNote);
    fprintf('[blind406] [%d/%d] %s/%s ETP\n',i,numel(keys),cycle,stage);
    [ep,eqraw]=blind406.readEtpStage(er.StageFolder,cfg);
    [eqc,etpStatus]=classifyEtp(ep,eqraw,cfg,cycle,stage);

    profiles(i).cycle_id=cycle;profiles(i).stage_id=stage;profiles(i).stage_ordinal=mr.StageOrdinal;
    profiles(i).source_note=mr.SourceNote;profiles(i).mag=aligned;profiles(i).magQC=mqc;
    profiles(i).etpComplex=ep.complexProfile;profiles(i).etpAmplitude=ep.amplitudeProfile;
    profiles(i).etpGrid=ep.grid;profiles(i).etpEventScore=ep.eventScore;profiles(i).etpEvent=ep.event;
    profiles(i).etpQC=eqc;profiles(i).etpQC.status=etpStatus;

    magQcRows(end+1,:)={cycle,stage,mr.StageOrdinal,mqc.status,mqc.source_note,mqc.rows, ...
        mqc.entry,mqc.weld,mqc.exit,mqc.in_pipe_span,mqc.left_right_ratio, ...
        mqc.span_relative_deviation,mqc.legacy_max_difference_fraction, ...
        mqc.remanence_x_saturation_fraction,mqc.mem_temperature_C,mqc.remanence_temperature_C, ...
        raw.qc.fragmentCount,raw.qc.allFragmentsContinuous,raw.qc.hasAllowedShortFinalFragment, ...
        mqc.feature_eligible,mqc.repeatability_eligible,mqc.known_operator_warning}; %#ok<AGROW>
    etpQcRows(end+1,:)={cycle,stage,mr.StageOrdinal,etpStatus,eqc.total_rows,eqc.csv_files, ...
        eqc.entry_raw_row,eqc.weld_raw_row,eqc.exit_raw_row,eqc.in_pipe_block_span, ...
        eqc.left_right_ratio,eqc.good_structural,eqc.global_clip_fraction,eqc.target_clip_fraction, ...
        eqc.phase_wrap_fraction,eqc.boundary_jump_ratio_max,eqc.temperature0_C,eqc.temperature1_C, ...
        eqc.coder_total_absolute_travel,eqc.warning_count,eqc.failure_count,eqc.feature_eligible}; %#ok<AGROW>

    q=raw.fragmentQC;
    q.cycle_id=repmat(cycle,height(q),1);q.stage_id=repmat(stage,height(q),1);
    q.modality=repmat("MAGNETIC",height(q),1);
    if isempty(magFrag),magFrag=q;else,magFrag=[magFrag;q];end %#ok<AGROW>
    for f=1:eqraw.csvFileCount
        etpFragRows(end+1,:)={"ETP",cycle,stage,f,eqraw.csvFiles(f),eqraw.numericFileStems(f), ...
            eqraw.rowsByFile(f),eqraw.rawColumnsReturnedByReadmatrix(f), ...
            eqraw.numericChunkStemsAreContiguous,eqraw.trailingEmptyCsvFieldTolerated, ...
            eqraw.fileBoundaryComplexJumpRatioMaximum,eqraw.allChunksHaveExpectedRows}; %#ok<AGROW>
    end
    clear raw ep eqraw
end

stageQC=struct();
stageQC.magnetic=cell2table(magQcRows,'VariableNames',{'cycle_id','stage_id','stage_ordinal', ...
    'status','source_note','rows','entry','weld','exit','in_pipe_span','left_right_ratio', ...
    'span_relative_deviation','legacy_max_difference_fraction','remanence_x_saturation_fraction', ...
    'MEM_temperature_C','remanence_temperature_C','fragment_count','fragments_continuous', ...
    'short_final_fragment','feature_eligible','repeatability_eligible','known_operator_warning'});
stageQC.etp=cell2table(etpQcRows,'VariableNames',{'cycle_id','stage_id','stage_ordinal','status', ...
    'total_rows','csv_files','entry_raw_row','weld_raw_row','exit_raw_row','in_pipe_block_span', ...
    'left_right_ratio','structural_pass','global_clip_fraction','target_clip_fraction', ...
    'phase_wrap_fraction','boundary_jump_ratio_max','temperature0_C','temperature1_C', ...
    'coder_total_absolute_travel','warning_count','failure_count','feature_eligible'});
fragmentQC=struct();
fragmentQC.magnetic=magFrag;
fragmentQC.etp=cell2table(etpFragRows,'VariableNames',{'modality','cycle_id','stage_id', ...
    'fragment_index','file_name','numeric_stem','rows','columns_detected','stems_contiguous', ...
    'trailing_empty_tolerated','stage_boundary_jump_ratio_max','all_chunks_expected_rows'});
cacheMeta=struct('schemaVersion',"blind406_profile_cache_v2_code_bound",'sourceFingerprint',fingerprint, ...
    'createdAt',string(datetime('now','TimeZone','local')),'stagePackets',numel(profiles), ...
    'truthUsed',false,'thirdCyclePartial',true);
folder=fileparts(cacheFile);if ~isfolder(folder),mkdir(folder);end
save(cacheFile,'profiles','stageQC','fragmentQC','cacheMeta','-v7.3');
fprintf('[blind406] Created profile cache: %s\n',cacheFile);
end

function [qc,status]=classifyEtp(stage,raw,cfg,cycle,stageId)
masks=blind406.regionMasks(stage.grid,cfg);
amp=stage.amplitudeProfile;
targetClip=mean((amp(masks.target,:)<=1)|(amp(masks.target,:)>=254),'all');
ratio=(stage.event.weldBlock-stage.event.entryBlock)/max(stage.event.exitBlock-stage.event.weldBlock,1);
failureCount=sum(struct2array(raw.failureFlags));
warningCount=sum(struct2array(raw.warningFlags));
if ~raw.passStructural||targetClip>=0.05
    status="REJECT";
elseif targetClip>=0.01||warningCount>0
    status="WARN";
else
    status="PASS";
end
qc=struct('cycle_id',string(cycle),'stage_id',string(stageId),'status',status, ...
    'total_rows',raw.totalRows,'csv_files',raw.csvFileCount, ...
    'entry_raw_row',stage.event.entryRawRowApprox,'weld_raw_row',stage.event.weldRawRowApprox, ...
    'exit_raw_row',stage.event.exitRawRowApprox,'in_pipe_block_span',stage.event.inPipeBlockSpan, ...
    'left_right_ratio',ratio,'good_structural',raw.passStructural, ...
    'global_clip_fraction',raw.amplitudeClipFractionGlobal,'target_clip_fraction',targetClip, ...
    'phase_wrap_fraction',raw.phaseWrapFractionGlobal, ...
    'boundary_jump_ratio_max',raw.fileBoundaryComplexJumpRatioMaximum, ...
    'temperature0_C',raw.temperatureMedianC(1),'temperature1_C',raw.temperatureMedianC(2), ...
    'coder_total_absolute_travel',raw.coder2TotalAbsoluteTravel, ...
    'warning_count',warningCount,'failure_count',failureCount, ...
    'feature_eligible',status~="REJECT");
end

function fingerprint=sourceFingerprint(manifest,cfg)
rows=manifest(manifest.Available,:);
parts=strings(0,1);
for i=1:height(rows)
    files=rows.FragmentFiles{i};
    for j=1:numel(files)
        d=dir(files(j));
        parts(end+1)=rows.Modality(i)+"|"+rows.CycleID(i)+"|"+rows.StageID(i)+"|"+ ...
            string(files(j))+"|"+d.bytes+"|"+sprintf('%.12f',d.datenum); %#ok<AGROW>
    end
end
parts=sort(parts);
codeFiles=[string(which('blind406.readMagneticStage'));string(which('blind406.readEtpStage')); ...
    string(which('blind406.detectMagneticLandmarks'));string(which('blind406.alignMagneticStage')); ...
    string(cfg.configFile)];
for k=1:numel(codeFiles)
    d=dir(codeFiles(k));
    parts(end+1)="IMPLEMENTATION|"+codeFiles(k)+"|"+d.bytes+"|"+sprintf('%.12f',d.datenum); %#ok<AGROW>
end
parts=sort(parts);
payload=strjoin(parts,newline);
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(unicode2native(char(payload),'UTF-8')));
fingerprint=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end
