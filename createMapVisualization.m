%added so visible on path

function createMapVisualization(sessions, hive, ax)
% Draw the full map:
%   - Bearing rays from each observation point (unit direction vectors)
%   - Pairwise intersection points of all rays
%   - Least-squares best-fit hive location
%   - Observation point markers with session labels
%
% Local ENU coordinate system centred on the map centroid.

    nObs    = length(sessions);
    obsLats = arrayfun(@(s) s.gpsCoords(1), sessions);
    obsLons = arrayfun(@(s) s.gpsCoords(2), sessions);
    brgs    = arrayfun(@(s) s.avgBearing,   sessions);
    confs   = arrayfun(@(s) s.confidence,   sessions);

    % Common ENU origin = centroid of all points including hive
    cLat = mean([obsLats, hive(1)]);
    cLon = mean([obsLons, hive(2)]);

    [obsX, obsY]   = ll2xy(obsLats, obsLons, cLat, cLon);
    [hiveX, hiveY] = ll2xy(hive(1), hive(2), cLat, cLon);

    cla(ax);  hold(ax, 'on');
    setAxesBounds(ax, [obsX, hiveX], [obsY, hiveY]);

    RAY_LEN = 5000;  % metres - length of drawn bearing rays

    % ── 1. Bearing rays (r_i(t) = p_i + t*v_i) ──────────────────────────
    % Store endpoints for intersection calculation
    rayEnds = zeros(nObs, 2);
    for i = 1:nObs
        % Unit direction vector: v = [sin(beta), cos(beta)]
        v      = [sind(brgs(i)), cosd(brgs(i))];
        endPt  = [obsX(i), obsY(i)] + RAY_LEN * v;
        rayEnds(i,:) = endPt;

        col = confColor(confs(i));
        lw  = 1.5 + 2 * confs(i);
        plot(ax, [obsX(i), endPt(1)], [obsY(i), endPt(2)], ...
             '-', 'Color', col, 'LineWidth', lw);
        drawArrow(ax, obsX(i), obsY(i), endPt(1), endPt(2), col, 40);
    end

    % ── 2. Pairwise intersections (all ray pairs) ──────────────────────
    % Line i: p = P_i + t * v_i
    % Solve: [v_i, -v_j] * [t; u] = P_j - P_i  (2x2 linear system)
    EPS_PARALLEL = 1e-10;
    intersections = [];
    for i = 1:nObs
        for j = i+1:nObs
            p1 = [obsX(i); obsY(i)];
            p2 = [obsX(j); obsY(j)];
            v1 = [sind(brgs(i)); cosd(brgs(i))];
            v2 = [sind(brgs(j)); cosd(brgs(j))];

            Amat = [v1, -v2];
            detA = det(Amat);
            if abs(detA) < EPS_PARALLEL, continue; end  % near-parallel rays

            tu   = Amat \ (p2 - p1);
            t    = tu(1);
            if t < 0, continue; end   % intersection behind observation point

            pInt = p1 + t * v1;
            intersections(end+1, :) = pInt'; %#ok<AGROW>
        end
    end

    if ~isempty(intersections)
        plot(ax, intersections(:,1), intersections(:,2), 'bx', ...
             'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', 'Ray Intersections');
    end

    % ── 3. Observation point markers ──────────────────────────────────
    for i = 1:nObs
        plot(ax, obsX(i), obsY(i), 'o', 'MarkerSize', 12, ...
             'MarkerFaceColor', [0.2 0.4 0.8], 'MarkerEdgeColor', 'white', 'LineWidth', 2);
        text(ax, obsX(i)+30, obsY(i)+30, sessions(i).name, ...
             'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.7]);
    end

    % ── 4. Best-fit hive (p*) ─────────────────────────────────────────
    plot(ax, hiveX, hiveY, 'p', 'MarkerSize', 28, ...
         'MarkerFaceColor', [0.2 0.8 0.2], 'MarkerEdgeColor', 'black', 'LineWidth', 2);
    text(ax, hiveX+40, hiveY+40, sprintf('Best-fit Hive\n%.6f, %.6f', hive(1), hive(2)), ...
         'FontSize', 11, 'FontWeight', 'bold', 'Color', [0 0.5 0], ...
         'BackgroundColor', [1 1 1 0.85]);

    % ── Axis formatting ───────────────────────────────────────────────
    axis(ax, 'equal');  grid(ax, 'on');
    xlabel(ax, 'East (m)',  'FontWeight', 'bold');
    ylabel(ax, 'North (m)', 'FontWeight', 'bold');
    title(ax, sprintf('B-TRAC: Estimated Hive Location [%.6f, %.6f]', hive(1), hive(2)), ...
          'FontSize', 12, 'FontWeight', 'bold');

    % Legend
    legend(ax, {'Bearing Ray','','Pairwise Intersection','Observation Point','','Best-fit Hive'}, ...
           'Location', 'bestoutside', 'FontSize', 9);

    addScaleBar(ax);
    addCompassRose(ax);
    hold(ax, 'off');
end

function [E, N] = ll2xy(lat, lon, rLat, rLon)
% Convert lat/lon (degrees) to local ENU metres.
%   E = R * (lambda - lambda_0) * cos(phi_0)
%   N = R * (phi - phi_0)
    R = 6378137;   % WGS84 semi-major axis (metres)
    E = R * deg2rad(lon  - rLon) * cosd(rLat);
    N = R * deg2rad(lat  - rLat);
end

function [lat, lon] = xy2ll(E, N, rLat, rLon)
    R   = 6378137;
    lat = rLat + rad2deg(N / R);
    lon = rLon + rad2deg(E / (R * cosd(rLat)));
end

function setAxesBounds(ax, xs, ys)
    xr = max(xs) - min(xs);  yr = max(ys) - min(ys);
    if xr < 1, xr = 500; end
    if yr < 1, yr = 500; end
    p = 0.25;
    xlim(ax, [min(xs)-p*xr,  max(xs)+p*xr]);
    ylim(ax, [min(ys)-p*yr,  max(ys)+p*yr]);
    ax.Color     = [0.97 0.97 0.97];
    ax.GridColor = [0.80 0.80 0.80];
    ax.GridAlpha = 0.5;
end

function col = confColor(c)
    % Red (low) -> Yellow -> Green (high confidence)
    if c < 0.5, col = [1, 2*c, 0]; else, col = [2*(1-c), 1, 0]; end
end

function drawArrow(ax, x1, y1, x2, y2, col, sz)
    ang = atan2(y2-y1, x2-x1);  a = 25*pi/180;
    lx = x2 - sz*cos(ang-a);  ly = y2 - sz*sin(ang-a);
    rx = x2 - sz*cos(ang+a);  ry = y2 - sz*sin(ang+a);
    patch(ax, [x2,lx,rx], [y2,ly,ry], col, 'EdgeColor', col, 'LineWidth', 1.5);
end

function drawCircle(ax, cx, cy, r, col)
    t = linspace(0, 2*pi, 60);
    plot(ax, cx + r*cos(t), cy + r*sin(t), '--', 'Color', col, 'LineWidth', 1.5);
end

function addScaleBar(ax)
    xl = xlim(ax);  yl = ylim(ax);
    % Pick a round scale bar length (~10% of plot width)
    rawLen = 0.10 * (xl(2) - xl(1));
    mag    = 10^floor(log10(rawLen));
    barLen = round(rawLen / mag) * mag;

    bx = xl(1) + 0.04*(xl(2)-xl(1));
    by = yl(1) + 0.04*(yl(2)-yl(1));
    plot(ax, [bx, bx+barLen], [by, by], 'k-', 'LineWidth', 3);
    if barLen >= 1000
        label = sprintf('%.0f km', barLen/1000);
    else
        label = sprintf('%.0f m', barLen);
    end
    text(ax, bx+barLen/2, by - 0.02*(yl(2)-yl(1)), label, ...
         'FontSize', 9, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1 0.8]);
end

function addCompassRose(ax)
    xl = xlim(ax);  yl = ylim(ax);
    rx  = xl(2) - 0.10*(xl(2)-xl(1));
    ry  = yl(2) - 0.13*(yl(2)-yl(1));
    sz  = 0.06*(yl(2)-yl(1));

    plot(ax, [rx,rx], [ry, ry+sz], 'k-', 'LineWidth', 2);
    patch(ax, [rx, rx-sz/4, rx+sz/4], [ry+sz, ry+sz-sz/3, ry+sz-sz/3], 'k');
    text(ax, rx, ry+sz+sz/3, 'N', 'FontSize', 11, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1 0.8]);
    plot(ax, [rx-sz/2, rx+sz/2], [ry, ry], 'k-', 'LineWidth', 1);
    text(ax, rx+sz/2+sz/4, ry, 'E', 'FontSize', 9, 'FontWeight', 'bold', ...
         'BackgroundColor', [1 1 1 0.8]);
    text(ax, rx-sz/2-sz/4, ry, 'W', 'FontSize', 9, 'FontWeight', 'bold', ...
         'BackgroundColor', [1 1 1 0.8]);
end