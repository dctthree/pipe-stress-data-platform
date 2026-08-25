function [profile, qc] = alignMagneticStage(raw, cfg, cycleId, stageId, sourceNote)
%ALIGNMAGNETICSTAGE Three-anchor registration and fail-closed stage QC.

landmark = blind406.detectMagneticLandmarks(raw.eventScore, cfg);
n = numel(raw.sampleIndex);
coordinate = nan(n,1);
left = (landmark.entry:landmark.weld).';
right = (landmark.weld:landmark.exit).';
coordinate(left) = (left-landmark.weld)/max(landmark.weld-landmark.entry,1);
coordinate(right) = (right-landmark.weld)/max(landmark.exit-landmark.weld,1);
grid = linspace(-1,1,cfg.spatial.magneticGridPoints).';
valid = isfinite(coordinate);

profile = struct();
profile.grid = grid;
profile.remXQ90 = interpolate(raw.remXQ90, coordinate, valid, grid);
profile.remXMedian = interpolate(raw.remXMedian, coordinate, valid, grid);
profile.remColumnMedian = interpolate(raw.remColumnMedian, coordinate, valid, grid);
profile.remCircMedian = interpolate(raw.remCircMedian, coordinate, valid, grid);
profile.memZStd = interpolate(raw.memZStd, coordinate, valid, grid);
profile.eventScoreRaw = raw.eventScore;
profile.sampleIndexRaw = raw.sampleIndex;
profile.landmark = landmark;

knownWarning = string(cycleId)==string(cfg.landmarks.knownWarnCycle) && ...
    string(stageId)==string(cfg.landmarks.knownWarnStage);
spanPass = landmark.spanRelativeDeviation <= cfg.landmarks.allowedSpanRelativeDeviation;
legacyPass = landmark.legacyMaxDifferenceFraction <= ...
    cfg.landmarks.maximumLegacyDifferenceFraction;
ratioPass = landmark.leftRightRatio >= cfg.landmarks.minimumLeftRightSpanRatio && ...
    landmark.leftRightRatio <= cfg.landmarks.maximumLeftRightSpanRatio;
saturationPass = raw.remXSaturationFraction < ...
    cfg.quality.maximumRemanenceXSaturationFraction;
orderPass = landmark.entry < landmark.weld && landmark.weld < landmark.exit;
hardPass = spanPass && saturationPass && orderPass;
if ~hardPass
    status = "REJECT";
elseif knownWarning || strlength(strtrim(string(sourceNote)))>0 || ~legacyPass || ~ratioPass
    status = "WARN";
else
    status = "PASS";
end
profile.featureEligible = status ~= "REJECT";
profile.repeatabilityEligible = status == "PASS";

qc = struct();
qc.cycle_id = string(cycleId); qc.stage_id = string(stageId);
qc.status = status; qc.known_operator_warning = knownWarning;
qc.source_note = string(sourceNote);
qc.rows = n; qc.entry = landmark.entry; qc.weld = landmark.weld;
qc.exit = landmark.exit; qc.in_pipe_span = landmark.inPipeSpan;
qc.left_right_ratio = landmark.leftRightRatio;
qc.span_relative_deviation = landmark.spanRelativeDeviation;
qc.legacy_max_difference_fraction = landmark.legacyMaxDifferenceFraction;
qc.remanence_x_saturation_fraction = raw.remXSaturationFraction;
qc.span_pass = spanPass; qc.legacy_pass = legacyPass; qc.ratio_pass = ratioPass;
qc.saturation_pass = saturationPass; qc.feature_eligible = profile.featureEligible;
qc.repeatability_eligible = profile.repeatabilityEligible;
qc.mem_temperature_C = raw.memTemperatureMedian;
qc.remanence_temperature_C = raw.remTemperatureMedian;
end

function result = interpolate(values, coordinate, valid, grid)
values = double(values);
if isvector(values)
    result = interp1(coordinate(valid),values(valid),grid,'linear');
else
    result = zeros(numel(grid),size(values,2));
    for j=1:size(values,2)
        result(:,j)=interp1(coordinate(valid),values(valid,j),grid,'linear');
    end
end
end
