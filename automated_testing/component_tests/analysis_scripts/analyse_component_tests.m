function analyse_component_tests( varargin)
% Analyse the results of all component tests and add the results to the
% scoreboard files.

%%

% In the GitHub Workflow, provide the component test results folders as
% input; but retain the option of running without input (i.e. as a script)
% locally, with user-defined folders

input_args = varargin;
if isempty( input_args)
  % Assume this is a local run

  foldername_automated_testing = '/Users/Beren017/Documents/GitHub/UFEMISM2.0/automated_testing';
  addpath('/Users/Beren017/Documents/GitHub/UFEMISM2.0/tools/matlab/')
  do_print_figures = false;

elseif isscalar( input_args)
  % Assume this is a GitHub Workflow run

  foldername_automated_testing = varargin{1};
  addpath('tools/matlab/')
  do_print_figures = true;

else
  error('need either foldername_component_tests, or nothing as input!')
end

addpath([foldername_automated_testing '/component_tests'])
addpath([foldername_automated_testing '/component_tests/analysis_scripts'])
addpath([foldername_automated_testing '/scoreboard/scripts'])

%%
analyse_component_tests_discretisation( foldername_automated_testing, do_print_figures);
analyse_component_tests_remapping(      foldername_automated_testing, do_print_figures);

end