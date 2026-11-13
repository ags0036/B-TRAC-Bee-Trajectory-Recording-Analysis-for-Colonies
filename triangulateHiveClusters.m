
function [candidates, diagnostics] = triangulateHiveClusters(sessions, options)
% Triangulate Hive Clusters
% Estimate potential hive locations from grouped bearings.
%
% Required session fields:
%   gpsCoords   [latitude, longitude]
%   avgBearing  True-compass bearings, clockwise from north
%   confidence  Confidence values corresponding to each bearing group
%
% Optional session field:
%   groupIDs    Cell array containing trajectory IDs for each group
%
% Options:
%   clusterRadiusMeters     Default: 150
%   minSupportingSessions   Default: 2
%   minSupportingRays       Default: 3
%   minClusterIntersections Default: 2
%   parallelAngleDeg        Default: 1
%
% Candidate coordinates are estimated using the centroid of clustered
% forward-ray intersections.
%
% IMPORTANT:
% Bearings must be corrected to true north.
% GPS coordinates must represent actual observation-station positions.
% Candidate locations are geometric predictions, not confirmed hive sites.

    %% Options

    if nargin < 2 || isempty(options)
        options = struct();
    end

    radius = getOption(options, 'clusterRadiusMeters', 150);
    minSessions = getOption(options, 'minSupportingSessions', 2);
    minRays = getOption(options, 'minSupportingRays', 3);
    minIntersections = getOption(options, 'minClusterIntersections', 2);
    parallelDeg = getOption(options, 'parallelAngleDeg', 1);

    validateattributes(radius, {'numeric'}, ...
        {'scalar','real','finite','positive'});

    validateattributes(minSessions, {'numeric'}, ...
        {'scalar','integer','>=',2});

    validateattributes(minRays, {'numeric'}, ...
        {'scalar','integer','>=',2});

    validateattributes(minIntersections, {'numeric'}, ...
        {'scalar','integer','>=',1});

    validateattributes(parallelDeg, {'numeric'}, ...
        {'scalar','real','finite','nonnegative','<',90});

    %% Initialize outputs

    emptyCandidate = struct( ...
        'lat',{}, ...
        'lon',{}, ...
        'east',{}, ...
        'north',{}, ...
        'supportSessions',{}, ...
        'supportRays',{}, ...
        'meanConfidence',{}, ...
        'intersectionCount',{}, ...
        'supportRaySessions',{}, ...
        'supportRayGroups',{});

    candidates = emptyCandidate;

    diagnostics = struct( ...
        'rayCount',0, ...
        'pairCount',0, ...
        'intersectionCount',0, ...
        'parallelRejected',0, ...
        'behindRayRejected',0, ...
        'insufficientSessionRejected',0, ...
        'insufficientRayRejected',0, ...
        'insufficientIntersectionRejected',0, ...
        'oversizedClusterRejected',0, ...
        'illConditionedRejected',0, ...
        'behindFitRejected',0, ...
        'candidateCount',0, ...
        'clusterRadiusMeters',radius);

    if isempty(sessions) || numel(sessions) < minSessions
        return;
    end

    %% Convert station GPS coordinates to local East/North coordinates

    lats = arrayfun(@(s) s.gpsCoords(1), sessions);
    lons = arrayfun(@(s) s.gpsCoords(2), sessions);

    if any(~isfinite(lats)) || any(~isfinite(lons))
        error('triangulateHiveClusters:InvalidGPS', ...
            'All sessions must have finite GPS coordinates.');
    end

    refLat = mean(lats);
    refLon = mean(lons);

    [stationE, stationN] = ll2xy(lats, lons, refLat, refLon);

    %% Convert directional groups into individual rays

    rays = struct( ...
        'p',{}, ...
        'v',{}, ...
        'session',{}, ...
        'group',{}, ...
        'confidence',{}, ...
        'groupSize',{});

    for s = 1:numel(sessions)

        bearings = sessions(s).avgBearing;
        conf = sessions(s).confidence;

        if isempty(bearings)
            continue;
        end

        if numel(conf) ~= numel(bearings)
            error('triangulateHiveClusters:FieldSizeMismatch', ...
                'Session %d has %d bearings but %d confidence values.', ...
                s, numel(bearings), numel(conf));
        end

        for g = 1:numel(bearings)

            if ~isfinite(bearings(g)) || ~isfinite(conf(g))
                continue;
            end

            groupSize = NaN;

            if isfield(sessions, 'groupIDs') && ...
                    numel(sessions(s).groupIDs) >= g

                groupSize = numel(sessions(s).groupIDs{g});
            end

            rays(end+1) = struct( ... %#ok<AGROW>
                'p',[stationE(s); stationN(s)], ...
                'v',[sind(bearings(g)); cosd(bearings(g))], ...
                'session',s, ...
                'group',g, ...
                'confidence',max(0,min(1,conf(g))), ...
                'groupSize',groupSize);
        end
    end

    diagnostics.rayCount = numel(rays);

    if isempty(rays)
        return;
    end

    %% Calculate forward intersections between different stations

    points = zeros(0,2);
    pairRayIds = zeros(0,2);

    sinParallel = sind(parallelDeg);

    for i = 1:numel(rays)-1

        for j = i+1:numel(rays)

            % Rays from the same station cannot triangulate a location.
            if rays(i).session == rays(j).session
                continue;
            end

            diagnostics.pairCount = diagnostics.pairCount + 1;

            cross = rays(i).v(1)*rays(j).v(2) - ...
                    rays(i).v(2)*rays(j).v(1);

            % Reject parallel or nearly parallel rays.
            if abs(cross) <= sinParallel

                diagnostics.parallelRejected = ...
                    diagnostics.parallelRejected + 1;

                continue;
            end

            A = [rays(i).v, -rays(j).v];

            tu = A \ (rays(j).p - rays(i).p);

            % Both intersections must be in front of their stations.
            if any(~isfinite(tu)) || tu(1) <= 0 || tu(2) <= 0

                diagnostics.behindRayRejected = ...
                    diagnostics.behindRayRejected + 1;

                continue;
            end

            q = rays(i).p + tu(1)*rays(i).v;

            points(end+1,:) = q.'; %#ok<AGROW>
            pairRayIds(end+1,:) = [i j]; %#ok<AGROW>

        end
    end

    diagnostics.intersectionCount = size(points,1);

    if isempty(points)
        return;
    end

    %% Group nearby intersection points into candidate regions

    nPts = size(points,1);

    visited = false(nPts,1);
    clusters = {};

    for seed = 1:nPts

        if visited(seed)
            continue;
        end

        queue = seed;
        visited(seed) = true;
        members = [];

        while ~isempty(queue)

            cur = queue(1);
            queue(1) = [];

            members(end+1) = cur; %#ok<AGROW>

            d = hypot( ...
                points(:,1)-points(cur,1), ...
                points(:,2)-points(cur,2));

            neighbors = find(d <= radius & ~visited);

            visited(neighbors) = true;

            queue = [queue; neighbors]; %#ok<AGROW>
        end

        clusters{end+1} = members; %#ok<AGROW>
    end

    %% Validate and estimate each candidate cluster

    for c = 1:numel(clusters)

        members = clusters{c};

        % Identify unique rays contributing to this cluster.
        usedRayIds = unique(pairRayIds(members,:));

        usedSessions = unique([rays(usedRayIds).session]);

        % Diagnostic output disabled:
        % fprintf('Supporting station IDs: ');
        % fprintf('%d ', usedSessions);
        % fprintf('\n');

        %% Check spatial diameter of the cluster

        clusterPoints = points(members,:);

        clusterDiameter = 0;

        % Calculate maximum pairwise distance without requiring
        % the Statistics and Machine Learning Toolbox.
        for i = 1:size(clusterPoints,1)-1

            for j = i+1:size(clusterPoints,1)

                d = norm(clusterPoints(i,:) - clusterPoints(j,:));

                clusterDiameter = max(clusterDiameter,d);

            end
        end

        % Detailed cluster diameter output disabled:
        % fprintf('\nCluster %d diameter: %.2f meters\n', ...
        %     c, clusterDiameter);

        if clusterDiameter > radius

            diagnostics.oversizedClusterRejected = ...
                diagnostics.oversizedClusterRejected + 1;

            % fprintf('Cluster %d rejected: excessive diameter.\n', c);

            continue;
        end

        %% Minimum intersection requirement

        if numel(members) < minIntersections

            diagnostics.insufficientIntersectionRejected = ...
                diagnostics.insufficientIntersectionRejected + 1;

            continue;
        end

        %% Minimum independent station requirement

        if numel(usedSessions) < minSessions

            diagnostics.insufficientSessionRejected = ...
                diagnostics.insufficientSessionRejected + 1;

            continue;
        end

        %% Minimum unique ray requirement

        if numel(usedRayIds) < minRays

            diagnostics.insufficientRayRejected = ...
                diagnostics.insufficientRayRejected + 1;

            continue;
        end

        %% Report independent ray-pair support

        uniquePairs = unique(pairRayIds(members,:), 'rows');

        raySessions = [rays(usedRayIds).session];

        % Detailed independent-support output disabled:
        % fprintf('\n--- Independent Support for Cluster %d ---\n', c);
        % fprintf('Intersections: %d\n', numel(members));
        % fprintf('Unique ray pairs: %d\n', size(uniquePairs,1));
        % fprintf('Unique supporting rays: %d\n', numel(usedRayIds));
        % fprintf('Supporting sessions: %d\n', numel(usedSessions));

        for k = 1:numel(usedSessions)

            sessionRayCount = sum(raySessions == usedSessions(k));

            % fprintf('Session %d contributes %d unique rays\n', ...
            %     usedSessions(k), sessionRayCount);

        end

        %% Weighted perpendicular-distance least squares

        M = zeros(2);
        rhs = zeros(2,1);

        for r = usedRayIds(:).'

            v = rays(r).v;

            Pperp = eye(2) - v*v.';

            % Preserve confidence weighting.
            w = max(rays(r).confidence, 0.05);

            M = M + w*Pperp;

            rhs = rhs + w*(Pperp*rays(r).p);

        end

        %% Reject poorly conditioned solutions

        if rcond(M) < 1e-10

            diagnostics.illConditionedRejected = ...
                diagnostics.illConditionedRejected + 1;

            continue;
        end

        qLS = M \ rhs;

        %% Estimate location using intersection centroid

        % Using the centroid-relative candidate estimation method
        qFit = mean(clusterPoints,1).';

        %% Display individual intersections

        % Detailed intersection listing disabled:
        % fprintf('\n--- Intersection Details for Cluster %d ---\n', c);
        % fprintf('Number of intersections: %d\n', numel(members));

        for k = 1:numel(members)

            pointID = members(k);

            ray1 = pairRayIds(pointID,1);
            ray2 = pairRayIds(pointID,2);

            distanceFromCenter = norm(points(pointID,:).' - qFit);

            % fprintf(['Intersection %d: Ray %d (Session %d, Group %d) ', ...
            %     'and Ray %d (Session %d, Group %d)\n'], ...
            %     pointID, ...
            %     ray1, rays(ray1).session, rays(ray1).group, ...
            %     ray2, rays(ray2).session, rays(ray2).group);
            %
            % fprintf('    Distance from cluster center: %.2f m\n', ...
            %     distanceFromCenter);

        end

        %% Compare centroid and weighted least-squares estimates

        centroidDistances = zeros(length(usedRayIds),1);
        lsDistances = zeros(length(usedRayIds),1);

        lsForward = true;

        for k = 1:length(usedRayIds)

            r = usedRayIds(k);

            v = rays(r).v;
            p = rays(r).p;

            % Centroid distance to forward ray.
            tCentroid = dot(qFit-p,v);
            closestCentroid = p + max(tCentroid,0)*v;

            centroidDistances(k) = norm(qFit-closestCentroid);

            % Weighted least-squares distance to forward ray.
            tLS = dot(qLS-p,v);
            closestLS = p + max(tLS,0)*v;

            lsDistances(k) = norm(qLS-closestLS);

            if tLS <= 0
                lsForward = false;
            end

        end

        % Detailed centroid-versus-least-squares comparison disabled:
        % fprintf('\n--- Candidate Cluster %d Comparison ---\n', c);
        %
        % fprintf('\nIntersection centroid:\n');
        % fprintf('Mean ray distance: %.2f m\n', mean(centroidDistances));
        % fprintf('Median ray distance: %.2f m\n', median(centroidDistances));
        % fprintf('Maximum ray distance: %.2f m\n', max(centroidDistances));
        %
        % fprintf('\nWeighted least-squares:\n');
        % fprintf('Mean ray distance: %.2f m\n', mean(lsDistances));
        % fprintf('Maximum ray distance: %.2f m\n', max(lsDistances));
        % fprintf('Forward of all supporting rays: %d\n', lsForward);
        % fprintf('Distance between estimates: %.2f m\n', norm(qFit-qLS));

        %% Ensure candidate is forward of every supporting ray

        forward = true;

        for r = usedRayIds(:).'

            if dot(qFit-rays(r).p,rays(r).v) <= 0

                forward = false;
                break;

            end
        end

        if ~forward

            diagnostics.behindFitRejected = ...
                diagnostics.behindFitRejected + 1;

            continue;
        end

        %% Calculate candidate-to-ray distances

        rayDistances = zeros(length(usedRayIds),1);

        for k = 1:length(usedRayIds)

            r = usedRayIds(k);

            v = rays(r).v;
            p = rays(r).p;

            t = dot(qFit-p,v);

            closestPoint = p + max(t,0)*v;

            rayDistances(k) = norm(qFit-closestPoint);

        end

        % Detailed per-ray distance output disabled, 
        % enable for diagnostic use:
        %
        % fprintf('\n--- Candidate %d Ray Diagnostics ---\n', c);
        % fprintf('Supporting rays: %d\n', length(usedRayIds));
        % fprintf('Mean distance: %.2f meters\n', mean(rayDistances));
        % fprintf('Median distance: %.2f meters\n', median(rayDistances));
        % fprintf('Maximum distance: %.2f meters\n', max(rayDistances));

        for k = 1:length(usedRayIds)

            % fprintf('Ray %d (Session %d, Group %d): %.2f meters\n', ...
            %     usedRayIds(k), ...
            %     rays(usedRayIds(k)).session, ...
            %     rays(usedRayIds(k)).group, ...
            %     rayDistances(k));

        end

        %% Convert candidate coordinates back to GPS

        [lat,lon] = xy2ll( ...
            qFit(1),qFit(2),refLat,refLon);

        %% Calculate mean bearing confidence

        confs = [rays(usedRayIds).confidence];

        meanConf = mean(confs);

        %% Save supporting ray session and group IDs

        supportRaySessions = [rays(usedRayIds).session];

        supportRayGroups = [rays(usedRayIds).group];

        %% Store accepted candidate

        candidates(end+1) = struct( ... %#ok<AGROW>
            'lat',lat, ...
            'lon',lon, ...
            'east',qFit(1), ...
            'north',qFit(2), ...
            'supportSessions',numel(usedSessions), ...
            'supportRays',numel(usedRayIds), ...
            'meanConfidence',meanConf, ...
            'intersectionCount',numel(members), ...
            'supportRaySessions',supportRaySessions, ...
            'supportRayGroups',supportRayGroups);

    end

    %% Sort candidates by independent station support

    if ~isempty(candidates)

        [~,order] = sort( ...
            [candidates.supportSessions],'descend');

        candidates = candidates(order);

    end

    diagnostics.candidateCount = numel(candidates);

    %% Final summary

    fprintf('\n--- Multi-hive triangulation ---\n');

    fprintf('Rays: %d | Forward intersections: %d | Candidates: %d\n', ...
        diagnostics.rayCount, ...
        diagnostics.intersectionCount, ...
        diagnostics.candidateCount);

    fprintf('Parallel rejected: %d\n', diagnostics.parallelRejected);
    fprintf('Behind-ray rejected: %d\n', diagnostics.behindRayRejected);
    fprintf('Oversized clusters rejected: %d\n', ...
        diagnostics.oversizedClusterRejected);

    for c = 1:numel(candidates)

        fprintf(['Candidate %d: %.6f, %.6f | %d sessions | ', ...
            '%d rays | mean confidence %.3f\n'], ...
            c, ...
            candidates(c).lat, ...
            candidates(c).lon, ...
            candidates(c).supportSessions, ...
            candidates(c).supportRays, ...
            candidates(c).meanConfidence);

    end

end


%% ========================================================================
% Helper functions
% ========================================================================

function value = getOption(options,name,defaultValue)

    if isfield(options,name) && ~isempty(options.(name))
        value = options.(name);
    else
        value = defaultValue;
    end

end


function [E,N] = ll2xy(lat,lon,refLat,refLon)

    R = 6378137;

    E = R .* deg2rad(lon-refLon) .* cosd(refLat);

    N = R .* deg2rad(lat-refLat);

end


function [lat,lon] = xy2ll(E,N,refLat,refLon)

    R = 6378137;

    lat = refLat + rad2deg(N/R);

    lon = refLon + rad2deg(E/(R*cosd(refLat)));

end
