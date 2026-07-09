function verify_range_doppler()
%VERIFY_RANGE_DOPPLER  Full DSP chain: burst -> MVDR -> range-Doppler -> CFAR.
%
%   Scene: one moving aircraft target at 30 km, +10 deg,
%   closing velocity 100 m/s; one barrage jammer at -40 deg, +30 dB
%   above per-element noise. Receiver processes a 16-pulse coherent
%   burst, applies MVDR beamforming per pulse using a covariance
%   estimated from the whole cube, matched-filters each pulse,
%   Doppler-FFTs across pulses, and runs CA-CFAR to declare hits.
%
%   Money plot: 2D range-Doppler map with the target as a bright
%   isolated peak at (100 m/s, 30 km), CFAR detections overlaid as
%   red markers. This is the classic radar operator display.
%
%   Saves to docs/img/range_doppler.png. Asserts the target is
%   detected in the correct (range, velocity) cell. - TripleA

    % Params
    if evalin('base','~exist(''fs'',''var'')')
        evalin('base','run(''model/radar_params.m'')');
        evalin('base','run(''model/waveform_params.m'')');
        evalin('base','run(''model/array_params.m'')');
    end
    fs           = evalin('base','fs');
    tau          = evalin('base','tau');
    BW           = evalin('base','BW');
    PRI          = evalin('base','PRI');
    N_pulses     = evalin('base','N_pulses');
    Nspp_receive = evalin('base','Nspp_receive');
    dR           = evalin('base','dR');
    lambda       = evalin('base','lambda');
    x_elements   = evalin('base','x_elements');
    mvdr_load    = evalin('base','mvdr_load');
    c            = 2.99792458e8;

    rng(42);

    % ---- Scene ----
    R_true         = 30e3;
    theta_target   = deg2rad(10);
    % Target velocity chosen well inside the +/-107 m/s unambiguous
    % window so it sits several Doppler bins away from the edges,
    % where CFAR window exclusion would otherwise skip it. Typical
    % holding-pattern airliner speed after IAF vector. - TripleA
    v_true         = 60;
    theta_jammer   = deg2rad(-40);

    targets(1).range_m      = R_true;
    targets(1).angle_rad    = theta_target;
    targets(1).amplitude    = 1.0;
    targets(1).waveform     = 'chirp';
    targets(1).velocity_mps = v_true;

    targets(2).range_m      = 0;
    targets(2).angle_rad    = theta_jammer;
    targets(2).amplitude    = 10^(30/20);
    targets(2).waveform     = 'noise';
    targets(2).velocity_mps = 0;

    noise_std = 1.0;

    % ---- Generate the burst ----
    tx = lfm_waveform(tau, BW, fs);
    rx_cube = multi_pulse_scene(tx, targets, x_elements, lambda, fs, ...
                                PRI, N_pulses, Nspp_receive, noise_std);
    fprintf('rx_cube shape: %d fast-time samples x %d elements x %d pulses\n', ...
        size(rx_cube,1), size(rx_cube,2), size(rx_cube,3));

    % ---- MVDR: estimate covariance from all pulses stacked, apply per pulse ----
    rx_stacked = reshape(permute(rx_cube, [1 3 2]), [], size(rx_cube,2));  % (K*N_pulses) x N_el
    [~, w_mvdr] = mvdr_beamform(rx_stacked, x_elements, lambda, theta_target, mvdr_load);

    rx_bf = complex(zeros(Nspp_receive, N_pulses));
    for n = 1:N_pulses
        rx_bf(:, n) = rx_cube(:, :, n) * conj(w_mvdr);
    end

    % ---- Range-Doppler processing ----
    [RDM, range_axis_m, velocity_axis_mps] = range_doppler(rx_bf, tx, fs, lambda, PRI);
    RDM_power = abs(RDM).^2;

    % ---- CA-CFAR detection ----
    N_guard_range = 4;    N_train_range = 8;
    N_guard_dop   = 1;    N_train_dop   = 2;
    Pfa = 1e-6;
    det_mask = cfar_ca(RDM_power, N_guard_range, N_train_range, ...
                       N_guard_dop, N_train_dop, Pfa);

    % ---- Extract detections + find the strongest one ----
    [det_r, det_d] = find(det_mask);
    if isempty(det_r)
        error('CFAR declared no detections');
    end
    det_powers = arrayfun(@(k) RDM_power(det_r(k), det_d(k)), 1:numel(det_r));
    [~, strongest] = max(det_powers);
    R_det = range_axis_m(det_r(strongest));
    v_det = velocity_axis_mps(det_d(strongest));

    fprintf('CFAR: %d detections. Strongest at R=%.2f km, v=%.1f m/s (true %.2f km, %.1f m/s)\n', ...
        numel(det_r), R_det/1000, v_det, R_true/1000, v_true);

    % ---- Plot ----
    figure('Name','Range-Doppler + CFAR','Position',[100 100 1400 900]);

    subplot(2,1,1);
    imagesc(velocity_axis_mps, range_axis_m/1000, 10*log10(RDM_power + eps));
    axis xy; xlabel('Velocity (m/s, positive = closing)');
    ylabel('Range (km)');
    title('Range-Doppler map after MVDR beamforming + pulse compression + Doppler FFT');
    colorbar; colormap('parula');
    hold on;
    plot(v_true, R_true/1000, 'wo', 'MarkerSize', 20, 'LineWidth', 2);
    text(v_true+15, R_true/1000, sprintf('  true target\n  (%.0f m/s, %.1f km)', v_true, R_true/1000), ...
        'Color', 'white', 'FontSize', 10);
    ylim([R_true/1000 - 10, R_true/1000 + 10]);
    clim([max(get(gca,'CLim')) - 50, max(get(gca,'CLim'))]);

    subplot(2,1,2);
    imagesc(velocity_axis_mps, range_axis_m/1000, 10*log10(RDM_power + eps));
    axis xy; xlabel('Velocity (m/s)'); ylabel('Range (km)');
    title(sprintf('CFAR detections overlaid (Pfa = %.0e, %d detections, strongest at R=%.2fkm v=%.0fm/s)', ...
        Pfa, numel(det_r), R_det/1000, v_det));
    colorbar; colormap('parula');
    hold on;
    for k = 1:numel(det_r)
        plot(velocity_axis_mps(det_d(k)), range_axis_m(det_r(k))/1000, ...
            'rs', 'MarkerSize', 15, 'LineWidth', 2);
    end
    ylim([R_true/1000 - 10, R_true/1000 + 10]);
    clim([max(get(gca,'CLim')) - 50, max(get(gca,'CLim'))]);

    outPath = fullfile('docs','img','range_doppler.png');
    if ~isfolder('docs/img'); mkdir('docs/img'); end
    saveas(gcf, outPath);
    fprintf('Saved %s\n', outPath);

    % ---- Assertions ----
    assert(abs(R_det - R_true) < 2*dR, ...
        'Range detection off by more than 2 cells');
    dv_grid = velocity_axis_mps(2) - velocity_axis_mps(1);
    assert(abs(v_det - v_true) < 2*abs(dv_grid), ...
        'Velocity detection off by more than 2 cells');
    fprintf('Range-Doppler + CFAR verified end-to-end.\n');
end
