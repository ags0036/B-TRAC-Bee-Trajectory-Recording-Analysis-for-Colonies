function result = testPathSwapping()
% B-TRAC path swapping verification
% Compares greedy nearest neighbor association using
% 1. Last measured position (original tracker)
% 2. Kalman predicted position
%
% Both trackers receive the same detections and use the same gate.

rng(20261101);
numTrials = 50;
noiseLevels = [1 3 5 10];
gate = 120;

scenarioNames = {'Opposing','Perpendicular','Overtaking', ...
                 'ThreeBee','Curved'};
% Results columns:
% Scenario, Noise, Trial, BaselineAccuracy, KFAccuracy,
% BaselineSwitches, KFSwitches, Baseline correct assignments, kalman
% correct assignmnets, baseline incorrect assignments, kf incorrect
% assignments, baseline missed, kf missed, total opportunities
rows = zeros(length(scenarioNames)*length(noiseLevels)*numTrials,14);
rowNumber = 0;

% Store one example per scenario for visualization.
examples = cell(length(scenarioNames),1);
bestImprovement = -inf(length(scenarioNames),1);
for s = 1:length(scenarioNames)
    for n = 1:length(noiseLevels)
        noise = noiseLevels(n);
        cfg = struct('q',0.2,'measurementSigma',noise);
        for trial = 1:numTrials

            % Generate true bee paths
            truePositions = generateBeePaths(s,trial);
            N = size(truePositions,1);
            numBees = size(truePositions,2);
            % Simulate noisy YOLO detections
            detections = zeros(N,numBees,2);
            ids = zeros(N,numBees);

            for k = 1:N
                positions = reshape(truePositions(k,:,:),[numBees 2]);
                positions = positions + noise*randn(numBees,2);
                % Randomize detection order independently each frame
                order = randperm(numBees);
                detections(k,:,:) = reshape(positions(order,:),[1 numBees 2]);
                ids(k,:) = order;
            end
            % Run both trackers on identical detections
            [baseAccuracy,baseSwitches,baseTracks, baseCorrect, ...
                baseIncorrect, baseMissed, baseTotal] = ...
                matchBees(detections,ids,false,gate,cfg);

            [kfAccuracy,kfSwitches,kfTracks, kfCorrect, ...
                kfIncorrect, kfMissed, kfTotal] = ...
                matchBees(detections,ids,true,gate,cfg);
            rowNumber = rowNumber + 1;
            assert(baseTotal == kfTotal, ...
                'Tracking methods have different opportunity counts.');
            rows(rowNumber,:) = [s, noise, trial,baseAccuracy, kfAccuracy, ...
                baseSwitches, kfSwitches,baseCorrect, kfCorrect, ...
                baseIncorrect, kfIncorrect, baseMissed, kfMissed, baseTotal];
            % Save the example with the greatest accuracy improvement
            % Use the lowest noise level for readable trajectory plots
            improvement = kfAccuracy - baseAccuracy;

            if n == 1 && improvement > bestImprovement(s)

                bestImprovement(s) = improvement;
                examples{s}.truth = truePositions;
                examples{s}.baseline = baseTracks;
                examples{s}.kalman = kfTracks;
                examples{s}.firstIDs = ids(1,:);
                examples{s}.trial = trial;
                examples{s}.baseAccuracy = baseAccuracy;
                examples{s}.kfAccuracy = kfAccuracy;
            end
        end
    end
end

% Save numerical results.
resultsDir = fullfile(fileparts(mfilename('fullpath')),'Results');
if ~exist(resultsDir,'dir')
    mkdir(resultsDir);
end
T = array2table(rows,'VariableNames', ...
    {'Scenario','Noise_px','Trial','BaselineAccuracy_pct', ...
     'KFAccuracy_pct','BaselineSwitches','KFSwitches', 'BaselineCorrect',...
     'KFCorrect', 'BaselineIncorrect','KFIncorrect', 'BaselineMissed', ...
     'KFMissed', 'TotalOpportunities'});
writetable(T,fullfile(resultsDir,'PathSwappingResults.csv'));
% Build summary by flight scenario and noise lvel
summaryRows = zeros( ...
    length(scenarioNames)*length(noiseLevels),13);
summaryRow = 0;
for s = 1:length(scenarioNames)
    for n = 1:length(noiseLevels)
        noise = noiseLevels(n);
        selected = rows(:,1)==s & rows(:,2)==noise;
        data = rows(selected,:);
        baseCorrect = sum(data(:,8));
        kfCorrect = sum(data(:,9));
        baseIncorrect = sum(data(:,10));
        kfIncorrect = sum(data(:,11));
        baseMissed = sum(data(:,12));
        kfMissed = sum(data(:,13));
        opportunities = sum(data(:,14));
        %correction
        baseRate = 100*baseCorrect/opportunities;
        kfRate = 100*kfCorrect/opportunities;

        %accuracy conditional on an assignment being made
        baseAssigned = baseCorrect + baseIncorrect;
        kfAssigned = kfCorrect + kfIncorrect;
        baseConditional = NaN;
        kfConditional = NaN;

        if baseAssigned > 0
            baseConditional = 100*baseCorrect/baseAssigned;
        end
        if kfAssigned > 0
            kfConditional = 100*kfCorrect/kfAssigned;
        end

        summaryRow = summaryRow + 1;
        summaryRows(summaryRow,:) = [ ...
            s, noise, ...
            baseRate, kfRate, ...
            baseConditional, kfConditional, ...
            sum(data(:,6)), sum(data(:,7)), ...
            baseIncorrect, kfIncorrect, ...
            baseMissed, kfMissed, ...
            opportunities];
    end
end

S = array2table(summaryRows,'VariableNames', ...
    {'Scenario','Noise_px','BaselineCorrectRate_pct','KFCorrectRate_pct', ...
     'BaselineAssignedAccuracy_pct','KFAssignedAccuracy_pct', ...
     'BaselineSwitches','KFSwitches','BaselineIncorrect','KFIncorrect', ...
     'BaselineMissed','KFMissed','TotalOpportunities'});

S.Scenario = string(scenarioNames(S.Scenario))';
writetable(S,fullfile(resultsDir,'PathSwappingSummary.csv'));


% Compact report sumary with identity switches
numScenarios = length(scenarioNames);
reportRows = zeros(numScenarios, 4);
for s = 1:numScenarios
    selected = S.Scenario == string(scenarioNames{s});
    % Mean association accuracy across noise levels
    nnAccuracy = mean(S.BaselineCorrectRate_pct(selected));
    kfAccuracy = mean(S.KFCorrectRate_pct(selected));

    % Total identity switches across noise levels
    nnSwitches = sum(S.BaselineSwitches(selected));
    kfSwitches = sum(S.KFSwitches(selected));
    reportRows(s,:) = [ ...
        nnAccuracy, kfAccuracy, nnSwitches, kfSwitches];
end

reportTable = array2table(reportRows, ...
    'VariableNames', ...
    {'NN_Accuracy_pct', 'KF_Accuracy_pct', ...
     'NN_Switches', 'KF_Switches'});
reportTable = addvars(reportTable, ...
    string(scenarioNames(:)), ...
    'Before', 1, ...
    'NewVariableNames', 'Scenario');

% Overall pooled association accuracy
totalOpportunities = sum(S.TotalOpportunities);
overallNN = 100 * sum(T.BaselineCorrect) / totalOpportunities;
overallKF = 100 * sum(T.KFCorrect) / totalOpportunities;

overallRow = table( ...
    "Overall", overallNN, overallKF, ...
    sum(S.BaselineSwitches), sum(S.KFSwitches), ...
    'VariableNames', reportTable.Properties.VariableNames);

reportTable = [reportTable; overallRow];

% Round accuracy without changing switch counts
reportTable.NN_Accuracy_pct = round(reportTable.NN_Accuracy_pct, 1);
reportTable.KF_Accuracy_pct = round(reportTable.KF_Accuracy_pct, 1);

writetable(reportTable, ...
    fullfile(resultsDir,'PathSwappingReportSummary.csv'));
disp(reportTable);

%display numerical summary for each scenario and noise level.
fprintf('\n=== PATH SWAPPING RESULTS ===\n');

for s = 1:length(scenarioNames)
    fprintf('\n%s\n',scenarioNames{s});
    for n = 1:length(noiseLevels)
        selected = rows(:,1)==s & rows(:,2)==noiseLevels(n);
        data = rows(selected,:);
        fprintf(['Noise %2d px: Baseline %.1f%%, KF %.1f%%, ' ...
                 'Switches %d vs %d\n'], ...
            noiseLevels(n), ...
            mean(data(:,4)),mean(data(:,5)), ...
            sum(data(:,6)),sum(data(:,7)));
    end

    plotTrackingComparison(examples{s},scenarioNames{s});
    % if ismember(s,[1 3])
    %     plotTrackingComparison(examples{s},scenarioNames{s});
    % end
end

%summary: accuracy against measurement noise
figure('Name','Path Swapping Accuracy Summary');

for s = 1:length(scenarioNames)

    baseMeans = zeros(length(noiseLevels),1);
    kfMeans = zeros(length(noiseLevels),1);

    for n = 1:length(noiseLevels)

        selected = rows(:,1)==s & rows(:,2)==noiseLevels(n);
        baseMeans(n) = mean(rows(selected,4));
        kfMeans(n) = mean(rows(selected,5));
    end

    subplot(2,3,s);
    plot(noiseLevels,baseMeans,'r-o','LineWidth',1.5);
    hold on;
    plot(noiseLevels,kfMeans,'b-o','LineWidth',1.5);
    title(scenarioNames{s});
    xlabel('Measurement Noise (px)');
    ylabel('Association Accuracy (%)');
    ylim([0 105]);
    grid on;
    legend('Original','Kalman','Location','best');
end

sgtitle('B-TRAC Association Accuracy by Flight Scenario');

% Overall result.
result.baselineAccuracy = mean(rows(:,4));
result.kfAccuracy = mean(rows(:,5));
result.baselineSwitches = sum(rows(:,6));
result.kfSwitches = sum(rows(:,7));
result.pass = result.kfAccuracy >= 90;
fprintf('\nOVERALL: Baseline %.1f%%, KF %.1f%%\n', ...
    result.baselineAccuracy,result.kfAccuracy);
fprintf('Identity switches: %d vs %d\n', ...
    result.baselineSwitches,result.kfSwitches);
fprintf('Overall 90%% accuracy criterion: PASS=%d\n',result.pass);

end


function truePositions = generateBeePaths(scenario,trial)
% Generate controlled synthetic bee trajectorie
% Dimensions: frame, bee, XY coordinate
% Paths are not measured bee behavior

t = (0:24)';
N = length(t);

% Change closest approach between trials
separations = [0 2 5 10 20];
speedScales = [0.9 0.95 1.0 1.05 1.1];
%separation = separations(mod(trial-1,length(separations))+1);
sepIdx = mod(trial-1, 5)+1;
speedIdx = mod(floor((trial-1)/5),5)+1;

% Small speed variation across trials
%speedScale = 0.9 + 0.05*mod(trial-1,5);
separation = separations(sepIdx);
speedScale = speedScales(speedIdx);
switch scenario

    case 1  % Opposing directions
        numBees = 2;
        truePositions = zeros(N,numBees,2);
        truePositions(:,1,1) = 202 + 11*speedScale*(t-12);
        truePositions(:,1,2) = 170;
        truePositions(:,2,1) = 202 - 11*speedScale*(t-12);
        truePositions(:,2,2) = 170 + separation;
    case 2  %Perpendicular crossing
        numBees = 2;
        truePositions = zeros(N,numBees,2);
        truePositions(:,1,1) = 202 + 11*speedScale*(t-12);
        truePositions(:,1,2) = 170;
        truePositions(:,2,1) = 202 + separation;
        truePositions(:,2,2) = 170 + 10*speedScale*(t-12);
    case 3  % Overtaking
        numBees = 2;
        truePositions = zeros(N,numBees,2);
        % Both travel right; Bee 2 catches and passes Bee 1
        truePositions(:,1,1) = 202 + 7*speedScale*(t-12);
        truePositions(:,1,2) = 170;
        truePositions(:,2,1) = 202 + 12*speedScale*(t-12);
        truePositions(:,2,2) = 170 + separation;
    case 4  % Three bee convergence
        numBees = 3;
        truePositions = zeros(N,numBees,2);
        truePositions(:,1,1) = 202 + 11*speedScale*(t-12);
        truePositions(:,1,2) = 170;
        truePositions(:,2,1) = 202 - 11*speedScale*(t-12);
        truePositions(:,2,2) = 170 + separation;
        truePositions(:,3,1) = 202 + separation/2;
        truePositions(:,3,2) = 170 + 10*speedScale*(t-12);
    case 5  % Smoothly curved paths
        numBees = 2;
        truePositions = zeros(N,numBees,2);
        truePositions(:,1,1) = 202 + 11*speedScale*(t-12);
        truePositions(:,1,2) = 170 + 0.035*(t-12).^2;
        truePositions(:,2,1) = 202 - 11*speedScale*(t-12);
        truePositions(:,2,2) = 170 + separation ...
                               - 0.035*(t-12).^2;
end
end

% function [accuracy,switches,trackedPositions] = ...
%     matchBees(detections,ids,useKalman,gate,cfg)
function [accuracy,switches,trackedPositions,correct,incorrect,missed,total] = ...
    matchBees(detections,ids,useKalman,gate,cfg)
incorrect = 0; 
missed = 0;
N = size(detections,1);
numBees = size(detections,2);
trackedPositions = nan(N,numBees,2);
lastPos = reshape(detections(1,:,:),[numBees 2]);
trackedPositions(1,:,:) = reshape(lastPos,[1 numBees 2]);

%identify which physical bee each track started with
firstIDs = ids(1,:);
previousIDs = firstIDs;

if useKalman
    % Initialize the first bee Kalman filter
    [tracks(1),~] = kalmanBeeFilter( ...
        'init',[],lastPos(1,:),1,cfg);
    %init remaining bees using the same structure
    for i = 2:numBees
        [tracks(i),~] = kalmanBeeFilter( ...
            'init',[],lastPos(i,:),1,cfg);

    end

end
correct = 0;
total = 0;
switches = 0;
for k = 2:N
    current = reshape(detections(k,:,:),[numBees 2]);

    if useKalman
        expected = zeros(numBees,2);
        for i = 1:numBees
            [tracks(i),out] = kalmanBeeFilter( ...
                'predict',tracks(i),k);
            expected(i,:) = out.position;
        end

    else
        expected = lastPos;
    end

    used = false(numBees,1);
%greedy assignment
for i = 1:numBees
    distances = sqrt(sum((current-expected(i,:)).^2,2));
    distances(used) = inf;
    [distance,j] = min(distances);
    %ignore first three frames for initialization
    if k >= 4
        total = total + 1;
    end

    if distance < gate

        used(j) = true;

        % Retain the actual measured detection.
        lastPos(i,:) = current(j,:);
        trackedPositions(k,i,:) = current(j,:);

        %correction
        if useKalman
            [tracks(i),~] = kalmanBeeFilter( ...
                'correct',tracks(i),current(j,:));
        end
        if k >= 4
            %determine whether this track received
            % the detection belonging to its original bee
            if ids(k,j) == firstIDs(i)
                correct = correct + 1;
            else
                incorrect = incorrect + 1;
            end
            % Count changes in physical bee identity
            if ids(k,j) ~= previousIDs(i)
                switches = switches + 1;
            end

        end
        %udate previous identity after a successful match
        previousIDs(i) = ids(k,j);
    else
        %No detection was assigned within the gate
        % This counts an unmatched association
        if k >= 4
            missed = missed + 1;
        end

    end
end
end

accuracy = 100*correct/total;
% Verify that every eligible opportunity was accounted for
assert(correct + incorrect + missed == total, ...
    'Association counts do not sum to total opportunities.');
end
function plotTrackingComparison(example,scenarioName)
% Plot the known true paths and the assigned detection paths
truth = example.truth;
numBees = size(truth,2);
colors = lines(numBees);
figure('Name',['Tracking - ' scenarioName]);
for method = 1:2
    subplot(1,2,method);
    hold on;
    if method == 1
        tracked = example.baseline;
        title('Original Nearest Neighbor');
    else
        tracked = example.kalman;
        title('Kalman-Based Tracking');
    end
    for bee = 1:numBees
        color = colors(bee,:);
        %known actual pat of this bee.
        trueXY = reshape(truth(:,bee,:),[],2);
        plot(trueXY(:,1),trueXY(:,2),'--', ...
            'Color',color,'LineWidth',1.5);
        %Find which track was initialized with this be
        trackIndex = find(example.firstIDs==bee,1);
        trackedXY = reshape(tracked(:,trackIndex,:),[],2);
        plot(trackedXY(:,1),trackedXY(:,2),'-o', ...
            'Color',color,'LineWidth',1,'MarkerSize',3);
    end
    xlabel('X Position (pixels)');
    ylabel('Y Position (pixels)');
    grid on;
    %Preserve identical axes for both tracking methods
    axis equal;
    xlim([40 365]);
    ylim([35 305]);
end

sgtitle(sprintf('%s - Trial %d (Baseline %.1f%%, KF %.1f%%)', ...
    scenarioName,example.trial, ...
    example.baseAccuracy,example.kfAccuracy));
end
