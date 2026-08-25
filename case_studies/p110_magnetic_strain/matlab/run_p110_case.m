%% P110 reviewed magnetic + strain case
% Starts from the frozen 10-row reviewed derived table. It does not claim to
% reconstruct those rows independently from all raw files in the Release.

clearvars;
close all;
clc;

matlabDir = fileparts(mfilename('fullpath'));
caseRoot = fileparts(matlabDir);
tablePath = fullfile(caseRoot, 'results', 'reviewed', 'p110_multisensor_mem_real.csv');
outputDir = fullfile(caseRoot, 'runtime');
if ~isfolder(outputDir)
    mkdir(outputDir);
end

T = readtable(tablePath, 'VariableNamingRule', 'preserve');
expectedNames = {'run_id','stage_mm','stress_mpa','q60_delta','q70_delta', ...
    'q75_delta','q80_delta','sensor_n'};
assert(isequal(T.Properties.VariableNames, expectedNames), 'Unexpected table columns.');
assert(height(T) == 10, 'Expected ten reviewed rows.');
assert(all(T.sensor_n == 5), 'Expected five preselected sensors per row.');

runIds = {'mem_r1','mem_r2'};
featureNames = {'q60_delta','q70_delta','q75_delta','q80_delta'};
expectedStages = [0 20 40 50 60];
slopes = zeros(numel(featureNames), numel(runIds));
rSquared = zeros(numel(featureNames), numel(runIds));
spearmanRho = zeros(numel(featureNames), numel(runIds));

for r = 1:numel(runIds)
    G = sortrows(T(strcmp(string(T.run_id), runIds{r}), :), 'stage_mm');
    assert(isequal(G.stage_mm', expectedStages), '%s stage mapping changed.', runIds{r});
    assert(G.stress_mpa(1) == 0, '%s stress baseline changed.', runIds{r});
    assert(all(diff(G.stress_mpa) > 0), '%s stress is not strictly increasing.', runIds{r});
    for f = 1:numel(featureNames)
        y = G.(featureNames{f});
        assert(y(1) == 0 && all(diff(y) > 0), ...
            '%s/%s no longer preserves the reviewed ordering.', runIds{r}, featureNames{f});
        p = polyfit(G.stress_mpa, y, 1);
        yFit = polyval(p, G.stress_mpa);
        slopes(f, r) = p(1);
        rSquared(f, r) = 1 - sum((y-yFit).^2) / sum((y-mean(y)).^2);
        spearmanRho(f, r) = localSpearman(G.stress_mpa, y);
    end
end

slopeRatio = max(slopes, [], 2) ./ min(slopes, [], 2);
minSpearman = min(spearmanRho, [], 2);
allowedUse = repmat("relative_order_candidate_only", numel(featureNames), 1);
metrics = table(string(featureNames)', minSpearman, slopes(:,1), slopes(:,2), ...
    slopeRatio, rSquared(:,1), rSquared(:,2), allowedUse, ...
    'VariableNames', {'feature_id','min_within_run_spearman', ...
    'mem_r1_slope_count_per_mpa','mem_r2_slope_count_per_mpa','slope_ratio', ...
    'mem_r1_r_squared','mem_r2_r_squared','allowed_use'});
writetable(metrics, fullfile(outputDir, 'feature_metrics_matlab.csv'));

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1400 900]);
tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
colors = [0.090 0.392 0.671; 0.851 0.373 0.008];

ax1 = nexttile;
hold(ax1, 'on');
ax2 = nexttile;
hold(ax2, 'on');
for r = 1:numel(runIds)
    G = sortrows(T(strcmp(string(T.run_id), runIds{r}), :), 'stress_mpa');
    plot(ax1, G.stress_mpa, G.q70_delta, 'o-', 'LineWidth', 2.2, ...
        'Color', colors(r,:), 'DisplayName', strrep(runIds{r}, '_', '\_'));
    plot(ax2, G.stress_mpa/max(G.stress_mpa), G.q70_delta/max(G.q70_delta), ...
        'o-', 'LineWidth', 2.2, 'Color', colors(r,:), ...
        'DisplayName', strrep(runIds{r}, '_', '\_'));
end
xlabel(ax1, 'Strain-gauge-derived bending stress [MPa]');
ylabel(ax1, 'Five-sensor median \DeltaQ70 [count]');
title(ax1, 'Real scale: same-run zero-load reference');
legend(ax1, 'Location', 'northwest');
plot(ax2, [0 1], [0 1], 'k--', 'DisplayName', 'identity');
xlabel(ax2, 'Normalized strain-gauge stress');
ylabel(ax2, 'Normalized magnetic \DeltaQ70');
title(ax2, 'Within-run normalized response');
legend(ax2, 'Location', 'northwest');

ax3 = nexttile;
bar(ax3, categorical({'Q60','Q70','Q75','Q80'}), minSpearman, ...
    'FaceColor', [0.165 0.616 0.561]);
yline(ax3, 0.9, 'k--');
ylim(ax3, [0 1.05]);
ylabel(ax3, 'Minimum within-run Spearman \rho');
title(ax3, 'Reviewed stress-order reproducibility');

ax4 = nexttile;
bar(ax4, categorical({'Q60','Q70','Q75','Q80'}), slopeRatio, ...
    'FaceColor', [0.914 0.769 0.416]);
yline(ax4, 1.0, 'k--');
ylabel(ax4, 'Larger/smaller calibration slope');
title(ax4, 'Cross-run scale instability (not hidden)');
grid(ax1, 'on'); grid(ax2, 'on'); grid(ax3, 'on'); grid(ax4, 'on');
sgtitle(fig, {'REAL P110 EXP2 — reviewed 6 o''clock complete-bilateral-MEM subset', ...
    'Ordering repeats; absolute scale does not transfer'});
exportgraphics(fig, fullfile(outputDir, 'real_p110_magnetic_case_matlab.png'), 'Resolution', 180);
close(fig);

summary = struct();
summary.source = 'reviewed_frozen_derived_real_P110_evidence';
summary.rows = height(T);
summary.runs = runIds;
summary.stage_mm_each_run = expectedStages;
summary.direct_mpa_prediction_enabled = false;
summary.allowed_use = 'same_pipe_same_configuration_relative_order_candidate_only';
summary.metrics = table2struct(metrics);
fid = fopen(fullfile(outputDir, 'analysis_summary_matlab.json'), 'w', 'n', 'UTF-8');
assert(fid >= 0, 'Could not open MATLAB summary output.');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(summary, 'PrettyPrint', true));
disp(metrics);
disp('P110 reviewed case completed. Direct MPa output remains disabled.');

function rho = localSpearman(x, y)
    x = x(:); y = y(:);
    [~, orderX] = sort(x);
    [~, orderY] = sort(y);
    rankX = zeros(size(x)); rankX(orderX) = 1:numel(x);
    rankY = zeros(size(y)); rankY(orderY) = 1:numel(y);
    C = corrcoef(rankX, rankY);
    rho = C(1,2);
end
