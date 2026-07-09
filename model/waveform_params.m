% model/waveform_params.m
% Pulsed LFM (linear frequency modulated) waveform parameters.
% Chirp bandwidth sets range resolution; pulse width sets minimum
% range; PRF sets unambiguous range and Doppler window. All standard
% pulsed-radar plumbing. - TripleA

% ---- Pulse shape ----
% Long chirp with pulse compression - matches how real long-range
% surveillance radars trade pulse width for SNR while keeping range
% resolution set by bandwidth. Time-bandwidth product tau*BW = 20
% here, so matched-filter compression yields 13 dB gain over an
% uncompressed pulse of the same peak power. - TripleA
tau  = 20e-6;           % pulse width (s)   - 20 microseconds
BW   = 1e6;             % chirp bandwidth (Hz) - 1 MHz LFM sweep

% Range resolution follows directly from chirp bandwidth after pulse
% compression: dR = c / (2*BW). At 1 MHz: 150 m per range cell,
% independent of pulse width.
dR = c / (2 * BW);

% ---- Sample rate ----
% Oversample by 10x so the chirp is well-represented for
% visualisation and the matched-filter output has plenty of samples
% per range cell to locate the correlation peak precisely.
fs   = 10 * BW;         % sample rate (Hz) - 10 MHz
Ts   = 1 / fs;          % sample period (s)
Nspp = round(tau * fs); % samples per pulse (128 at these numbers)

% ---- Pulse repetition ----
% Medium-PRF surveillance: 4 kHz balances unambiguous range vs
% unambiguous velocity for the airliner regime. At PRF = 4 kHz:
%   R_unamb = c * PRI / 2       = 37.5 km   (targets to 37.5 km unambig)
%   v_unamb = lambda / (4 * PRI) = +/-107 m/s (>= typical airliner speed)
% Real long-range radars stagger PRF to disambiguate targets beyond
% these limits; a single PRF is enough for the demo. - TripleA
PRF  = 4000;            % pulse repetition frequency (Hz) - 4 kHz
PRI  = 1 / PRF;         % pulse repetition interval  (s)  - 250 us

% Unambiguous range: c * PRI / 2. At PRI = 250 us: 37.5 km.
R_max_unamb = c * PRI / 2;

% ---- Coherent processing interval (CPI) ----
% Number of pulses processed together as a coherent burst for
% Doppler analysis. More pulses -> finer Doppler resolution +
% higher integration gain, at the cost of longer time-to-detection.
N_pulses = 16;
CPI      = N_pulses * PRI;    % total CPI duration (s)

% Doppler resolution: dv = lambda / (2 * CPI). At 16 pulses of 1 ms
% and 0.107 m wavelength, dv = 3.35 m/s (about 6.5 knots).
dv = lambda / (2 * CPI);

% ---- Total samples per CPI ----
% Not every sample is a "pulse"; there's silence between pulses.
% We only process the receive window per pulse - typically a subset
% of the PRI. For simplicity assume we process the full PRI.
Nspp_receive = round(PRI * fs);   % samples in a receive window
N_total      = Nspp_receive * N_pulses;

if ~exist('VERBOSE','var') || VERBOSE
    fprintf('waveform_params: tau=%.1f us, BW=%.1f MHz, PRF=%.0f Hz\n', ...
        tau*1e6, BW/1e6, PRF);
    fprintf('  range resolution %.0f m, unamb range %.0f km, Doppler res %.2f m/s\n', ...
        dR, R_max_unamb/1000, dv);
    fprintf('  fs=%.1f MHz, N_pulses=%d, CPI=%.1f ms\n', fs/1e6, N_pulses, CPI*1000);
end
