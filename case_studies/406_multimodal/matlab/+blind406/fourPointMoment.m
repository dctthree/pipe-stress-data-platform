function moment = fourPointMoment(grid, cfg)
%FOURPOINTMOMENT Unit four-point-bending moment template.

grid = grid(:); s = cfg.spatial; moment = zeros(size(grid));
left = grid>s.leftSupport & grid<s.leftHead;
center = grid>=s.leftHead & grid<=s.rightHead;
right = grid>s.rightHead & grid<s.rightSupport;
moment(left) = (grid(left)-s.leftSupport)/(s.leftHead-s.leftSupport);
moment(center) = 1;
moment(right) = (s.rightSupport-grid(right))/(s.rightSupport-s.rightHead);
end
