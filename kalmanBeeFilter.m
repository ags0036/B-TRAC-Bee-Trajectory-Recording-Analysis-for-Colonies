function [track, output] = kalmanBeeFilter(action, track, varargin)
% Constant velocity Kalman filter for B-TRAC bee tracking.
%
% The filter estimates four values
%   x  = horizontal position (pixels)
%   y  = vertical position (pixels)
%   vx = horizontal velocity (pixels/frame)
%   vy = vertical velocity (pixels/frame)
%
% State vector = [x; y; vx; vy]
%
% Filter has three operations:
%   'init'    - Start a new bee track
%   'predict' - Predict the bee's next position
%   'correct' - Correct the prediction using a YOLO detection
%
% If YOLO misses a bee, predict without correcting.


switch lower(action)
    case 'init'
        % INITIALIZATION
        %creates the Kalman filter when a new bee is detected.

        measuredPosition = varargin{1};
        currentFrame = varargin{2};

        %load settings if they were provided.
        if length(varargin) >= 3
            cfg = varargin{3};
        else
            cfg = struct();
        end

        % Process noise controls how much we expect the bee velocity to
        % change between frames
        % Larger values allow the filter to react to motion changes.
        if ~isfield(cfg, 'q')
            cfg.q = 0.2;
        end

        % Expected ststd dev of YOLO position errors
        % 2 means approximately 2 pixels of noise in each coordinate
        if ~isfield(cfg, 'measurementSigma')
            cfg.measurementSigma = 2;
        end

        %initial uncertainty in the bee position.
        % 25 pixels^2 corresponds to a standard deviation of 5 pixels.
        if ~isfield(cfg, 'initialPositionVariance')
            cfg.initialPositionVariance = 25;
        end

        % Initial uncertainty in the beevelocity.
        % 100 (pixels/frame)^2 corresponds to a std dev 10 pixels/frame.
        if ~isfield(cfg, 'initialVelocityVariance')
            cfg.initialVelocityVariance = 100;
        end

        %valid X and Y coord check
        validateattributes(measuredPosition, {'numeric'}, ...
            {'vector', 'numel', 2, 'finite'});

        %valid nonnegative integer frame
        validateattributes(currentFrame, {'numeric'}, ...
            {'scalar', 'integer', 'nonnegative'});

        %Bee starts at its first measured position.
        % Velocity is initially zero because we have only one measurement
        initialX = measuredPosition(1);
        initialY = measuredPosition(2);

        initialVx = 0;
        initialVy = 0;

        track.x = [initialX;
                   initialY;
                   initialVx;
                   initialVy];

        % Initial covariance matrix P
        % Diagonal entries represent uncertainty in each state
        % Off-diagonal entries start at zero because we aren't
        % assuming any initial correlation between the states
        positionVariance = cfg.initialPositionVariance;
        velocityVariance = cfg.initialVelocityVariance;

        track.P = [positionVariance  0                 0                 0;
                   0                 positionVariance  0                 0;
                   0                 0                 velocityVariance  0;
                   0                 0                 0                 velocityVariance];

        track.q = cfg.q;

        % Measurement covariance - R
        % Variance = standard dev squared
        % assuming equal and independent noise in X and Y
        measurementVariance = cfg.measurementSigma^2;

        track.R = [measurementVariance  0;
                   0                    measurementVariance];

        track.frame = currentFrame;

        % Return the initial estimated position and velocity.
        output = makeOutput(track, [NaN NaN]);

    case 'predict'
        % PREDICTION
        % Eestimate where the bee should be at the next processed fram

        targetFrame = varargin{1};

        % time elapse calc
        dt = targetFrame - track.frame;
        if dt <= 0 || dt ~= floor(dt) || ~isfinite(dt)
            error('Prediction requires a later integer frame number.');
        end

        % State transition - F.
        %
        % Constant velocity eqns
        %   newX  = oldX + vx*dt
        %   newY  = oldY + vy*dt
        %   newVx = oldVx
        %   newVy = oldVy
        %
        %1s preserve the existing state values.
        % dt terms move the bee based on its estimated velocity
        F = [1  0  dt  0;
             0  1  0   dt;
             0  0  1   0;
             0  0  0   1];

        % Process noise covariance- Q.
        %
        % accounts for uncertainty caused by changes in velocity
        % that the constant velocity model cannot predict.
        % not arbitrary tuning values.
        dt2 = dt^2;
        dt3 = dt^3;
        dt4 = dt^4;

        positionNoise = dt4 / 4;
        positionVelocityNoise = dt3 / 2;
        velocityNoise = dt2;

        Q = [positionNoise          0                      positionVelocityNoise  0;
             0                      positionNoise          0                      positionVelocityNoise;
             positionVelocityNoise  0                      velocityNoise          0;
             0                      positionVelocityNoise  0                      velocityNoise];

        %scaling Q
        % q controls how much uncertainty is added during prediction
        Q = track.q * Q;

        % opredict the new state & covariance & save
        predictedState = F * track.x;
        predictedCovariance = F * track.P * F' + Q;
        track.x = predictedState;
        track.P = predictedCovariance;

        track.P = (track.P + track.P') / 2;
        track.frame = targetFrame;
        %predicted pos & velocity
        output = makeOutput(track, [NaN NaN]);


    case 'correct'
        % CORRECTION
        % Update the predicted position using a YOLO detection
        %we don't want to be saving data that we didn't actually measure since
        % this is a more rudimentary mathematical model aimed to 
        % assist with issues in physicel measurement and yolo detection

        measuredPosition = varargin{1};

        %valid x y
        validateattributes(measuredPosition, {'numeric'}, ...
            {'vector', 'numel', 2, 'finite'});
        z = measuredPosition(:);

        % Measurement matrix H
        % YOLO provides X and Y pos
        %0s exclude the velocity components.
        H = [1  0  0  0;
             0  1  0  0];
        predictedMeasurement = H * track.x;

        % Innovation
        %residual =measured- predicted
        residual = z - predictedMeasurement;

        % Innovation covariance S
        % Combines the uncertainty in the predicted w uncertainty in YOLO
        S = H * track.P * H' + track.R;
        % Kalman gain K
        % Determines how strongly the measurement should
        %influence the predicted state
        % High prediction uncertainty means
        %trustin measurement more
        K = (track.P * H') / S;

        correctedState = track.x + K * residual;
        track.x = correctedState;
        I = eye(4);

        % Correct the covariance using Joseph form
        % This is numerically more stable than the simplified
        % covariance update equation.
        covarianceAdjustment = I - K * H;
        correctedCovariance = ...
            covarianceAdjustment * track.P * covarianceAdjustment' ...
            + K * track.R * K';
        track.P = correctedCovariance;
        track.P = (track.P + track.P') / 2;

        %corrected pos, velocity, and residual
        output = makeOutput(track, residual');

        % NIS measures how large the prediction error is relative
        % to the uncertainty expected by filter.
        %Larger NIS values lean that measurement is
        % less consistent with the predicted motion
        output.NIS = residual' * (S \ residual);
    otherwise
        error('Use init, predict, or correct.');

end
end

function output = makeOutput(track, residual)
% Collect the filter results into a struc
%estimated X and Y position
output.position = track.x(1:2)';
%estimated X and Y velocity
output.velocity = track.x(3:4)';
% Current raw video frame
output.frame = track.frame;
%measurement and prediction diff
% NaN when there was no measurement correction
output.innovation = residual;
%correction step
output.NIS = NaN;

end
