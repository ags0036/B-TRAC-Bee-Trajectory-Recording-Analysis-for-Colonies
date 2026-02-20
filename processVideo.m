function [trajectories, departureAngles] = processVideo(session, cameraParams, displayAxes, yoloConfig)
% processVideo  Process a single bee-tracking video session.
%
%   Trajectory math follows the B-TRAC report:
%     - Position sequence: p_k = [x_k; y_k], k = 1..N
%     - Frame displacement: dp_k = p_{k+1} - p_k  (finite differences)
%     - Net displacement used for bearing: dx = x_end - x_1, dy = y_end - y_1
%     - Image-to-compass angle: theta = atan2(dx, -dy)   (inverts y axis)
%     - Global bearing: beta = mod(H + theta_deg + 360, 360)
%     - Quality filter: min track length enforced before bearing extraction

    trajectories    = {};
    departureAngles = [];

    if nargin < 4 || isempty(yoloConfig), yoloConfig.useYOLO = false; end
    if ~isfield(yoloConfig,'confidenceThreshold'), yoloConfig.confidenceThreshold = 0.25; end
    if ~isfield(yoloConfig,'frameSample'),          yoloConfig.frameSample = 1; end

    % Tracking parameters
    MAX_DISTANCE    = 150;   % px - max displacement between frames
    MIN_TRAJ_LENGTH = 5;     % frames - quality filter (report: min track length)
    MAX_MISSES      = 15;    % consecutive missed frames before track dies

    try
        vr              = VideoReader(session.videoFile);
        totalFrames     = vr.NumFrames;
        effectiveFrames = ceil(totalFrames / yoloConfig.frameSample);

        fprintf('\n[processVideo] %s\n', session.videoFile);
        fprintf('  Frames: %d total, every %d => %d to process\n', ...
                totalFrames, yoloConfig.frameSample, effectiveFrames);

        if ~yoloConfig.useYOLO
            fprintf('  Method: Background Subtraction\n');
            bgModel = buildBGModel(vr, 50);
        else
            fprintf('  Method: YOLO  (conf >= %.2f)\n', yoloConfig.confidenceThreshold);
            bgModel = [];
        end

        activeTrackers  = [];
        nextTrackID     = 1;
        processedFrames = 0;
        totalDetections = 0;

        tic;
        lastDisplayTime = 0;

        while hasFrame(vr)
            frame        = readFrame(vr);
            currentFrame = round(vr.CurrentTime * vr.FrameRate);

            if mod(currentFrame - 1, yoloConfig.frameSample) ~= 0
                continue;
            end
            processedFrames = processedFrames + 1;

            % ── Detection ──────────────────────────────────────────────
            if yoloConfig.useYOLO
                dets = detectBeesYOLO(frame, yoloConfig.modelPath, ...
                                      yoloConfig.pythonExe, processedFrames);
                fgMask = [];
                if ~isempty(dets)
                    confs = [dets.Confidence];
                    dets  = dets(confs >= yoloConfig.confidenceThreshold);
                    totalDetections = totalDetections + numel(dets);
                    if processedFrames <= 5 && ~isempty(dets)
                        validConfs = confs(confs >= yoloConfig.confidenceThreshold);
                        fprintf('  Frame %d: %d dets (%.2f-%.2f)\n', ...
                                processedFrames, numel(dets), min(validConfs), max(validConfs));
                    end
                end
            else
                [dets, fgMask] = detectBeesBG(frame, bgModel);
                totalDetections = totalDetections + numel(dets);
                if mod(processedFrames, 10) == 0
                    bgModel = uint8(0.01*double(rgb2gray(frame)) + 0.99*double(bgModel));
                end
            end

            % ── Tracker update ─────────────────────────────────────────
            [activeTrackers, trajectories, nextTrackID] = updateTrackers( ...
                activeTrackers, dets, trajectories, processedFrames, ...
                nextTrackID, MAX_DISTANCE, MAX_MISSES, MIN_TRAJ_LENGTH);

            % ── Live preview (every 3 s) ───────────────────────────────
            elapsed = toc;
            if (elapsed - lastDisplayTime) >= 3
                updateDisplay(displayAxes, frame, fgMask, activeTrackers, ...
                              yoloConfig.useYOLO, processedFrames, ...
                              length(trajectories), totalDetections);
                pct = 100 * processedFrames / effectiveFrames;
                rem = (elapsed/(processedFrames/effectiveFrames)) - elapsed;
                fprintf('  [%.1f%%] frame %d/%d | active %d | saved %d | dets %d | ~%.0fs left\n', ...
                        pct, processedFrames, effectiveFrames, ...
                        length(activeTrackers), length(trajectories), totalDetections, rem);
                drawnow;
                lastDisplayTime = elapsed;
            end
        end

        % Flush remaining live trackers
        for i = 1:length(activeTrackers)
            if size(activeTrackers(i).positions, 1) >= MIN_TRAJ_LENGTH
                trajectories{end+1} = activeTrackers(i).positions;
            end
        end

        totalTime = toc;
        fprintf('  Done: %.1fs | Dets: %d | Trajectories: %d\n', ...
                totalTime, totalDetections, length(trajectories));

        % ── Extract bearings (report math) ─────────────────────────────
        departureAngles = extractDepartureAngles(trajectories, cameraParams);
        fprintf('  Bearings: %d', length(departureAngles));
        if ~isempty(departureAngles)
            fprintf(' (mean %.1f deg, std %.1f deg)', mean(departureAngles), std(departureAngles));
        end
        fprintf('\n');

    catch ME
        error('processVideo failed: %s\n%s', ME.message, getReport(ME));
    end
end


%% =========================================================================
%% DETECTION
%% =========================================================================

function [dets, fgMask] = detectBeesBG(frame, bgModel)
    gray   = rgb2gray(frame);
    fgMask = abs(double(gray) - double(bgModel)) > 30;
    se     = strel('disk', 3);
    fgMask = imopen(imclose(fgMask, se), se);
    fgMask = bwareaopen(fgMask, 20);
    stats  = regionprops(fgMask, 'Centroid', 'Area');
    if isempty(stats)
        dets = struct([]); return;
    end
    dets = stats([stats.Area] >= 20 & [stats.Area] <= 500);
end

function dets = detectBeesYOLO(frame, modelPath, pythonExe, frameNum)
    persistent tmpPath scriptPath warnCount
    if isempty(tmpPath)
        tmpPath   = 'temp_frame_yolo.jpg';
        warnCount = 0;
        if     exist('detect_bees_yolov5_optimized.py','file')
            scriptPath = 'detect_bees_yolov5_optimized.py';
        elseif exist('detect_bees_yolov5.py','file')
            scriptPath = 'detect_bees_yolov5.py';
        else
            error('YOLO script not found (need detect_bees_yolov5_optimized.py).');
        end
    end
    dets = struct([]);
    try
        imwrite(frame, tmpPath, 'Quality', 85);
    catch ME
        if warnCount < 3
            warning('Frame write failed at %d: %s', frameNum, ME.message);
            warnCount = warnCount + 1;
        end
        return;
    end
    cmd = sprintf('"%s" "%s" "%s" "%s"', pythonExe, scriptPath, modelPath, tmpPath);
    [status, output] = system(cmd);
    if status ~= 0 || ~contains(output, 'DETECTED:')
        if warnCount < 3
            warning('YOLO failed at frame %d (status %d).', frameNum, status);
            warnCount = warnCount + 1;
        end
        return;
    end
    try
        if ~exist('detections_boxes.txt','file') || ~exist('detections_scores.txt','file')
            return;
        end
        boxes  = readmatrix('detections_boxes.txt');
        scores = readmatrix('detections_scores.txt');
        if isempty(boxes) || isempty(scores), return; end
        n = size(boxes,1);
        dets(n).Centroid    = [];
        dets(n).BoundingBox = [];
        dets(n).Confidence  = [];
        for i = 1:n
            w = boxes(i,3)-boxes(i,1);  h = boxes(i,4)-boxes(i,2);
            dets(i).Centroid    = [boxes(i,1)+w/2, boxes(i,2)+h/2];
            dets(i).BoundingBox = [boxes(i,1), boxes(i,2), w, h];
            dets(i).Confidence  = scores(i);
        end
    catch ME
        if warnCount < 3
            warning('YOLO output parse error at frame %d: %s', frameNum, ME.message);
            warnCount = warnCount + 1;
        end
        dets = struct([]);
    end
end


%% =========================================================================
%% BACKGROUND MODEL
%% =========================================================================

function bgModel = buildBGModel(vr, nFrames)
    frames = [];  count = 0;
    while hasFrame(vr) && count < nFrames
        frames = cat(3, frames, rgb2gray(readFrame(vr)));
        count  = count + 1;
    end
    bgModel         = median(frames, 3);
    vr.CurrentTime  = 0;
end


%% =========================================================================
%% TRACKING
%% =========================================================================

function [trackers, trajs, nextID] = updateTrackers( ...
        trackers, dets, trajs, frameNum, nextID, maxDist, maxMiss, minLen)
% Greedy nearest-neighbour tracker.
% Each tracker stores positions as [x, y, frameNum] rows — the full
% trajectory sequence p_k used for finite-difference bearing extraction.

    nT = length(trackers);
    nD = numel(dets);

    if nT == 0
        for i = 1:nD
            trackers = [trackers, makeTrack(nextID, dets(i).Centroid, frameNum)];
            nextID   = nextID + 1;
        end
        return;
    end

    if nD == 0
        for i = 1:nT
            trackers(i).consecutiveMisses = trackers(i).consecutiveMisses + 1;
        end
    else
        assigned = false(nD,1);
        for i = 1:nT
            lastPos  = trackers(i).positions(end, 1:2);
            best = inf;  bestJ = -1;
            for j = 1:nD
                if assigned(j), continue; end
                d = norm(lastPos - dets(j).Centroid);
                if d < maxDist && d < best
                    best = d;  bestJ = j;
                end
            end
            if bestJ > 0
                trackers(i).positions(end+1,:) = [dets(bestJ).Centroid, frameNum];
                trackers(i).consecutiveMisses  = 0;
                assigned(bestJ) = true;
            else
                trackers(i).consecutiveMisses = trackers(i).consecutiveMisses + 1;
            end
        end
        for j = 1:nD
            if ~assigned(j)
                trackers = [trackers, makeTrack(nextID, dets(j).Centroid, frameNum)];
                nextID   = nextID + 1;
            end
        end
    end

    keep = [];
    for i = 1:length(trackers)
        if trackers(i).consecutiveMisses > maxMiss
            if size(trackers(i).positions,1) >= minLen
                trajs{end+1} = trackers(i).positions;
            end
        else
            keep = [keep, i];
        end
    end
    trackers = trackers(keep);
end

function t = makeTrack(id, centroid, frameNum)
    t.id                = id;
    t.positions         = [centroid, frameNum];
    t.consecutiveMisses = 0;
end


%% =========================================================================
%% DEPARTURE ANGLE EXTRACTION  (report Section: Trajectory Math)
%% =========================================================================

function angles = extractDepartureAngles(trajs, cameraParams)
% Implements the bearing formula from the B-TRAC report:
%
%   For each trajectory p_k = [x_k, y_k], k = 1..N  (image pixel coords)
%
%   Net displacement (first -> last point):
%     dx = x_N - x_1,   dy = y_N - y_1
%
%   Image y increases downward, so invert dy to align with math convention:
%     dy_math = -dy
%
%   Angle relative to camera forward (atan2 gives horizontal azimuth):
%     theta = atan2(dx, -dy)          [radians]
%
%   Convert to global compass bearing using camera heading H (deg CW from N):
%     beta = mod(H + theta*(180/pi) + 360, 360)
%
%   Quality filter: trajectories with < MIN_TRAJ_LENGTH frames are already
%   removed by the tracker; here we additionally require net motion > 5 px
%   to reject stationary detections (motion consistency check).

    MIN_NET_MOTION = 5;  % pixels - rejects near-stationary tracks

    if isempty(trajs), angles = []; return; end

    angles = nan(length(trajs), 1);
    H      = cameraParams.compassHeading;   % camera heading, degrees CW from North

    for i = 1:length(trajs)
        pos = trajs{i};          % [x, y, frameNum]  N x 3
        if size(pos, 1) < 2, continue; end

        % Net displacement across the full trajectory (first and last points)
        dx = pos(end,1) - pos(1,1);
        dy = pos(end,2) - pos(1,2);

        % Motion consistency check - skip near-stationary tracks
        if norm([dx, dy]) < MIN_NET_MOTION, continue; end

        % theta = atan2(dx, -dy): image y is downward, so negate dy
        % This matches the report formula exactly
        theta_rad = atan2(dx, -dy);
        theta_deg = theta_rad * (180 / pi);

        % Global compass bearing
        beta = mod(H + theta_deg + 360, 360);
        angles(i) = beta;
    end

    angles = angles(~isnan(angles));
end


%% =========================================================================
%% LIVE DISPLAY
%% =========================================================================

function updateDisplay(ax, frame, mask, trackers, usingYOLO, fNum, saved, dets)
    imshow(frame, 'Parent', ax);
    hold(ax, 'on');
    for i = 1:length(trackers)
        p = trackers(i).positions;
        % Draw full trajectory path (sequence of p_k positions)
        plot(ax, p(:,1), p(:,2), 'r-', 'LineWidth', 2);
        plot(ax, p(end,1), p(end,2), 'ro', 'MarkerSize', 8, 'LineWidth', 2);
    end
    if usingYOLO, meth = 'YOLO'; else, meth = 'BG Sub'; end
    title(ax, sprintf('%s | Frame %d | Active: %d | Saved: %d | Dets: %d', ...
          meth, fNum, length(trackers), saved, dets), 'FontSize', 10);
    hold(ax, 'off');
end