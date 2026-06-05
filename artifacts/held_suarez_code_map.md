# Code Map Report

Repository: `/explore/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere`
Keywords: `held_suarez, held, suarez, forcing, hs`

## Most relevant files

### `src/atmos_param/hs_forcing/hs_forcing.F90`

- Language: `fortran`
- Lines: `1028`
- Relevance score: `120`
- Modules: `hs_forcing_mod`
- Uses: `astronomy_mod, constants_mod, diag_manager_mod, field_manager_mod, fms_mod, interpolator_mod, mpp_mod, spec_mpp_mod, time_manager_mod, tracer_manager_mod, transforms_mod`
- Subroutines: `calc_ecc_anomaly, calc_hour_angle, get_zonal_mean_flow, get_zonal_mean_temp, hs_forcing, hs_forcing_end, hs_forcing_init, local_heating, newtonian_damping, rayleigh_damping, top_down_newtonian_damping, tracer_source_sink, update_orbit`
- Calls: `astronomy_init, calc_ecc_anomaly, calc_hour_angle, close_file, diurnal_exoplanet, error_mesg, get_grid_domain, get_number_tracers, get_time, get_zonal_mean_flow, get_zonal_mean_temp, interpolator, interpolator_end, interpolator_init, local_heating, newtonian_damping, rayleigh_damping, read_data, set_domain, top_down_newtonian_damping, tracer_source_sink, update_orbit, write_data, write_version_number`

### `exp/test_cases/held_suarez/held_suarez_test_case.py`

- Language: `python`
- Lines: `110`
- Relevance score: `110`
- Mentions: `held_suarez, namelist, compile, run, fms`

### `exp/test_cases/held_suarez/parameter_sweep.py`

- Language: `python`
- Lines: `42`
- Relevance score: `90`
- Mentions: `held_suarez, namelist, run`

### `run_held_suarez.sh`

- Language: `script`
- Lines: `37`
- Relevance score: `80`
- Mentions: `held_suarez, run`

### `src/atmos_spectral/driver/solo/atmosphere.F90`

- Language: `fortran`
- Lines: `400`
- Relevance score: `80`
- Modules: `atmosphere_mod`
- Uses: `column_grid_mod, column_mod, constants_mod, field_manager_mod, fms_mod, hs_forcing_mod, idealized_moist_phys_mod, mpp_mod, press_and_geopot_mod, spec_mpp_mod, spectral_dynamics_mod, time_manager_mod, tracer_manager_mod, tracer_type_mod, transforms_mod`
- Subroutines: `atmosphere, atmosphere_end, atmosphere_init`
- Calls: `close_file, column, column_diagnostics, column_end, column_init, compute_pressures_and_heights, error_mesg, field_size, get_deg_lat, get_deg_lon, get_grid_boundaries, get_grid_domain, get_initial_fields, get_lat_max, get_lon_max, get_num_levels, get_number_tracers, get_surf_geopotential, get_time, hs_forcing, hs_forcing_end, hs_forcing_init, idealized_moist_phys, idealized_moist_phys_end, idealized_moist_phys_init, nullify_domain, read_data, set_domain, spectral_diagnostics, spectral_dynamics`

### `agents/code_mapper.py`

- Language: `python`
- Lines: `316`
- Relevance score: `60`
- Mentions: `held_suarez, namelist, compile, run, fms, mpp`

### `src/extra/python/isca/codebase.py`

- Language: `python`
- Lines: `477`
- Relevance score: `40`
- Mentions: `held_suarez, compile, run, fms`

### `src/extra/python/isca/templates/compile.sh`

- Language: `script`
- Lines: `83`
- Relevance score: `40`
- Mentions: `compile, run, fms, mpp`

### `src/extra/python/scripts/get_namelist_defaults.py`

- Language: `python`
- Lines: `83`
- Relevance score: `40`
- Mentions: `namelist, compile, run, fms`

### `tools/test_cases.F90`

- Language: `fortran`
- Lines: `9350`
- Relevance score: `30`
- Modules: `test_cases_mod`
- Uses: `constants_mod, field_manager_mod, fv_arrays_mod, fv_diagnostics_mod, fv_eta_mod, fv_grid_tools_mod, fv_grid_utils_mod, fv_mp_mod, fv_sg_mod, fv_surf_map_mod, init_hydro_mod, mpp_domains_mod, mpp_mod, mpp_parameter_mod, tracer_manager_mod`
- Subroutines: `atob_s, atoc, atod, balanced_K, case51_forcing, case9_forcing1, case9_forcing2, check_courant_numbers, checker_tracers, ctoa, d2a2c, DCMIP16_BC, DCMIP16_TC, DCMIP16_TC_uwind_pert, dtoa, get_case9_B, get_pt_on_great_circle, get_scalar_stats, get_stats, get_unit_vector, get_vector_stats, get_vorticity, init_case, init_double_periodic, init_latlon, init_latlon_winds, init_winds, interp_left_edge_1d, mp_ghost_ew, mp_update_dwinds_2d, mp_update_dwinds_3d, normalize_vect, output, output_ncdf, pmxn, prt_m1, rankine_vortex, rotate_winds, sm1_edge, SuperK_Sounding, SuperK_u, terminator_tracers, var_dz, vpol5, wrt2d, wrtvar_ncdf`
- Functions: `DCMIP16_BC_pressure, DCMIP16_BC_sphum, DCMIP16_BC_temperature, DCMIP16_BC_uwind, DCMIP16_BC_uwind_pert, DCMIP16_TC_pressure, DCMIP16_TC_sphum, DCMIP16_TC_temperature, gh_jet, globalsum, u_jet`
- Calls: `atob_s, atoc, atod, balanced_K, cart_to_latlon, checker_tracers, compute_dz_L101, compute_dz_L32, ctoa, cubed_to_latlon, DCMIP16_BC, DCMIP16_TC, DCMIP16_TC_uwind_pert, dtoa, exit, fill_corners, get_case9_B, get_latlon_vector, get_pt_on_great_circle, get_scalar_stats, get_unit_vect2, get_unit_vector, get_vector_stats, get_vorticity, gw_1d, hybrid_z_dz, hydro_eq, init_latlon_winds, init_winds, interp_left_edge_1d`

### `src/extra/python/isca/__init__.py`

- Language: `python`
- Lines: `86`
- Relevance score: `30`
- Mentions: `namelist, compile, run`

### `src/extra/python/isca/experiment.py`

- Language: `python`
- Lines: `400`
- Relevance score: `30`
- Mentions: `namelist, run, mpp`

### `src/extra/python/isca/util.py`

- Language: `python`
- Lines: `264`
- Relevance score: `30`
- Mentions: `namelist, compile, run`

### `agents/tools.py`

- Language: `python`
- Lines: `155`
- Relevance score: `30`
- Mentions: `held_suarez, compile, run`

### `agents/pipeline.py`

- Language: `python`
- Lines: `383`
- Relevance score: `30`
- Mentions: `held_suarez, compile, run`

### `model/dyn_core.F90`

- Language: `fortran`
- Lines: `2528`
- Relevance score: `20`
- Modules: `dyn_core_mod`
- Uses: `a2b_edge_mod, boundary_mod, constants_mod, diag_manager_mod, fv_ada_nudge_mod, fv_arrays_mod, fv_diagnostics_mod, fv_mp_mod, fv_nwp_nudge_mod, fv_timing_mod, fv_update_phys_mod, mpp_domains_mod, mpp_mod, mpp_parameter_mod, nh_core_mod, sw_core_mod, test_cases_mod, tp_core_mod`
- Subroutines: `adv_pe, Beljaars, del2_cubed, dyn_core, geopk, grad1_p_update, init_ijk_mem, mix_dp, nh_p_grad, one_grad_p, p_grad_c, pe_halo, pk3_halo, pln_halo, Ray_fast, split_p_grad`
- Calls: `a2b_ord2, a2b_ord4, adv_pe, Beljaars, breed_slp_inline, breed_slp_inline_ada, c_sw, case9_forcing1, case9_forcing2, complete_group_halo_update, copy_corners, d2a2c_vect, d_sw, del2_cubed, geopk, grad1_p_update, init_ijk_mem, mix_dp, mpp_get_boundary, mpp_update_domains, nest_halo_nh, nested_grid_BC_apply_intT, nh_p_grad, one_grad_p, p_grad_c, pe_halo, pk3_halo, pln_halo, prt_mxm, Ray_fast`

### `src/extra/python/isca/templates/run.sh`

- Language: `script`
- Lines: `42`
- Relevance score: `20`
- Mentions: `run, mpp`

### `src/extra/python/scripts/edit_nc_file_to_preserve_monthly_means.py`

- Language: `python`
- Lines: `120`
- Relevance score: `20`
- Mentions: `run, fms`

### `src/extra/python/scripts/qflux_warmpool_with_amip.py`

- Language: `python`
- Lines: `296`
- Relevance score: `20`
- Mentions: `run, fms`

### `src/extra/python/scripts/remove_certain_restart_and_data_files.py`

- Language: `python`
- Lines: `142`
- Relevance score: `20`
- Mentions: `run, fms`

### `src/extra/python/scripts/calculate_qflux/nc_file_io_xarray.py`

- Language: `python`
- Lines: `321`
- Relevance score: `20`
- Mentions: `run, fms`

### `postprocessing/compile_mppn.sh`

- Language: `script`
- Lines: `28`
- Relevance score: `20`
- Mentions: `compile, mpp`

### `postprocessing/mppnccombine_run.sh`

- Language: `script`
- Lines: `10`
- Relevance score: `20`
- Mentions: `run, mpp`

### `postprocessing/plevel_interpolation/compile_plev_interpolation.sh`

- Language: `script`
- Lines: `10`
- Relevance score: `20`
- Mentions: `compile, mpp`

### `postprocessing/plevel_interpolation/scripts/run_plevel.py`

- Language: `python`
- Lines: `109`
- Relevance score: `20`
- Mentions: `compile, run`

### `requirements/docker-entrypoint.sh`

- Language: `script`
- Lines: `20`
- Relevance score: `10`
- Mentions: `run`

### `src/atmos_param/edt/edt.F90`

- Language: `fortran`
- Lines: `4800`
- Relevance score: `10`
- Modules: `edt_mod`
- Uses: `constants_mod, diag_manager_mod, fms_io_mod, fms_mod, monin_obukhov_mod, mpp_mod, sat_vapor_pres_mod, time_manager_mod`
- Subroutines: `caleddy, edt, edt_end, edt_init, exacol, galperin, gaussian_cloud, sfdiag, trbintd, zisocl`
- Functions: `erfcc, lengthscale`
- Calls: `caleddy, Close_File, compute_qs, error_mesg, exacol, galperin, gaussian_cloud, get_date, mo_diff, restore_state, save_restart, sfdiag, trbintd, write_version_number, zisocl`

### `src/extra/python/setup.py`

- Language: `python`
- Lines: `28`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/isca/create_alert.py`

- Language: `python`
- Lines: `37`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/isca/diagtable.py`

- Language: `python`
- Lines: `122`
- Relevance score: `10`
- Mentions: `fms`

### `src/extra/python/isca/git_info.py`

- Language: `python`
- Lines: `41`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/isca/helpers.py`

- Language: `python`
- Lines: `84`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/scripts/cell_area.py`

- Language: `python`
- Lines: `86`
- Relevance score: `10`
- Mentions: `fms`

### `src/extra/python/scripts/change_horizontal_resolution_of_restart_file.py`

- Language: `python`
- Lines: `185`
- Relevance score: `10`
- Mentions: `fms`

### `src/extra/python/scripts/create_era5_topography.py`

- Language: `python`
- Lines: `189`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/scripts/create_timeseries.py`

- Language: `python`
- Lines: `253`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/scripts/find_namelists_to_check.py`

- Language: `python`
- Lines: `88`
- Relevance score: `10`
- Mentions: `namelist`

### `src/extra/python/scripts/general_spinup_fn.py`

- Language: `python`
- Lines: `157`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/scripts/modified_time_script.py`

- Language: `python`
- Lines: `86`
- Relevance score: `10`
- Mentions: `run`

### `src/extra/python/scripts/resolutions.py`

- Language: `python`
- Lines: `188`
- Relevance score: `10`
- Mentions: `run`

## Local dependency graph for relevant Fortran files

### `model/dyn_core.F90`
- uses `UNRESOLVED_OR_EXTERNAL::fv_ada_nudge_mod`
- uses `model/a2b_edge.F90`
- uses `model/boundary.F90`
- uses `model/fv_update_phys.F90`
- uses `model/nh_core.F90`
- uses `model/sw_core.F90`
- uses `model/tp-core-driver/stubs/fv_arrays_stub.F90`
- uses `model/tp_core.F90`
- uses `postprocessing/plevel_interpolation/src/shared/constants/constants.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp_domains.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp_parameter.F90`
- uses `src/shared/diag_manager/diag_manager.F90`
- uses `tools/fv_diagnostics.F90`
- uses `tools/fv_mp_mod.F90`
- uses `tools/fv_nudge.F90`
- uses `tools/fv_timing.F90`
- uses `tools/test_cases.F90`

### `src/atmos_param/edt/edt.F90`
- uses `postprocessing/plevel_interpolation/src/shared/constants/constants.F90`
- uses `postprocessing/plevel_interpolation/src/shared/fms/fms.F90`
- uses `postprocessing/plevel_interpolation/src/shared/fms/fms_io.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp.F90`
- uses `postprocessing/plevel_interpolation/src/shared/sat_vapor_pres/sat_vapor_pres.F90`
- uses `src/atmos_param/monin_obukhov/monin_obukhov.F90`
- uses `src/shared/diag_manager/diag_manager.F90`
- uses `src/shared/time_manager/time_manager.F90`

### `src/atmos_param/hs_forcing/hs_forcing.F90`
- uses `postprocessing/plevel_interpolation/src/shared/constants/constants.F90`
- uses `postprocessing/plevel_interpolation/src/shared/fms/fms.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp.F90`
- uses `src/atmos_shared/interpolator/interpolator.F90`
- uses `src/atmos_spectral/tools/spec_mpp.F90`
- uses `src/atmos_spectral/tools/transforms.F90`
- uses `src/shared/astronomy/astronomy.f90`
- uses `src/shared/diag_manager/diag_manager.F90`
- uses `src/shared/field_manager/field_manager.F90`
- uses `src/shared/time_manager/time_manager.F90`
- uses `src/shared/tracer_manager/tracer_manager.F90`

### `src/atmos_spectral/driver/solo/atmosphere.F90`
- uses `postprocessing/plevel_interpolation/src/shared/constants/constants.F90`
- uses `postprocessing/plevel_interpolation/src/shared/fms/fms.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp.F90`
- uses `src/atmos_column/column.F90`
- uses `src/atmos_column/column_grid.F90`
- uses `src/atmos_param/hs_forcing/hs_forcing.F90`
- uses `src/atmos_spectral/driver/solo/idealized_moist_phys.F90`
- uses `src/atmos_spectral/model/press_and_geopot.F90`
- uses `src/atmos_spectral/model/spectral_dynamics.F90`
- uses `src/atmos_spectral/model/tracer_type.F90`
- uses `src/atmos_spectral/tools/spec_mpp.F90`
- uses `src/atmos_spectral/tools/transforms.F90`
- uses `src/shared/field_manager/field_manager.F90`
- uses `src/shared/time_manager/time_manager.F90`
- uses `src/shared/tracer_manager/tracer_manager.F90`

### `tools/test_cases.F90`
- uses `model/fv_sg.F90`
- uses `model/tp-core-driver/stubs/fv_arrays_stub.F90`
- uses `model/tp-core-driver/stubs/fv_grid_utils_stub.F90`
- uses `postprocessing/plevel_interpolation/src/shared/constants/constants.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp_domains.F90`
- uses `postprocessing/plevel_interpolation/src/shared/mpp/mpp_parameter.F90`
- uses `src/shared/field_manager/field_manager.F90`
- uses `src/shared/tracer_manager/tracer_manager.F90`
- uses `tools/fv_diagnostics.F90`
- uses `tools/fv_eta.F90`
- uses `tools/fv_grid_tools.F90`
- uses `tools/fv_mp_mod.F90`
- uses `tools/fv_surf_map.F90`
- uses `tools/init_hydro.F90`
