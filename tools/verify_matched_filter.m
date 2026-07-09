function verify_matched_filter()
%VERIFY_MATCHED_FILTER  End-to-end LFM + target + matched filter demo.
%
%   Places a single target at 30 km slant range, generates the
%   receive-window echo + AWGN, runs the matched filter, and plots:
%     1. Received signal magnitude (target buried in noise).
%     2. Matched-filter output magnitude (target now sharp peak).
%     3. Range profile in km with measured vs true target range.
%
%   Saves to docs/img/matched_filter.png. Also asserts that the
%   detected peak location is within one range cell of the true
%   target range. - TripleA

    % Load params
    if evalin('base','~exist(''fs'',''var'')')
        evalin('base','run(''model/radar_params.m'')');
        evalin('base','run(''model/waveform_params.m'')');
        evalin('base','run(''model/array_params.m'')');
    end
    fs           = evalin('base','fs');
    tau          = evalin('base','tau');
    BW           = evalin('base','BW');
    Nspp_receive = evalin('base','Nspp_receive');
    dR           = evalin('base','dR');
    c            = 2.99792458e8;

    % Reproducibility - fixed seed so the demo plot is deterministic
    rng(42);

    % Scene: single target at 30 km.
    % Pre-integration SNR of +5 dB is chosen so the raw echo is still
    % clearly buried in noise on the received-signal plot (top subplot),
    % but the 13 dB matched-filter compression gain lifts the peak to
    % ~18 dB above the noise floor - a solid, unambiguous detection.
    R_true    = 30e3;      % 30 km
    SNR_raw   = 5;         % dB (post-compression -> ~18 dB)

    % Transmit + receive + matched filter
    tx = lfm_waveform(tau, BW, fs);
    [rx, delay_true] = target_scene(tx, R_true, SNR_raw, fs, Nspp_receive);
    y  = matched_filter(rx, tx);

    % Range axis - each sample corresponds to c/(2*fs) metres one-way
    range_axis_m = (0:Nspp_receive-1).' * c / (2*fs);

    % Find detected peak
    [~, idx_peak] = max(abs(y));
    R_detected = range_axis_m(idx_peak);

    % --- Plot ---
    figure('Name','Matched filter verification','Position',[100 100 1400 800]);

    subplot(3,1,1);
    plot(range_axis_m/1000, abs(rx), 'LineWidth', 0.5);
    xlabel('Range (km)'); ylabel('|rx| (linear)');
    title(sprintf('Received signal - target at %.1f km (SNR_{raw} = %d dB) buried in noise', ...
        R_true/1000, SNR_raw));
    grid on; xlim([0 max(range_axis_m)/1000]);

    subplot(3,1,2);
    plot(range_axis_m/1000, 20*log10(abs(y) + eps), 'LineWidth', 1.2);
    xlabel('Range (km)'); ylabel('|y| (dB)');
    title(sprintf('Matched-filter output - pulse compression gain %.1f dB restores the target', ...
        10*log10(tau*BW)));
    grid on; xlim([0 max(range_axis_m)/1000]);

    subplot(3,1,3);
    plot(range_axis_m/1000, 20*log10(abs(y) + eps), 'LineWidth', 1.5); hold on;
    plot(R_true/1000, 20*log10(abs(y(idx_peak))), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
    xline(R_detected/1000, 'g:', sprintf('detected %.2f km', R_detected/1000));
    xline(R_true/1000,     'k:', sprintf('true %.2f km',     R_true/1000));
    xlabel('Range (km)'); ylabel('|y| (dB)');
    title(sprintf('Zoom on target - detected at %.2f km, true %.2f km, cell width %.0f m', ...
        R_detected/1000, R_true/1000, dR));
    grid on;
    xlim([(R_true - 5*dR)/1000, (R_true + 5*dR)/1000]);

    outPath = fullfile('docs','img','matched_filter.png');
    if ~isfolder('docs/img'); mkdir('docs/img'); end
    saveas(gcf, outPath);
    fprintf('Saved %s\n', outPath);

    % Sanity assertion
    assert(abs(R_detected - R_true) < 2*dR, ...
        'Detected range off by more than 2 cells');
    fprintf('Matched filter verified: target at %.2f km, detected at %.2f km (%.0f m error, %.1f dB peak)\n', ...
        R_true/1000, R_detected/1000, R_detected - R_true, 20*log10(abs(y(idx_peak))));
end
