function createMapVisualization(observations, estimatedHiveLocation, axesHandle)
    % Create GPS map visualization with bearing arrows and hive location
    % Optimized for display in uiaxes
    
    % Extract data
    nObs = length(observations);
    obsLats = arrayfun(@(x) x.gpsCoords(1), observations);
    obsLons = arrayfun(@(x) x.gpsCoords(2), observations);
    bearings = arrayfun(@(x) x.avgBearing, observations);
    confidences = arrayfun(@(x) x.confidence, observations);
    
    % Clear axes
    cla(axesHandle);
    hold(axesHandle, 'on');
    
    % Calculate map bounds
    allLats = [obsLats, estimatedHiveLocation(1)];
    allLons = [obsLons, estimatedHiveLocation(2)];
    
    centerLat = mean(allLats);
    centerLon = mean(allLons);
    
    % Convert to local coordinates for plotting
    [obsX, obsY] = latlon2localPlot(obsLats, obsLons, centerLat, centerLon);
    [hiveX, hiveY] = latlon2localPlot(estimatedHiveLocation(1), estimatedHiveLocation(2), ...
                                       centerLat, centerLon);
    
    % Plot settings
    maxBearingDistance = 500; % meters
    
    % Create background grid
    plotBackgroundGrid(axesHandle, obsX, obsY, hiveX, hiveY);
    
    % Plot bearing lines with arrows
    for i = 1:nObs
        % Calculate bearing endpoint
        bearing = bearings(i);
        [endX, endY] = calculateBearingEndpointLocal(obsX(i), obsY(i), bearing, ...
                                                      maxBearingDistance);
        
        % Color by confidence
        color = getConfidenceColor(confidences(i));
        lineWidth = 2 + 2 * confidences(i);
        
        % Plot bearing line
        plot(axesHandle, [obsX(i), endX], [obsY(i), endY], '-', ...
             'Color', color, 'LineWidth', lineWidth);
        
        % Add arrow at end
        arrowSize = 30;
        drawArrow(axesHandle, obsX(i), obsY(i), endX, endY, color, arrowSize);
        
        % Add confidence circle
        if confidences(i) < 1.0
            circleRadius = 40 * (1 - confidences(i));
            drawCircle(axesHandle, obsX(i), obsY(i), circleRadius, color);
        end
    end
    
    % Plot observation points
    for i = 1:nObs
        plot(axesHandle, obsX(i), obsY(i), 'o', ...
             'MarkerSize', 12, 'MarkerFaceColor', [0.2 0.4 0.8], ...
             'MarkerEdgeColor', 'white', 'LineWidth', 2);
        
        % Add label
        text(axesHandle, obsX(i) + 20, obsY(i) + 20, observations(i).name, ...
             'FontSize', 10, 'FontWeight', 'bold', 'Color', 'black', ...
             'BackgroundColor', [1 1 1 0.7]);
    end
    
    % Plot estimated hive location
    plot(axesHandle, hiveX, hiveY, 'p', ...
         'MarkerSize', 25, 'MarkerFaceColor', [0.9 0.7 0.1], ...
         'MarkerEdgeColor', 'black', 'LineWidth', 3);
    
    text(axesHandle, hiveX + 30, hiveY + 30, 'Estimated Hive', ...
         'FontSize', 12, 'FontWeight', 'bold', 'Color', [0.6 0.4 0], ...
         'BackgroundColor', [1 1 1 0.8]);
    
    % Draw uncertainty circle around hive
    uncertaintyRadius = 50; % meters
    drawCircle(axesHandle, hiveX, hiveY, uncertaintyRadius, [0.9 0.7 0.1]);
    
    % Set axes properties
    axis(axesHandle, 'equal');
    grid(axesHandle, 'on');
    xlabel(axesHandle, 'East-West Distance (m)', 'FontWeight', 'bold');
    ylabel(axesHandle, 'North-South Distance (m)', 'FontWeight', 'bold');
    title(axesHandle, sprintf('Estimated Hive Location: [%.6f, %.6f]', ...
                              estimatedHiveLocation(1), estimatedHiveLocation(2)), ...
          'FontSize', 12, 'FontWeight', 'bold');
    
    % Add legend
    legendEntries = {'Observation Point', 'Flight Bearing', 'Estimated Hive'};
    legend(axesHandle, legendEntries, 'Location', 'best', 'FontSize', 10);
    
    % Add scale reference
    addScaleBar(axesHandle);
    
    % Add compass rose
    addCompassRose(axesHandle);
    
    hold(axesHandle, 'off');
end

function [x, y] = latlon2localPlot(lat, lon, refLat, refLon)
    % Convert lat/lon to local Cartesian for plotting
    R = 6371000; % Earth radius in meters
    x = R * deg2rad(lon - refLon) * cosd(refLat);
    y = R * deg2rad(lat - refLat);
end

function [endX, endY] = calculateBearingEndpointLocal(startX, startY, bearing, distance)
    % Calculate endpoint in local coordinates
    bearingRad = deg2rad(bearing);
    endX = startX + distance * sin(bearingRad);
    endY = startY + distance * cos(bearingRad);
end

function color = getConfidenceColor(confidence)
    % Map confidence (0-1) to color gradient (red -> yellow -> green)
    if confidence < 0.5
        % Red to yellow
        color = [1, 2*confidence, 0];
    else
        % Yellow to green
        color = [2*(1-confidence), 1, 0];
    end
end

function drawArrow(axesHandle, x1, y1, x2, y2, color, arrowSize)
    % Draw arrow at end of line
    
    % Calculate arrow direction
    dx = x2 - x1;
    dy = y2 - y1;
    angle = atan2(dy, dx);
    
    % Arrow head points
    arrowAngle = 25 * pi/180; % 25 degrees
    leftX = x2 - arrowSize * cos(angle - arrowAngle);
    leftY = y2 - arrowSize * sin(angle - arrowAngle);
    rightX = x2 - arrowSize * cos(angle + arrowAngle);
    rightY = y2 - arrowSize * sin(angle + arrowAngle);
    
    % Draw arrow head
    patch(axesHandle, [x2, leftX, rightX], [y2, leftY, rightY], color, ...
          'EdgeColor', color, 'LineWidth', 2);
end

function drawCircle(axesHandle, centerX, centerY, radius, color)
    % Draw circle
    theta = linspace(0, 2*pi, 50);
    circleX = centerX + radius * cos(theta);
    circleY = centerY + radius * sin(theta);
    plot(axesHandle, circleX, circleY, '--', 'Color', color, 'LineWidth', 1.5);
end

function plotBackgroundGrid(axesHandle, obsX, obsY, hiveX, hiveY)
    % Create light background grid
    
    allX = [obsX, hiveX];
    allY = [obsY, hiveY];
    
    % Set limits with padding
    xRange = max(allX) - min(allX);
    yRange = max(allY) - min(allY);
    padding = 0.2;
    
    xlim(axesHandle, [min(allX) - padding*xRange, max(allX) + padding*xRange]);
    ylim(axesHandle, [min(allY) - padding*yRange, max(allY) + padding*yRange]);
    
    % Light gray background
    axesHandle.Color = [0.97 0.97 0.97];
    axesHandle.GridColor = [0.8 0.8 0.8];
    axesHandle.GridAlpha = 0.5;
end

function addScaleBar(axesHandle)
    % Add scale bar to plot
    
    xlims = xlim(axesHandle);
    ylims = ylim(axesHandle);
    
    % Position in bottom left
    barX = xlims(1) + 0.05 * (xlims(2) - xlims(1));
    barY = ylims(1) + 0.05 * (ylims(2) - ylims(1));
    
    % Scale bar length (100m)
    barLength = 100;
    
    % Draw scale bar
    plot(axesHandle, [barX, barX + barLength], [barY, barY], 'k-', 'LineWidth', 3);
    
    % Add text
    text(axesHandle, barX + barLength/2, barY - 15, '100 m', ...
         'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
         'BackgroundColor', [1 1 1 0.8]);
end

function addCompassRose(axesHandle)
    % Add compass rose to plot
    
    xlims = xlim(axesHandle);
    ylims = ylim(axesHandle);
    
    % Position in top right
    roseX = xlims(2) - 0.1 * (xlims(2) - xlims(1));
    roseY = ylims(2) - 0.1 * (ylims(2) - ylims(1));
    roseSize = 40;
    
    % North arrow
    plot(axesHandle, [roseX, roseX], [roseY, roseY + roseSize], 'k-', 'LineWidth', 2);
    
    % Arrow head
    arrowSize = 10;
    patch(axesHandle, [roseX, roseX - arrowSize/2, roseX + arrowSize/2], ...
          [roseY + roseSize, roseY + roseSize - arrowSize, roseY + roseSize - arrowSize], ...
          'k', 'EdgeColor', 'k');
    
    % 'N' label
    text(axesHandle, roseX, roseY + roseSize + 15, 'N', ...
         'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
         'BackgroundColor', [1 1 1 0.8]);
    
    % East-West line
    plot(axesHandle, [roseX - roseSize/2, roseX + roseSize/2], [roseY, roseY], ...
         'k-', 'LineWidth', 1);
    
    % E and W labels
    text(axesHandle, roseX + roseSize/2 + 10, roseY, 'E', ...
         'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.8]);
    text(axesHandle, roseX - roseSize/2 - 10, roseY, 'W', ...
         'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.8]);
end

function createIndividualSessionMap(session, axesHandle)
    % Create map for a single observation session showing all trajectories
    
    cla(axesHandle);
    hold(axesHandle, 'on');
    
    % Get session data
    angles = session.departureAngles;
    
    if isempty(angles)
        text(axesHandle, 0.5, 0.5, 'No data to display', ...
             'HorizontalAlignment', 'center', 'Units', 'normalized', ...
             'FontSize', 14);
        return;
    end
    
    % Create polar histogram
    polaraxes(axesHandle.Parent);
    pax = gca;
    polarhistogram(pax, deg2rad(angles), 36, 'FaceColor', [0.3 0.7 0.3]);
    
    % Set properties
    pax.ThetaZeroLocation = 'top';
    pax.ThetaDir = 'clockwise';
    title(pax, sprintf('%s - Bearing Distribution', session.name), ...
          'FontSize', 12, 'FontWeight', 'bold');
    
    % Add average bearing line
    if isfield(session, 'avgBearing')
        hold(pax, 'on');
        avgRad = deg2rad(session.avgBearing);
        maxCount = max(histcounts(deg2rad(angles), 36));
        polarplot(pax, [avgRad, avgRad], [0, maxCount], 'r-', 'LineWidth', 3);
        legend(pax, 'Departures', 'Average', 'Location', 'best');
        hold(pax, 'off');
    end
end
