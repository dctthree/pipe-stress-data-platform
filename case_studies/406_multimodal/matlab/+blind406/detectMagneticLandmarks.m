function landmark = detectMagneticLandmarks(eventScore, cfg)
%DETECTMAGNETICLANDMARKS Locate entry, weld and exit without midpoint slicing.
%   The triplet search is deliberately tolerant of unequal sample spans.  A
%   separate legacy-window detector is retained only as a disagreement QC.

score = double(eventScore(:));
n = numel(score);
assert(n >= 10000, 'Blind406:ShortMagneticStage', ...
    'Magnetic stage has too few samples for landmark detection.');
rz = robustZ(score);
rz = min(max(rz, 0), 20);

local = find(rz(2:end-1) >= rz(1:end-2) & rz(2:end-1) > rz(3:end)) + 1;
if isempty(local)
    error('Blind406:NoMagneticPeaks', 'No local event peaks found.');
end
[~, order] = sort(rz(local), 'descend');
selected = zeros(0,1);
for ii = 1:numel(order)
    p = local(order(ii));
    if rz(p) < 0.35, continue; end
    if isempty(selected) || all(abs(selected-p) >= 450)
        selected(end+1,1) = p; %#ok<AGROW>
    end
    if numel(selected) >= 45, break; end
end
selected = sort(selected);
assert(numel(selected) >= 3, 'Blind406:FewMagneticPeaks', ...
    'Fewer than three separated magnetic event peaks.');

prior = cfg.landmarks.priorMagneticInPipeSpanSamples;
bestObjective = -Inf; secondObjective = -Inf; best = [NaN NaN NaN];
candidateCount = 0;
for ia = 1:numel(selected)-2
    entry = selected(ia);
    for ib = ia+1:numel(selected)-1
        weld = selected(ib);
        for ic = ib+1:numel(selected)
            exitIndex = selected(ic);
            span = exitIndex-entry;
            if span < 0.72*prior || span > 1.28*prior, continue; end
            if entry < round(0.003*n) || exitIndex > round(0.997*n), continue; end
            leftFraction = (weld-entry)/span;
            if leftFraction < 0.28 || leftFraction > 0.72, continue; end
            strength = rz(entry)+rz(weld)+rz(exitIndex);
            spanPenalty = 8*abs(span/prior-1);
            fractionPenalty = 6*abs(leftFraction-0.505);
            boundaryBonus = 0.8*(rz(entry)+rz(exitIndex));
            objective = strength+boundaryBonus-spanPenalty-fractionPenalty;
            candidateCount = candidateCount+1;
            if objective > bestObjective
                secondObjective = bestObjective;
                bestObjective = objective;
                best = [entry weld exitIndex];
            elseif objective > secondObjective
                secondObjective = objective;
            end
        end
    end
end
assert(all(isfinite(best)), 'Blind406:NoMagneticTopology', ...
    'No plausible entry-weld-exit topology found.');
for k = 1:3
    best(k) = refine(score, best(k), 350);
end

legacyEntryRange = max(1,round(0.02*n)):max(2,round(0.28*n));
legacyExitRange = min(n-1,round(0.72*n)):min(n,round(0.98*n));
[~, a] = max(score(legacyEntryRange)); legacyEntry = legacyEntryRange(a);
[~, b] = max(score(legacyExitRange)); legacyExit = legacyExitRange(b);
margin = max(1000, round(0.12*(legacyExit-legacyEntry)));
wStart = legacyEntry+margin; wStop = legacyExit-margin;
if wStop > wStart
    [~, c] = max(score(wStart:wStop)); legacyWeld = wStart+c-1;
else
    legacyWeld = best(2);
end
legacy = [refine(score,legacyEntry,350), refine(score,legacyWeld,350), ...
    refine(score,legacyExit,350)];

span = best(3)-best(1);
leftSpan = best(2)-best(1); rightSpan = best(3)-best(2);
landmark = struct();
landmark.entry = best(1);
landmark.weld = best(2);
landmark.exit = best(3);
landmark.inPipeSpan = span+1;
landmark.leftSpan = leftSpan;
landmark.rightSpan = rightSpan;
landmark.leftRightRatio = leftSpan/max(rightSpan,1);
landmark.leftFraction = leftSpan/max(span,1);
landmark.spanRelativeDeviation = abs(span/prior-1);
landmark.legacyEntry = legacy(1);
landmark.legacyWeld = legacy(2);
landmark.legacyExit = legacy(3);
landmark.legacyMaxDifferenceFraction = max(abs(best-legacy))/max(span,1);
landmark.topologyObjective = bestObjective;
landmark.topologyMargin = bestObjective-secondObjective;
landmark.candidateTriplets = candidateCount;
landmark.eventScore = score;
end

function index = refine(score, center, radius)
first = max(1,center-radius); last = min(numel(score),center+radius);
[~,local] = max(score(first:last)); index = first+local-1;
end

function z = robustZ(x)
center = median(x,'omitnan');
scale = 1.4826*median(abs(x-center),'omitnan');
if ~isfinite(scale) || scale < 1e-12
    scale = std(x,'omitnan');
end
if ~isfinite(scale) || scale < 1e-12, z=zeros(size(x)); else, z=(x-center)/scale; end
end
