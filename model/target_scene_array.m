function rx = target_scene_array(tx, targets, x_elements, lambda, fs, Nspp_receive, noise_std)
%TARGET_SCENE_ARRAY  Simulate a multi-element receive window with
%                    multiple targets / jammers.
%
%   RX = TARGET_SCENE_ARRAY(TX, TARGETS, X_ELEMENTS, LAMBDA, FS,
%                           NSPP_RECEIVE, NOISE_STD)
%   returns an NSPP_RECEIVE x N complex matrix RX where column i
%   is the receive signal at array element X_ELEMENTS(i).
%
%   TARGETS is a struct array with fields:
%     .range_m      slant range in metres (used for delay)
%     .angle_rad    angle of arrival in radians (used for phase across array)
%     .amplitude    complex or real gain applied to the target return
%                   (use amplitude = 10^(SNR_dB/20) if you want a
%                    specific target SNR against noise_std)
%     .waveform     'chirp' - target reflects the transmitted chirp
%                   'noise' - jammer, radiates noise instead of chirp
%
%   NOISE_STD is per-element AWGN standard deviation. Each element
%   sees independent noise.
%
%   Signal model: for a chirp target at (range, angle), each element
%   sees a delayed copy of tx multiplied by the element's phase in
%   the target's steering vector a(angle). Jammer targets multiply
%   the steering vector by band-limited noise over the whole receive
%   window (representing a barrage jammer illuminating the array). - TripleA

    c = 2.99792458e8;
    N_tx = numel(tx);
    N_el = numel(x_elements);

    rx = complex(zeros(Nspp_receive, N_el));

    for i = 1:numel(targets)
        tgt = targets(i);
        a_tgt = steering_vector(tgt.angle_rad, x_elements, lambda);

        switch tgt.waveform
            case 'chirp'
                delay_samples = round(2 * tgt.range_m / c * fs);
                if delay_samples + N_tx > Nspp_receive; continue; end
                % Element-shaped delayed copy
                for k = 1:N_el
                    rx(delay_samples + (1:N_tx), k) = ...
                        rx(delay_samples + (1:N_tx), k) + ...
                        tgt.amplitude * a_tgt(k) * tx;
                end

            case 'noise'
                % Jammer illuminates the receive window with complex
                % noise, shaped by the steering vector at its angle.
                j_signal = tgt.amplitude * ...
                    (randn(Nspp_receive,1) + 1j*randn(Nspp_receive,1)) / sqrt(2);
                for k = 1:N_el
                    rx(:,k) = rx(:,k) + a_tgt(k) * j_signal;
                end
        end
    end

    % Per-element AWGN
    rx = rx + noise_std * (randn(Nspp_receive,N_el) + 1j*randn(Nspp_receive,N_el)) / sqrt(2);
end
