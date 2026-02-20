function BTRAC_GUI()
% BTRAC_GUI  Bee Trajectory Recording & Analysis for Colonies
%
%   Requires (same folder or on MATLAB path):
%     processVideo.m                   - video processing & tracking
%     bearingAnalysis.m                - circular stats, triangulation, map, export
%     detect_bees_yolov5_optimized.py  - YOLO Python script (YOLO mode only)

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

    % Left grid - 25 rows, children added sequentially (no Layout.Row needed)
    leftGrid = uigridlayout(leftPanel, [23, 1]);
    leftGrid.RowHeight = repmat({'fit'}, 1, 23);
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
    focalGrid = uigridlayout(leftGrid, [1, 2]);
    focalGrid.ColumnWidth = {'2x', '1x'};
    focalGrid.Padding = [0 0 0 0];
    uilabel(focalGrid, 'Text', 'Focal Length (px):');
    focalField = uieditfield(focalGrid, 'numeric', 'Value', 1000);
    uilabel(leftGrid, 'Text', '');  % spacer

    %% Detection Settings
    uilabel(leftGrid, 'Text', 'DETECTION SETTINGS', ...
            'FontSize', 13, 'FontWeight', 'bold');

    detMethodGrid = uigridlayout(leftGrid, [1, 2]);
    detMethodGrid.ColumnWidth = {'2x', '2x'};
    detMethodGrid.Padding = [0 0 0 0];
    uilabel(detMethodGrid, 'Text', 'Detection Method:');
    detMethodDropdown = uidropdown(detMethodGrid, ...
        'Items', {'Background Subtraction', 'YOLO (Deep Learning)'}, ...
        'Value', 'Background Subtraction', ...
        'ValueChangedFcn', @(dd, ~) onMethodChanged(dd.Value));

    % YOLO config panel - hidden until YOLO selected
    yoloPanel = uipanel(leftGrid, 'Title', 'YOLO Configuration', ...
                        'BackgroundColor', [0.94 0.97 1.0], 'Visible', 'off');
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

    uilabel(leftGrid, 'Text', '');  % spacer

    %% Analysis
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
    %% CALLBACKS
    %% ================================================================

    function onMethodChanged(method)
        if strcmp(method, 'YOLO (Deep Learning)')
            yoloPanel.Visible = 'on';
        else
            yoloPanel.Visible = 'off';
        end
    end

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

        appData.cameraParams.focalLength    = focalField.Value;

        useYOLO = strcmp(detMethodDropdown.Value, 'YOLO (Deep Learning)');
        if useYOLO
            if isempty(strtrim(pyExeField.Value))
                uialert(fig, 'Set Python path in Detection Settings.', 'Config Error', 'Icon', 'error'); return;
            end
            if isempty(strtrim(modelPathField.Value)) || ~exist(strtrim(modelPathField.Value), 'file')
                uialert(fig, 'YOLO model not found. Check path.', 'Config Error', 'Icon', 'error'); return;
            end
            appData.yoloConfig.useYOLO             = true;
            appData.yoloConfig.pythonExe           = strtrim(pyExeField.Value);
            appData.yoloConfig.modelPath           = strtrim(modelPathField.Value);
            appData.yoloConfig.confidenceThreshold = confField.Value;
            appData.yoloConfig.frameSample         = frameSampleField.Value;
        else
            appData.yoloConfig.useYOLO = false;
        end

        lockUI(true);
        tag = 'BG Subtraction'; if useYOLO, tag = 'YOLO'; end

        try
            n = length(appData.sessions);
            for i = 1:n
                progressBar.Value = (i-1)/n * 100;
                setStatus(sprintf('[%s] Processing %d/%d: %s ...', ...
                          tag, i, n, appData.sessions(i).name));

                % Build per-session camera params using this session's compass bearing
                sessionCameraParams = appData.cameraParams;
                sessionCameraParams.compassHeading = appData.sessions(i).compassBearing;

                [trajs, angles] = processVideo(appData.sessions(i), ...
                                               sessionCameraParams, ...
                                               resultsAxes, ...
                                               appData.yoloConfig);

                appData.sessions(i).trajectories    = trajs;
                appData.sessions(i).departureAngles = angles;
                appData.sessions(i).processed       = true;

                [appData.sessions(i).avgBearing, ...
                 appData.sessions(i).confidence] = analyzeBearings(angles);

                refreshSessionList();
            end

            progressBar.Value = 100;
            setStatus('Triangulating hive location...');
            drawnow;

            done = appData.sessions([appData.sessions.processed]);
            if length(done) >= 2
                hive = triangulateHive(done);
                appData.results.estimatedHiveLocation = hive;
                createMapVisualization(done, hive, resultsAxes);
                setStatus(sprintf('Done! Hive approx [%.6f, %.6f]', hive(1), hive(2)));
            else
                showSingleResult(done(1));
                setStatus('Done (single session - add more for triangulation).');
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

    %% ================================================================
    %% LOCAL HELPERS
    %% ================================================================

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

end % BTRAC_GUI


%% ================================================================
%% FILE-LOCAL UTILITIES
%% ================================================================

function cp = defaultCameraParams()
    cp.focalLength      = 1000;
    cp.principalPoint   = [960, 540];
    cp.radialDistortion = [0, 0];
    cp.compassHeading   = 0;
end

function yc = defaultYOLOConfig()
    yc.useYOLO             = false;
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