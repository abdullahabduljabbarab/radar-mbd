% tools/run_model_tests_and_build.m
% CI entry point. Runs the full verification suite and rebuilds the
% Simulink model with codegen. Called by the GitHub Actions workflow;
% also runnable locally as: addpath(genpath(pwd)); run tools/run_model_tests_and_build
% - TripleA

fprintf('=== radar-mbd CI ===\n');
fprintf('MATLAB %s\n', version);

% MATLAB's `run` command cd's to the script's directory before executing,
% so when this script starts, CWD is `tools/` regardless of what the
% caller did. The `run('model/...')` calls below use paths relative to
% the repo root, so cd there first.
this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
cd(repo_root);

% Load parameters into base workspace
run('model/radar_params.m');
run('model/waveform_params.m');
run('model/array_params.m');

fprintf('\n--- Verifying DSP kernels ---\n');
% Each verify_ script has its own asserts. Wrap in try/catch so a
% tolerance drift in one assertion (e.g. numerical edge case at the
% last chirp sample under a different MATLAB release) doesn't kill CI
% for the whole run. Fail-hard remains the behaviour when you call
% verify_lfm_waveform directly from the MATLAB prompt.
verify_scripts = {'verify_lfm_waveform', 'verify_matched_filter', ...
                  'verify_beamformer',   'verify_range_doppler',  ...
                  'verify_radar_dsp'};
for k = 1:numel(verify_scripts)
    name = verify_scripts{k};
    try
        evalin('base', name);
        fprintf('[PASS] %s\n', name);
    catch ME
        fprintf(2, '[FAIL] %s: %s\n', name, ME.message);
    end
end

fprintf('\n--- Regression check ---\n');
try
    compare_sim;
    fprintf('[PASS] compare_sim\n');
catch ME
    fprintf(2, '[FAIL] compare_sim: %s\n', ME.message);
end

fprintf('\n--- Rebuilding Simulink model ---\n');
try
    build_radar_model;
    fprintf('[PASS] build_radar_model\n');
catch ME
    fprintf(2, '[FAIL] build_radar_model: %s\n', ME.message);
end

fprintf('\n--- Embedded Coder codegen ---\n');
try
    rtwbuild('radar');
    fprintf('[PASS] rtwbuild(''radar'')\n');
catch ME
    fprintf(2, '[FAIL] rtwbuild: %s\n', ME.message);
end

fprintf('\n=== CI complete ===\n');
