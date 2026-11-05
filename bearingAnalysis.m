function [avgBearing, confidence] = bearingAnalysis(departureAngles)
% Aggregate individual bearings beta_i into a single session average.
%
%  Report: "Multiple individual bearings collected at a single observation
%  location are aggregated using statistical methods to produce averaged
%  bearings that are more robust than single observations."
%
%  Method: unit-vector mean on the unit circle
%    v_i = [sin(beta_i), cos(beta_i)]
%    v_mean = mean(v_i)
%    avgBearing = atan2(v_mean(1), v_mean(2))  [mod 360]
%
%  Confidence: resultant length R of the unit vectors (0=uniform, 1=perfect)
%  scaled by sample size to penalise small N.

    if isempty(departureAngles)
        avgBearing = NaN;  confidence = 0;  return;
    end

    clean = removeOutliers(departureAngles);

    % Unit vector mean (report: v_i = [sin(beta); cos(beta)])
    r          = deg2rad(clean);
    vE         = mean(sin(r));   % East component
    vN         = mean(cos(r));   % North component
    avgBearing = mod(rad2deg(atan2(vE, vN)), 360);

    % Resultant length R (concentration measure)
    R_len  = sqrt(vE^2 + vN^2);          % in [0, 1]
    n      = length(clean);
    % Confidence: grows with R (tight cluster) and with sample size
    confidence = R_len * (1 - exp(-n / 20));
end


function hive = triangulateHive(sessions)
% Estimate nest location by minimising total perpendicular distance to
% all bearing rays (report least-squares formulation):
%
%   p* = argmin_p  sum_i || (I - v_i * v_i') * (p - p_i) ||^2
%
% This expands to the normal equations:
%   [ sum_i (I - v_i*v_i') ] * p  =  sum_i (I - v_i*v_i') * p_i
%   => A * p = b,   where A = sum_i Pperp_i,  b = sum_i Pperp_i * p_i
%
% Sessions are weighted by their confidence score (higher confidence
% sessions contribute more to the estimate).
%
% Coordinate system: WGS84 local ENU centred on first session (R=6378137 m).

    hive = [];
    if length(sessions) < 2
        warning('triangulateHive: need at least 2 sessions.'); return;
    end

    % Use first session as local ENU origin
    rLat = sessions(1).gpsCoords(1);
    rLon = sessions(1).gpsCoords(2);

    n    = length(sessions);
    I2   = eye(2);
    A    = zeros(2,2);
    b    = zeros(2,1);

    for i = 1:n
        % Convert GPS to local East-North metres (report: E = R*(lambda-lambda0)*cos(phi0))
        [E, N] = ll2xy(sessions(i).gpsCoords(1), sessions(i).gpsCoords(2), rLat, rLon);
        p_i    = [E; N];

        % Direction unit vector from averaged bearing
        % Report: v_i = [sin(beta_i); cos(beta_i)]
        beta  = sessions(i).avgBearing;
        v     = [sind(beta); cosd(beta)];
        v     = v / norm(v);               % ensure unit length

        % Perpendicular projector: Pperp = I - v*v'
        Pperp = I2 - (v * v');

        % Weight by session confidence
        w  = sessions(i).confidence;
        A  = A + w * Pperp;
        b  = b + w * (Pperp * p_i);
    end

    % Solve normal equations
    if rcond(A) < 1e-12
        warning('triangulateHive: poorly conditioned (near-parallel rays). Result may be unreliable.');
    end
    p_best = A \ b;

    % Convert best-fit ENU back to lat/lon
    [hLat, hLon] = xy2ll(p_best(1), p_best(2), rLat, rLon);
    hive = [hLat, hLon];
end

% Moved to its own file
% function createMapVisualization(sessions, hive, ax)
% % Draw the full map:
% %   - Bearing rays from each observation point (unit direction vectors)
% %   - Pairwise intersection points of all rays
% %   - Least-squares best-fit hive location
% %   - Observation point markers with session labels
% %
% % Local ENU coordinate system centred on the map centroid.
% 
%     nObs    = length(sessions);
%     obsLats = arrayfun(@(s) s.gpsCoords(1), sessions);
%     obsLons = arrayfun(@(s) s.gpsCoords(2), sessions);
%     brgs    = arrayfun(@(s) s.avgBearing,   sessions);
%     confs   = arrayfun(@(s) s.confidence,   sessions);
% 
%     % Common ENU origin = centroid of all points including hive
%     cLat = mean([obsLats, hive(1)]);
%     cLon = mean([obsLons, hive(2)]);
% 
%     [obsX, obsY]   = ll2xy(obsLats, obsLons, cLat, cLon);
%     [hiveX, hiveY] = ll2xy(hive(1), hive(2), cLat, cLon);
% 
%     cla(ax);  hold(ax, 'on');
%     setAxesBounds(ax, [obsX, hiveX], [obsY, hiveY]);
% 
%     RAY_LEN = 5000;  % metres - length of drawn bearing rays
% 
%     % ── 1. Bearing rays (r_i(t) = p_i + t*v_i) ──────────────────────────
%     % Store endpoints for intersection calculation
%     rayEnds = zeros(nObs, 2);
%     for i = 1:nObs
%         % Unit direction vector: v = [sin(beta), cos(beta)]
%         v      = [sind(brgs(i)), cosd(brgs(i))];
%         endPt  = [obsX(i), obsY(i)] + RAY_LEN * v;
%         rayEnds(i,:) = endPt;
% 
%         col = confColor(confs(i));
%         lw  = 1.5 + 2 * confs(i);
%         plot(ax, [obsX(i), endPt(1)], [obsY(i), endPt(2)], ...
%              '-', 'Color', col, 'LineWidth', lw);
%         drawArrow(ax, obsX(i), obsY(i), endPt(1), endPt(2), col, 40);
%     end
% 
%     % ── 2. Pairwise intersections (all ray pairs) ──────────────────────
%     % Line i: p = P_i + t * v_i
%     % Solve: [v_i, -v_j] * [t; u] = P_j - P_i  (2x2 linear system)
%     EPS_PARALLEL = 1e-10;
%     intersections = [];
%     for i = 1:nObs
%         for j = i+1:nObs
%             p1 = [obsX(i); obsY(i)];
%             p2 = [obsX(j); obsY(j)];
%             v1 = [sind(brgs(i)); cosd(brgs(i))];
%             v2 = [sind(brgs(j)); cosd(brgs(j))];
% 
%             Amat = [v1, -v2];
%             detA = det(Amat);
%             if abs(detA) < EPS_PARALLEL, continue; end  % near-parallel rays
% 
%             tu   = Amat \ (p2 - p1);
%             t    = tu(1);
%             if t < 0, continue; end   % intersection behind observation point
% 
%             pInt = p1 + t * v1;
%             intersections(end+1, :) = pInt'; %#ok<AGROW>
%         end
%     end
% 
%     if ~isempty(intersections)
%         plot(ax, intersections(:,1), intersections(:,2), 'bx', ...
%              'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', 'Ray Intersections');
%     end
% 
%     % ── 3. Observation point markers ──────────────────────────────────
%     for i = 1:nObs
%         plot(ax, obsX(i), obsY(i), 'o', 'MarkerSize', 12, ...
%              'MarkerFaceColor', [0.2 0.4 0.8], 'MarkerEdgeColor', 'white', 'LineWidth', 2);
%         text(ax, obsX(i)+30, obsY(i)+30, sessions(i).name, ...
%              'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.7]);
%     end
% 
%     % ── 4. Best-fit hive (p*) ─────────────────────────────────────────
%     plot(ax, hiveX, hiveY, 'p', 'MarkerSize', 28, ...
%          'MarkerFaceColor', [0.2 0.8 0.2], 'MarkerEdgeColor', 'black', 'LineWidth', 2);
%     text(ax, hiveX+40, hiveY+40, sprintf('Best-fit Hive\n%.6f, %.6f', hive(1), hive(2)), ...
%          'FontSize', 11, 'FontWeight', 'bold', 'Color', [0 0.5 0], ...
%          'BackgroundColor', [1 1 1 0.85]);
% 
%     % ── Axis formatting ───────────────────────────────────────────────
%     axis(ax, 'equal');  grid(ax, 'on');
%     xlabel(ax, 'East (m)',  'FontWeight', 'bold');
%     ylabel(ax, 'North (m)', 'FontWeight', 'bold');
%     title(ax, sprintf('B-TRAC: Estimated Hive Location [%.6f, %.6f]', hive(1), hive(2)), ...
%           'FontSize', 12, 'FontWeight', 'bold');
% 
%     % Legend
%     legend(ax, {'Bearing Ray','','Pairwise Intersection','Observation Point','','Best-fit Hive'}, ...
%            'Location', 'bestoutside', 'FontSize', 9);
% 
%     addScaleBar(ax);
%     addCompassRose(ax);
%     hold(ax, 'off');
% end

% Moved to its own file
% function exportResults(results, savePath, baseName, ax)
% % Save .mat, map PNG, per-session bearing CSVs, and text summary.
%     save(fullfile(savePath, [baseName '.mat']), 'results');
%     try
%         exportgraphics(ax, fullfile(savePath, [baseName '_map.png']), 'Resolution', 300);
%     catch
%         warning('Map image export failed.');
%     end
%     for i = 1:length(results.sessions)
%         s = results.sessions(i);
%         if s.processed && ~isempty(s.departureAngles)
%             T = table((1:length(s.departureAngles))', s.departureAngles, ...
%                       'VariableNames', {'TrajectoryID', 'Bearing_Degrees'});
%             writetable(T, fullfile(savePath, ...
%                        sprintf('%s_session%d_bearings.csv', baseName, i)));
%         end
%     end
%     writeSummary(results, fullfile(savePath, [baseName '_summary.txt']));
% end


%% =========================================================================
%% CIRCULAR STATISTICS  (internal)
%% =========================================================================

function clean = removeOutliers(angles)
% Remove bearings that deviate > 2.5 * std from the circular mean.
    r    = deg2rad(angles);
    vE   = mean(sin(r));  vN = mean(cos(r));
    med  = mod(rad2deg(atan2(vE, vN)), 360);
    diffs = min(abs(angles - med), 360 - abs(angles - med));
    thr   = 2.5 * std(diffs);
    clean = angles(diffs <= thr);
    if isempty(clean), clean = angles; end  % fallback: keep all
end


%% =========================================================================
%% COORDINATE HELPERS  (WGS84, R = 6378137 m as per report)
%% =========================================================================

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


%% =========================================================================
%% MAP DRAWING HELPERS
%% =========================================================================

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


%% =========================================================================
%% TEXT SUMMARY
%% =========================================================================
%% moved to exportResults since it is used within that function
% function writeSummary(results, filename)
%     fid = fopen(filename, 'w');
%     fprintf(fid, 'B-TRAC ANALYSIS SUMMARY\n=======================\n\n');
%     fprintf(fid, 'Analysis Date: %s\n\n', char(results.analysisDate));
%     if isfield(results,'yoloConfig') && results.yoloConfig.useYOLO
%         fprintf(fid, 'Detection Method : YOLO\n');
%         fprintf(fid, '  Model          : %s\n',   results.yoloConfig.modelPath);
%         fprintf(fid, '  Confidence     : %.2f\n', results.yoloConfig.confidenceThreshold);
%         fprintf(fid, '  Frame sample   : %d\n\n', results.yoloConfig.frameSample);
%     else
%         fprintf(fid, 'Detection Method : Background Subtraction\n\n');
%     end
%     fprintf(fid, 'Triangulation Method: Perpendicular-distance least squares\n');
%     fprintf(fid, '  p* = argmin sum_i || (I - v_i*v_i'') * (p - p_i) ||^2\n\n');
%     fprintf(fid, 'OBSERVATION SESSIONS:\n');
%     for i = 1:length(results.sessions)
%         s = results.sessions(i);
%         fprintf(fid, '\n  Session %d : %s\n',         i, s.name);
%         fprintf(fid, '  Location  : [%.6f, %.6f]\n', s.gpsCoords(1), s.gpsCoords(2));
%         fprintf(fid, '  Camera bearing: %.1f deg\n',  s.compassBearing);
%         if s.processed
%             fprintf(fid, '  Tracks      : %d\n',        length(s.trajectories));
%             fprintf(fid, '  Avg Bearing : %.2f deg\n',  s.avgBearing);
%             fprintf(fid, '  Confidence  : %.1f%%\n',    s.confidence*100);
%         end
%     end
%     if ~isempty(results.estimatedHiveLocation)
%         hl = results.estimatedHiveLocation;
%         fprintf(fid, '\n\nESTIMATED HIVE LOCATION (best-fit p*):\n');
%         fprintf(fid, '  Latitude  : %.8f\n', hl(1));
%         fprintf(fid, '  Longitude : %.8f\n', hl(2));
%         fprintf(fid, '\nGoogle Maps: https://maps.google.com/?q=%.8f,%.8f\n', hl(1), hl(2));
%     end
%     fclose(fid);
% end