function single_run = add_stability_info_cost_functions( single_run, stab)

single_run = add_cost_function_to_single_run( single_run, ...
  'n_dt_ice', 'total number of ice-dynamical time steps', stab.n_dt_ice);
single_run = add_cost_function_to_single_run( single_run, ...
  'inv_min_dt_ice', '1 / (smallest ice-dynamical time step)', 1 / stab.min_dt_ice);
single_run = add_cost_function_to_single_run( single_run, ...
  'inv_max_dt_ice', '1 / (largest ice-dynamical time step)', 1 / stab.max_dt_ice);
single_run = add_cost_function_to_single_run( single_run, ...
  'inv_mean_dt_ice', '1 / (mean ice-dynamical time step)', 1 / stab.mean_dt_ice);

single_run = add_cost_function_to_single_run( single_run, ...
  'n_visc_its', 'total number of viscosity iterations', stab.n_visc_its);
single_run = add_cost_function_to_single_run( single_run, ...
  'min_visc_its_per_dt', 'smallest number of visc its per time step', stab.min_visc_its_per_dt);
single_run = add_cost_function_to_single_run( single_run, ...
  'max_visc_its_per_dt', 'largest number of visc its per time step', stab.max_visc_its_per_dt);
single_run = add_cost_function_to_single_run( single_run, ...
  'mean_visc_its_per_dt', 'mean number of visc its per time step', stab.mean_visc_its_per_dt);

single_run = add_cost_function_to_single_run( single_run, ...
  'n_Axb_its', 'total number of linear solver iterations', stab.n_Axb_its);
single_run = add_cost_function_to_single_run( single_run, ...
  'min_Axb_its_per_visc_it', 'smallest number of linear solver its per visc it', stab.min_Axb_its_per_visc_it);
single_run = add_cost_function_to_single_run( single_run, ...
  'max_Axb_its_per_visc_it', 'largest number of linear solver its per visc it', stab.max_Axb_its_per_visc_it);
single_run = add_cost_function_to_single_run( single_run, ...
  'mean_Axb_its_per_visc_it', 'mean number of linear solver its per visc it', stab.mean_Axb_its_per_visc_it);

end