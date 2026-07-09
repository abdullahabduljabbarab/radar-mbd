% model/radar_params.m
% Radar system-level parameters. Values chosen to match the ASR-9
% civil airport surveillance baseline that CLEARANCE's C++ radar
% equation module uses, so link-budget analysis produces the same
% numbers whether you run it in MATLAB or CLEARANCE. - TripleA

% ---- Physical constants ----
c    = 2.99792458e8;    % speed of light (m/s)
kB   = 1.380649e-23;    % Boltzmann's constant (J/K)

% ---- RF front end ----
Pt   = 1.4e6;           % peak transmit power (W)  - ASR-9 class
fc   = 2.8e9;           % carrier frequency  (Hz)  - S-band
lambda = c / fc;        % wavelength         (m)   - approx 0.107 m

% ---- Antenna / system gains ----
GtdB = 34;              % transmit antenna gain (dBi)
GrdB = 34;              % receive antenna gain  (dBi)
LdB  = 6;               % system loss (feedline + processing + atmos) (dB)

% ---- Receiver noise ----
Tsys = 290;             % system noise temperature (K)  - IEEE reference
NFdB = 3;               % receiver noise figure   (dB)

% ---- Detection threshold ----
% Classic single-pulse Swerling-0 threshold for Pd = 0.9, Pfa = 1e-6.
% Real designs achieve higher Pd via pulse integration - see the
% range-Doppler section, which integrates N pulses coherently before
% CFAR thresholding. Effective per-pulse SNR requirement drops by
% 10*log10(N) dB after coherent integration.
SNR_req_dB = 13;

% ---- Convenience: linear versions ----
Gt   = 10^(GtdB / 10);
Gr   = 10^(GrdB / 10);
L    = 10^(LdB  / 10);
NF   = 10^(NFdB / 10);

if ~exist('VERBOSE','var') || VERBOSE
    fprintf('radar_params: fc=%.1f GHz, lambda=%.1f mm, Pt=%.1f kW, Gt=Gr=%.0f dB\n', ...
        fc/1e9, lambda*1000, Pt/1000, GtdB);
end
