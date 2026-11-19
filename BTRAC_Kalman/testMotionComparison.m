function result = testMotionComparison()
% Compare Kalman prediction errors for straight and parabolic bee paths.

rng(20261031);
t = (0:34)';
frames = t + 1;
linear = [100+5*t, 200+2*t];
parabolic = [100+5*t, 200+2*t+0.35*t.^2];
noise = 2;
cfg = struct('q',0.2,'measurementSigma',noise);
numTrials = 50;
errors = zeros(numTrials,2);

for trial = 1:numTrials
    addedNoise = noise*randn(size(linear));
    errors(trial,1) = getPredictionError(linear+addedNoise,linear,frames,cfg);
    errors(trial,2) = getPredictionError(parabolic+addedNoise,parabolic,frames,cfg);
end

result.linearError = mean(errors(:,1));
result.parabolicError = mean(errors(:,2));
result.difference = 100*(result.parabolicError-result.linearError)/result.linearError;
result.linearStd = std(errors(:,1));
result.parabolicStd = std(errors(:,2));
%result.pass = result.difference >= 20;
fprintf('\n=== MOTION MODEL SENSITIVITY ===\n');
fprintf('Linear prediction error: %.2f +/- %.2f px\n', ...
    result.linearError,result.linearStd);
fprintf('Parabolic prediction error: %.2f +/- %.2f px\n', ...
    result.parabolicError,result.parabolicStd);
fprintf('Relative increase: %.1f%%\n',result.difference);
fprintf('Motion comparison: linear %.2f px, parabolic %.2f px, difference %.1f%%', ...
    result.linearError,result.parabolicError,result.difference);

resultsDir = fullfile(fileparts(mfilename('fullpath')),'Results');
if ~exist(resultsDir,'dir'), mkdir(resultsDir); end
T = table((1:numTrials)',errors(:,1),errors(:,2), ...
    'VariableNames',{'Trial','LinearError_px','ParabolicError_px'});
writetable(T,fullfile(resultsDir,'MotionResults.csv'));
end

function meanError = getPredictionError(measured,truePos,frames,cfg)
% Calculate one-frame-ahead prediction errors BEFORE measurement correction.
[track,~] = kalmanBeeFilter('init',[],measured(1,:),frames(1),cfg);
errors = nan(length(frames),1);
for k = 2:length(frames)
    [track,out] = kalmanBeeFilter('predict',track,frames(k));
    errors(k) = norm(out.position-truePos(k,:));
    [track,~] = kalmanBeeFilter('correct',track,measured(k,:));
end
meanError = mean(errors(6:end));  % Skip initial velocity warm-up
end
