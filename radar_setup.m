% radar_setup.m
% One-shot session initialiser. Adds tools/ and model/ to the MATLAB
% path and loads every radar/waveform/array parameter into the base
% workspace so rtwbuild('radar') can resolve StopTime, PortDimensions,
% SampleTime, etc. Run this once per fresh MATLAB session.

repo_root = fileparts(mfilename('fullpath'));
addpath(fullfile(repo_root, 'tools'));
addpath(fullfile(repo_root, 'model'));

radar_params
waveform_params
array_params

fprintf('\nradar_repo ready.\n');
fprintf('  build_radar_model      (regenerate radar.slx if params changed)\n');
fprintf('  rtwbuild(''radar'')     (generate C into radar_ert_rtw/)\n\n');
