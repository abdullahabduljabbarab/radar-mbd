function y = matched_filter(rx, tx)
%MATCHED_FILTER  Pulse compression via matched filtering.
%
%   Y = MATCHED_FILTER(RX, TX) returns the matched-filter output for
%   received signal RX (length N) and transmitted pulse TX (length M).
%   Impulse response of the matched filter is the time-reversed
%   complex conjugate of the transmitted pulse:
%       h[n] = conj(tx[M-1-n])
%   which maximises SNR at the correlation peak and compresses the
%   long chirp into a narrow pulse of width approx 1/BW.
%
%   Output Y has length N (same-length convolution) so the peak
%   location in Y maps directly to the delay index of the target.
%   Matched-filter gain over the raw echo is 10*log10(M) dB, where
%   M is the pulse length in samples - the coherent integration gain
%   that lets pulse-compressed radars see targets at ranges an
%   uncompressed pulse of equal peak power could not.
%
%   Codegen-safe: uses only conv1 with an explicitly-sized output.
%   - TripleA

    h    = conj(flipud(tx(:)));            % matched-filter impulse response
    N_rx = numel(rx);
    N_tx = numel(tx);

    % Full convolution has length N_rx + N_tx - 1. In it, a target at
    % 0-indexed delay D produces its peak at sample N_tx + D - 1
    % (1-indexed in MATLAB). Slicing the causal region y_full[N_tx:end]
    % gives an N_rx-length output where sample index i (1-indexed) maps
    % to delay (i-1). Range axis (0:N_rx-1)*c/(2*fs) then reads directly.
    % The 'same' variant would shift the peak by floor(N_tx/2) samples;
    % downstream mapping would need to compensate. This variant keeps
    % the range axis honest with no post-hoc offset. - TripleA
    y_full = conv(rx(:), h);
    y      = y_full(N_tx : N_tx + N_rx - 1);
end
