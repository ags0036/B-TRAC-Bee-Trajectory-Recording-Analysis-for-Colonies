
%added to alleviate function calling issues

function exportResults(results, savePath, baseName, ax)
% Save .mat, map PNG, per-session bearing CSVs, and text summary.
    save(fullfile(savePath, [baseName '.mat']), 'results');
    try
        exportgraphics(ax, fullfile(savePath, [baseName '_map.png']), 'Resolution', 300);
    catch
        warning('Map image export failed.');
    end
    for i = 1:length(results.sessions)
        s = results.sessions(i);
        if s.processed && ~isempty(s.departureAngles)
            T = table((1:length(s.departureAngles))', s.departureAngles, ...
                      'VariableNames', {'TrajectoryID', 'Bearing_Degrees'});
            writetable(T, fullfile(savePath, ...
                       sprintf('%s_session%d_bearings.csv', baseName, i)));
        end
    end
    writeSummary(results, fullfile(savePath, [baseName '_summary.txt']));
end

function writeSummary(results, filename)
    fid = fopen(filename, 'w');
    fprintf(fid, 'B-TRAC ANALYSIS SUMMARY\n=======================\n\n');
    fprintf(fid, 'Analysis Date: %s\n\n', char(results.analysisDate));
    if isfield(results,'yoloConfig') && results.yoloConfig.useYOLO
        fprintf(fid, 'Detection Method : YOLO\n');
        fprintf(fid, '  Model          : %s\n',   results.yoloConfig.modelPath);
        fprintf(fid, '  Confidence     : %.2f\n', results.yoloConfig.confidenceThreshold);
        fprintf(fid, '  Frame sample   : %d\n\n', results.yoloConfig.frameSample);
    else
        fprintf(fid, 'Detection Method : Background Subtraction\n\n');
    end
    fprintf(fid, 'Triangulation Method: Perpendicular-distance least squares\n');
    fprintf(fid, '  p* = argmin sum_i || (I - v_i*v_i'') * (p - p_i) ||^2\n\n');
    fprintf(fid, 'OBSERVATION SESSIONS:\n');
    for i = 1:length(results.sessions)
        s = results.sessions(i);
        fprintf(fid, '\n  Session %d : %s\n',         i, s.name);
        fprintf(fid, '  Location  : [%.6f, %.6f]\n', s.gpsCoords(1), s.gpsCoords(2));
        fprintf(fid, '  Camera bearing: %.1f deg\n',  s.compassBearing);
        if s.processed
            fprintf(fid, '  Tracks      : %d\n',        length(s.trajectories));
            fprintf(fid, '  Avg Bearing : %.2f deg\n',  s.avgBearing);
            fprintf(fid, '  Confidence  : %.1f%%\n',    s.confidence*100);
        end
    end
    if ~isempty(results.estimatedHiveLocation)
        hl = results.estimatedHiveLocation;
        fprintf(fid, '\n\nESTIMATED HIVE LOCATION (best-fit p*):\n');
        fprintf(fid, '  Latitude  : %.8f\n', hl(1));
        fprintf(fid, '  Longitude : %.8f\n', hl(2));
        fprintf(fid, '\nGoogle Maps: https://maps.google.com/?q=%.8f,%.8f\n', hl(1), hl(2));
    end
    fclose(fid);
end