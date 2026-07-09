function compare_sim()
%COMPARE_SIM  Regression check: rerun the DSP against a frozen baseline.
%
%   Loads ci_artifacts/simOut_radar_defaults.mat (the rx_cube + tx +
%   expected strongest detection captured by save_reference_baseline.m),
%   runs radar_dsp on the same inputs, and asserts the output matches
%   the baseline within tolerance. Any drift in the shipped MATLAB
%   kernels - or in the generated C once we run it back through a
%   MEX equivalence check - trips the regression. Called from
%   tools/run_model_tests_and_build.m as the CI gate. - TripleA

    ref_path = fullfile('ci_artifacts','simOut_radar_defaults.mat');
    if ~isfile(ref_path)
        error('compare_sim:MissingReference', ...
              'Reference baseline missing: %s. Run save_reference_baseline first.', ref_path);
    end
    ref = load(ref_path);

    if evalin('base','~exist(''fs'',''var'')')
        evalin('base','run(''model/radar_params.m'')');
        evalin('base','run(''model/waveform_params.m'')');
        evalin('base','run(''model/array_params.m'')');
    end
    fs         = evalin('base','fs');
    PRI        = evalin('base','PRI');
    lambda     = evalin('base','lambda');
    x_elements = evalin('base','x_elements');
    mvdr_load  = evalin('base','mvdr_load');

    N_guard_range = 4; N_train_range = 8;
    N_guard_dop   = 1; N_train_dop   = 2;
    Pfa           = 1e-6;

    [det_r_m, det_v_mps, det_snr_dB, n_det] = radar_dsp( ...
        ref.rx_cube, ref.tx, ref.look_angle_rad, x_elements, lambda, fs, PRI, ...
        mvdr_load, N_guard_range, N_train_range, N_guard_dop, N_train_dop, Pfa);

    % Tolerances
    range_tol_m    = 300;    % 2 range cells
    velocity_tol_ms = 30;    % 2 Doppler cells
    snr_tol_dB     = 2.0;
    n_det_tol      = 3;

    dr = abs(det_r_m(1)    - ref.strongest_range_m);
    dv = abs(det_v_mps(1)  - ref.strongest_velocity);
    ds = abs(det_snr_dB(1) - ref.strongest_snr_dB);
    dn = abs(double(n_det) - double(ref.n_detections));

    fprintf('compare_sim: strongest R %.2f km (ref %.2f km, drift %.1f m)\n', ...
        det_r_m(1)/1000, ref.strongest_range_m/1000, dr);
    fprintf('             strongest v %.1f m/s (ref %.1f, drift %.1f m/s)\n', ...
        det_v_mps(1), ref.strongest_velocity, dv);
    fprintf('             strongest SNR %.1f dB (ref %.1f, drift %.1f dB)\n', ...
        det_snr_dB(1), ref.strongest_snr_dB, ds);
    fprintf('             count %d (ref %d, drift %d)\n', ...
        n_det, ref.n_detections, dn);

    ok = (dr < range_tol_m) && (dv < velocity_tol_ms) && ...
         (ds < snr_tol_dB)  && (dn <= n_det_tol);
    if ok
        fprintf('PASS: within tolerance.\n');
    else
        error('compare_sim:Drift', 'Regression drift outside tolerance.');
    end
end
