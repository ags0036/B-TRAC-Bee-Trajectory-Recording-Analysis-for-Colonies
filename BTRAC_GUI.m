function BTRAC_GUI()
% BTRAC_GUI  Bee Trajectory Recording & Analysis for Colonies
%
%   Requires (same folder or on MATLAB path):
%     processVideo.m                   - video processing & tracking
%     bearingAnalysis.m                - circular stats, triangulation, map, export
%     bee_tracker_btrac.py            - YOLO Python script
%
%  TEST_SCENARIO options:
%    'beeline'    - 3 stations, bees heading to one hive (clean demo)
%    'scatter'    - 4 stations, 25 deg noise (realistic messy data)
%    'long_range' - 4 stations spread ~2 km apart
%    'close_range'- 3 stations within 200 m (backyard scenario)
% =========================================================================

    % ------------------------------------------------------------------ %
    %  "DEFINE" FLAGS  —  edit the two lines below                        %
    TEST_MODE     = false;          % true  = skip GUI, show synthetic plots
    TEST_SCENARIO = 'beeline';      % 'beeline' | 'scatter' | 'long_range' | 'close_range'
    NO_BEARINGANALYSIS = false;      % set to true to skip bearing clustering

    if TEST_MODE
        runTestMode(TEST_SCENARIO);
        return;                     % GUI never opens in test mode
    end

    % ==================================================================
    %  Normal GUI path (unchanged from original)
    % ==================================================================

    appData.sessions     = [];
    appData.cameraParams = defaultCameraParams();
    appData.yoloConfig   = defaultYOLOConfig();
    appData.results      = struct('estimatedHiveLocation', []);

    %% Figure
    fig = uifigure('Name', 'B-TRAC - Bee Tracking System', ...
                   'Position', [100, 100, 1280, 860], ...
                   'Color', [0.95 0.95 0.95]);

    %% Main layout
    mainGrid = uigridlayout(fig, [1, 2]);
    mainGrid.ColumnWidth = {'2x', '3x'};

    leftPanel = uipanel(mainGrid, 'Title', 'Control Panel', ...
                        'BackgroundColor', [0.98 0.98 0.98]);
    rightPanel = uipanel(mainGrid, 'Title', 'Results / Live Preview', ...
                         'BackgroundColor', 'white');

    % Left grid - 25 rows
    leftGrid = uigridlayout(leftPanel, [26, 1]);
    leftGrid.RowHeight = repmat({'fit'}, 1, 26);
    leftGrid.Padding = [16 16 16 16];
    leftGrid.RowSpacing = 5;

    % Right grid and axes
    rightGrid = uigridlayout(rightPanel, [1, 1]);
    resultsAxes = uiaxes(rightGrid);
    resultsAxes.Title.String = 'Results will appear here after processing';
    axis(resultsAxes, 'off');

    %% LEFT PANEL - Title
    uilabel(leftGrid, 'Text', 'B-TRAC System', ...
            'FontSize', 20, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center');
    uilabel(leftGrid, 'Text', 'Bee Trajectory Analysis', ...
            'FontSize', 11, 'FontColor', [0.4 0.4 0.4], ...
            'HorizontalAlignment', 'center');
    uilabel(leftGrid, 'Text', '');  % spacer

    %% Sessions
    uilabel(leftGrid, 'Text', 'OBSERVATION SESSIONS', ...
            'FontSize', 13, 'FontWeight', 'bold');
    sessionListBox = uilistbox(leftGrid, 'Items', {}, 'Multiselect', 'off');

    sessionBtnGrid = uigridlayout(leftGrid, [1, 2]);
    sessionBtnGrid.ColumnWidth = {'1x', '1x'};
    sessionBtnGrid.Padding = [0 0 0 0];
    addSessionBtn = uibutton(sessionBtnGrid, 'Text', '+ Add Session', ...
                             'FontWeight', 'bold', ...
                             'BackgroundColor', [0.2 0.6 0.3], 'FontColor', 'white', ...
                             'ButtonPushedFcn', @(~,~) addSession());
    removeSessionBtn = uibutton(sessionBtnGrid, 'Text', '- Remove', ...
                                'BackgroundColor', [0.8 0.3 0.3], 'FontColor', 'white', ...
                                'ButtonPushedFcn', @(~,~) removeSession());
    uilabel(leftGrid, 'Text', '');  % spacer

    %% Camera Settings
    uilabel(leftGrid, 'Text', 'CAMERA SETTINGS', ...
            'FontSize', 13, 'FontWeight', 'bold');

    % Focal length in mm
    focalGrid = uigridlayout(leftGrid, [1, 2]);
    focalGrid.ColumnWidth = {'2x', '1x'};
    focalGrid.Padding = [0 0 0 0];
    uilabel(focalGrid, 'Text', 'Focal Length (mm):', ...
            'Tooltip', 'Physical focal length printed on your lens (e.g. 4, 12, 25 mm)');
    focalField = uieditfield(focalGrid, 'numeric', 'Value', 18, 'Limits', [0.1 2000]);

    % Sensor width in mm
    sensorGrid = uigridlayout(leftGrid, [1, 2]);
    sensorGrid.ColumnWidth = {'2x', '1x'};
    sensorGrid.Padding = [0 0 0 0];
    uilabel(sensorGrid, 'Text', 'Sensor Width (mm) Cannon R7 has 22.3 sensor width :', ...
            'Tooltip', ['Physical width of your camera sensor. ' ...
                        'Common values: phone ~5 mm, 1/2.3" CMOS ~6.2 mm, ' ...
                        'GoPro ~6.2 mm, 4/3" ~17 mm, APS-C ~23 mm, Full-frame ~36 mm']);
    sensorWidthField = uieditfield(sensorGrid, 'numeric', 'Value', 22.3, 'Limits', [0.1 200]);

    uilabel(leftGrid, 'Text', '');  % spacer

    %% Detection Settings
    uilabel(leftGrid, 'Text', 'DETECTION SETTINGS', ...
            'FontSize', 13, 'FontWeight', 'bold');

    uilabel(leftGrid, 'Text', 'Detection Method: YOLO (Deep Learning - YOLOv8)', ...
            'FontSize', 11, 'FontColor', [0.15 0.4 0.75], 'FontWeight', 'bold');

    % YOLO config panel — always visible
    yoloPanel = uipanel(leftGrid, 'Title', 'YOLO Configuration', ...
                        'BackgroundColor', [0.94 0.97 1.0], 'Visible', 'on');
    yoloPanelGrid = uigridlayout(yoloPanel, [5, 2]);
    yoloPanelGrid.ColumnWidth = {'2x', '3x'};
    yoloPanelGrid.RowHeight = repmat({'fit'}, 1, 5);
    yoloPanelGrid.Padding = [8 8 8 8];
    yoloPanelGrid.RowSpacing = 5;

    uilabel(yoloPanelGrid, 'Text', 'Python Exe:');
    pyExeSubGrid = uigridlayout(yoloPanelGrid, [1, 2]);
    pyExeSubGrid.ColumnWidth = {'4x', '1x'};
    pyExeSubGrid.Padding = [0 0 0 0];
    pyExeField = uieditfield(pyExeSubGrid, 'text', 'Value', '');
    uibutton(pyExeSubGrid, 'Text', '...', 'ButtonPushedFcn', @(~,~) browsePyExe());

    uilabel(yoloPanelGrid, 'Text', 'Model (.pt):');
    modelSubGrid = uigridlayout(yoloPanelGrid, [1, 2]);
    modelSubGrid.ColumnWidth = {'4x', '1x'};
    modelSubGrid.Padding = [0 0 0 0];
    modelPathField = uieditfield(modelSubGrid, 'text', 'Value', '');
    uibutton(modelSubGrid, 'Text', '...', 'ButtonPushedFcn', @(~,~) browseModel());

    uilabel(yoloPanelGrid, 'Text', 'Confidence:');
    confField = uieditfield(yoloPanelGrid, 'numeric', 'Value', 0.25, 'Limits', [0.01 1]);

    uilabel(yoloPanelGrid, 'Text', 'Frame Sample (N):');
    frameSampleField = uieditfield(yoloPanelGrid, 'numeric', 'Value', 1, 'Limits', [1 30]);

    uilabel(yoloPanelGrid, 'Text', '');
    uibutton(yoloPanelGrid, 'Text', 'Auto-Detect Python', ...
             'BackgroundColor', [0.3 0.6 0.9], 'FontColor', 'white', ...
             'ButtonPushedFcn', @(~,~) autoDetectPython());



    uilabel(leftGrid, 'Text', '');
    uilabel(leftGrid, 'Text', 'ANALYSIS', 'FontSize', 13, 'FontWeight', 'bold');
    processBtn = uibutton(leftGrid, 'Text', 'Process All Sessions', ...
                          'FontSize', 14, 'FontWeight', 'bold', ...
                          'BackgroundColor', [0.2 0.4 0.8], 'FontColor', 'white', ...
                          'ButtonPushedFcn', @(~,~) processAllSessions());
    progressBar = uigauge(leftGrid, 'linear', 'Limits', [0 100], 'Value', 0);
    statusLabel = uilabel(leftGrid, 'Text', 'Ready', ...
                          'FontSize', 11, 'HorizontalAlignment', 'center', ...
                          'FontColor', [0.2 0.5 0.2]);
    exportBtn = uibutton(leftGrid, 'Text', 'Export Results', ...
                         'FontSize', 12, ...
                         'BackgroundColor', [0.5 0.5 0.5], 'FontColor', 'white', ...
                         'Enable', 'off', ...
                         'ButtonPushedFcn', @(~,~) doExport());

    %% ================================================================
    %% CALLBACKS  (nested — can see appData and all GUI handles)
    %% ================================================================

    function browsePyExe()
        [f, p] = uigetfile({'*.exe;*', 'Executable'}, 'Select Python');
        if f ~= 0, pyExeField.Value = fullfile(p, f); end
    end

    function browseModel()
        [f, p] = uigetfile({'*.pt', 'PyTorch weights (*.pt)'}, 'Select YOLO Model');
        if f ~= 0, modelPathField.Value = fullfile(p, f); end
    end

    function autoDetectPython()
        setStatus('Detecting Python...');
        try
            exe = char(pyenv().Executable);
            if isempty(exe)
                [~, out] = system('where python');
                lines = strsplit(strtrim(out), newline);
                exe = strtrim(lines{1});
            end
            if ~isempty(exe)
                pyExeField.Value = exe;
                setStatus('Python auto-detected');
            else
                setStatus('Not found - set path manually');
            end
        catch
            setStatus('Auto-detect failed - set path manually');
        end
    end

    function addSession()
        d = uifigure('Name', 'Add Observation Session', ...
                     'Position', [400, 300, 500, 420]);
        dGrid = uigridlayout(d, [10, 2]);
        dGrid.ColumnWidth = {'1x', '2x'};
        dGrid.RowHeight = repmat({'fit'}, 1, 10);
        dGrid.Padding = [20 20 20 20];
        dGrid.RowSpacing = 6;

        uilabel(dGrid, 'Text', 'Session Name:');
        nameField = uieditfield(dGrid, 'text', ...
                    'Value', sprintf('Session %d', length(appData.sessions)+1));

        uilabel(dGrid, 'Text', 'Video File:');
        videoSubGrid = uigridlayout(dGrid, [1, 2]);
        videoSubGrid.ColumnWidth = {'4x', '1x'};
        videoSubGrid.Padding = [0 0 0 0];
        videoPathField = uieditfield(videoSubGrid, 'text', 'Editable', 'off', ...
                                     'Value', 'No file selected');
        uibutton(videoSubGrid, 'Text', '...', 'ButtonPushedFcn', @(~,~) browseVideo());

        uilabel(dGrid, 'Text', 'Latitude:');
        latField = uieditfield(dGrid, 'numeric', 'Value', 34.7304, 'Limits', [-90 90]);

        uilabel(dGrid, 'Text', 'Longitude:');
        lonField = uieditfield(dGrid, 'numeric', 'Value', -86.5861, 'Limits', [-180 180]);

        uilabel(dGrid, 'Text', 'Compass Bearing (deg):');
        compassBearingField = uieditfield(dGrid, 'numeric', 'Value', 0, 'Limits', [0 360], ...
                                          'Tooltip', 'Camera heading: 0=North, 90=East, 180=South, 270=West');

        uilabel(dGrid, 'Text', 'GPS File (opt.):');
        gpsSubGrid = uigridlayout(dGrid, [1, 2]);
        gpsSubGrid.ColumnWidth = {'4x', '1x'};
        gpsSubGrid.Padding = [0 0 0 0];
        gpsPathField = uieditfield(gpsSubGrid, 'text', 'Editable', 'off', 'Value', 'Optional');
        uibutton(gpsSubGrid, 'Text', '...', 'ButtonPushedFcn', @(~,~) browseGPS());

        uilabel(dGrid, 'Text', 'Date:');
        dateField = uieditfield(dGrid, 'text', 'Value', datestr(now, 'yyyy-mm-dd'));

        uilabel(dGrid, 'Text', 'Notes:');
        notesField = uitextarea(dGrid, 'Value', '');

        uilabel(dGrid, 'Text', '');
        btnSubGrid = uigridlayout(dGrid, [1, 2]);
        btnSubGrid.ColumnWidth = {'1x', '1x'};
        btnSubGrid.Padding = [0 0 0 0];
        uibutton(btnSubGrid, 'Text', 'Add Session', ...
                 'BackgroundColor', [0.2 0.6 0.3], 'FontColor', 'white', ...
                 'ButtonPushedFcn', @(~,~) confirmAdd());
        uibutton(btnSubGrid, 'Text', 'Cancel', ...
                 'ButtonPushedFcn', @(~,~) close(d));

        selectedVideoFile = '';

        function browseVideo()
            [f, p] = uigetfile({'*.mp4;*.avi;*.mov;*.mkv', 'Video Files'}, 'Select Video');
            if f ~= 0
                selectedVideoFile = fullfile(p, f);
                videoPathField.Value = selectedVideoFile;
            end
        end

        function browseGPS()
            [f, p] = uigetfile({'*.gpx;*.csv;*.txt', 'GPS Files'}, 'Select GPS File');
            if f ~= 0
                try
                    [lat, lon] = parseGPSFile(fullfile(p, f));
                    latField.Value = lat;
                    lonField.Value = lon;
                    gpsPathField.Value = fullfile(p, f);
                    uialert(d, sprintf('GPS loaded: %.6f, %.6f', lat, lon), 'OK', 'Icon', 'success');
                catch ME
                    uialert(d, ['GPS parse failed: ' ME.message], 'Warning', 'Icon', 'warning');
                end
            end
        end

        function confirmAdd()
            if isempty(selectedVideoFile)
                uialert(d, 'Please select a video file.', 'Error', 'Icon', 'error'); return;
            end
            if ~exist(selectedVideoFile, 'file')
                uialert(d, 'Video file not found.', 'Error', 'Icon', 'error'); return;
            end
            ns.name           = nameField.Value;
            ns.videoFile      = selectedVideoFile;
            ns.gpsCoords      = [latField.Value, lonField.Value];
            ns.compassBearing = compassBearingField.Value;
            ns.date           = dateField.Value;
            ns.notes          = notesField.Value;

            % Trajectory and bearing analysis results 
            ns.trajectories     = {};
            ns.departureAngles  = [];
            ns.trajectoryIDs    = [];

            % One value per detected bearing group
            ns.avgBearing   = [];
            ns.confidence   = [];
            
            ns.processed      = false;
            if isempty(appData.sessions)
                appData.sessions = ns;
            else
                appData.sessions(end+1) = ns;
            end
            refreshSessionList();
            setStatus(sprintf('Added: %s', ns.name));
            close(d);
        end
    end

    function removeSession()
        idx = sessionListBox.Value;
        if isempty(idx)
            uialert(fig, 'Select a session first.', 'Warning', 'Icon', 'warning'); return;
        end
        i = find(strcmp(sessionListBox.Items, idx{1}));
        if ~isempty(i)
            appData.sessions(i) = [];
            refreshSessionList();
            setStatus('Session removed.');
        end
    end

    function processAllSessions()
        if isempty(appData.sessions)
            uialert(fig, 'Add at least one session first.', 'Warning', 'Icon', 'warning'); return;
        end

        % Convert focal length mm -> pixels using sensor width and video resolution
        % focal_px = (frame_width_px / sensor_width_mm) * focal_length_mm
        % Read frame width from the first session's video for accuracy,
        % falling back to principalPoint*2 (default 1920) if video is unavailable.
        try
            tmpVR = VideoReader(strtrim(appData.sessions(1).videoFile));
            frameWidthPx = tmpVR.Width;
            clear tmpVR;
        catch
            frameWidthPx = appData.cameraParams.principalPoint(1) * 2;
        end
        focalLengthPx = (frameWidthPx / sensorWidthField.Value) * focalField.Value;
        appData.cameraParams.focalLength   = focalLengthPx;
        appData.cameraParams.focalLengthMm = focalField.Value;
        appData.cameraParams.sensorWidthMm = sensorWidthField.Value;
        fprintf('[Camera] Focal: %.1f mm | Sensor: %.1f mm | Frame: %d px => focal_px = %.1f\n', ...
                focalField.Value, sensorWidthField.Value, frameWidthPx, focalLengthPx);

        % Always YOLO — validate config before proceeding
        if isempty(strtrim(pyExeField.Value))
            uialert(fig, 'Set Python path in Detection Settings.', 'Config Error', 'Icon', 'error'); return;
        end
        if isempty(strtrim(modelPathField.Value)) || ~exist(strtrim(modelPathField.Value), 'file')
            uialert(fig, 'YOLO model not found. Check path.', 'Config Error', 'Icon', 'error'); return;
        end
        appData.yoloConfig.useYOLO             = true;
        appData.yoloConfig.detectionMethod     = 'YOLO';
        appData.yoloConfig.pythonExe           = strtrim(pyExeField.Value);
        appData.yoloConfig.modelPath           = strtrim(modelPathField.Value);
        appData.yoloConfig.confidenceThreshold = confField.Value;
        appData.yoloConfig.frameSample         = frameSampleField.Value;

        lockUI(true);
        tag = 'YOLO';

        try
            n = length(appData.sessions);
            for i = 1:n
                progressBar.Value = (i-1)/n * 100;
                setStatus(sprintf('[%s] Processing %d/%d: %s ...', ...
                          tag, i, n, appData.sessions(i).name));

                sessionCameraParams = appData.cameraParams;
                sessionCameraParams.compassHeading = appData.sessions(i).compassBearing;

                [trajs, angles, trajectoryIDs] = processVideo(appData.sessions(i), ...
                                             sessionCameraParams, ...
                                             resultsAxes, ...
                                             appData.yoloConfig);

                appData.sessions(i).trajectories    = trajs;
                appData.sessions(i).departureAngles = angles;
                appData.sessions(i).processed       = true;
                appData.sessions(i).trajectoryIDs = trajectoryIDs;

                % ── Bearing analysis — skipped when NO_BEARINGANALYSIS = true ──
                % ── Group individual trajectory bearings ──
                % Group individual trajectory bearings
                if ~NO_BEARINGANALYSIS

                    [avgBearings, groupConfidences] = analyzeBearings( ...
                        angles, trajectoryIDs);

                    appData.sessions(i).avgBearing = avgBearings;
                    appData.sessions(i).confidence = groupConfidences;

                else

                    appData.sessions(i).avgBearing = [];
                    appData.sessions(i).confidence = [];

                end

                refreshSessionList();
            end

            progressBar.Value = 100;
            drawnow;

            % ── Post-processing — skipped when NO_BEARINGANALYSIS = true ──────
            % ── Post-processing: display grouped bearing results ──

done = appData.sessions([appData.sessions.processed]);

if ~NO_BEARINGANALYSIS

    if ~isempty(done)

        % Display the grouped bearings from the most recently processed session
        showGroupedResult(done(end));

        totalGroups = 0;

        for k = 1:length(done)
            totalGroups = totalGroups + length(done(k).avgBearing);
        end

        setStatus(sprintf( ...
            'Done. %d session(s) processed; %d bearing group(s) identified.', ...
            length(done), totalGroups));

    else

        setStatus('Processing complete, but no sessions were processed.');

    end

else

    setStatus(sprintf( ...
        'Done. Bearing analysis skipped. %d session(s) processed.', ...
        length(done)));

end

            exportBtn.Enable = 'on';

        catch ME
            uialert(fig, ['Processing error: ' ME.message], 'Error', 'Icon', 'error');
            fprintf('Full error:\n%s\n', getReport(ME));
            setStatus('Error - see MATLAB console.');
        end

        lockUI(false);
    end

    function doExport()
        [file, path] = uiputfile('*.mat', 'Save Results As');
        if file == 0, return; end
        [~, baseName] = fileparts(file);

        results.sessions              = appData.sessions;
        results.cameraParams          = appData.cameraParams;
        results.yoloConfig            = appData.yoloConfig;
        results.analysisDate          = datetime('now');
        results.estimatedHiveLocation = appData.results.estimatedHiveLocation;

        exportResults(results, path, baseName, resultsAxes);
        uialert(fig, sprintf('Saved to:\n%s', path), 'Export Complete', 'Icon', 'success');
        setStatus('Results exported.');
    end

    %% ---- nested helpers (can see appData + GUI handles) ----------------

    function refreshSessionList()
        if isempty(appData.sessions)
            sessionListBox.Items = {}; return;
        end
        items = cell(1, length(appData.sessions));
        for i = 1:length(appData.sessions)
            tick = '';
            if appData.sessions(i).processed, tick = ' [done]'; end
            items{i} = sprintf('%d: %s [%.4f, %.4f]%s', i, ...
                appData.sessions(i).name, ...
                appData.sessions(i).gpsCoords(1), ...
                appData.sessions(i).gpsCoords(2), tick);
        end
        sessionListBox.Items = items;
    end

    function setStatus(msg)
        statusLabel.Text = msg; drawnow;
    end

    function lockUI(on)
        state = 'on'; if on, state = 'off'; end
        processBtn.Enable       = state;
        addSessionBtn.Enable    = state;
        removeSessionBtn.Enable = state;
    end

    function showSingleResult(sess)
        angles = sess.departureAngles;
        cla(resultsAxes);
        if isempty(angles)
            text(resultsAxes, 0.5, 0.5, 'No departures detected.', ...
                 'HorizontalAlignment', 'center', 'Units', 'normalized', 'FontSize', 14);
            return;
        end
        histogram(resultsAxes, angles, 36, 'FaceColor', [0.3 0.7 0.3], 'EdgeColor', 'k');
        xlabel(resultsAxes, 'Bearing (deg from North)');
        ylabel(resultsAxes, 'Count');
        title(resultsAxes, sprintf('%s - Bearings (n=%d)', sess.name, length(angles)), ...
              'FontSize', 12, 'FontWeight', 'bold');
        xlim(resultsAxes, [0 360]);
        grid(resultsAxes, 'on');
    end

function showGroupedResult(sess)

    angles = sess.departureAngles;
    groupBearings = sess.avgBearing;
    groupConfidences = sess.confidence;

    cla(resultsAxes);

    if isempty(angles)

        text(resultsAxes, 0.5, 0.5, 'No departures detected.', ...
             'HorizontalAlignment', 'center', ...
             'Units', 'normalized', ...
             'FontSize', 14);

        return;

    end

    % Plot individual trajectory bearings
    histogram(resultsAxes, angles, 36, ...
              'FaceColor', [0.3 0.7 0.3], ...
              'EdgeColor', 'k');

    hold(resultsAxes, 'on');

    % Mark average bearing and display confidence for each group
    for g = 1:length(groupBearings)

        xline(resultsAxes, groupBearings(g), '--', ...
              sprintf('Group %d: %.1f deg | Conf: %.3f', ...
              g, groupBearings(g), groupConfidences(g)), ...
              'LineWidth', 1.5, ...
              'LabelVerticalAlignment', 'middle');

    end

    hold(resultsAxes, 'off');

    xlabel(resultsAxes, 'Bearing (degrees from North)');
    ylabel(resultsAxes, 'Number of trajectories');

    title(resultsAxes, ...
          sprintf('%s - Grouped Departure Bearings (n=%d, groups=%d)', ...
          sess.name, length(angles), length(groupBearings)), ...
          'FontSize', 12, 'FontWeight', 'bold');

    xlim(resultsAxes, [0 360]);
    grid(resultsAxes, 'on');

end

end % BTRAC_GUI  <-- closes the main function; file-local functions follow


%% ====================================================================
%%  FILE-LOCAL UTILITY FUNCTIONS
%%  These cannot see appData or GUI handles — they are pure utilities.
%% ====================================================================

function cp = defaultCameraParams()
    cp.focalLength      = 1032;   % ~4mm lens / 6.2mm sensor * 1600px — reasonable default
    cp.focalLengthMm    = 4;      % physical focal length in mm (shown in GUI)
    cp.sensorWidthMm    = 6.2;    % sensor width in mm (shown in GUI)
    cp.principalPoint   = [960, 540];
    cp.radialDistortion = [0, 0];
    cp.compassHeading   = 0;
end

function yc = defaultYOLOConfig()
    yc.useYOLO             = true;
    yc.detectionMethod     = 'YOLO';
    yc.pythonExe           = '';
    yc.modelPath           = '';
    yc.confidenceThreshold = 0.25;
    yc.frameSample         = 1;
end

function [lat, lon] = parseGPSFile(filename)
    [~, ~, ext] = fileparts(filename);
    switch lower(ext)
        case '.gpx'
            txt = fileread(filename);
            lm  = regexp(txt, 'lat="([^"]+)"', 'tokens');
            lom = regexp(txt, 'lon="([^"]+)"', 'tokens');
            if isempty(lm) || isempty(lom), error('Cannot parse GPX.'); end
            lat = str2double(lm{1}{1});
            lon = str2double(lom{1}{1});
        case {'.csv', '.txt'}
            data = readmatrix(filename);
            if size(data, 2) < 2, error('Need lat,lon columns.'); end
            lat = data(1, 1); lon = data(1, 2);
        otherwise
            error('Unsupported GPS format: %s', ext);
    end
end

% ------------------------------------------------------------------
%  triangulateHive  — shared by GUI path AND test mode
%  Least-squares intersection of N>=2 bearing lines. 
%  imported from bearingAnalysis.m
%  Returns [lat, lon].
% ------------------------------------------------------------------
function hive = triangulateHive(sessions)
    n      = numel(sessions);
    refLat = sessions(1).gpsCoords(1);
    refLon = sessions(1).gpsCoords(2);
    mPerDegLat = 111320;
    mPerDegLon = 111320 * cosd(refLat);

    A = zeros(2,2);
    b = zeros(2,1);
    I2 = eye(2);

    for k = 1:n
        sx = (sessions(k).gpsCoords(2) - refLon) * mPerDegLon;
        sy = (sessions(k).gpsCoords(1) - refLat) * mPerDegLat;
        p  = [sx; sy];

        dx = sind(sessions(k).avgBearing);
        dy = cosd(sessions(k).avgBearing);
        v  = [dx; dy];

        % Perpendicular projector: I - v*v'
        Pperp = I2 - (v * v');

        w = sessions(k).confidence;   % weight by confidence
        A = A + w * Pperp;
        b = b + w * (Pperp * p);
    end

    xy     = A \ b;
    hive(2) = refLon + xy(1) / mPerDegLon;
    hive(1) = refLat + xy(2) / mPerDegLat;
end
% ------------------------------------------------------------------
%  circMeanBearing — circular mean & concentration (R-bar)
% ------------------------------------------------------------------
function [meanBrg, Rbar] = circMeanBearing(angles_deg)
    rad     = deg2rad(angles_deg);
    S       = mean(sin(rad));
    C       = mean(cos(rad));
    meanBrg = mod(atan2d(S, C), 360);
    Rbar    = sqrt(S^2 + C^2);     % 0 = random, 1 = all same direction
end

% ------------------------------------------------------------------
%  geoBearing — compass bearing (0=N, CW) from point 1 to point 2
% ------------------------------------------------------------------
function brg = geoBearing(lat1, lon1, lat2, lon2)
    mPerDegLon = 111320 * cosd((lat1+lat2)/2);
    dx  = (lon2 - lon1) * mPerDegLon;
    dy  = (lat2 - lat1) * 111320;
    brg = mod(atan2d(dx, dy), 360);
end


%% ====================================================================
%%  TEST MODE  — only reached when TEST_MODE = true
%% ====================================================================

function runTestMode(scenario)
% runTestMode  Build synthetic sessions and render GPS map + bearing rose.
    fprintf('\n');
    fprintf('======================================================\n');
    fprintf('  B-TRAC  >>>  TEST MODE  <<<  Synthetic Data\n');
    fprintf('  Scenario : %s\n', scenario);
    fprintf('======================================================\n\n');

    switch lower(scenario)

        case 'beeline'
            % 3 stations, tight 12-deg spread — clean textbook demo
            trueHive = [34.7320, -86.5830];
            sessions = buildSyntheticSessions( ...
                { 'North Gate',   34.7295, -86.5870,   0 ; ...
                  'South Meadow', 34.7275, -86.5855, 180 ; ...
                  'East Barn',    34.7305, -86.5820,  90 }, ...
                trueHive, 10, 12.0);

        case 'scatter'
            % 4 stations, 25-deg noise — realistic messy data
            trueHive = [34.7340, -86.5810];
            sessions = buildSyntheticSessions( ...
                { 'Station A', 34.7295, -86.5870,  45 ; ...
                  'Station B', 34.7280, -86.5840, 270 ; ...
                  'Station C', 34.7310, -86.5800, 130 ; ...
                  'Station D', 34.7260, -86.5860,  20 }, ...
                trueHive, 12, 25.0);

        case 'long_range'
            % 4 stations ~2 km apart
            trueHive = [34.7400, -86.5700];
            sessions = buildSyntheticSessions( ...
                { 'NW Farm',     34.7290, -86.5920, 315 ; ...
                  'SE Orchard',  34.7180, -86.5680, 135 ; ...
                  'Town Centre', 34.7310, -86.5760,  10 ; ...
                  'River Bank',  34.7240, -86.5850,  60 }, ...
                trueHive, 10, 15.0);

        case 'close_range'
            % 3 stations 150-200 m apart — backyard beekeeping
            trueHive = [34.7308, -86.5856];
            sessions = buildSyntheticSessions( ...
                { 'Front Garden', 34.7302, -86.5868,   0 ; ...
                  'Back Fence',   34.7296, -86.5861, 180 ; ...
                  'Side Gate',    34.7305, -86.5850,  90 }, ...
                trueHive, 15, 8.0);

        otherwise
            error('Unknown TEST_SCENARIO "%s". Use: beeline | scatter | long_range | close_range', scenario);
    end

    hive = triangulateHive(sessions);

    % Print stats table
    fprintf('  %-20s  %-10s  %-8s  %s\n', 'Session', 'Bearing', 'Conc.', 'n');
    fprintf('  %s\n', repmat('-', 1, 50));
    for k = 1:numel(sessions)
        fprintf('  %-20s  %6.1f deg   %5.3f    %2d\n', ...
            sessions(k).name, sessions(k).avgBearing, ...
            sessions(k).confidence, numel(sessions(k).departureAngles));
    end
    fprintf('  %s\n', repmat('-', 1, 50));
    fprintf('  Estimated hive : %.6fN,  %.6fE\n\n', hive(1), hive(2));

    renderTestFigures(sessions, hive, scenario);
    fprintf('  Figures ready — take your screenshots!\n');
    fprintf('  Set TEST_MODE = false to return to normal operation.\n\n');
end

% ------------------------------------------------------------------
%  buildSyntheticSessions
%  stationTable : Nx4 cell array  { name, lat, lon, camHeading ; ... }
%  trueHive     : [lat, lon]
%  nBees        : number of synthetic bee detections per station
%  spreadDeg    : Gaussian std of bearing noise in degrees
% ------------------------------------------------------------------
function sessions = buildSyntheticSessions(stationTable, trueHive, nBees, spreadDeg)
    nStations = size(stationTable, 1);
    sessions  = struct();
    for k = 1:nStations
        sLat    = stationTable{k,2};
        sLon    = stationTable{k,3};
        trueBrg = geoBearing(sLat, sLon, trueHive(1), trueHive(2));

        rng(k * 7 + 13);   % reproducible but varied per station
        angles = mod(trueBrg + spreadDeg * randn(nBees, 1), 360);

        [avgB, conf] = circMeanBearing(angles);

        sessions(k).name            = stationTable{k,1};
        sessions(k).gpsCoords       = [sLat, sLon];
        sessions(k).compassBearing  = stationTable{k,4};
        sessions(k).date            = datestr(now, 'yyyy-mm-dd');
        sessions(k).notes           = sprintf('Synthetic — true bearing %.1f deg', trueBrg);
        sessions(k).departureAngles = angles;
        sessions(k).avgBearing      = avgB;
        sessions(k).confidence      = conf;
        sessions(k).processed       = true;

        % Minimal trajectory structs
        trajs = struct('points', {}, 'bearing', {});
        for j = 1:nBees
            len = 60 + 40*rand();
            r   = deg2rad(angles(j));
            trajs(j).points  = [640, 360; 640+len*sin(r), 360-len*cos(r)];
            trajs(j).bearing = angles(j);
        end
        sessions(k).trajectories = trajs;
    end
end

% ------------------------------------------------------------------
%  renderTestFigures  — 3-panel figure: GPS map + bearing rose
% ------------------------------------------------------------------
function renderTestFigures(sessions, hive, scenario)

    BLUE   = [0.10, 0.40, 0.75];
    GREEN  = [0.15, 0.60, 0.25];
    RED    = [0.80, 0.20, 0.15];
    AMBER  = [0.90, 0.60, 0.05];
    PURPLE = [0.55, 0.10, 0.75];
    TEAL   = [0.05, 0.65, 0.70];
    LTGRAY = [0.93, 0.93, 0.93];
    FONT   = 11;

    stationColours = [BLUE; GREEN; AMBER; PURPLE; TEAL];
    nSessions      = numel(sessions);
    refLat         = sessions(1).gpsCoords(1);
    refLon         = sessions(1).gpsCoords(2);
    mPerDegLat     = 111320;
    mPerDegLon     = 111320 * cosd(refLat);

    stXm = zeros(1, nSessions);
    stYm = zeros(1, nSessions);
    for k = 1:nSessions
        stXm(k) = (sessions(k).gpsCoords(2) - refLon) * mPerDegLon;
        stYm(k) = (sessions(k).gpsCoords(1) - refLat) * mPerDegLat;
    end
    hiveXm = (hive(2) - refLon) * mPerDegLon;
    hiveYm = (hive(1) - refLat) * mPerDegLat;

    figure('Name', sprintf('B-TRAC Test Mode — %s', scenario), ...
           'NumberTitle', 'off', 'Position', [60, 60, 1400, 860], ...
           'Color', LTGRAY);

    sgtitle(sprintf('B-TRAC  |  TEST MODE  |  Scenario: %s  |  %d sessions', ...
            upper(scenario), nSessions), ...
            'FontSize', 15, 'FontWeight', 'bold', 'Color', [0.12 0.12 0.12]);

    % ── GPS map (left 2/3) ─────────────────────────────────────────
    axMap = subplot(1, 3, [1 2]);
    hold(axMap, 'on');
    set(axMap, 'Color', [0.96 0.97 0.99], 'FontSize', FONT);

    lineLen    = 1500;
    legHandles = gobjects(nSessions + 1, 1);

    for k = 1:nSessions
        col  = stationColours(mod(k-1, size(stationColours,1))+1, :);
        brg  = sessions(k).avgBearing;
        conf = sessions(k).confidence;

        % Uncertainty cone
        halfCone   = max(5, (1 - conf) * 40);
        coneAngles = linspace(brg - halfCone, brg + halfCone, 30);
        coneX = [stXm(k), stXm(k) + sind(coneAngles)*lineLen, stXm(k)];
        coneY = [stYm(k), stYm(k) + cosd(coneAngles)*lineLen, stYm(k)];
        patch(axMap, coneX, coneY, col, 'FaceAlpha', 0.08, 'EdgeColor', 'none');

        % Beam + arrow
        dx = sind(brg) * lineLen;
        dy = cosd(brg) * lineLen;
        plot(axMap, [stXm(k), stXm(k)+dx], [stYm(k), stYm(k)+dy], ...
             '-', 'Color', [col, 0.50], 'LineWidth', 1.8);
        quiver(axMap, stXm(k), stYm(k), dx*0.55, dy*0.55, 0, ...
               'Color', col, 'LineWidth', 2.5, 'MaxHeadSize', 0.35);

        legHandles(k) = scatter(axMap, stXm(k), stYm(k), 160, col, 's', 'filled', ...
                                'MarkerEdgeColor', 'k', 'LineWidth', 1.2);

        text(axMap, stXm(k)+18, stYm(k)+18, ...
             sprintf('  %s\n  %.4fN, %.4fE\n  Brg: %.1f deg  (n=%d)', ...
             sessions(k).name, sessions(k).gpsCoords(1), sessions(k).gpsCoords(2), ...
             sessions(k).avgBearing, numel(sessions(k).departureAngles)), ...
             'FontSize', 8.5, 'Color', col * 0.75);
    end

    % Estimated hive crosshair + star
    cs = 30;
    plot(axMap, hiveXm + [-cs cs], [hiveYm hiveYm], '-', 'Color', RED, 'LineWidth', 2.5);
    plot(axMap, [hiveXm hiveXm], hiveYm + [-cs cs], '-', 'Color', RED, 'LineWidth', 2.5);
    legHandles(end) = scatter(axMap, hiveXm, hiveYm, 240, RED, 'p', 'filled', ...
                              'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
    text(axMap, hiveXm + 22, hiveYm - 40, ...
         sprintf(' Estimated Hive\n [%.6fN\n  %.6fE]', hive(1), hive(2)), ...
         'Color', RED, 'FontSize', 9.5, 'FontWeight', 'bold');

    legend(axMap, legHandles, [{sessions.name}, {'Estimated Hive'}], ...
           'Location', 'best', 'FontSize', 9);
    xlabel(axMap, 'East  (m from reference)');
    ylabel(axMap, 'North (m from reference)');
    title(axMap, 'GPS Map  —  Bee-line Bearings & Triangulation', ...
          'FontSize', 13, 'FontWeight', 'bold');
    grid(axMap, 'on');
    axis(axMap, 'equal');
    box(axMap, 'on');

    % ── Bearing rose (right 1/3) ───────────────────────────────────
    axRose = subplot(1, 3, 3);
    hold(axRose, 'on');
    set(axRose, 'Color', [0.97 0.97 0.99], 'FontSize', FONT);

    allAngles = vertcat(sessions.departureAngles);
    nBins     = 24;                             % 15-deg bins
    edges     = linspace(0, 360, nBins+1);
    counts    = histcounts(allAngles, edges);
    binCentres = (edges(1:end-1) + edges(2:end)) / 2;

    % Convert compass bearing -> math angle (so North points up)
    theta_rad = deg2rad(90 - binCentres);
    rMax      = max(counts) * 1.15;
    if rMax == 0, rMax = 1; end

    % Grid rings
    for ri = 1:4
        rv = rMax * ri/4;
        th = linspace(0, 2*pi, 200);
        plot(axRose, rv*cos(th), rv*sin(th), ':', ...
             'Color', [0.75 0.75 0.75], 'LineWidth', 0.8);
        text(axRose, rv*cosd(75), rv*sind(75), sprintf('%.0f', rv), ...
             'FontSize', 7, 'Color', [0.5 0.5 0.5]);
    end

    % Cardinal spokes
    dirs = {0,'N'; 90,'E'; 180,'S'; 270,'W'};
    for s = 1:4
        ang = deg2rad(90 - dirs{s,1});
        plot(axRose, [0, rMax*1.12*cos(ang)], [0, rMax*1.12*sin(ang)], ...
             '-', 'Color', [0.80 0.80 0.80], 'LineWidth', 0.9);
        text(axRose, rMax*1.32*cos(ang), rMax*1.22*sin(ang), dirs{s,2}, ...
             'HorizontalAlignment', 'center', 'FontSize', 11, ...
             'FontWeight', 'bold', 'Color', [0.25 0.25 0.25]);
    end

    % Rose petals
    dw = deg2rad(360/nBins * 0.82);
    for i = 1:nBins
        if counts(i) == 0, continue; end
        t1 = theta_rad(i) - dw/2;
        t2 = theta_rad(i) + dw/2;
        tv = linspace(t1, t2, 20);
        patch(axRose, [0, counts(i)*cos(tv), 0], [0, counts(i)*sin(tv), 0], GREEN, ...
              'FaceAlpha', 0.72, 'EdgeColor', [0.10 0.40 0.15], 'LineWidth', 0.7);
    end

    % Mean resultant arrow
    [meanB, Rbar] = circMeanBearing(allAngles);
    meanRad = deg2rad(90 - meanB);
    quiver(axRose, 0, 0, Rbar*rMax*cos(meanRad), Rbar*rMax*sin(meanRad), 0, ...
           'Color', RED, 'LineWidth', 3.2, 'MaxHeadSize', 0.45);

    text(axRose, 0, -rMax*1.55, ...
         sprintf('Mean bearing : %.1f deg\nCircular conc.: %.3f\nn = %d departures', ...
         meanB, Rbar, numel(allAngles)), ...
         'HorizontalAlignment', 'center', 'FontSize', 9.5, 'Color', [0.12 0.12 0.12]);

    axis(axRose, 'equal', 'off');
    xlim(axRose, [-rMax*1.45, rMax*1.45]);
    ylim(axRose, [-rMax*1.85, rMax*1.55]);
    title(axRose, 'Departure Bearing Rose  (all sessions)', ...
          'FontSize', 12, 'FontWeight', 'bold');
end