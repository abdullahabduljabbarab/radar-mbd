function rx_cube = multi_pulse_scene(tx, targets, x_elements, lambda, fs, PRI, N_pulses, Nspp_receive, noise_std)
%MULTI_PULSE_SCENE  Simulate a coherent burst of pulses with Doppler.
%
%   RX_CUBE = MULTI_PULSE_SCENE(TX, TARGETS, X_ELEMENTS, LAMBDA, FS,
%                               PRI, N_PULSES, NSPP_RECEIVE, NOISE_STD)
%   returns a Nspp_receive x N_elements x N_pulses complex cube.
%
%   TARGETS is a struct array (same fields as target_scene_array,
%   plus a new .velocity_mps field for radial velocity). For each
%   pulse index n = 0..N_pulses-1, the chirp target receives a phase
%   advance of exp(j*2*pi*f_d*n*PRI) where the Doppler frequency
%   f_d = 2 * velocity_mps / lambda maps radial velocity to phase
%   change per PRI. A stationary target has f_d = 0 and the same
%   phase across every pulse; a mover has a linear phase ramp that
%   the downstream slow-time FFT will resolve into a Doppler bin.
%
%   Jammers ('noise' waveform) have no Doppler structure - their
%   noise is drawn fresh each pulse. Codegen-safe. - TripleA

    c    = 2.99792458e8;
    N_el = numel(x_elements);
    rx_cube = complex(zeros(Nspp_receive, N_el, N_pulses));

    for n = 1:N_pulses
        pulse_slice = complex(zeros(Nspp_receive, N_el));

        for i = 1:numel(targets)
            tgt = targets(i);
            a_tgt = steering_vector(tgt.angle_rad, x_elements, lambda);

            switch tgt.waveform
                case 'chirp'
                    delay_samples = round(2 * tgt.range_m / c * fs);
                    if delay_samples + numel(tx) > Nspp_receive; continue; end

                    % Doppler phase for THIS pulse
                    v = 0;
                    if isfield(tgt,'velocity_mps'); v = tgt.velocity_mps; end
                    f_d = 2 * v / lambda;
                    doppler_phase = exp(1j * 2*pi * f_d * (n-1) * PRI);

                    % Delayed chirp times element steering times Doppler
                    for k = 1:N_el
                        pulse_slice(delay_samples + (1:numel(tx)), k) = ...
                            pulse_slice(delay_samples + (1:numel(tx)), k) + ...
                            tgt.amplitude * a_tgt(k) * doppler_phase * tx;
                    end

                case 'noise'
                    j_signal = tgt.amplitude * ...
                        (randn(Nspp_receive,1) + 1j*randn(Nspp_receive,1)) / sqrt(2);
                    for k = 1:N_el
                        pulse_slice(:,k) = pulse_slice(:,k) + a_tgt(k) * j_signal;
                    end
            end
        end

        pulse_slice = pulse_slice + noise_std * ...
            (randn(Nspp_receive,N_el) + 1j*randn(Nspp_receive,N_el)) / sqrt(2);
        rx_cube(:,:,n) = pulse_slice;
    end
end
