function [det_mask, threshold_map] = cfar_ca(RDM_power, N_guard_range, N_train_range, N_guard_dop, N_train_dop, Pfa)
%CFAR_CA  Cell-averaging constant false-alarm-rate detector.
%
%   [DET_MASK, THRESHOLD_MAP] =
%       CFAR_CA(RDM_POWER, N_GUARD_RANGE, N_TRAIN_RANGE,
%               N_GUARD_DOP, N_TRAIN_DOP, PFA)
%
%   Slides a rectangular window across the range-Doppler power map
%   RDM_POWER. For each cell under test (CUT):
%     - Sum surrounding TRAINING cells to estimate local noise power
%       (guard cells around the CUT are skipped to avoid target
%       energy leaking into the noise estimate).
%     - Threshold = alpha * noise_estimate, alpha = Rohling formula
%       N_train * (Pfa^(-1/N_train) - 1) for constant false-alarm
%       rate under exponential noise.
%     - Declare detection if CUT power > threshold.
%
%   Codegen-safe: iteration is done with scalar indexing only. No
%   submatrix slicing or dynamic ranges. Every array index is a
%   scalar arithmetic expression Coder can resolve to fixed offsets
%   at compile time. Edge cells within the CFAR window of a boundary
%   are left as non-detections. - TripleA

    [N_range, N_dop] = size(RDM_power);
    det_mask      = false(N_range, N_dop);
    threshold_map = zeros(N_range, N_dop);

    N_train_total = ...
        (2*(N_train_range + N_guard_range) + 1) * ...
        (2*(N_train_dop   + N_guard_dop  ) + 1) - ...
        (2*N_guard_range + 1) * (2*N_guard_dop + 1);

    alpha = N_train_total * (Pfa^(-1/N_train_total) - 1);

    half_r = N_train_range + N_guard_range;
    half_d = N_train_dop   + N_guard_dop;

    for r = 1 + half_r : N_range - half_r
        for d = 1 + half_d : N_dop - half_d
            % Accumulate training cells via scalar-index inner loops.
            % Guard region skipped in place - no submatrix extraction.
            training_sum = 0.0;
            for dr = -half_r : half_r
                for dd = -half_d : half_d
                    if abs(dr) <= N_guard_range && abs(dd) <= N_guard_dop
                        continue;
                    end
                    training_sum = training_sum + RDM_power(r + dr, d + dd);
                end
            end

            noise_estimate = training_sum / N_train_total;
            threshold      = alpha * noise_estimate;
            threshold_map(r, d) = threshold;

            if RDM_power(r, d) > threshold
                det_mask(r, d) = true;
            end
        end
    end
end
