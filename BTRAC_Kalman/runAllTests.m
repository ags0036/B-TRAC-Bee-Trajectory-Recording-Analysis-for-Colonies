function results = runAllTests()
% Run the three Kalman proof of concept tests.

fprintf('\n=== B-TRAC KALMAN VERIFICATION ===\n');
gap = testMissingDetections();
motion = testMotionComparison();
swap = testPathSwapping();

names = {'Missing detections';'Motion comparison';'Path swapping'};
passed = [gap.pass;motion.pass;swap.pass];
results = table(names,passed,'VariableNames',{'Test','Pass'});
disp(results);
fprintf('Passed %d of 3 tests.\n',sum(passed));

resultsDir = fullfile(fileparts(mfilename('fullpath')),'Results');
if ~exist(resultsDir,'dir'), mkdir(resultsDir); end
writetable(results,fullfile(resultsDir,'TestSummary.csv'));
end
