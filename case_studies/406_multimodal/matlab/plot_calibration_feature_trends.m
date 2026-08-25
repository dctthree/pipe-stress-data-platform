function outputFile = plot_calibration_feature_trends(outputFile)
%PLOT_CALIBRATION_FEATURE_TRENDS Redraw the frozen 406 calibration evidence.
% The MPa axis is derived as 206 GPa times median bending strain. It is not
% a load-cell measurement, blind truth, or an independently validated model.

matlabRoot = fileparts(mfilename('fullpath'));
caseRoot = fileparts(matlabRoot);
dataRoot = fullfile(caseRoot,'results','calibration');
if nargin < 1 || strlength(string(outputFile)) == 0
    outputFile = fullfile(caseRoot,'runtime','results','calibration', ...
        '07_physical_contrast_trends_regenerated.png');
end
outputFile = char(outputFile);
if ~isfolder(fileparts(outputFile)), mkdir(fileparts(outputFile)); end

values = readtable(fullfile(dataRoot,'calibration_feature_values.csv'), ...
    'TextType','string','VariableNamingRule','preserve');
metrics = readtable(fullfile(dataRoot,'calibration_feature_metrics.csv'), ...
    'TextType','string','VariableNamingRule','preserve');

featureIDs = [ ...
    "remanence_X_q90_level_central_minus_outside"; ...
    "remanence_X_median_level_heads_minus_supports"; ...
    "MEM_Z_right_support_spatial_std_zero_delta_rms"; ...
    "remanence_X_circ_h1_amplitude_central_minus_outside"];
titles = [ ...
    "Remanence X: central span minus outside supports"; ...
    "Remanence X: loading heads minus supports"; ...
    "MEM Z: right-half-span spatial spread change"; ...
    "Remanence X: central first harmonic minus outside"];

fig = figure('Color','w','Position',[80 80 1500 1000]);
layout = tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
for i = 1:numel(featureIDs)
    rows = values(values.feature_id == featureIDs(i),:);
    rows = sortrows(rows,'stage_ordinal');
    metric = metrics(metrics.feature_id == featureIDs(i),:);
    assert(height(rows) == 7 && height(metric) == 1, ...
        'Blind406:CalibrationEvidence','Unexpected frozen calibration rows for %s.',featureIDs(i));
    anchored = any(strcmpi(string(metric.zero_reference_anchored),["true","1"]));
    selected = true(height(rows),1);
    if anchored, selected = rows.stage_ordinal > 0; end
    x = double(rows.nominal_stress_mpa(selected));
    y = double(rows.feature_value(selected));
    ids = rows.stage_id(selected);
    coefficients = polyfit(x,y,1);
    lineX = linspace(min(x),max(x),100);

    ax = nexttile(layout);
    scatter(ax,x,y,60,'filled','MarkerFaceColor',[0.12 0.47 0.71]); hold(ax,'on');
    plot(ax,lineX,polyval(coefficients,lineX),'Color',[0.20 0.20 0.20],'LineWidth',1.1);
    for j = 1:numel(x)
        text(ax,x(j),y(j),"  " + ids(j),'FontSize',8,'VerticalAlignment','bottom');
    end
    if anchored
        evidenceR = metric.pearson_r_loaded6;
        evidenceP = metric.familywise_maxstat_p_loaded6_all_features;
        evidenceLOO = metric.fixed_feature_loaded6_loo_r_squared;
        scope = "loaded6";
    else
        evidenceR = metric.pearson_r_all7;
        evidenceP = metric.familywise_maxstat_p_all_features;
        evidenceLOO = metric.fixed_feature_loo_r_squared;
        scope = "all7";
    end
    title(ax,sprintf('%s\n%s r=%.3f, max-p=%.3g, LOO R^2=%.3f', ...
        titles(i),scope,double(evidenceR),double(evidenceP),double(evidenceLOO)), ...
        'FontWeight','bold','FontSize',10);
    xlabel(ax,'Strain-derived nominal stress (MPa)');
    ylabel(ax,'Feature value'); grid(ax,'on'); ax.GridAlpha = 0.2;
end
title(layout,'Mechanics-anchored candidate stage features','FontSize',16,'FontWeight','bold');
exportgraphics(fig,outputFile,'Resolution',180);
close(fig);
fprintf('Regenerated frozen calibration figure: %s\n',outputFile);
end
