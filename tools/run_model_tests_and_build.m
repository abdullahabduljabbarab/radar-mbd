% tools/run_model_tests_and_build.m
% CI entry point. Runs the full verification suite and rebuilds the
% Simulink model with codegen. Called by the GitHub Actions workflow;
% also runnable locally as: addpath(genpath(pwd)); run tools/run_model_tests_and_build
% - TripleA

fprintf('=== radar-mbd CI ===\n');
fprintf('MATLAB %s\n', version);

% Load parameters into base workspace
run('model/radar_params.m');
run('model/waveform_params.m');
run('model/array_params.m');

fprintf('\n--- Verifying DSP kernels ---\n');
verify_lfm_waveform;
verify_matched_filter;
verify_beamformer;
verify_range_doppler;
verify_radar_dsp;

fprintf('\n--- Regression check ---\n');
compare_sim;

fprintf('\n--- Rebuilding Simulink model ---\n');
build_radar_model;

fprintf('\n--- Embedded Coder codegen ---\n');
rtwbuild('radar');

fprintf('\n=== CI complete ===\n');
