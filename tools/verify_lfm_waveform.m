function verify_lfm_waveform()
%VERIFY_LFM_WAVEFORM  Generate and verify the LFM chirp.
%
%   Loads the shipped waveform parameters, generates a single LFM
%   pulse, and plots three views proving it's correct:
%     1. Real / imaginary parts vs time (chirp is visible as
%        increasing oscillation frequency).
%     2. Instantaneous frequency vs time (should be a straight line
%        sloping from -BW/2 to +BW/2).
%     3. Spectrogram (short-time FT) showing the frequency ramp.
%
%   Saves the figure to docs/img/lfm_waveform.png. - TripleA

    % Load parameters into base workspace (safe if already loaded)
    if evalin('base','~exist(''fs'',''var'')')
        evalin('base','run(''model/radar_params.m'')');
        evalin('base','run(''model/waveform_params.m'')');
        evalin('base','run(''model/array_params.m'')');
    end
    fs = evalin('base','fs');
    tau = evalin('base','tau');
    BW  = evalin('base','BW');

    % Generate one pulse
    s = lfm_waveform(tau, BW, fs);
    t = (0:numel(s)-1).' / fs;

    % Instantaneous frequency via phase derivative
    phi = unwrap(angle(s));
    f_inst = diff(phi) / (2*pi) * fs;   % Hz

    % Set up figure
    figure('Name', 'LFM chirp verification', 'Position', [100 100 1400 750]);

    % --- Plot 1: real / imag time domain ---
    subplot(3, 1, 1);
    plot(t*1e6, real(s), 'LineWidth', 1.2); hold on;
    plot(t*1e6, imag(s), 'LineWidth', 1.2, 'LineStyle', '--');
    xlabel('Time (\mus)'); ylabel('Amplitude');
    title(sprintf('LFM pulse - real (solid) and imag (dashed): tau=%.1f \\mus, BW=%.1f MHz', ...
        tau*1e6, BW/1e6));
    legend('Re[s(t)]', 'Im[s(t)]'); grid on;

    % --- Plot 2: instantaneous frequency ---
    subplot(3, 1, 2);
    plot(t(2:end)*1e6, f_inst/1e6, 'LineWidth', 1.5);
    xlabel('Time (\mus)'); ylabel('Instantaneous frequency (MHz)');
    title('Instantaneous frequency - straight-line sweep from -BW/2 to +BW/2');
    yline(-BW/2/1e6, ':', 'Expected f_{start}');
    yline(+BW/2/1e6, ':', 'Expected f_{end}');
    grid on;

    % --- Plot 3: spectrogram ---
    subplot(3, 1, 3);
    win = round(numel(s)/8);
    spectrogram(s, win, round(win*0.75), 512, fs, 'centered', 'yaxis');
    title('Spectrogram - visualises the linear frequency sweep');

    % Save to docs/img
    outPath = fullfile('docs','img','lfm_waveform.png');
    if ~isfolder('docs/img'); mkdir('docs/img'); end
    saveas(gcf, outPath);
    fprintf('Saved %s\n', outPath);

    % Sanity assertions
    assert(abs(f_inst(1)   - (-BW/2)) < BW*0.05, 'Start frequency off spec');
    assert(abs(f_inst(end) - (+BW/2)) < BW*0.05, 'End frequency off spec');
    assert(all(abs(abs(s) - 1) < 1e-9), 'Chirp is not unit-amplitude');
    fprintf('LFM waveform verified: start freq %.2f MHz, end freq %.2f MHz\n', ...
        f_inst(1)/1e6, f_inst(end)/1e6);
end
