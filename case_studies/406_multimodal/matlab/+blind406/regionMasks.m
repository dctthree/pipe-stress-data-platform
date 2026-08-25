function masks = regionMasks(grid, cfg, leftShift, rightShift, halfWidth)
%REGIONMASKS Frozen target, reference, fixture and weld masks.

if nargin < 3, leftShift = 0; end
if nargin < 4, rightShift = 0; end
if nargin < 5, halfWidth = cfg.spatial.fixtureHalfWidth; end
grid = grid(:);
s = cfg.spatial;
leftSupport = s.leftSupport + leftShift;
leftHead = s.leftHead + leftShift;
rightHead = s.rightHead + rightShift;
rightSupport = s.rightSupport + rightShift;
masks.target = grid >= leftHead + halfWidth & grid <= rightHead - halfWidth & ...
    abs(grid) > s.weldExclusionHalfWidth;
masks.center = masks.target;
masks.leftReference = grid >= -s.outsideLimit & grid <= leftSupport - halfWidth;
masks.rightReference = grid >= rightSupport + halfWidth & grid <= s.outsideLimit;
masks.leftHead = abs(grid-leftHead) <= halfWidth;
masks.rightHead = abs(grid-rightHead) <= halfWidth;
masks.leftSupport = abs(grid-leftSupport) <= halfWidth;
masks.rightSupport = abs(grid-rightSupport) <= halfWidth;
masks.weld = abs(grid) <= s.weldExclusionHalfWidth;
masks.analysis = abs(grid) <= s.outsideLimit & abs(grid) > 0.045;
assert(any(masks.target) && any(masks.leftReference) && any(masks.rightReference), ...
    'Blind406:EmptyWindow', 'A frozen feature window became empty.');
end
