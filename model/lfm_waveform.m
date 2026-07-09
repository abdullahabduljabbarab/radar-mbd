function s = lfm_waveform(tau, BW, fs)
%LFM_WAVEFORM  Complex-baseband LFM (linear frequency modulated) chirp.
%
%   S = LFM_WAVEFORM(TAU, BW, FS) returns a length-N column vector S
%   of complex baseband samples representing a single LFM pulse of
%   width TAU (seconds) and swept bandwidth BW (Hz), sampled at rate
%   FS (Hz). Sweep runs from -BW/2 to +BW/2 across the pulse.
%
%   The chirp rate is k = BW / TAU (Hz/s). Instantaneous frequency at
%   time t is f(t) = -BW/2 + k*t, so the phase at time t is
%       phi(t) = 2*pi * integral(f(t) dt) = 2*pi * (-BW/2 * t + k/2 * t^2).
%   Complex baseband signal is then s(t) = exp(1j * phi(t)).
%
%   The output is codegen-safe: only real arithmetic and complex
%   exponentials, no cell arrays or dynamic memory. Suitable to paste
%   directly into a Simulink MATLAB Function block. - TripleA

    N  = round(tau * fs);              % samples per pulse
    n  = (0:N-1).';                    % sample index vector
    t  = n / fs;                       % time vector (s)
    k  = BW / tau;                     % chirp rate (Hz/s)

    % Instantaneous phase from integrated frequency
    phi = 2*pi * (-BW/2 .* t + 0.5 * k .* t.^2);

    s = exp(1j * phi);
end
