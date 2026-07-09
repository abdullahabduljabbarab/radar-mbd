% model/waveform_params.m
% Pulsed LFM (linear frequency modulated) waveform parameters.
% Chirp bandwidth sets range resolution; pulse width sets minimum
% range; PRF sets unambiguous range and Doppler window. All standard
% pulsed-radar plumbing. - TripleA

% ---- Pulse shape ----
% Long-range profile: shorter pulse + narrower bandwidth to sit
% inside the reduced 250 kHz Nyquist window. tau*BW = 10 gives
% 10 dB pulse compression gain, min range = c*tau/2 = 15 km
% (~8 nm) which is well inside the shortest-inter-site distance
% on the CLEARANCE main sector. - TripleA
tau  = 100e-6;          % pulse width (s)   - 100 microseconds
BW   = 100e3;           % chirp bandwidth (Hz) - 100 kHz LFM sweep

% Range resolution follows directly from chirp bandwidth after pulse
% compression: dR = c / (2*BW). At 1 MHz: 150 m per range cell,
% independent of pulse width.
dR = c / (2 * BW);

% ---- Sample rate ----
% Long-range profile: 250 kHz is enough at PRI = 10 ms to keep
% Nspp_receive = 2500 unchanged, which means the generated code's
% fixed-size range-Doppler cube keeps the same dimensions and the
% CLEARANCE plugin wrapper doesn't need resizing. Range resolution
% drops to c/(2*fs) = 600 m per bin - coarse but fine at 800 nm
% scale where a single blip is a whole aircraft-in-airway, not a
% wingtip. - TripleA
fs   = 250e3;           % sample rate (Hz) - 250 kHz
Ts   = 1 / fs;          % sample period (s)
Nspp = round(tau * fs); % samples per pulse (5 at these numbers)

% ---- Pulse repetition ----
% Long-range surveillance profile: 100 Hz. At PRF = 100 Hz:
%   R_unamb = c * PRI / 2       = 1500 km  (targets to 810 nm unambig)
%   v_unamb = lambda / (4 * PRI) = +/-2.7 m/s  (velocity aliases badly)
% This is the BMEWS / early-warning trade: buy huge unambiguous range
% at the cost of throwing away Doppler resolution entirely. Downstream
% CLEARANCE code matches detections on range only for this profile.
% - TripleA
PRF  = 100;             % pulse repetition frequency (Hz) - 100 Hz
PRI  = 1 / PRF;         % pulse repetition interval  (s)  - 10 ms

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
