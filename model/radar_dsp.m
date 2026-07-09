function [det_range_m, det_velocity_mps, det_snr_dB, n_detections] = radar_dsp( ...
    rx_cube, tx, look_angle_rad, x_elements, lambda, fs, PRI, ...
    mvdr_load, N_guard_range, N_train_range, N_guard_dop, N_train_dop, Pfa)
%RADAR_DSP  Complete radar signal-processing chain.
%
%   Wraps MVDR beamforming, matched-filter pulse compression,
%   range-Doppler processing, and CA-CFAR detection into a single
%   codegen-safe entry point. Consumed by the Simulink model
%   (radar.slx) as its main MATLAB Function block; consumed by
%   CLEARANCE's ClearanceRadarMBD plugin module as the extern-C
%   entry point after Embedded Coder codegen.
%
%   Inputs:
%     rx_cube        Nspp_receive x N_el x N_pulses complex I/Q
%     tx             Nspp x 1 transmit chirp reference
%     look_angle_rad steering look direction (rad from broadside)
%     x_elements     N_el x 1 element positions (m)
%     lambda, fs, PRI  RF + timing constants
%     mvdr_load       diagonal loading factor for MVDR
%     N_guard_range, N_train_range, N_guard_dop, N_train_dop  CFAR
%     Pfa             CFAR false-alarm rate
%
%   Outputs:
%     det_range_m       [MAX_DETECTIONS x 1] range of each detection
%     det_velocity_mps  [MAX_DETECTIONS x 1] velocity (positive closing)
%     det_snr_dB        [MAX_DETECTIONS x 1] SNR in dB
%     n_detections      actual number of detections in the above arrays
%
%   Fixed-size outputs (MAX_DETECTIONS = 16) so Embedded Coder can
%   produce a static memory layout. Unused entries are NaN. - TripleA

    MAX_DETECTIONS = 16;
    [Nspp_receive, N_el, N_pulses] = size(rx_cube);

    % ---- 1. MVDR beamforming ----
    % Estimate spatial covariance from all pulses stacked; apply
    % weights per pulse to collapse the element dimension.
    rx_stacked = reshape(permute(rx_cube, [1 3 2]), [], N_el);
    [~, w_mvdr] = mvdr_beamform(rx_stacked, x_elements, lambda, look_angle_rad, mvdr_load);

    rx_bf = complex(zeros(Nspp_receive, N_pulses));
    for n = 1:N_pulses
        rx_bf(:, n) = rx_cube(:, :, n) * conj(w_mvdr);
    end

    % ---- 2. Range-Doppler processing ----
    [RDM, range_axis_m, velocity_axis_mps] = ...
        range_doppler(rx_bf, tx, fs, lambda, PRI);
    RDM_power = abs(RDM).^2;

    % ---- 3. CA-CFAR detection ----
    det_mask = cfar_ca(RDM_power, N_guard_range, N_train_range, ...
                       N_guard_dop, N_train_dop, Pfa);

    % ---- 4. Extract detections into fixed-size output arrays ----
    det_range_m      = nan(MAX_DETECTIONS, 1);
    det_velocity_mps = nan(MAX_DETECTIONS, 1);
    det_snr_dB       = nan(MAX_DETECTIONS, 1);

    % Sort detections by power (strongest first), keep top MAX_DETECTIONS
    [det_r, det_d] = find(det_mask);
    n_hits = numel(det_r);
    if n_hits == 0
        n_detections = int32(0);
        return;
    end

    powers = zeros(n_hits, 1);
    for k = 1:n_hits
        powers(k) = RDM_power(det_r(k), det_d(k));
    end
    [~, sort_idx] = sort(powers, 'descend');

    % Estimate noise floor for SNR: median of non-detected cells.
    noise_floor = median(RDM_power(~det_mask), 'omitnan');

    n_out = min(n_hits, MAX_DETECTIONS);
    for k = 1:n_out
        idx = sort_idx(k);
        det_range_m(k)      = range_axis_m(det_r(idx));
        det_velocity_mps(k) = velocity_axis_mps(det_d(idx));
        det_snr_dB(k)       = 10 * log10(powers(idx) / max(noise_floor, eps));
    end
    n_detections = int32(n_out);
end
