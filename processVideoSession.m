function [trajectories, departureAngles] = processVideoSession(session, cameraParams, displayAxes)
    % Process a single video session for bee tracking
    % Optimized for GUI integration with progress updates
    
    trajectories = {};
    departureAngles = [];
    
    try
        % Initialize video
        videoReader = VideoReader(session.videoFile);
        totalFrames = videoReader.NumFrames;
        
        % Build background model from first 50 frames
        backgroundModel = buildBackgroundModel(videoReader, 50);
        
        % Initialize tracking
        activeTrackers = [];
        nextTrackID = 1;
        
        % Processing parameters
        minBeeArea = 20;
        maxBeeArea = 500;
        maxDistance = 50;
        minTrajectoryLength = 10;
        maxMisses = 10;
        
        frameNum = 1;
        
        % Process video
        while hasFrame(videoReader)
            frame = readFrame(videoReader);
            grayFrame = rgb2gray(frame);
            
            % Background subtraction
            foregroundMask = abs(double(grayFrame) - double(backgroundModel)) > 30;
            
            % Clean up mask
            se = strel('disk', 3);
            foregroundMask = imopen(foregroundMask, se);
            foregroundMask = imclose(foregroundMask, se);
            
            % Detect blobs
            stats = regionprops(foregroundMask, 'Centroid', 'Area');
            validBlobs = [stats.Area] >= minBeeArea & [stats.Area] <= maxBeeArea;
            detections = stats(validBlobs);
            
            % Update trackers
            [activeTrackers, trajectories, nextTrackID] = updateTrackers(...
                activeTrackers, detections, trajectories, frameNum, ...
                nextTrackID, maxDistance, maxMisses, minTrajectoryLength);
            
            % Adaptive background update
            alpha = 0.01;
            backgroundModel = uint8(alpha * double(grayFrame) + (1 - alpha) * double(backgroundModel));
            
            % Display progress every 30 frames
            if mod(frameNum, 30) == 0
                displayTrackingProgress(frame, foregroundMask, activeTrackers, displayAxes);
                drawnow;
            end
            
            frameNum = frameNum + 1;
        end
        
        % Extract departure angles from trajectories
        departureAngles = extractDepartureAngles(trajectories, cameraParams, session.gpsCoords);
        
    catch ME
        error('Video processing failed: %s', ME.message);
    end
end

function backgroundModel = buildBackgroundModel(videoReader, nFrames)
    % Build background model using median of frames
    
    frames = [];
    count = 0;
    
    while hasFrame(videoReader) && count < nFrames
        frame = readFrame(videoReader);
        grayFrame = rgb2gray(frame);
        frames = cat(3, frames, grayFrame);
        count = count + 1;
    end
    
    backgroundModel = median(frames, 3);
    
    % Reset video
    videoReader.CurrentTime = 0;
end

function [trackers, trajectories, nextTrackID] = updateTrackers(trackers, detections, ...
    trajectories, frameNum, nextTrackID, maxDistance, maxMisses, minLength)
    % Update trackers with new detections
    
    nTrackers = length(trackers);
    nDetections = length(detections);
    
    if nTrackers == 0
        % Create new trackers for all detections
        for i = 1:nDetections
            newTracker.id = nextTrackID;
            nextTrackID = nextTrackID + 1;
            newTracker.positions = [detections(i).Centroid, frameNum];
            newTracker.age = 1;
            newTracker.consecutiveMisses = 0;
            trackers = [trackers, newTracker];
        end
        return;
    end
    
    % Assignment using distance
    costMatrix = inf(nTrackers, nDetections);
    
    for i = 1:nTrackers
        lastPos = trackers(i).positions(end, 1:2);
        for j = 1:nDetections
            detPos = detections(j).Centroid;
            distance = norm(lastPos - detPos);
            if distance < maxDistance
                costMatrix(i, j) = distance;
            end
        end
    end
    
    % Greedy assignment
    assigned = false(nDetections, 1);
    
    for i = 1:nTrackers
        [minCost, minIdx] = min(costMatrix(i, :));
        if minCost < inf && ~assigned(minIdx)
            % Update tracker
            trackers(i).positions(end+1, :) = [detections(minIdx).Centroid, frameNum];
            trackers(i).age = trackers(i).age + 1;
            trackers(i).consecutiveMisses = 0;
            assigned(minIdx) = true;
        else
            % No match found
            trackers(i).consecutiveMisses = trackers(i).consecutiveMisses + 1;
        end
    end
    
    % Create new trackers for unassigned detections
    for j = 1:nDetections
        if ~assigned(j)
            newTracker.id = nextTrackID;
            nextTrackID = nextTrackID + 1;
            newTracker.positions = [detections(j).Centroid, frameNum];
            newTracker.age = 1;
            newTracker.consecutiveMisses = 0;
            trackers = [trackers, newTracker];
        end
    end
    
    % Remove dead trackers and save trajectories
    keepTrackers = [];
    for i = 1:length(trackers)
        if trackers(i).consecutiveMisses > maxMisses
            % Save if long enough
            if trackers(i).age >= minLength
                trajectories{end+1} = trackers(i).positions;
            end
        else
            keepTrackers = [keepTrackers, i];
        end
    end
    
    trackers = trackers(keepTrackers);
end

function departureAngles = extractDepartureAngles(trajectories, cameraParams, gpsCoords)
    % Extract departure angle for each trajectory
    
    if isempty(trajectories)
        departureAngles = [];
        return;
    end
    
    departureAngles = zeros(length(trajectories), 1);
    
    for i = 1:length(trajectories)
        traj = trajectories{i};
        
        if size(traj, 1) >= 2
            % Use first and last points
            startPoint = traj(1, 1:2);
            endPoint = traj(end, 1:2);
            
            % Calculate angle
            dx = endPoint(1) - startPoint(1);
            dy = endPoint(2) - startPoint(2);
            
            % Convert to compass bearing (0 = North, clockwise)
            angleRad = atan2(dx, -dy);
            angleDeg = rad2deg(angleRad);
            
            % Normalize to [0, 360)
            if angleDeg < 0
                angleDeg = angleDeg + 360;
            end
            
            % Apply camera heading correction
            angleDeg = angleDeg + cameraParams.compassHeading;
            angleDeg = mod(angleDeg, 360);
            
            departureAngles(i) = angleDeg;
        end
    end
end

function displayTrackingProgress(frame, mask, trackers, axesHandle)
    % Display current tracking state
    
    % Overlay mask on frame
    overlay = frame;
    overlay(:,:,2) = overlay(:,:,2) + uint8(mask * 100);
    
    % Display
    imshow(overlay, 'Parent', axesHandle);
    hold(axesHandle, 'on');
    
    % Draw active tracks
    for i = 1:length(trackers)
        pos = trackers(i).positions;
        plot(axesHandle, pos(:,1), pos(:,2), 'y-', 'LineWidth', 2);
        plot(axesHandle, pos(end,1), pos(end,2), 'ro', 'MarkerSize', 8, 'LineWidth', 2);
    end
    
    title(axesHandle, sprintf('Tracking: %d active tracks', length(trackers)));
    hold(axesHandle, 'off');
end

function [avgBearing, confidence, hiveLocation] = analyzeBearings(departureAngles, gpsCoords, allObservations)
    % Analyze bearings and triangulate hive location
    
    hiveLocation = [];
    
    if nargin < 3 || isempty(allObservations)
        % Single session analysis
        if isempty(departureAngles)
            avgBearing = NaN;
            confidence = 0;
            return;
        end
        
        % Remove outliers
        cleanAngles = removeCircularOutliers(departureAngles);
        
        % Calculate circular mean
        avgBearing = circularMean(cleanAngles);
        
        % Calculate confidence
        circStd = circularStd(cleanAngles);
        n = length(cleanAngles);
        sampleFactor = 1 - exp(-n / 50);
        consistencyFactor = exp(-circStd / 30);
        confidence = sampleFactor * consistencyFactor;
        
    else
        % Multiple session triangulation
        avgBearing = NaN;
        confidence = 0;
        
        nObs = length(allObservations);
        if nObs < 2
            return;
        end
        
        % Triangulate
        hiveLocation = triangulateHiveLocation(allObservations);
    end
end

function meanAngle = circularMean(angles)
    % Circular mean of angles in degrees
    anglesRad = deg2rad(angles);
    xMean = mean(cos(anglesRad));
    yMean = mean(sin(anglesRad));
    meanAngle = rad2deg(atan2(yMean, xMean));
    if meanAngle < 0
        meanAngle = meanAngle + 360;
    end
end

function stdDev = circularStd(angles)
    % Circular standard deviation
    anglesRad = deg2rad(angles);
    xMean = mean(cos(anglesRad));
    yMean = mean(sin(anglesRad));
    R = sqrt(xMean^2 + yMean^2);
    stdDev = rad2deg(sqrt(-2 * log(R)));
end

function cleanAngles = removeCircularOutliers(angles)
    % Remove outliers from circular data
    medianAngle = circularMean(angles);
    distances = min(abs(angles - medianAngle), 360 - abs(angles - medianAngle));
    threshold = 2.5 * std(distances);
    cleanAngles = angles(distances <= threshold);
end

function hiveLocation = triangulateHiveLocation(observations)
    % Triangulate hive location from multiple bearings
    
    nObs = length(observations);
    
    % Use first observation as reference
    refLat = observations(1).gpsCoords(1);
    refLon = observations(1).gpsCoords(2);
    
    % Set up least squares
    A = zeros(nObs, 2);
    b = zeros(nObs, 1);
    weights = zeros(nObs, 1);
    
    for i = 1:nObs
        % Convert to local coordinates
        [x, y] = latlon2local(observations(i).gpsCoords(1), ...
                              observations(i).gpsCoords(2), refLat, refLon);
        
        % Direction vector
        bearing = observations(i).avgBearing;
        dx = sind(bearing);
        dy = cosd(bearing);
        
        % Line equation
        A(i, :) = [dy, -dx];
        b(i) = x * dy - y * dx;
        weights(i) = observations(i).confidence;
    end
    
    % Weighted least squares
    W = diag(weights);
    estimatedPos = (A' * W * A) \ (A' * W * b);
    
    % Convert back to lat/lon
    [estLat, estLon] = local2latlon(estimatedPos(1), estimatedPos(2), refLat, refLon);
    hiveLocation = [estLat, estLon];
end

function [x, y] = latlon2local(lat, lon, refLat, refLon)
    % Convert lat/lon to local Cartesian (meters)
    R = 6371000;
    x = R * deg2rad(lon - refLon) * cosd(refLat);
    y = R * deg2rad(lat - refLat);
end

function [lat, lon] = local2latlon(x, y, refLat, refLon)
    % Convert local Cartesian to lat/lon
    R = 6371000;
    lat = refLat + rad2deg(y / R);
    lon = refLon + rad2deg(x / (R * cosd(refLat)));
end

function exportSummaryReport(results, filename)
    % Export text summary
    
    fid = fopen(filename, 'w');
    
    fprintf(fid, 'B-TRAC ANALYSIS SUMMARY\n');
    fprintf(fid, '======================\n\n');
    fprintf(fid, 'Analysis Date: %s\n\n', datestr(results.analysisDate));
    
    fprintf(fid, 'OBSERVATION SESSIONS:\n');
    for i = 1:length(results.sessions)
        sess = results.sessions(i);
        fprintf(fid, '\nSession %d: %s\n', i, sess.name);
        fprintf(fid, '  Location: [%.6f, %.6f]\n', sess.gpsCoords);
        if sess.processed
            fprintf(fid, '  Trajectories: %d\n', length(sess.trajectories));
            fprintf(fid, '  Average Bearing: %.2f°\n', sess.avgBearing);
            fprintf(fid, '  Confidence: %.1f%%\n', sess.confidence * 100);
        end
    end
    
    if isfield(results, 'estimatedHiveLocation') && ~isempty(results.estimatedHiveLocation)
        fprintf(fid, '\n\nESTIMATED HIVE LOCATION:\n');
        fprintf(fid, 'Latitude:  %.6f\n', results.estimatedHiveLocation(1));
        fprintf(fid, 'Longitude: %.6f\n', results.estimatedHiveLocation(2));
        fprintf(fid, '\nGoogle Maps: https://www.google.com/maps?q=%.6f,%.6f\n', ...
                results.estimatedHiveLocation(1), results.estimatedHiveLocation(2));
    end
    
    fclose(fid);
end
