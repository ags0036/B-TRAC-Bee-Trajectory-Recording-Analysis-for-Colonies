function [trajectories, departureAngles] = processVideo(session, cameraParams, displayAxes, yoloConfig)
% processVideo  Process a single bee-tracking video session using YOLOv8.
%
%   Detection: YOLOv8 deep learning via bee_tracker_btrac.py
%              Model is loaded ONCE per video (not per frame).
%              Requires Python + ultralytics + trained best.pt model.
%
%   CHANGE FROM ORIGINAL:
%     Old approach: spawned Python + YOLO for EVERY frame (slow, fragile).
%     New approach: calls bee_tracker_btrac.py ONCE per video, which streams
%     the full video in Python and writes btrac_detections.csv. MATLAB then
%     reads that single CSV and runs the tracker entirely in MATLAB.
%     This matches the architecture of bee_tracker.py (the pendulum script
%     that worked well) — model loaded once, whole video streamed.

    trajectories    = {};
    departureAngles = [];

    if nargin < 4 || isempty(yoloConfig), yoloConfig = struct(); end
    yoloConfig = applyDefaults(yoloConfig);

    fs              = yoloConfig.frameSample;
    MAX_DISTANCE    = 120;
    MAX_MISSES      = max(8, 3*fs);
    MIN_TRAJ_LENGTH = max(4, ceil(6/fs)*fs);
    MIN_NET_MOTION  = 15;

    try
        %% Pre-flight
        videoPath = validateVideoFile(session);
        fprintf('\n[processVideo] Opening: %s\n', videoPath);
        try
            vr = VideoReader(videoPath);
        catch vrErr
            error(['Cannot open video. Install K-Lite Codec Pack Basic (free):\n' ...
                   'https://codecguide.com\nRestart MATLAB after installing.\n' ...
                   'Original error: %s'], vrErr.message);
        end

        try
            totalFrames = vr.NumFrames;
        catch
            totalFrames = round(vr.Duration * vr.FrameRate);
            fprintf('  Warning: NumFrames unavailable, estimated as %d\n', totalFrames);
        end

        fprintf('  %dx%d @ %.1ffps | %d frames | every %d\n', ...
                vr.Width, vr.Height, vr.FrameRate, totalFrames, yoloConfig.frameSample);
        fprintf('  Method: %s (whole-video inference via bee_tracker_btrac.py)\n', ...
                yoloConfig.detectionMethod);

% ── Run Python inference (blocking — MATLAB waits for completion) ──
        fprintf('  [BTRAC] Launching bee_tracker_btrac.py...\n');
        fprintf('  [BTRAC] MATLAB will wait here until Python finishes.\n');
        fprintf('  [BTRAC] Live output below:\n');
        fprintf('  %s\n', repmat('-', 1, 55));

        detCSV = runBTracPython(videoPath, yoloConfig);

        fprintf('  %s\n', repmat('-', 1, 55));
        fprintf('  [BTRAC] Python complete. Loading detections...\n');

        % ── Load completed CSV all at once ───────────────────────────────
        allDets = loadDetectionsCSV(detCSV, yoloConfig.confidenceThreshold);
        fprintf('  [BTRAC] Loaded %d detections from CSV.\n', height(allDets));

        % ── Initialize tracking state ────────────────────────────────────
        rawFrameCount   = 0;
        processedFrames = 0;
        activeTrackers  = struct([]);
        nextTrackID     = 1;
        totalDetections = 0;

        % ── Tracking loop — video playback only, detections already known ─
        while hasFrame(vr)
            frame         = readFrame(vr);
            rawFrameCount = rawFrameCount + 1;

            if mod(rawFrameCount - 1, yoloConfig.frameSample) ~= 0
                clear frame; continue;
            end
            processedFrames = processedFrames + 1;

            % Look up detections for this frame from the completed table
            if ~isempty(allDets) && ismember('frame', allDets.Properties.VariableNames)
                frameDets = allDets(allDets.frame == rawFrameCount, :);
            else
                frameDets = table();
            end
            dets = tableRowsToDetStruct(frameDets);

            if ~isempty(dets)
                totalDetections = totalDetections + numel(dets);
            end

            [activeTrackers, trajectories, nextTrackID] = updateTrackers( ...
                activeTrackers, dets, trajectories, processedFrames, ...
                nextTrackID, MAX_DISTANCE, MAX_MISSES, MIN_TRAJ_LENGTH, MIN_NET_MOTION);

            updateDisplay(displayAxes, frame, activeTrackers, ...
                          processedFrames, length(trajectories), totalDetections);

            elapsed = toc;
            effectiveFrames = max(1, ceil(totalFrames / yoloConfig.frameSample));
            pct   = 100 * processedFrames / effectiveFrames;
            rem_t = max(0, (elapsed / max(processedFrames/effectiveFrames, 1e-6)) - elapsed);
            fprintf('  [%5.1f%%] fr %d | active %d | saved %d | dets %d | ~%.0fs left\n', ...
                    pct, processedFrames, length(activeTrackers), ...
                    length(trajectories), totalDetections, rem_t);
            drawnow;
            clear frame;
        end

        %% Flush remaining trackers
        for i = 1:length(activeTrackers)
            if isValidTrajectory(activeTrackers(i).positions, MIN_TRAJ_LENGTH, MIN_NET_MOTION)
                trajectories{end+1} = activeTrackers(i).positions;
            end
        end
        clear activeTrackers;

        fprintf('  Done: %.1fs | Dets: %d | Valid trajectories: %d\n', ...
                toc, totalDetections, length(trajectories));

        departureAngles = extractDepartureAngles(trajectories, cameraParams, MIN_NET_MOTION);
        if ~isempty(departureAngles)
            fprintf('  Bearings: %d (mean %.1f deg, std %.1f deg)\n', ...
                    length(departureAngles), mean(departureAngles), std(departureAngles));
        else
            fprintf('  Bearings: 0 (no qualifying trajectories found)\n');
        end

        exportSessionExcel(trajectories, departureAngles, cameraParams, session.name);

    catch ME
        error('processVideo failed: %s\n%s', ME.message, getReport(ME));
    end
end


%% =========================================================================
%% CONFIG DEFAULTS
%% =========================================================================

function cfg = applyDefaults(cfg)
    cfg.detectionMethod     = 'YOLO';
    cfg.useYOLO             = true;
    if ~isfield(cfg, 'confidenceThreshold'), cfg.confidenceThreshold = 0.35;  end
    if ~isfield(cfg, 'frameSample'),         cfg.frameSample         = 1;     end
    if ~isfield(cfg, 'imgSize'),             cfg.imgSize             = 1280;  end
    if ~isfield(cfg, 'classId'),             cfg.classId             = 0;     end
end


%% =========================================================================
%% VIDEO VALIDATION
%% =========================================================================

function videoPath = validateVideoFile(session)
    if ~isfield(session,'videoFile') || isempty(strtrim(session.videoFile))
        error('No video file set for session "%s".', session.name);
    end
    videoPath = strtrim(session.videoFile);
    if ~exist(videoPath, 'file')
        error('Video file not found:\n  %s', videoPath);
    end
    [~,~,ext] = fileparts(videoPath);
    supported = {'.mp4','.avi','.mov','.mkv','.mj2','.wmv','.m4v'};
    if ~any(strcmpi(ext, supported))
        error('Unsupported format "%s". Supported: %s', ext, strjoin(supported,', '));
    end
end


%% =========================================================================
%% WHOLE-VIDEO PYTHON INFERENCE  (replaces per-frame detectBeesYOLO)
%% =========================================================================

function detCSV = runBTracPython(videoPath, yoloConfig)
% Runs bee_tracker_btrac.py synchronously. Streams its log to the MATLAB
% console in real time. MATLAB blocks until Python exits.

    detCSV = '';

    scriptCandidates = { ...
        fullfile(fileparts(mfilename('fullpath')), 'bee_tracker_btrac.py'), ...
        'bee_tracker_btrac.py' };

    scriptPath = '';
    for k = 1:numel(scriptCandidates)
        if exist(scriptCandidates{k}, 'file')
            scriptPath = scriptCandidates{k};  break;
        end
    end
    if isempty(scriptPath)
        error('bee_tracker_btrac.py not found.');
    end

    outCSV = 'btrac_detections.csv';
    logFile = 'btrac_python.log';

    % Delete stale files
    if exist(outCSV,  'file'), delete(outCSV);  end
    if exist(logFile, 'file'), delete(logFile); end

    % Build command — quoted paths handle spaces on Windows
    cmd = sprintf('"%s" "%s" "%s" "%s" --conf %.3f --imgsz %d --every_n %d --class_id %d --output "%s"', ...
        yoloConfig.pythonExe, scriptPath, ...
        yoloConfig.modelPath, videoPath, ...
        yoloConfig.confidenceThreshold, ...
        yoloConfig.imgSize, ...
        yoloConfig.frameSample, ...
        yoloConfig.classId, ...
        outCSV);

    % Launch Python — redirect output to log file, run in background
    % so we can tail the log. We use ProcessBuilder just to get the
    % handle for waitFor(); all output goes to the log.
    tokens = strsplit(cmd);
    jArray = javaArray('java.lang.String', numel(tokens));
    for k = 1:numel(tokens)
        jArray(k) = java.lang.String(tokens{k});
    end
    jList = java.util.ArrayList();
    for k = 1:numel(tokens)
        jList.add(jArray(k));
    end

    pb = java.lang.ProcessBuilder(jList);
    pb.redirectErrorStream(true);
    pb.redirectOutput(java.io.File(logFile));
    process = pb.start();

    % ── Tail the log file until Python exits ────────────────────────────
    lastLine  = 0;
    t0        = tic;
    TIMEOUT_S = 3600;   % 1 hour — long videos can take a while

    fprintf('  [BTRAC] Python running... (output from btrac_python.log)\n');

    while true
        pause(2);   % poll every 2 seconds

        % Print any new log lines
        try
            if exist(logFile, 'file')
                logLines = readlines(logFile);   % R2020b+
                logLines = logLines(logLines ~= "");
                if numel(logLines) > lastLine
                    for li = lastLine+1 : numel(logLines)
                        fprintf('  [PY] %s\n', logLines(li));
                    end
                    lastLine = numel(logLines);
                end
            end
        catch
            % Log not written yet or mid-write — skip
        end

        % Check if Python has exited
        try
            exitVal = process.exitValue();   % throws if still running
            % Print any final lines
            try
                logLines = readlines(logFile);
                logLines = logLines(logLines ~= "");
                for li = lastLine+1 : numel(logLines)
                    fprintf('  [PY] %s\n', logLines(li));
                end
            catch; end
            fprintf('  [BTRAC] Python exited (code %d) after %.0fs.\n', exitVal, toc(t0));
            break;
        catch
            % Still running — normal
        end

        if toc(t0) > TIMEOUT_S
            process.destroy();
            error('[BTRAC] Python timed out after %d seconds.', TIMEOUT_S);
        end
    end

    if ~exist(outCSV, 'file')
        error('[BTRAC] Python finished but %s was not created. Check btrac_python.log', outCSV);
    end

    detCSV = outCSV;
end


%% =========================================================================
%% LOAD DETECTIONS CSV → MATLAB TABLE
%% =========================================================================

function T = loadDetectionsCSV(csvPath, confThreshold)
% loadDetectionsCSV  Read btrac_detections.csv and filter by confidence.
%   Returns a table with columns: frame, x1, y1, x2, y2, cx, cy, confidence

    try
        T = readtable(csvPath, 'TextType', 'string');
    catch ME
        warning('Could not read %s: %s', csvPath, ME.message);
        T = table();
        return;
    end

    % Filter by confidence threshold
    if ismember('confidence', T.Properties.VariableNames) && ~isempty(T)
        T = T(T.confidence >= confThreshold, :);
    end
end


%% =========================================================================
%% CONVERT TABLE ROWS → DETECTION STRUCT ARRAY  (same format as before)
%% =========================================================================

function dets = tableRowsToDetStruct(rows)
% tableRowsToDetStruct  Convert a subset of the detections table to the
%   struct array format used by updateTrackers.
%   dets(i).Centroid    = [cx, cy]
%   dets(i).BoundingBox = [x1, y1, w, h]
%   dets(i).Confidence  = score

    if isempty(rows) || height(rows) == 0
        dets = struct([]);
        return;
    end

    n = height(rows);
    dets(n).Centroid    = [];
    dets(n).BoundingBox = [];
    dets(n).Confidence  = [];

    for i = 1:n
        w = rows.x2(i) - rows.x1(i);
        h = rows.y2(i) - rows.y1(i);
        dets(i).Centroid    = [rows.cx(i), rows.cy(i)];
        dets(i).BoundingBox = [rows.x1(i), rows.y1(i), w, h];
        dets(i).Confidence  = rows.confidence(i);
    end
end


%% =========================================================================
%% TRAJECTORY VALIDATION
%% =========================================================================

function valid = isValidTrajectory(positions, minLen, minMotion)
% Rejects noise using: length, net displacement, and directional consistency.
% Directional consistency: net/totalPath >= 0.25
%   Bees fly in one direction => score ~1.0
%   Swaying branches/grass => large total path, near-zero net => score ~0

    if size(positions,1) < minLen, valid = false; return; end

    dx  = positions(end,1) - positions(1,1);
    dy  = positions(end,2) - positions(1,2);
    net = sqrt(dx^2 + dy^2);
    if net < minMotion, valid = false; return; end

    steps     = diff(positions(:,1:2), 1, 1);
    totalPath = sum(sqrt(sum(steps.^2, 2)));
    if totalPath > 0 && (net / totalPath) < 0.25
        valid = false; return;
    end

    valid = true;
end


%% =========================================================================
%% TRACKING
%% =========================================================================

function [trackers, trajs, nextID] = updateTrackers( ...
        trackers, dets, trajs, frameNum, nextID, maxDist, maxMiss, minLen, minMotion)

    nD = numel(dets);

    if isempty(trackers)
        for i = 1:nD
            trackers = [trackers, makeTrack(nextID, dets(i).Centroid, frameNum)]; %#ok<AGROW>
            nextID   = nextID + 1;
        end
        return;
    end

    nT = length(trackers);
    if nD == 0
        for i = 1:nT
            trackers(i).misses = trackers(i).misses + 1;
        end
    else
        assigned = false(nD,1);
        for i = 1:nT
            lastPos = trackers(i).positions(end, 1:2);
            bestD = inf;  bestJ = -1;
            for j = 1:nD
                if assigned(j), continue; end
                d = norm(lastPos - dets(j).Centroid);
                if d < maxDist && d < bestD
                    bestD = d;  bestJ = j;
                end
            end
            if bestJ > 0
                trackers(i).positions(end+1,:) = [dets(bestJ).Centroid, frameNum];
                trackers(i).misses             = 0;
                assigned(bestJ)                = true;
            else
                trackers(i).misses = trackers(i).misses + 1;
            end
        end
        for j = 1:nD
            if ~assigned(j)
                trackers = [trackers, makeTrack(nextID, dets(j).Centroid, frameNum)]; %#ok<AGROW>
                nextID   = nextID + 1;
            end
        end
    end

    keep = false(length(trackers),1);
    for i = 1:length(trackers)
        if trackers(i).misses > maxMiss
            if isValidTrajectory(trackers(i).positions, minLen, minMotion)
                trajs{end+1} = trackers(i).positions; %#ok<AGROW>
            end
        else
            keep(i) = true;
        end
    end
    trackers = trackers(keep);
end

function t = makeTrack(id, centroid, frameNum)
    t.id        = id;
    t.positions = [centroid, frameNum];
    t.misses    = 0;
end


%% =========================================================================
%% BEARING EXTRACTION
%% =========================================================================

function angles = extractDepartureAngles(trajs, cameraParams, minMotion)
    if isempty(trajs), angles = []; return; end
    H      = cameraParams.compassHeading;
    angles = nan(length(trajs),1);
    for i = 1:length(trajs)
        pos = trajs{i};
        if size(pos,1) < 2, continue; end
        dx = pos(end,1) - pos(1,1);
        dy = pos(end,2) - pos(1,2);
        if norm([dx,dy]) < minMotion, continue; end
        angles(i) = mod(H + atan2(dx,-dy)*(180/pi) + 360, 360);
    end
    angles = angles(~isnan(angles));
end


%% =========================================================================
%% LIVE DISPLAY
%% =========================================================================

function updateDisplay(ax, frame, trackers, fNum, saved, dets)
% updateDisplay  Render live YOLO tracking preview.
    imshow(frame, 'Parent', ax);
    hold(ax, 'on');

    cols = {'r','c','m','y','w','g'};
    for i = 1:length(trackers)
        p   = trackers(i).positions;
        col = cols{mod(i-1, length(cols)) + 1};
        if size(p, 1) >= 2
            plot(ax, p(:,1), p(:,2), '-', 'Color', col, 'LineWidth', 1.5);
        end
        plot(ax, p(end,1), p(end,2), 'o', 'Color', col, ...
             'MarkerSize', 8, 'LineWidth', 2, 'MarkerFaceColor', 'none');
    end

    title(ax, sprintf('YOLO | Frame %d | Active: %d | Saved: %d | Dets: %d', ...
          fNum, length(trackers), saved, dets), ...
          'FontSize', 9, 'Color', 'white', 'BackgroundColor', [0.1 0.1 0.1]);
    hold(ax, 'off');
end


%% =========================================================================
%% EXCEL EXPORT  — one workbook per session
%% =========================================================================

function exportSessionExcel(trajectories, departureAngles, cameraParams, sessionName)
% exportSessionExcel  Write a .xlsx workbook for one processed session.

    safeName  = regexprep(sessionName, '[^\w\-]', '_');
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    xlsxFile  = sprintf('BTRAC_%s_%s.xlsx', safeName, timestamp);

    nTrajs = length(trajectories);
    H      = cameraParams.compassHeading;
    MIN_MOTION = 15;

    bearingPerTraj = nan(nTrajs, 1);
    for i = 1:nTrajs
        pos = trajectories{i};
        if size(pos, 1) < 2, continue; end
        dx = pos(end,1) - pos(1,1);
        dy = pos(end,2) - pos(1,2);
        if norm([dx, dy]) >= MIN_MOTION
            bearingPerTraj(i) = mod(H + atan2(dx,-dy)*(180/pi) + 360, 360);
        end
    end

    % Sheet 1 — Trajectories
    rowData = {};
    rowData = [rowData; {'TrajectoryID','PointIndex','X_px','Y_px','Frame'}];
    for i = 1:nTrajs
        pos = trajectories{i};
        nPts = size(pos, 1);
        if ~isnan(bearingPerTraj(i))
            bearing_str = sprintf('%.2f deg', bearingPerTraj(i));
        else
            bearing_str = 'no valid bearing';
        end
        rowData = [rowData; {sprintf('--- Trajectory %d  (bearing: %s) ---', i, bearing_str), ...
                             '', '', '', ''}]; %#ok<AGROW>
        for p = 1:nPts
            rowData = [rowData; {i, p, pos(p,1), pos(p,2), pos(p,3)}]; %#ok<AGROW>
        end
        rowData = [rowData; {'', '', '', '', ''}];
    end

    try
        writecell(rowData, xlsxFile, 'Sheet', 'Trajectories');
    catch ME
        warning('Excel Sheet 1 write failed: %s', ME.message);
        return;
    end

    % Sheet 2 — Bearings Summary
    summaryHeader = {'TrajectoryID','StartX_px','StartY_px','EndX_px','EndY_px', ...
                     'NumPoints','NetDisplacement_px','Bearing_deg','BearingStatus'};
    summaryRows = {};
    for i = 1:nTrajs
        pos  = trajectories{i};
        dx   = pos(end,1) - pos(1,1);
        dy   = pos(end,2) - pos(1,2);
        netD = sqrt(dx^2 + dy^2);
        if ~isnan(bearingPerTraj(i))
            brg_val    = bearingPerTraj(i);
            brg_status = 'Valid';
        else
            brg_val    = NaN;
            brg_status = 'Below motion threshold';
        end
        summaryRows = [summaryRows; {i, pos(1,1), pos(1,2), pos(end,1), pos(end,2), ...
                                     size(pos,1), netD, brg_val, brg_status}]; %#ok<AGROW>
    end

    validBrgs = bearingPerTraj(~isnan(bearingPerTraj));
    if ~isempty(validBrgs)
        r = deg2rad(validBrgs);
        circMeanBrg = mod(rad2deg(atan2(mean(sin(r)), mean(cos(r)))), 360);
        circStd     = rad2deg(sqrt(-2 * log(sqrt(mean(sin(r))^2 + mean(cos(r))^2))));
    else
        circMeanBrg = NaN;  circStd = NaN;
    end

    summaryRows = [summaryRows; {'', '', '', '', '', '', '', '', ''}];
    summaryRows = [summaryRows; {'SUMMARY', '', '', '', '', ...
                                 length(validBrgs), '', circMeanBrg, ...
                                 sprintf('Circular mean (n=%d, circ_std=%.1f deg)', ...
                                         length(validBrgs), circStd)}];

    try
        writecell([summaryHeader; summaryRows], xlsxFile, 'Sheet', 'Bearings Summary');
        fprintf('  [Excel] Saved: %s\n', xlsxFile);
    catch ME
        warning('Excel Sheet 2 write failed: %s', ME.message);
    end
end
