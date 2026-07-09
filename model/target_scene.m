function [rx, delay_samples] = target_scene(tx, R, SNR_dB, fs, Nspp_receive)
%TARGET_SCENE  Simulate a receive window with one point target return.
%
%   [RX, DELAY_SAMPLES] = TARGET_SCENE(TX, R, SNR_dB, FS, NSPP_RECEIVE)
%   returns a complex baseband receive-window signal RX of length
%   NSPP_RECEIVE containing a delayed copy of the transmit pulse TX
%   plus additive white Gaussian noise. The target return is placed
%   at slant range R (metres); the round-trip time delay in samples
%   is DELAY_SAMPLES = round(2 * R / c * FS).
%
%   SNR_dB sets the pre-integration signal-to-noise ratio of the raw
%   target return relative to the noise variance (0 dB = target
%   amplitude equal to noise standard deviation). Matched-filter
%   processing downstream adds coherent-integration gain of
%   10*log10(TB) dB on top of this.
%
%   Codegen-safe: no cell arrays, no dynamic allocation beyond the
%   fixed-size output vector. - TripleA

    c = 2.99792458e8;
    N_tx = numel(tx);

    delay_samples = round(2 * R / c * fs);
    if delay_samples + N_tx > Nspp_receive
        error('target_scene:RangeTooFar', ...
              'Target at %.0f km falls outside receive window', R/1000);
    end

    % Build noise-free target return
    rx = complex(zeros(Nspp_receive, 1));
    rx(delay_samples + (1:N_tx)) = tx;

    % Add AWGN. Scale target amplitude so SNR = |signal|^2 / noise_var
    % has the requested value in dB. Target amplitude is unit (|tx|=1),
    % so noise_std = 10^(-SNR/20).
    noise_std = 10^(-SNR_dB/20);
    rx = rx + noise_std * (randn(Nspp_receive,1) + 1j*randn(Nspp_receive,1)) / sqrt(2);
end
