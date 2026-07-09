function verify_radar_dsp()
%VERIFY_RADAR_DSP  Sanity check the top-level radar_dsp function.
%
%   Runs the same scene as verify_range_doppler through the wrapped
%   radar_dsp entry point, asserts the strongest detection lands on
%   the target within one range/velocity cell. Confirms the wrapper
%   is behaviourally identical to the piecewise pipeline before we
%   drop it into a Simulink model. - TripleA

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

    rng(42);

    % Scene
    R_true       = 30e3;
    theta_target = deg2rad(10);
    v_true       = 60;
    targets(1).range_m      = R_true;
    targets(1).angle_rad    = theta_target;
    targets(1).amplitude    = 1.0;
    targets(1).waveform     = 'chirp';
    targets(1).velocity_mps = v_true;
    targets(2).range_m      = 0;
    targets(2).angle_rad    = deg2rad(-40);
    targets(2).amplitude    = 10^(30/20);
    targets(2).waveform     = 'noise';
    targets(2).velocity_mps = 0;
    noise_std = 1.0;

    % Signals
    tx = lfm_waveform(tau, BW, fs);
    rx_cube = multi_pulse_scene(tx, targets, x_elements, lambda, fs, ...
                                PRI, N_pulses, Nspp_receive, noise_std);

    % CFAR params
    N_guard_range = 4;
    N_train_range = 8;
    N_guard_dop   = 1;
    N_train_dop   = 2;
    Pfa           = 1e-6;

    % Run the top-level chain
    [det_r_m, det_v_mps, det_snr_dB, n_det] = radar_dsp( ...
        rx_cube, tx, theta_target, x_elements, lambda, fs, PRI, ...
        mvdr_load, N_guard_range, N_train_range, N_guard_dop, N_train_dop, Pfa);

    fprintf('radar_dsp returned %d detections\n', n_det);
    for k = 1:min(n_det, 5)
        fprintf('  det %d: R=%.2f km, v=%.1f m/s, SNR=%.1f dB\n', ...
            k, det_r_m(k)/1000, det_v_mps(k), det_snr_dB(k));
    end

    assert(n_det > 0, 'No detections');
    assert(abs(det_r_m(1) - R_true) < 2*dR, 'Range off');
    assert(abs(det_v_mps(1) - v_true) < 2*13.4, 'Velocity off');
    fprintf('radar_dsp verified: strongest detection matches target within 2 cells.\n');
end
