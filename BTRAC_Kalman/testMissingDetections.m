
function result = testMissingDetections()
% B-TRAC Kalman missingdetection verification
% Evaluates prediction coverage and positional accuracy
% during gaps of 1, 3, 5, and 8 consecutive frames

rng(20261030);
frames = (1:65)';
truePos = [100 + 5*frames, 200 + 2*frames];
noise = 1.5;
measured = truePos + noise*randn(size(truePos));
cfg = struct('q',0.2,'measurementSigma',noise);
gapSizes = [1 3 5 8];
numTrials = 5;
numExpected = 0;
numPredicted = 0;
allErrors = [];

% Trial columns:
% Gap, Trial, Expected, Predicted, Coverage, mean error, max error
rows = zeros(length(gapSizes)*numTrials,7);
rowNumber = 0;
for g = gapSizes

    for trial = 1:numTrials
        startFrame = 19 + 5*(trial-1);
        missing = startFrame:(startFrame+g-1);
        %start each trial with a fresh kf
        [track,~] = kalmanBeeFilter( ...
            'init',[],measured(1,:),frames(1),cfg);

        predicted = nan(length(frames),2);
        for k = 2:length(frames)

            [track,out] = kalmanBeeFilter( ...
                'predict',track,frames(k));
            if ismember(k,missing)
                %Predict without correcting
                predicted(k,:) = out.position;
            else
                [track,~] = kalmanBeeFilter( ...
                    'correct',track,measured(k,:));
            end
        end

        % Compare predictions to known true positions
        predictedGap = predicted(missing,:);
        trueGap = truePos(missing,:);
        valid = all(isfinite(predictedGap),2);
        count = sum(valid);
        errors = sqrt(sum((predictedGap(valid,:) -trueGap(valid,:)).^2,2));

        numExpected = numExpected+ g;
        numPredicted = numPredicted + count;
        allErrors = [allErrors; errors]; %#ok<AGROW>
        meanError = NaN;
        maxError = NaN;

        if ~isempty(errors)
            meanError = mean(errors);
            maxError = max(errors);
        end
        coverage = 100*count/g;
        rowNumber = rowNumber + 1;
        rows(rowNumber,:) = [ ...
            g,trial,g,count,coverage,meanError,maxError];
    end
end

%Overall verification results
result.coverage = 100*numPredicted/numExpected;
result.meanError = NaN;
result.maxError = NaN;

if ~isempty(allErrors)
    result.meanError = mean(allErrors);
    result.maxError = max(allErrors);
end

result.pass = ...
    numPredicted == numExpected &&isfinite(result.meanError) && ...
    result.meanError <= 15;

% Export trial-level data

resultsDir = fullfile(fileparts(mfilename('fullpath')),'Results');
if ~exist(resultsDir,'dir')
    mkdir(resultsDir);
end

T = array2table(rows,'VariableNames', ...
    {'GapFrames','Trial','Expected','Predicted','Coverage_pct','MeanError_px','MaxError_px'});
writetable(T,fullfile(resultsDir,'GapResults.csv'));

%Summary by gap length
summaryRows = zeros(length(gapSizes),6);

for i = 1:length(gapSizes)
    g = gapSizes(i);
    selected = T.GapFrames == g;
    data = T(selected,:);
    expected = sum(data.Expected);
    predictedCount = sum(data.Predicted);

    % Each trial has the same gap length
    %weight error means by valid prediction count
    validTrials = data.Predicted > 0;

    meanError = NaN;
    maxError = NaN;

    if any(validTrials)
        meanError = sum(data.MeanError_px(validTrials) .*data.Predicted(validTrials)) / predictedCount;
        maxError = max(data.MaxError_px(validTrials));
    end
    summaryRows(i,:) = [g,expected,predictedCount, 100*predictedCount/expected, ...
        meanError,maxError];
end

S = array2table(summaryRows,'VariableNames', ...
    {'GapFrames','Expected','Predicted', ...
     'Coverage_pct','MeanError_px','MaxError_px'});
writetable(S,fullfile(resultsDir,'GapSummary.csv'));
% Console output

fprintf('\n=== MISSING DETECTION VERIFICATION ===\n');
disp(S);
fprintf('Overall prediction coverage: %d/%d (%.1f%%)\n',numPredicted,numExpected,result.coverage);
fprintf('Overall mean prediction error: %.2f px\n',result.meanError);
fprintf('Maximum prediction error: %.2f px\n',result.maxError);
fprintf('PASS criteria: 100%% coverage and mean error <= 15 px\n');
fprintf('PASS = %d\n',result.pass);

% Figure for report
figure('Name','Missing Detection Prediction Error');
bar(S.GapFrames,S.MeanError_px);

xlabel('Consecutive Missing Frames');
ylabel('Mean Prediction Error (pixels)');
title('Kalman Prediction Error During Detection Gaps');
grid on;
exportgraphics(gcf, ...
    fullfile(resultsDir,'GapPredictionError.png'), ...
    'Resolution',300);
end