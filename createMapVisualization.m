function createMapVisualization(sessions, candidates, ax)
% Create Map Visualization
% Displays observation stations, directional bearing groups,
% supporting rays, and predicted hive candidates.
%
% Thin gray lines  = All directional bearing groups
% Thick green lines = Rays supporting a hive candidate
% Blue circles     = Observation stations
% Green pentagons  = Predicted hive candidates
% Candidate labels use offset callouts so they do not cover intersections.

    %% Validate inputs
    if nargin < 3 || isempty(ax) || ~isvalid(ax)
        error('createMapVisualization:InvalidAxes', ...
            'A valid UIAxes handle must be supplied.');
    end

    if isempty(sessions)
        cla(ax);
        title(ax, 'No observation sessions to display');
        return;
    end

    if nargin < 2 || isempty(candidates)
        candidates = struct([]);
    end

    %% Get observation and candidate coordinates
    obsLats = arrayfun(@(s) s.gpsCoords(1), sessions);
    obsLons = arrayfun(@(s) s.gpsCoords(2), sessions);

    if isempty(candidates)
        candLats = [];
        candLons = [];
    else
        candLats = [candidates.lat];
        candLons = [candidates.lon];
    end

    %% Convert GPS to local East/North coordinates
    refLat = mean(obsLats);
    refLon = mean(obsLons);
    [obsE, obsN] = ll2xy(obsLats, obsLons, refLat, refLon);
    [candE, candN] = ll2xy(candLats, candLons, refLat, refLon);

    %% Prepare plot
    cla(ax);
    hold(ax, 'on');

    ax.Color = [0.975 0.978 0.982];
    ax.XColor = [0.22 0.25 0.28];
    ax.YColor = [0.22 0.25 0.28];
    ax.GridColor = [0.62 0.66 0.71];
    ax.GridAlpha = 0.30;
    ax.MinorGridColor = [0.78 0.81 0.84];
    ax.MinorGridAlpha = 0.20;
    ax.FontName = 'Arial';
    ax.FontSize = 9;
    ax.LineWidth = 1;
    ax.Box = 'on';

    %% Visualization settings
    % Extend rays far enough to reach all estimated hive candidates
    if isempty(candE)
        rayLength = 2000;
    else
        candidateDistances = hypot( ...
            candE(:)' - obsE(:), ...
            candN(:)' - obsN(:));

        rayLength = max(candidateDistances(:)) + 300;
    end

    allRayColor = [0.62 0.65 0.68];
    supportRayColor = [0.10 0.58 0.28];
    stationColor = [0.12 0.35 0.78];
    candidateColor = [0.10 0.58 0.28];

    hAllRays = gobjects(1);
    hSupportRays = gobjects(1);
    hStations = gobjects(1);
    hCandidate = gobjects(1);

    %% Draw all directional bearing rays
    allX = [obsE(:); candE(:)];
    allY = [obsN(:); candN(:)];

    for s = 1:numel(sessions)
        bearings = sessions(s).avgBearing;

        for g = 1:numel(bearings)
            bearing = bearings(g);
            if ~isfinite(bearing)
                continue;
            end

            v = [sind(bearing), cosd(bearing)];
            endpoint = [obsE(s), obsN(s)] + rayLength * v;

            h = plot(ax, [obsE(s), endpoint(1)], ...
                [obsN(s), endpoint(2)], '-', ...
                'Color', allRayColor, 'LineWidth', 1.25, ...
                'HandleVisibility', 'off');

            if ~isgraphics(hAllRays)
                hAllRays = h;
            end

            arrowLength = 35;
            arrowStart = endpoint - arrowLength * v;
            quiver(ax, arrowStart(1), arrowStart(2), ...
                arrowLength*v(1), arrowLength*v(2), 0, ...
                'Color', allRayColor, 'LineWidth', 1.2, ...
                'MaxHeadSize', 1.8, 'HandleVisibility', 'off');

            allX(end+1,1) = endpoint(1); %#ok<AGROW>
            allY(end+1,1) = endpoint(2); %#ok<AGROW>
        end
    end

    %% Highlight rays supporting each hive candidate
    for c = 1:numel(candidates)
        hasSupportIDs = ...
            isfield(candidates, 'supportRaySessions') && ...
            isfield(candidates, 'supportRayGroups') && ...
            ~isempty(candidates(c).supportRaySessions) && ...
            ~isempty(candidates(c).supportRayGroups);

        if ~hasSupportIDs
            continue;
        end

        supportSessions = candidates(c).supportRaySessions;
        supportGroups = candidates(c).supportRayGroups;

        for k = 1:numel(supportSessions)
            s = supportSessions(k);
            g = supportGroups(k);

            if ~isfinite(s) || ~isfinite(g) || ...
                    s ~= fix(s) || g ~= fix(g) || ...
                    s < 1 || s > numel(sessions) || ...
                    g < 1 || g > numel(sessions(s).avgBearing)
                continue;
            end

            bearing = sessions(s).avgBearing(g);
            if ~isfinite(bearing)
                continue;
            end

            v = [sind(bearing), cosd(bearing)];
            endpoint = [obsE(s), obsN(s)] + rayLength * v;

            h = plot(ax, [obsE(s), endpoint(1)], ...
                [obsN(s), endpoint(2)], '-', ...
                'Color', supportRayColor, 'LineWidth', 3.0, ...
                'HandleVisibility', 'off');

            if ~isgraphics(hSupportRays)
                hSupportRays = h;
            end
        end
    end

    %% Draw observation stations
    for s = 1:numel(sessions)
        h = plot(ax, obsE(s), obsN(s), 'o', ...
            'MarkerSize', 8, 'MarkerFaceColor', stationColor, ...
            'MarkerEdgeColor', [0.12 0.14 0.18], ...
            'LineWidth', 1.2, 'HandleVisibility', 'off');

        if ~isgraphics(hStations)
            hStations = h;
        end

        if isfield(sessions, 'name') && ~isempty(sessions(s).name)
            stationName = char(sessions(s).name);
        else
            stationName = sprintf('Station %d', s);
        end

        % Small station label, offset from the station marker
        text(ax, obsE(s)+18, obsN(s)+18, stationName, ...
            'FontSize', 8, 'FontWeight', 'bold', ...
            'Color', stationColor, 'BackgroundColor', [1 1 1 0.88], ...
            'Margin', 2, 'Interpreter', 'none', 'Clipping', 'on');
    end

    %% Establish plot limits and a readable coordinate grid
    spanX = max(allX) - min(allX);
    spanY = max(allY) - min(allY);
    if spanX < 1, spanX = 250; end
    if spanY < 1, spanY = 250; end

    padX = max(100, 0.12 * spanX);
    padY = max(100, 0.12 * spanY);

    % Reserve room around candidate points for their labels
    labelOffset = max(80, 0.10 * max(spanX, spanY));
    if ~isempty(candE)
        calloutX = candE(:) + labelOffset;
        calloutY = candN(:) + labelOffset;
        allX = [allX; calloutX];
        allY = [allY; calloutY];
    end

    xLimits = [min(allX)-padX, max(allX)+padX];
    yLimits = [min(allY)-padY, max(allY)+padY];
    xlim(ax, xLimits);
    ylim(ax, yLimits);
    axis(ax, 'equal');

    grid(ax, 'on');
    ax.XMinorGrid = 'on';
    ax.YMinorGrid = 'on';
    ax.GridLineStyle = '-';
    ax.MinorGridLineStyle = ':';
    ax.Layer = 'bottom';

    %% Point to hive candidates with offset arrow 
    for c = 1:numel(candidates)
        h = plot(ax, candE(c), candN(c), 'p', ...
            'MarkerSize', 15, 'MarkerFaceColor', [1 0.8 0.15], ...
            'MarkerEdgeColor', [0.65 0.45 0.05], ...
            'LineWidth', 1.5, 'HandleVisibility', 'off');

        if ~isgraphics(hCandidate)
            hCandidate = h;
        end

        if isfield(candidates, 'meanConfidence')
            confidencePercent = 100 * max(0, min(1, ...
                candidates(c).meanConfidence));
        else
            confidencePercent = NaN;
        end

        if isfield(candidates, 'supportSessions')
            supportSessionCount = candidates(c).supportSessions;
        else
            supportSessionCount = 0;
        end

        if isfield(candidates, 'supportRays')
            supportRayCount = candidates(c).supportRays;
        else
            supportRayCount = 0;
        end

        label = sprintf('Hive %d\nConfidence: %.1f%%\nStations: %d | Rays: %d\nGPS: %.6f, %.6f', ...
            c, confidencePercent, supportSessionCount, supportRayCount, ...
            candidates(c).lat, candidates(c).lon);

        % Stagger callouts to reduce overlap when several candidates are
        % close together
        directions = [1 1; -1 1; 1 -1; -1 -1];
        direction = directions(mod(c-1, size(directions,1))+1,:);
        dx = direction(1) * labelOffset;
        dy = direction(2) * labelOffset;

        labelX = candE(c) + dx;
        labelY = candN(c) + dy;

        % Leader line and arrowhead connect the hive marker to its label
        plot(ax, [candE(c), labelX], [candN(c), labelY], ...
            '-', 'Color', candidateColor, 'LineWidth', 1.1, ...
            'HandleVisibility', 'off');

        % Arrowhead at the candidate end of the leader line.
        quiver(ax, labelX, labelY, -0.78*dx, -0.78*dy, 0, ...
            'Color', [1.0 0.80 0.15], 'LineWidth', 1.6, ...
            'MaxHeadSize', 1.2, 'HandleVisibility', 'off');

        horizontalAlignment = 'left';
        if dx < 0
            horizontalAlignment = 'right';
        end

        verticalAlignment = 'bottom';
        if dy < 0
            verticalAlignment = 'top';
        end

        text(ax, labelX, labelY, label, ...
            'FontSize', 7.5, 'FontWeight', 'bold', ...
            'Color', [0.12 0.12 0.12], ...
            'BackgroundColor', [1 1 1 0.94], ...
            'EdgeColor', [0.58 0.63 0.60], ...
            'LineWidth', 0.8, 'Margin', 4, ...
            'HorizontalAlignment', horizontalAlignment, ...
            'VerticalAlignment', verticalAlignment, ...
            'Interpreter', 'none', 'Clipping', 'on');
    end

    %% Labels and title
    xlabel(ax, 'East (m)', 'FontWeight', 'bold', ...
        'Color', [1 1 1]);
    ylabel(ax, 'North (m)', 'FontWeight', 'bold', ... 
        'Color', [1 1 1]);

    if isempty(candidates)
        title(ax, ...
            'B-TRAC II | Observation Stations and Bearing Directions', ...
            'FontWeight', 'bold');
    else
        title(ax, sprintf('B-TRAC II | %d Hive Candidate(s)', ...
            numel(candidates)), 'FontWeight', 'bold');
    end

    %% North indicator
    text(ax, 0.965, 0.94, 'N', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'FontSize', 10, ...
        'FontWeight', 'bold', 'Color', [1 1 1], ...
        'Interpreter', 'none');

    text(ax, 0.965, 0.895, '^', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'FontSize', 14, ...
        'FontWeight', 'bold', 'Color', [1 1 1], ...
        'Interpreter', 'none');

    %% Legend
    legendHandles = gobjects(0);
    legendNames = {};

    if isgraphics(hAllRays)
        legendHandles(end+1) = hAllRays;
        legendNames{end+1} = 'Directional bearing groups';
    end
    if isgraphics(hSupportRays)
        legendHandles(end+1) = hSupportRays;
        legendNames{end+1} = 'Supporting bearing rays';
    end
    if isgraphics(hStations)
        legendHandles(end+1) = hStations;
        legendNames{end+1} = 'Observation stations';
    end
    if isgraphics(hCandidate)
        legendHandles(end+1) = hCandidate;
        legendNames{end+1} = 'Hive candidate';
    end

    if ~isempty(legendHandles)
        legend(ax, legendHandles, legendNames, ...
            'Location', 'northwest', 'Box', 'off', 'FontSize', 8);
    end

    hold(ax, 'off');
end


%% Helper function: GPS to local East/North coordinates
function [E, N] = ll2xy(lat, lon, refLat, refLon)
    R = 6378137;
    E = R .* deg2rad(lon - refLon) .* cosd(refLat);
    N = R .* deg2rad(lat - refLat);
end