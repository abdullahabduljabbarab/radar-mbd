function verify_beamformer()
%VERIFY_BEAMFORMER  Adaptive beamforming demo: MVDR nulls a jammer.
%
%   Scene: one target at 30 km, +10 degrees; one barrage jammer at
%   -25 degrees, 20 dB stronger than the target. Compares two
%   receive beamformers:
%
%     1. Static delay-and-sum steered at the target (broad mainlobe,
%        vulnerable to the jammer).
%     2. Adaptive MVDR steered at the target (places a sharp null on
%        the jammer while preserving unit gain at the target).
%
%   Three plots:
%     - Beam patterns (linear gain vs angle) - shows the MVDR null.
%     - Matched-filter output on the delay-and-sum beam - target
%       buried under the jammer.
%     - Matched-filter output on the MVDR beam - target lifts clean
%       above the noise floor.
%
%   Saves to docs/img/beamformer.png and asserts the target is
%   detected within 2 range cells on the MVDR beam. - TripleA

    % Params
    if evalin('base','~exist(''fs'',''var'')')
        evalin('base','run(''model/radar_params.m'')');
        evalin('base','run(''model/waveform_params.m'')');
        evalin('base','run(''model/array_params.m'')');
    end
    fs           = evalin('base','fs');
    tau          = evalin('base','tau');
    BW           = evalin('base','BW');
    Nspp_receive = evalin('base','Nspp_receive');
    dR           = evalin('base','dR');
    lambda       = evalin('base','lambda');
    x_elements   = evalin('base','x_elements');
    mvdr_load    = evalin('base','mvdr_load');
    c            = 2.99792458e8;

    rng(42);

    % ---- Scene ----
    % Jammer placed at -40 deg deliberately between the delay-and-sum
    % pattern's natural nulls (which sit near +/-30 and +/-49 deg for
    % an 8-element half-wavelength ULA at broadside look). This forces
    % MVDR to work: it can't rely on a lucky pre-existing null. Jammer
    % 30 dB above per-element noise so its effect is visible on the
    % matched-filter output as well as on the beam pattern. - TripleA
    theta_target_deg = 10;      theta_target = deg2rad(theta_target_deg);
    theta_jammer_deg = -40;     theta_jammer = deg2rad(theta_jammer_deg);
    R_true = 30e3;

    targets(1).range_m   = R_true;
    targets(1).angle_rad = theta_target;
    targets(1).amplitude = 1.0;                  % unit amplitude target
    targets(1).waveform  = 'chirp';

    targets(2).range_m   = 0;
    targets(2).angle_rad = theta_jammer;
    targets(2).amplitude = 10^(30/20);           % +30 dB jammer
    targets(2).waveform  = 'noise';

    noise_std = 1.0;                             % per-element AWGN

    % ---- Generate signals ----
    tx = lfm_waveform(tau, BW, fs);
    rx_array = target_scene_array(tx, targets, x_elements, lambda, fs, Nspp_receive, noise_std);

    % ---- Static delay-and-sum steered at target ----
    a_target = steering_vector(theta_target, x_elements, lambda);
    w_das    = a_target / norm(a_target)^2;      % unit-gain distortionless in target direction
    y_das    = rx_array * conj(w_das);

    % ---- Adaptive MVDR steered at target ----
    [y_mvdr, w_mvdr] = mvdr_beamform(rx_array, x_elements, lambda, theta_target, mvdr_load);

    % ---- Beam patterns ----
    theta_grid_deg = -90:0.25:90;
    G_das  = zeros(size(theta_grid_deg));
    G_mvdr = zeros(size(theta_grid_deg));
    for i = 1:numel(theta_grid_deg)
        a = steering_vector(deg2rad(theta_grid_deg(i)), x_elements, lambda);
        G_das(i)  = abs(w_das'  * a)^2;
        G_mvdr(i) = abs(w_mvdr' * a)^2;
    end

    % ---- Matched filter both beams ----
    yc_das  = matched_filter(y_das,  tx);
    yc_mvdr = matched_filter(y_mvdr, tx);

    range_axis_m = (0:Nspp_receive-1).' * c / (2*fs);
    [~, idx_das]  = max(abs(yc_das));
    [~, idx_mvdr] = max(abs(yc_mvdr));
    R_det_das  = range_axis_m(idx_das);
    R_det_mvdr = range_axis_m(idx_mvdr);

    % ---- Plot ----
    figure('Name','MVDR adaptive beamformer','Position',[100 100 1500 900]);

    subplot(3,1,1);
    plot(theta_grid_deg, 10*log10(G_das + eps),  'LineWidth', 1.2); hold on;
    plot(theta_grid_deg, 10*log10(G_mvdr + eps), 'LineWidth', 1.5);
    xline(theta_target_deg, 'g:', 'target');
    xline(theta_jammer_deg, 'r:', 'jammer');
    xlabel('Angle (deg from broadside)'); ylabel('Gain (dB)');
    title('Beam patterns - MVDR places a sharp null at the jammer angle');
    legend('Delay-and-sum (static)', 'MVDR (adaptive)', 'Location', 'south');
    grid on; ylim([-60 5]);

    subplot(3,1,2);
    plot(range_axis_m/1000, 20*log10(abs(yc_das) + eps), 'LineWidth', 1);
    xlabel('Range (km)'); ylabel('|y| (dB)');
    title(sprintf('Matched filter after static beam - target %.1f km, detected %.1f km (jammer swamps it)', ...
        R_true/1000, R_det_das/1000));
    xline(R_true/1000, 'k:', 'true target');
    grid on; xlim([0 max(range_axis_m)/1000]);

    subplot(3,1,3);
    plot(range_axis_m/1000, 20*log10(abs(yc_mvdr) + eps), 'LineWidth', 1.2);
    xlabel('Range (km)'); ylabel('|y| (dB)');
    title(sprintf('Matched filter after MVDR beam - target detected at %.2f km, clean peak', ...
        R_det_mvdr/1000));
    xline(R_true/1000, 'k:', 'true target');
    grid on; xlim([0 max(range_axis_m)/1000]);

    outPath = fullfile('docs','img','beamformer.png');
    if ~isfolder('docs/img'); mkdir('docs/img'); end
    saveas(gcf, outPath);
    fprintf('Saved %s\n', outPath);

    % Assertions
    assert(abs(R_det_mvdr - R_true) < 2*dR, ...
        'MVDR failed: detected range off by more than 2 cells');
    fprintf('MVDR beamformer verified: target %.2f km, DAS detected %.2f km, MVDR detected %.2f km\n', ...
        R_true/1000, R_det_das/1000, R_det_mvdr/1000);
    fprintf('  Peak gains: DAS %.1f dB, MVDR %.1f dB\n', ...
        20*log10(abs(yc_das(idx_das))), 20*log10(abs(yc_mvdr(idx_mvdr))));
end
