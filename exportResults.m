function exportResults(results, savePath, baseName, ax)
% Export Results
% Save B-TRAC II grouped bearings and hive candidates.

    save(fullfile(savePath, [baseName '.mat']), 'results');

    try
        exportgraphics(ax, fullfile(savePath, [baseName '_map.png']), 'Resolution', 300);
    catch
        warning('Map image export failed.');
    end

    for i = 1:numel(results.sessions)
        s = results.sessions(i);
        if isfield(s,'processed') && s.processed && ~isempty(s.departureAngles)
            if isfield(s,'trajectoryIDs') && numel(s.trajectoryIDs) == numel(s.departureAngles)
                ids = s.trajectoryIDs(:);
            else
                ids = (1:numel(s.departureAngles))';
            end
            T = table(ids, s.departureAngles(:), ...
                'VariableNames', {'TrajectoryID','Bearing_Degrees'});
            if isfield(s,'groupIDs') && ~isempty(s.groupIDs)
                groupAssignment = nan(numel(ids),1);
                for g = 1:numel(s.groupIDs)
                    theseIDs = s.groupIDs{g};
                    [~,loc] = ismember(ids, theseIDs(:));
                    groupAssignment(loc > 0) = g;
                end
                T.GroupID = groupAssignment;
            end
            writetable(T, fullfile(savePath, sprintf('%s_session%d_bearings.csv',baseName,i)));
        end
    end

    writeSummary(results, fullfile(savePath, [baseName '_summary.txt']));
end

function writeSummary(results, filename)
    fid = fopen(filename, 'w');
    if fid < 0
        error('exportResults_multi:FileOpenFailed','Could not create summary file.');
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'B-TRAC II ANALYSIS SUMMARY\n==========================\n\n');
    if isfield(results,'analysisDate')
        fprintf(fid, 'Analysis Date: %s\n\n', char(results.analysisDate));
    end

    if isfield(results,'yoloConfig') && isfield(results.yoloConfig,'useYOLO') ...
            && results.yoloConfig.useYOLO
        fprintf(fid, 'Detection Method : YOLO\n');
        fprintf(fid, '  Model          : %s\n', results.yoloConfig.modelPath);
        fprintf(fid, '  Confidence     : %.2f\n', results.yoloConfig.confidenceThreshold);
        fprintf(fid, '  Frame sample   : %d\n\n', results.yoloConfig.frameSample);
    else
        fprintf(fid, 'Detection Method : Background Subtraction / configured tracker\n\n');
    end

    fprintf(fid, 'Triangulation: multi-ray forward intersections and weighted least-squares refinement\n');
    fprintf(fid, 'OBSERVATION SESSIONS:\n');
    for i = 1:numel(results.sessions)
        s = results.sessions(i);
        fprintf(fid, '\n  Session %d: %s\n', i, s.name);
        fprintf(fid, '  Location: [%.6f, %.6f]\n', s.gpsCoords(1), s.gpsCoords(2));
        fprintf(fid, '  Camera compass heading: %.1f deg\n', s.compassBearing);
        if isfield(s,'processed') && s.processed
            fprintf(fid, '  Tracks: %d\n', numel(s.trajectories));
            for g = 1:numel(s.avgBearing)
                nTracks = NaN;
                if isfield(s,'groupIDs') && numel(s.groupIDs) >= g
                    nTracks = numel(s.groupIDs{g});
                end
                fprintf(fid, '  Group %d: bearing %.2f deg, confidence %.3f, trajectories %g\n', ...
                    g, s.avgBearing(g), s.confidence(g), nTracks);
            end
        end
    end

    if isfield(results,'hiveCandidates') && ~isempty(results.hiveCandidates)
        fprintf(fid, '\nHIVE CANDIDATES:\n');
        for c = 1:numel(results.hiveCandidates)
            h = results.hiveCandidates(c);
            fprintf(fid, ['  Candidate %d: %.8f, %.8f | supporting stations: %d | ' ...
                'rays: %d | mean confidence: %.3f | intersections: %d\n'], ...
                c, h.lat, h.lon, h.supportSessions, h.supportRays, ...
                h.meanConfidence, h.intersectionCount);
            fprintf(fid, '  Google Maps: https://maps.google.com/?q=%.8f,%.8f\n', h.lat, h.lon);
        end
    elseif isfield(results,'estimatedHiveLocation') && ~isempty(results.estimatedHiveLocation)
        hl = results.estimatedHiveLocation;
        fprintf(fid, '\nEstimated hive location: %.8f, %.8f\n', hl(1), hl(2));
    else
        fprintf(fid, '\nNo hive candidate could be estimated from the available sessions.\n');
    end
end
