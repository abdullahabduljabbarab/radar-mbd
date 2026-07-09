function [RDM, range_axis_m, velocity_axis_mps] = range_doppler(rx_pulses, tx, fs, lambda, PRI)
%RANGE_DOPPLER  2D matched filter + Doppler FFT.
%
%   [RDM, RANGE_AXIS_M, VELOCITY_AXIS_MPS] =
%       RANGE_DOPPLER(RX_PULSES, TX, FS, LAMBDA, PRI)
%
%   RX_PULSES is a Nspp_receive x N_pulses matrix of single-channel
%   receive data (post-beamforming). Each column is one pulse; each
%   row is one fast-time sample.
%
%   Processing:
%     1. Matched filter every pulse independently in fast-time.
%        This is the pulse-compression step - each pulse's target
%        return collapses to a narrow peak at its range cell.
%     2. Window the slow-time dimension (Hamming) to suppress
%        Doppler sidelobes.
%     3. FFT across slow-time (pulses) at every range cell. Coherent
%        integration across N_pulses lifts the target by 10*log10(N)
%        dB above the noise floor at its Doppler bin.
%     4. fftshift so the zero-Doppler bin sits in the middle.
%
%   Returns RDM as Nspp_receive x N_pulses complex range-Doppler map,
%   plus the range axis (m) and velocity axis (m/s). Positive velocity
%   is closing (target approaching); negative is opening.
%
%   Codegen-safe. Fixed-size FFT and convolution shapes throughout.
%   - TripleA

    c = 2.99792458e8;
    [N_range, N_pulses] = size(rx_pulses);
    N_tx = numel(tx);

    % ---- 1. Matched filter every pulse in fast-time ----
    range_compressed = complex(zeros(N_range, N_pulses));
    for n = 1:N_pulses
        range_compressed(:, n) = matched_filter(rx_pulses(:, n), tx);
    end

    % ---- 2. Slow-time windowing to suppress Doppler sidelobes ----
    slow_time_window = hamming(N_pulses).';   % row vector
    range_compressed = range_compressed .* slow_time_window;

    % ---- 3. Doppler FFT across pulses (dimension 2) ----
    RDM_raw = fft(range_compressed, N_pulses, 2);

    % ---- 4. fftshift so zero-Doppler sits at the centre column ----
    RDM = fftshift(RDM_raw, 2);

    % ---- Axes ----
    % Range axis: sample index * c / (2*fs)
    range_axis_m = (0:N_range-1).' * c / (2*fs);

    % Doppler frequency axis (Hz), shifted so bin 0 is in the middle
    doppler_bins = (-N_pulses/2 : N_pulses/2 - 1);
    doppler_freqs_Hz = doppler_bins / (N_pulses * PRI);

    % Velocity axis (m/s): v = lambda * f_d / 2 (positive = closing)
    velocity_axis_mps = lambda * doppler_freqs_Hz(:) / 2;
end
