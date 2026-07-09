function save_reference_baseline()
%SAVE_REFERENCE_BASELINE  Freeze a reference sim output for regression.
%
%   Runs the standard verification scene (30 km target, 60 m/s
%   closing, +10 deg; -40 deg / +30 dB jammer) with a fixed RNG seed
%   and saves the resulting rx_cube plus the strongest detection
%   returned by radar_dsp. tools/compare_sim.m loads this and runs
%   a fresh instance of the chain, asserting the outputs match. Any
%   drift in the DSP kernels or the model - even after codegen -
%   trips the regression. - TripleA

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
    lambda       = evalin('base','lambda');
    x_elements   = evalin('base','x_elements');
    mvdr_load    = evalin('base','mvdr_load');

    rng(42);

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

    tx      = lfm_waveform(tau, BW, fs);
    rx_cube = multi_pulse_scene(tx, targets, x_elements, lambda, fs, ...
                                PRI, N_pulses, Nspp_receive, noise_std);

    N_guard_range = 4; N_train_range = 8;
    N_guard_dop   = 1; N_train_dop   = 2;
    Pfa           = 1e-6;

    [det_r_m, det_v_mps, det_snr_dB, n_det] = radar_dsp( ...
        rx_cube, tx, theta_target, x_elements, lambda, fs, PRI, ...
        mvdr_load, N_guard_range, N_train_range, N_guard_dop, N_train_dop, Pfa);

    ref.rx_cube            = rx_cube;
    ref.tx                 = tx;
    ref.look_angle_rad     = theta_target;
    ref.strongest_range_m  = det_r_m(1);
    ref.strongest_velocity = det_v_mps(1);
    ref.strongest_snr_dB   = det_snr_dB(1);
    ref.n_detections       = n_det;
    ref.true_range_m       = R_true;
    ref.true_velocity_mps  = v_true;

    outPath = fullfile('ci_artifacts','simOut_radar_defaults.mat');
    if ~isfolder('ci_artifacts'); mkdir('ci_artifacts'); end
    save(outPath, '-struct', 'ref');
    fprintf('Reference baseline saved to %s\n', outPath);
    fprintf('  strongest detection: R=%.2f km, v=%.1f m/s, SNR=%.1f dB, n=%d\n', ...
        ref.strongest_range_m/1000, ref.strongest_velocity, ...
        ref.strongest_snr_dB, ref.n_detections);
end
