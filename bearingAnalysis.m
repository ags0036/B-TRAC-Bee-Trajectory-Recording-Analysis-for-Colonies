function [avgBearing, confidence, groupIDs, referenceBearings] = ...
    bearingAnalysis(angles, trajectoryIDs)
% bearingAnalysis
% Original B-TRAC I functionality: circular averaging and confidence
% calculation are retained within each B-TRAC II directional group.
%
% B-TRAC II:
% Groups individual bee trajectory bearings into directional clusters.
%
% Inputs:
%   angles - Individual trajectory bearings (degrees)
%   trajectoryIDs - Corresponding trajectory IDs
%
% Outputs:
%   avgBearing - Circular mean bearing for each group
%   confidence - Confidence score for each group
%   groupIDs - Trajectory IDs assigned to each group
%   referenceBearings - Initial reference bearing for each group

    %% SETTINGS - Parameters able to be adjusted

    angleThreshold = 10;   % Parameter for first pass
    minGroupSize = 5;      
    outlierThreshold = 2;  % Parameter for second pass

    reassignmentThreshold = angleThreshold + outlierThreshold;


    %% VALIDATE INPUTS

    avgBearing = [];
    confidence = [];
    groupIDs = {};
    referenceBearings = [];

    if isempty(angles) || isempty(trajectoryIDs)
        return;
    end

    angles = angles(:);
    trajectoryIDs = trajectoryIDs(:);

    if length(angles) ~= length(trajectoryIDs)
        error('The number of bearings must match the number of trajectory IDs.');
    end

    % Remove invalid bearings while preserving matching IDs
    valid = isfinite(angles) & isfinite(trajectoryIDs);

    validBearings = mod(angles(valid), 360);
    validIDs = trajectoryIDs(valid);

    if isempty(validBearings)
        return;
    end


    %% FIRST PASS: GROUP TRAJECTORIES BY BEARING CONCENTRATION

    unassigned = true(size(validBearings));

    groups = {};
    groupIDs = {};
    referenceBearings = [];

    groupNumber = 0;

    while any(unassigned)

        remainingBearings = validBearings(unassigned);
        remainingIDs = validIDs(unassigned);

        remainingIndices = find(unassigned);

        bestCount = 0;
        bestReference = NaN;
        bestMembers = [];

        % Find the densest +/- angleThreshold concentration
        for i = 1:length(remainingBearings)

            referenceBearing = remainingBearings(i);

            angularDistance = abs( ...
                mod(remainingBearings - referenceBearing + 180, 360) - 180);

            members = angularDistance <= angleThreshold;
            count = sum(members);

            if count > bestCount
                bestCount = count;
                bestReference = referenceBearing;
                bestMembers = members;
            end

        end

        % Create group
        groupNumber = groupNumber + 1;

        groups{groupNumber} = remainingBearings(bestMembers);
        groupIDs{groupNumber} = remainingIDs(bestMembers);

        referenceBearings(groupNumber) = bestReference;

        % Remove assigned trajectories
        unassigned(remainingIndices(bestMembers)) = false;

    end


    %% SECOND PASS: REASSIGN BORDERLINE TRAJECTORIES

    changed = true;

    while changed

        changed = false;

        groupSizes = cellfun(@length, groupIDs);

        % Only groups larger than minGroupSize are destinations
        largeGroups = find(groupSizes > minGroupSize);

        if isempty(largeGroups)
            break;
        end

        for g = 1:length(groups)

            groupSizes = cellfun(@length, groupIDs);

            if groupSizes(g) > minGroupSize
                continue;
            end

            if isempty(groupIDs{g})
                continue;
            end

            % Snapshot small group before reassignment
            smallGroupIDs = groupIDs{g};
            smallGroupBearings = groups{g};

            for i = 1:length(smallGroupIDs)

                trajectoryID = smallGroupIDs(i);
                trajectoryBearing = smallGroupBearings(i);

                bestGroup = NaN;
                bestDistance = Inf;

                for j = 1:length(largeGroups)

                    targetGroup = largeGroups(j);

                    if targetGroup == g
                        continue;
                    end

                    targetReference = referenceBearings(targetGroup);

                    angularDistance = abs( ...
                        mod(trajectoryBearing - targetReference + 180, 360) - 180);

                    if angularDistance > angleThreshold && ...
                            angularDistance <= reassignmentThreshold

                        if angularDistance < bestDistance
                            bestDistance = angularDistance;
                            bestGroup = targetGroup;
                        end

                    end

                end

                % Move trajectory if an eligible group was found
                if ~isnan(bestGroup)

                    groupIDs{bestGroup}(end + 1) = trajectoryID;
                    groups{bestGroup}(end + 1) = trajectoryBearing;

                    removeIndex = find(groupIDs{g} == trajectoryID, 1);

                    if ~isempty(removeIndex)
                        groupIDs{g}(removeIndex) = [];
                        groups{g}(removeIndex) = [];
                    end

                    changed = true;

                end

            end

        end

    end


    %% REMOVE EMPTY GROUPS

    nonemptyGroups = ~cellfun(@isempty, groupIDs);

    groups = groups(nonemptyGroups);
    groupIDs = groupIDs(nonemptyGroups);
    referenceBearings = referenceBearings(nonemptyGroups);


    %% CALCULATE FINAL GROUP BEARINGS AND CONFIDENCE

    numGroups = length(groups);

    avgBearing = nan(numGroups, 1);
    confidence = zeros(numGroups, 1);

    for g = 1:numGroups

        groupBearings = groups{g};

        % Circular mean bearing (original B-TRAC I averaging method)
        r = deg2rad(groupBearings);

        vE = mean(sin(r));
        vN = mean(cos(r));

        avgBearing(g) = mod(rad2deg(atan2(vE, vN)), 360);

        % Resultant length
        R_len = sqrt(vE^2 + vN^2);

        % Confidence based on directional agreement and trajectory support
        n = length(groupBearings);
        referenceCount = 5;  % Tunable parameter, not a universal threshold of any sort

        confidence(g) = R_len * min(n / referenceCount, 1);

    end

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