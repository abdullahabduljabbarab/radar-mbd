function [det_mask, threshold_map] = cfar_ca(RDM_power, N_guard_range, N_train_range, N_guard_dop, N_train_dop, Pfa)
%CFAR_CA  Cell-averaging constant false-alarm-rate detector.
%
%   [DET_MASK, THRESHOLD_MAP] =
%       CFAR_CA(RDM_POWER, N_GUARD_RANGE, N_TRAIN_RANGE,
%               N_GUARD_DOP,   N_TRAIN_DOP,   PFA)
%
%   Slides a rectangular window across the range-Doppler power map
%   RDM_POWER (assumed non-negative real, e.g. abs(RDM).^2). For each
%   cell under test (CUT):
%     - Skip GUARD cells immediately around the CUT (to avoid the
%       target's own energy leaking into the noise estimate).
%     - Average the surrounding TRAINING cells to estimate the local
%       noise power.
%     - Threshold = alpha * noise_estimate, where alpha comes from
%       the Rohling formula for cell-averaging CFAR:
%          alpha = N_train * (Pfa^(-1/N_train) - 1)
%       This gives a constant false-alarm rate PFA across the map
%       under an exponential-noise assumption.
%     - Declare detection if CUT power > threshold.
%
%   Returns DET_MASK (logical, same size as RDM_POWER) and
%   THRESHOLD_MAP (same size, useful for plotting).
%
%   Edge cells (within the CFAR window of a boundary) are left as
%   non-detections. Codegen-safe: pre-allocated fixed-size arrays,
%   no dynamic growth. - TripleA

    [N_range, N_dop] = size(RDM_power);
    det_mask      = false(N_range, N_dop);
    threshold_map = zeros(N_range, N_dop);

    % Number of training cells forming the noise-estimate ring
    N_train_total = ...
        (2*(N_train_range + N_guard_range) + 1) * ...
        (2*(N_train_dop   + N_guard_dop  ) + 1) - ...
        (2*N_guard_range + 1) * (2*N_guard_dop + 1);

    % Rohling threshold multiplier for CA-CFAR
    alpha = N_train_total * (Pfa^(-1/N_train_total) - 1);

    % Window half-widths
    half_r = N_train_range + N_guard_range;
    half_d = N_train_dop   + N_guard_dop;

    for r = 1 + half_r : N_range - half_r
        for d = 1 + half_d : N_dop - half_d
            % Full window around CUT
            window_r = r - half_r : r + half_r;
            window_d = d - half_d : d + half_d;
            block = RDM_power(window_r, window_d);

            % Zero out the guard region + CUT
            guard_r_local = half_r - N_guard_range + 1 : half_r + N_guard_range + 1;
            guard_d_local = half_d - N_guard_dop   + 1 : half_d + N_guard_dop   + 1;
            block(guard_r_local, guard_d_local) = 0;

            % Sum training cells (guard-nulled block sums only trainers)
            training_sum = sum(block(:));
            noise_estimate = training_sum / N_train_total;

            threshold = alpha * noise_estimate;
            threshold_map(r, d) = threshold;

            if RDM_power(r, d) > threshold
                det_mask(r, d) = true;
            end
        end
    end
end
