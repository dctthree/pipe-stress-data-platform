function result = profileContrast(profile, grid, masks)
%PROFILECONTRAST Median target minus distance-weighted two-side references.

grid = grid(:); profile = profile(:);
xC = median(grid(masks.target));
xL = median(grid(masks.leftReference));
xR = median(grid(masks.rightReference));
wL = (xR-xC)/(xR-xL); wR = 1-wL;
C = median(profile(masks.target), 'omitnan');
L = median(profile(masks.leftReference), 'omitnan');
R = median(profile(masks.rightReference), 'omitnan');
result = struct('center',C,'leftReference',L,'rightReference',R, ...
    'weightLeft',wL,'weightRight',wR, ...
    'distanceWeighted',C-wL*L-wR*R, ...
    'equalWeight',C-0.5*(L+R));
end
