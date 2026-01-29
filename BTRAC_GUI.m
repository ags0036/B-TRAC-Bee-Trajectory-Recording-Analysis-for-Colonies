function BTRAC_GUI()
    % BTRAC_GUI - Bee Trajectory Recording & Analysis for Colonies
    % Interactive GUI application for bee tracking and hive location
    
    %% Initialize GUI
    fig = uifigure('Name', 'B-TRAC - Bee Tracking System', ...
                   'Position', [100, 100, 1200, 800], ...
                   'Color', [0.95 0.95 0.95]);
    
    % Store application data
    appData = struct();
    appData.sessions = [];
    appData.cameraParams = initializeCameraParams();
    appData.results = struct();
    
    %% Create UI Layout
    mainGrid = uigridlayout(fig, [1, 2]);
    mainGrid.ColumnWidth = {'2x', '3x'};
    
    % Left Panel - Controls
    leftPanel = uipanel(mainGrid, 'Title', 'Control Panel', ...
                        'BackgroundColor', [0.98 0.98 0.98]);
    leftGrid = uigridlayout(leftPanel, [20, 1]);
    leftGrid.RowHeight = repmat({'fit'}, 1, 20);
    leftGrid.Padding = [20 20 20 20];
    
    % Right Panel - Results/Visualization
    rightPanel = uipanel(mainGrid, 'Title', 'Results', ...
                         'BackgroundColor', 'white');
    rightGrid = uigridlayout(rightPanel, [1, 1]);
    
    %% LEFT PANEL COMPONENTS
    
    % Title
    titleLabel = uilabel(leftGrid, 'Text', 'B-TRAC System', ...
                        'FontSize', 20, 'FontWeight', 'bold', ...
                        'HorizontalAlignment', 'center');
    
    % Subtitle
    subtitleLabel = uilabel(leftGrid, 'Text', 'Bee Trajectory Analysis', ...
                           'FontSize', 12, 'FontColor', [0.4 0.4 0.4], ...
                           'HorizontalAlignment', 'center');
    
    % Separator
    uilabel(leftGrid, 'Text', '');
    
    % Session Management Section
    sessionLabel = uilabel(leftGrid, 'Text', 'OBSERVATION SESSIONS', ...
                          'FontSize', 14, 'FontWeight', 'bold');
    
    % Session List
    sessionListBox = uilistbox(leftGrid, 'Items', {}, ...
                               'Multiselect', 'off');
    sessionListBox.Layout.Row = 5;
    
    % Add Session Button
    addSessionBtn = uibutton(leftGrid, 'Text', '+ Add New Session', ...
                            'FontSize', 12, 'FontWeight', 'bold', ...
                            'BackgroundColor', [0.2 0.6 0.3], ...
                            'FontColor', 'white', ...
                            'ButtonPushedFcn', @(btn,event) addSession());
    
    % Remove Session Button
    removeSessionBtn = uibutton(leftGrid, 'Text', '- Remove Selected', ...
                               'FontSize', 11, ...
                               'BackgroundColor', [0.8 0.3 0.3], ...
                               'FontColor', 'white', ...
                               'ButtonPushedFcn', @(btn,event) removeSession());
    
    % Separator
    uilabel(leftGrid, 'Text', '');
    
    % Camera Settings Section
    cameraLabel = uilabel(leftGrid, 'Text', 'CAMERA SETTINGS', ...
                         'FontSize', 14, 'FontWeight', 'bold');
    
    % Focal Length
    focalGrid = uigridlayout(leftGrid, [1, 2]);
    focalGrid.ColumnWidth = {'2x', '1x'};
    uilabel(focalGrid, 'Text', 'Focal Length (px):');
    focalField = uieditfield(focalGrid, 'numeric', 'Value', 1000);
    
    % Compass Heading
    compassGrid = uigridlayout(leftGrid, [1, 2]);
    compassGrid.ColumnWidth = {'2x', '1x'};
    uilabel(compassGrid, 'Text', 'Compass Offset (°):');
    compassField = uieditfield(compassGrid, 'numeric', 'Value', 0);
    
    % Separator
    uilabel(leftGrid, 'Text', '');
    
    % Processing Section
    processLabel = uilabel(leftGrid, 'Text', 'ANALYSIS', ...
                          'FontSize', 14, 'FontWeight', 'bold');
    
    % Process All Button
    processBtn = uibutton(leftGrid, 'Text', 'Process All Sessions', ...
                         'FontSize', 14, 'FontWeight', 'bold', ...
                         'BackgroundColor', [0.2 0.4 0.8], ...
                         'FontColor', 'white', ...
                         'ButtonPushedFcn', @(btn,event) processAllSessions());
    
    % Progress Bar
    progressBar = uigauge(leftGrid, 'linear', ...
                         'Limits', [0 100], 'Value', 0);
    
    % Status Label
    statusLabel = uilabel(leftGrid, 'Text', 'Ready', ...
                         'FontSize', 11, ...
                         'HorizontalAlignment', 'center');
    
    % Export Results Button
    exportBtn = uibutton(leftGrid, 'Text', 'Export Results', ...
                        'FontSize', 12, ...
                        'BackgroundColor', [0.5 0.5 0.5], ...
                        'FontColor', 'white', ...
                        'Enable', 'off', ...
                        'ButtonPushedFcn', @(btn,event) exportResults());
    
    %% RIGHT PANEL - Axes for visualization
    resultsAxes = uiaxes(rightGrid);
    resultsAxes.Title.String = 'Results will appear here after processing';
    resultsAxes.XLabel.String = '';
    resultsAxes.YLabel.String = '';
    axis(resultsAxes, 'off');
    
    %% CALLBACK FUNCTIONS
    
    function addSession()
        % Open dialog to add new observation session
        
        % Create dialog
        d = uifigure('Name', 'Add Observation Session', ...
                     'Position', [400, 300, 500, 450]);
        dGrid = uigridlayout(d, [12, 2]);
        dGrid.RowHeight = repmat({'fit'}, 1, 12);
        dGrid.ColumnWidth = {'1x', '2x'};
        dGrid.Padding = [20 20 20 20];
        
        % Session Name
        uilabel(dGrid, 'Text', 'Session Name:');
        nameField = uieditfield(dGrid, 'text', 'Value', sprintf('Session %d', length(appData.sessions)+1));
        
        % Video File
        uilabel(dGrid, 'Text', 'Video File:');
        videoGrid = uigridlayout(dGrid, [1, 2]);
        videoGrid.ColumnWidth = {'3x', '1x'};
        videoPathField = uieditfield(videoGrid, 'text', 'Editable', 'off', 'Value', 'No file selected');
        videoBrowseBtn = uibutton(videoGrid, 'Text', 'Browse', ...
                                  'ButtonPushedFcn', @(btn,event) browseVideo());
        
        % GPS Latitude
        uilabel(dGrid, 'Text', 'Latitude:');
        latField = uieditfield(dGrid, 'numeric', 'Value', 34.7304, 'Limits', [-90 90]);
        
        % GPS Longitude
        uilabel(dGrid, 'Text', 'Longitude:');
        lonField = uieditfield(dGrid, 'numeric', 'Value', -86.5861, 'Limits', [-180 180]);
        
        % GPS File Option
        uilabel(dGrid, 'Text', 'OR Load GPS File:');
        gpsGrid = uigridlayout(dGrid, [1, 2]);
        gpsGrid.ColumnWidth = {'3x', '1x'};
        gpsPathField = uieditfield(gpsGrid, 'text', 'Editable', 'off', 'Value', 'Optional');
        gpsBrowseBtn = uibutton(gpsGrid, 'Text', 'Browse', ...
                               'ButtonPushedFcn', @(btn,event) browseGPS());
        
        % Date
        uilabel(dGrid, 'Text', 'Date:');
        dateField = uieditfield(dGrid, 'text', 'Value', datestr(now, 'yyyy-mm-dd'));
        
        % Notes
        uilabel(dGrid, 'Text', 'Notes:');
        notesField = uitextarea(dGrid, 'Value', '');
        notesField.Layout.Row = 8;
        notesField.Layout.Column = 2;
        
        % Buttons
        uilabel(dGrid, 'Text', '');
        btnGrid = uigridlayout(dGrid, [1, 2]);
        btnGrid.ColumnWidth = {'1x', '1x'};
        
        okBtn = uibutton(btnGrid, 'Text', 'Add Session', ...
                        'BackgroundColor', [0.2 0.6 0.3], ...
                        'FontColor', 'white', ...
                        'ButtonPushedFcn', @(btn,event) confirmAddSession());
        
        cancelBtn = uibutton(btnGrid, 'Text', 'Cancel', ...
                            'ButtonPushedFcn', @(btn,event) close(d));
        
        % Local variables
        selectedVideoFile = '';
        selectedGPSFile = '';
        
        function browseVideo()
            [file, path] = uigetfile({'*.mp4;*.avi;*.mov;*.mkv', 'Video Files (*.mp4,*.avi,*.mov,*.mkv)'}, ...
                                     'Select Video File');
            if file ~= 0
                selectedVideoFile = fullfile(path, file);
                videoPathField.Value = selectedVideoFile;
            end
        end
        
        function browseGPS()
            [file, path] = uigetfile({'*.gpx;*.csv;*.txt', 'GPS Files (*.gpx,*.csv,*.txt)'}, ...
                                     'Select GPS File');
            if file ~= 0
                selectedGPSFile = fullfile(path, file);
                gpsPathField.Value = selectedGPSFile;
                
                % Try to parse GPS file
                try
                    [lat, lon] = parseGPSFile(selectedGPSFile);
                    latField.Value = lat;
                    lonField.Value = lon;
                    uialert(d, sprintf('GPS coordinates loaded: %.6f, %.6f', lat, lon), ...
                           'Success', 'Icon', 'success');
                catch ME
                    uialert(d, ['Could not parse GPS file: ' ME.message], ...
                           'Warning', 'Icon', 'warning');
                end
            end
        end
        
        function confirmAddSession()
            % Validate inputs
            if isempty(selectedVideoFile)
                uialert(d, 'Please select a video file', 'Error', 'Icon', 'error');
                return;
            end
            
            if ~exist(selectedVideoFile, 'file')
                uialert(d, 'Video file does not exist', 'Error', 'Icon', 'error');
                return;
            end
            
            % Create new session
            newSession = struct();
            newSession.name = nameField.Value;
            newSession.videoFile = selectedVideoFile;
            newSession.gpsCoords = [latField.Value, lonField.Value];
            newSession.date = dateField.Value;
            newSession.notes = notesField.Value;
            newSession.processed = false;
            
            % Add to sessions
            if isempty(appData.sessions)
                appData.sessions = newSession;
            else
                appData.sessions(end+1) = newSession;
            end
            
            % Update listbox
            updateSessionList();
            
            % Close dialog
            close(d);
            
            statusLabel.Text = sprintf('Added session: %s', newSession.name);
        end
    end
    
    function removeSession()
        % Remove selected session
        idx = sessionListBox.Value;
        if isempty(idx)
            uialert(fig, 'Please select a session to remove', 'Warning', 'Icon', 'warning');
            return;
        end
        
        % Convert cell to index
        selectedIdx = find(strcmp(sessionListBox.Items, idx{1}));
        
        if ~isempty(selectedIdx)
            % Remove session
            appData.sessions(selectedIdx) = [];
            updateSessionList();
            statusLabel.Text = 'Session removed';
        end
    end
    
    function updateSessionList()
        % Update session listbox
        if isempty(appData.sessions)
            sessionListBox.Items = {};
        else
            items = cell(1, length(appData.sessions));
            for i = 1:length(appData.sessions)
                status = '';
                if appData.sessions(i).processed
                    status = ' ✓';
                end
                items{i} = sprintf('%d: %s [%.4f, %.4f]%s', ...
                    i, appData.sessions(i).name, ...
                    appData.sessions(i).gpsCoords(1), ...
                    appData.sessions(i).gpsCoords(2), status);
            end
            sessionListBox.Items = items;
        end
    end
    
    function processAllSessions()
        % Main processing function
        
        if isempty(appData.sessions)
            uialert(fig, 'Please add at least one observation session', ...
                   'Warning', 'Icon', 'warning');
            return;
        end
        
        % Disable buttons during processing
        processBtn.Enable = 'off';
        addSessionBtn.Enable = 'off';
        removeSessionBtn.Enable = 'off';
        
        % Update camera parameters
        appData.cameraParams.focalLength = focalField.Value;
        appData.cameraParams.compassHeading = compassField.Value;
        
        try
            % Process each session
            nSessions = length(appData.sessions);
            
            for i = 1:nSessions
                % Update progress
                progressBar.Value = (i-1) / nSessions * 100;
                statusLabel.Text = sprintf('Processing session %d of %d: %s', ...
                    i, nSessions, appData.sessions(i).name);
                drawnow;
                
                % Process video
                [trajectories, departureAngles] = processVideoSession(appData.sessions(i), ...
                    appData.cameraParams, resultsAxes);
                
                % Store results
                appData.sessions(i).trajectories = trajectories;
                appData.sessions(i).departureAngles = departureAngles;
                appData.sessions(i).processed = true;
                
                % Analyze bearings
                [avgBearing, confidence, ~] = analyzeBearings(departureAngles, ...
                    appData.sessions(i).gpsCoords);
                
                appData.sessions(i).avgBearing = avgBearing;
                appData.sessions(i).confidence = confidence;
                
                % Update session list
                updateSessionList();
            end
            
            % Update progress
            progressBar.Value = 100;
            statusLabel.Text = 'Triangulating hive location...';
            drawnow;
            
            % Triangulate hive location
            processedSessions = appData.sessions([appData.sessions.processed]);
            
            if length(processedSessions) >= 2
                [~, ~, hiveLocation] = analyzeBearings([], [], processedSessions);
                appData.results.estimatedHiveLocation = hiveLocation;
                
                % Create map visualization
                createMapVisualization(processedSessions, hiveLocation, resultsAxes);
                
                statusLabel.Text = sprintf('Complete! Hive estimated at [%.6f, %.6f]', ...
                    hiveLocation(1), hiveLocation(2));
            else
                uialert(fig, 'Need at least 2 processed sessions for triangulation', ...
                       'Info', 'Icon', 'info');
                statusLabel.Text = 'Processing complete (no triangulation)';
            end
            
            % Enable export
            exportBtn.Enable = 'on';
            
        catch ME
            uialert(fig, ['Error during processing: ' ME.message], ...
                   'Error', 'Icon', 'error');
            statusLabel.Text = 'Error occurred';
        end
        
        % Re-enable buttons
        processBtn.Enable = 'on';
        addSessionBtn.Enable = 'on';
        removeSessionBtn.Enable = 'on';
    end
    
    function exportResults()
        % Export results to files
        
        [file, path] = uiputfile('*.mat', 'Save Results As');
        if file == 0
            return;
        end
        
        % Save MAT file
        results = struct();
        results.sessions = appData.sessions;
        results.estimatedHiveLocation = appData.results.estimatedHiveLocation;
        results.analysisDate = datetime('now');
        results.cameraParams = appData.cameraParams;
        
        [~, name, ~] = fileparts(file);
        fullPath = fullfile(path, file);
        save(fullPath, 'results');
        
        % Export map image
        mapFile = fullfile(path, [name '_map.png']);
        exportgraphics(resultsAxes, mapFile, 'Resolution', 300);
        
        % Export summary text
        txtFile = fullfile(path, [name '_summary.txt']);
        exportSummaryReport(results, txtFile);
        
        uialert(fig, sprintf('Results saved to:\n%s\n%s\n%s', ...
                            fullPath, mapFile, txtFile), ...
               'Export Complete', 'Icon', 'success');
        
        statusLabel.Text = 'Results exported';
    end
    
    %% HELPER FUNCTIONS
    
    function cameraParams = initializeCameraParams()
        cameraParams = struct();
        cameraParams.focalLength = 1000;
        cameraParams.principalPoint = [960, 540];
        cameraParams.radialDistortion = [0, 0];
        cameraParams.compassHeading = 0;
    end
    
    function [lat, lon] = parseGPSFile(filename)
        % Parse GPS file (supports GPX, CSV, TXT formats)
        
        [~, ~, ext] = fileparts(filename);
        
        switch lower(ext)
            case '.gpx'
                % Parse GPX file (simplified)
                gpxText = fileread(filename);
                latMatch = regexp(gpxText, 'lat="([^"]+)"', 'tokens');
                lonMatch = regexp(gpxText, 'lon="([^"]+)"', 'tokens');
                
                if ~isempty(latMatch) && ~isempty(lonMatch)
                    lat = str2double(latMatch{1}{1});
                    lon = str2double(lonMatch{1}{1});
                else
                    error('Could not parse GPX coordinates');
                end
                
            case {'.csv', '.txt'}
                % Try to parse as CSV with lat,lon format
                data = readmatrix(filename);
                if size(data, 2) >= 2
                    lat = data(1, 1);
                    lon = data(1, 2);
                else
                    error('Invalid CSV format');
                end
                
            otherwise
                error('Unsupported GPS file format');
        end
    end
    
end
