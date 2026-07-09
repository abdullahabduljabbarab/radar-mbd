% model/array_params.m
% Phased array antenna parameters. 8-element uniform linear array
% (ULA) with lambda/2 spacing - the textbook baseline for adaptive
% beamforming analysis. Steering vector + MVDR beamforming math
% lives in the Simulink model as MATLAB Function blocks so the
% generated C stays self-contained. - TripleA

% ---- Array geometry ----
N_elements = 8;                         % number of ULA elements
d          = lambda / 2;                % element spacing (m) - half wavelength
                                        %   avoids grating lobes across full FOV

% ---- Element positions (metres, along x axis) ----
% Zero-centered array so the phase reference sits at the array centre,
% making the beamforming math read cleanly regardless of element count.
x_elements = ((0:N_elements-1) - (N_elements-1)/2) * d;

% ---- Steering ----
theta_steer_deg = 0;                    % nominal boresight (degrees, 0 = broadside)
theta_steer_rad = deg2rad(theta_steer_deg);

% Steering vector for a plane wave arriving from angle theta:
% a(theta) = [exp(-j*2pi*x_1*sin(theta)/lambda);
%             exp(-j*2pi*x_2*sin(theta)/lambda);
%             ... ]
% The MATLAB Function block inside the model computes this per
% snapshot from the current commanded steering angle - stored here
% only as an initial value for the workspace variable.
a_steer = exp(-1j * 2*pi * x_elements(:) * sin(theta_steer_rad) / lambda);

% ---- MVDR loading factor ----
% Diagonal-loading of the spatial covariance matrix to avoid
% ill-conditioning when the snapshot count is close to N_elements.
% Typical guidance: load = 10 * noise variance, or 0.001 * trace(R_hat).
% Fixed at 0.001 for the demo; MVDR block reads this variable.
mvdr_load = 0.001;

% ---- Beam pattern grid (for verification plots, not runtime) ----
% Sweep angle for evaluating the array pattern from -90 to +90 deg.
theta_grid_deg = -90:0.5:90;
theta_grid_rad = deg2rad(theta_grid_deg);

if ~exist('VERBOSE','var') || VERBOSE
    fprintf('array_params: N=%d elements, d=lambda/2=%.1f mm, ', N_elements, d*1000);
    fprintf('aperture=%.2f m\n', (N_elements-1)*d);
end
