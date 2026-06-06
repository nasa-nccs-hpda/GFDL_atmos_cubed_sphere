# Makefile created by mkmf $Id: mkmf,v 16.1 2010/05/19 18:49:19 fms Exp $ 

SRCROOT = /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/

CPPDEFS = -Duse_libMPI -Duse_netCDF -Duse_LARGEFILE -DINTERNAL_FILE_NML -DOVERLOAD_C8 -DUSE_CPP_HS_FORCE


include /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/src/extra/python/isca/templates/mkmf.template.hybrid


.DEFAULT:
	-echo $@ does not exist.
all: held_suarez.x
MersenneTwister.o: $(SRCROOT)shared/random_numbers/MersenneTwister.F90
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/random_numbers/MersenneTwister.F90
affinity.o: $(SRCROOT)shared/mpp/affinity.c
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mpp/affinity.c
astronomy.o: $(SRCROOT)shared/astronomy/astronomy.f90 fms.o time_manager.o constants.o mpp.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/astronomy/astronomy.f90
atmos_model.o: $(SRCROOT)atmos_solo/atmos_model.F90 mpp.o fms.o atmosphere.o time_manager.o fms_io.o mpp_domains.o mpp_io.o diag_manager.o field_manager.o tracer_manager.o memutils.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_solo/atmos_model.F90
atmosphere.o: $(SRCROOT)atmos_spectral/driver/solo/atmosphere.F90 mpp.o fms.o constants.o time_manager.o press_and_geopot.o spec_mpp.o spectral_dynamics.o transforms.o tracer_type.o hs_forcing.o field_manager.o tracer_manager.o idealized_moist_phys.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/driver/solo/atmosphere.F90
axis_utils.o: $(SRCROOT)shared/axis_utils/axis_utils.F90 mpp_io.o mpp.o fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/axis_utils/axis_utils.F90
betts_miller.o: $(SRCROOT)atmos_param/betts_miller/betts_miller.f90 fms.o sat_vapor_pres.o constants.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/betts_miller/betts_miller.f90
cg_drag.o: $(SRCROOT)atmos_param/cg_drag/cg_drag.f90 fms.o time_manager.o diag_manager.o constants.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cg_drag/cg_drag.f90
cloud_cover_diags.o: $(SRCROOT)atmos_param/cloud_simple/cloud_cover_diags.F90 mpp.o fms.o time_manager.o diag_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cloud_simple/cloud_cover_diags.F90
cloud_simple.o: $(SRCROOT)atmos_param/cloud_simple/cloud_simple.F90 mpp.o fms.o time_manager.o sat_vapor_pres.o diag_manager.o constants.o lcl.o large_scale_cloud.o marine_strat_cloud.o cloud_cover_diags.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cloud_simple/cloud_simple.F90
cloud_spookie.o: $(SRCROOT)atmos_param/cloud_simple/cloud_spookie.F90 fms.o time_manager.o sat_vapor_pres.o constants.o diag_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cloud_simple/cloud_spookie.F90
constants.o: $(SRCROOT)shared/constants/constants.F90 fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/constants/constants.F90
create_xgrid.o: $(SRCROOT)shared/mosaic/create_xgrid.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/create_xgrid.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic	$(SRCROOT)shared/mosaic/create_xgrid.c
damping_driver.o: $(SRCROOT)atmos_param/damping_driver/damping_driver.f90 mg_drag.o cg_drag.o topo_drag.o fms.o diag_manager.o time_manager.o constants.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/damping_driver/damping_driver.f90
diag_axis.o: $(SRCROOT)shared/diag_manager/diag_axis.F90 mpp_domains.o fms.o diag_data.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/diag_manager/diag_axis.F90
diag_data.o: $(SRCROOT)shared/diag_manager/diag_data.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h time_manager.o mpp_domains.o mpp_io.o fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/diag_manager/diag_data.F90
diag_grid.o: $(SRCROOT)shared/diag_manager/diag_grid.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h constants.o fms.o mpp.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/diag_manager/diag_grid.F90
diag_manager.o: $(SRCROOT)shared/diag_manager/diag_manager.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h time_manager.o mpp_io.o mpp.o fms.o diag_axis.o diag_util.o diag_data.o diag_table.o diag_output.o diag_grid.o constants.o mpp_domains.o fms_io.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/diag_manager/diag_manager.F90
diag_output.o: $(SRCROOT)shared/diag_manager/diag_output.F90 mpp_io.o mpp_domains.o mpp.o diag_axis.o diag_data.o time_manager.o fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/diag_manager/diag_output.F90
diag_table.o: $(SRCROOT)shared/diag_manager/diag_table.F90 mpp_io.o mpp.o fms.o time_manager.o constants.o diag_data.o diag_util.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/diag_manager/diag_table.F90
diag_util.o: $(SRCROOT)shared/diag_manager/diag_util.F90 diag_data.o diag_axis.o diag_output.o diag_grid.o fms.o fms_io.o mpp_domains.o time_manager.o mpp_io.o mpp.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/diag_manager/diag_util.F90
diffusivity.o: $(SRCROOT)atmos_param/diffusivity/diffusivity.F90 constants.o mpp.o fms.o monin_obukhov.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/diffusivity/diffusivity.F90
dry_convection.o: $(SRCROOT)atmos_param/dry_convection/dry_convection.f90 fms.o constants.o time_manager.o diag_manager.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/dry_convection/dry_convection.f90
edt.o: $(SRCROOT)atmos_param/edt/edt.F90 constants.o mpp.o fms.o fms_io.o diag_manager.o time_manager.o monin_obukhov.o sat_vapor_pres.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/edt/edt.F90
entrain.o: $(SRCROOT)atmos_param/entrain/entrain.F90 constants.o mpp.o fms.o diag_manager.o time_manager.o sat_vapor_pres.o monin_obukhov.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/entrain/entrain.F90
every_step_diagnostics.o: $(SRCROOT)atmos_spectral/model/every_step_diagnostics.F90 fms.o time_manager.o field_manager.o tracer_manager.o diag_manager.o press_and_geopot.o transforms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/every_step_diagnostics.F90
fft.o: $(SRCROOT)shared/fft/fft.F90 platform.o fms.o fft99.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/fft/fft.F90
fft99.o: $(SRCROOT)shared/fft/fft99.F90 constants.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/fft/fft99.F90
field_manager.o: $(SRCROOT)shared/field_manager/field_manager.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/field_manager/parse.inc mpp.o mpp_io.o fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/field_manager	$(SRCROOT)shared/field_manager/field_manager.F90
fm_util.o: $(SRCROOT)shared/field_manager/fm_util.F90 field_manager.o fms.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/field_manager/fm_util.F90
fms.o: $(SRCROOT)shared/fms/fms.F90 mpp.o mpp_domains.o mpp_io.o fms_io.o memutils.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/fms/fms.F90
fms_io.o: $(SRCROOT)shared/fms/fms_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_2d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_3d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_4d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/write_data.inc mpp_io.o mpp_domains.o mpp.o platform.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms	$(SRCROOT)shared/fms/fms_io.F90
fv_advection.o: $(SRCROOT)atmos_spectral/model/fv_advection.F90 fms.o constants.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/fv_advection.F90
gauss_and_legendre.o: $(SRCROOT)atmos_spectral/tools/gauss_and_legendre.F90 fms.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/tools/gauss_and_legendre.F90
gaussian_topog.o: $(SRCROOT)shared/topography/gaussian_topog.F90 fms.o constants.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/topography/gaussian_topog.F90
get_cal_time.o: $(SRCROOT)shared/time_manager/get_cal_time.F90 fms.o time_manager.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/time_manager/get_cal_time.F90
global_integral.o: $(SRCROOT)atmos_spectral/model/global_integral.F90 fms.o press_and_geopot.o transforms.o constants.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/global_integral.F90
gradient.o: $(SRCROOT)shared/mosaic/gradient.F90 mpp.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mosaic/gradient.F90
gradient_c2l.o: $(SRCROOT)shared/mosaic/gradient_c2l.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/gradient_c2l.h
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic	$(SRCROOT)shared/mosaic/gradient_c2l.c
grid.o: $(SRCROOT)shared/mosaic/grid.F90 mpp.o constants.o fms.o mosaic.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mosaic/grid.F90
grid_fourier.o: $(SRCROOT)atmos_spectral/tools/grid_fourier.F90 fms.o constants.o fft.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/tools/grid_fourier.F90
horiz_interp.o: $(SRCROOT)shared/horiz_interp/horiz_interp.F90 fms.o mpp.o constants.o horiz_interp_type.o horiz_interp_conserve.o horiz_interp_bilinear.o horiz_interp_bicubic.o horiz_interp_spherical.o mpp_io.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/horiz_interp/horiz_interp.F90
horiz_interp_bicubic.o: $(SRCROOT)shared/horiz_interp/horiz_interp_bicubic.F90 mpp.o fms.o horiz_interp_type.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/horiz_interp/horiz_interp_bicubic.F90
horiz_interp_bilinear.o: $(SRCROOT)shared/horiz_interp/horiz_interp_bilinear.F90 mpp.o fms.o constants.o horiz_interp_type.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/horiz_interp/horiz_interp_bilinear.F90
horiz_interp_conserve.o: $(SRCROOT)shared/horiz_interp/horiz_interp_conserve.F90 mpp.o fms.o constants.o horiz_interp_type.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/horiz_interp/horiz_interp_conserve.F90
horiz_interp_spherical.o: $(SRCROOT)shared/horiz_interp/horiz_interp_spherical.F90 mpp.o fms.o constants.o horiz_interp_type.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/horiz_interp/horiz_interp_spherical.F90
horiz_interp_type.o: $(SRCROOT)shared/horiz_interp/horiz_interp_type.F90 mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/horiz_interp/horiz_interp_type.F90
hs_forcing.o: $(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc mpp.o fms.o constants.o time_manager.o diag_manager.o field_manager.o tracer_manager.o interpolator.o astronomy.o spec_mpp.o transforms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/extra/local_overrides/hs_forcing	$(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90
ic_from_external_file.o: $(SRCROOT)atmos_spectral/init/ic_from_external_file.F90 mpp.o fms.o transforms.o tracer_type.o field_manager.o tracer_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/ic_from_external_file.F90
idealized_moist_phys.o: $(SRCROOT)atmos_spectral/driver/solo/idealized_moist_phys.F90 mpp.o fms.o constants.o time_manager.o vert_turb_driver.o vert_diff.o two_stream_gray_rad.o cloud_simple.o cloud_spookie.o mixed_layer.o lscale_cond.o qe_moist_convection.o ras.o betts_miller.o dry_convection.o diag_manager.o spec_mpp.o transforms.o spectral_dynamics.o surface_flux.o sat_vapor_pres.o damping_driver.o press_and_geopot.o mpp_domains.o tracer_manager.o field_manager.o rayleigh_bottom_drag.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/driver/solo/idealized_moist_phys.F90
implicit.o: $(SRCROOT)atmos_spectral/model/implicit.F90 fms.o constants.o press_and_geopot.o matrix_invert.o transforms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/implicit.F90
interp.o: $(SRCROOT)shared/mosaic/interp.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/interp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/create_xgrid.h
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic	$(SRCROOT)shared/mosaic/interp.c
interpolator.o: $(SRCROOT)atmos_shared/interpolator/interpolator.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o mpp_io.o mpp_domains.o diag_manager.o fms.o horiz_interp.o time_manager.o time_interp.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)atmos_shared/interpolator/interpolator.F90
jablonowski_2006.o: $(SRCROOT)atmos_spectral/init/jablonowski_2006.F90 mpp.o fms.o constants.o vert_coordinate.o transforms.o press_and_geopot.o diag_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/jablonowski_2006.F90
large_scale_cloud.o: $(SRCROOT)atmos_param/cloud_simple/large_scale_cloud.F90 mpp.o fms.o time_manager.o sat_vapor_pres.o diag_manager.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cloud_simple/large_scale_cloud.F90
lcl.o: $(SRCROOT)atmos_param/cloud_simple/lcl.F90
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cloud_simple/lcl.F90
leapfrog.o: $(SRCROOT)atmos_spectral/model/leapfrog.F90 fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/leapfrog.F90
lscale_cond.o: $(SRCROOT)atmos_param/lscale_cond/lscale_cond.F90 mpp.o fms.o sat_vapor_pres.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/lscale_cond/lscale_cond.F90
marine_strat_cloud.o: $(SRCROOT)atmos_param/cloud_simple/marine_strat_cloud.F90 mpp.o fms.o time_manager.o sat_vapor_pres.o diag_manager.o constants.o lcl.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/cloud_simple/marine_strat_cloud.F90
matrix_invert.o: $(SRCROOT)atmos_spectral/model/matrix_invert.F90 fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/matrix_invert.F90
memuse.o: $(SRCROOT)shared/memutils/memuse.c
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/memutils/memuse.c
memutils.o: $(SRCROOT)shared/memutils/memutils.F90 mpp.o mpp_io.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/memutils/memutils.F90
mg_drag.o: $(SRCROOT)atmos_param/mg_drag/mg_drag.f90 topography.o fms.o fms_io.o constants.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/mg_drag/mg_drag.f90
mixed_layer.o: $(SRCROOT)atmos_spectral/driver/solo/mixed_layer.F90 fms.o field_manager.o tracer_manager.o constants.o diag_manager.o time_manager.o spec_mpp.o transforms.o spectral_dynamics.o vert_diff.o mpp_domains.o interpolator.o qflux.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/driver/solo/mixed_layer.F90
monin_obukhov.o: $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov.F90 constants.o mpp.o fms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/monin_obukhov/monin_obukhov.F90
monin_obukhov_kernel.o: $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov_kernel.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/atmos_param/monin_obukhov/monin_obukhov_interfaces.h
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/atmos_param/monin_obukhov	$(SRCROOT)atmos_param/monin_obukhov/monin_obukhov_kernel.F90
mosaic.o: $(SRCROOT)shared/mosaic/mosaic.F90 mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mosaic/mosaic.F90
mosaic_util.o: $(SRCROOT)shared/mosaic/mosaic_util.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic	$(SRCROOT)shared/mosaic/mosaic_util.c
mpp.o: $(SRCROOT)shared/mpp/mpp.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/system_clock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_nocomm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_a.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_s.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_a.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_s.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_mpi.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_mpi.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_mpi.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_nocomm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_int.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_scalar.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_gather.h mpp_parameter.o mpp_data.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include	$(SRCROOT)shared/mpp/mpp.F90
mpp_data.o: $(SRCROOT)shared/mpp/mpp_data.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_nocomm.inc mpp_parameter.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include	$(SRCROOT)shared/mpp/mpp_data.F90
mpp_domains.o: $(SRCROOT)shared/mpp/mpp_domains.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_define_nest_domains.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_comm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_define.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_misc.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D_nonblock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nonblock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV_nonblock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_check.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_checkV.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_nest_domains.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nest.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_redistribute.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_get_boundary.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_get_boundary.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_reduce.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_reduce.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum_tl.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_field.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_global_field.h mpp_parameter.o mpp_data.o mpp.o mpp_memutils.o mpp_pset.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include	$(SRCROOT)shared/mpp/mpp_domains.F90
mpp_io.o: $(SRCROOT)shared/mpp/mpp_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_misc.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_connect.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_read.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_read_2Ddecomp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_write.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write_2Ddecomp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write.h mpp_parameter.o mpp.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include	$(SRCROOT)shared/mpp/mpp_io.F90
mpp_memutils.o: $(SRCROOT)shared/mpp/mpp_memutils.F90 mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mpp/mpp_memutils.F90
mpp_parameter.o: $(SRCROOT)shared/mpp/mpp_parameter.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/mpp/mpp_parameter.F90
mpp_pset.o: $(SRCROOT)shared/mpp/mpp_pset.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/mpp/mpp_pset.F90
mpp_utilities.o: $(SRCROOT)shared/mpp/mpp_utilities.F90 mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mpp/mpp_utilities.F90
my25_turb.o: $(SRCROOT)atmos_param/my25_turb/my25_turb.F90 mpp.o fms.o fms_io.o tridiagonal.o constants.o monin_obukhov.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/my25_turb/my25_turb.F90
nsclock.o: $(SRCROOT)shared/mpp/nsclock.c
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mpp/nsclock.c
platform.o: $(SRCROOT)shared/platform/platform.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/platform/platform.F90
polvani_2004.o: $(SRCROOT)atmos_spectral/init/polvani_2004.F90 mpp.o fms.o constants.o vert_coordinate.o transforms.o press_and_geopot.o diag_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/polvani_2004.F90
polvani_2007.o: $(SRCROOT)atmos_spectral/init/polvani_2007.F90 mpp.o fms.o constants.o vert_coordinate.o transforms.o press_and_geopot.o diag_manager.o tracer_type.o field_manager.o tracer_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/polvani_2007.F90
press_and_geopot.o: $(SRCROOT)atmos_spectral/model/press_and_geopot.F90 fms.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/press_and_geopot.F90
qe_moist_convection.o: $(SRCROOT)atmos_param/qe_moist_convection/qe_moist_convection.F90 fms.o sat_vapor_pres.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/qe_moist_convection/qe_moist_convection.F90
qflux.o: $(SRCROOT)atmos_param/qflux/qflux.f90 constants.o fms.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/qflux/qflux.f90
rad_utilities.o: $(SRCROOT)atmos_param/sea_esf_rad/null/rad_utilities.F90 fms.o time_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/sea_esf_rad/null/rad_utilities.F90
random_numbers.o: $(SRCROOT)shared/random_numbers/random_numbers.F90 MersenneTwister.o time_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/random_numbers/random_numbers.F90
ras.o: $(SRCROOT)atmos_param/ras/ras.f90 mpp.o sat_vapor_pres.o constants.o diag_manager.o time_manager.o fms.o field_manager.o tracer_manager.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/ras/ras.f90
rayleigh_bottom_drag.o: $(SRCROOT)atmos_param/rayleigh_bottom_drag/rayleigh_bottom_drag.F90 constants.o fms.o time_manager.o diag_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/rayleigh_bottom_drag/rayleigh_bottom_drag.F90
read_mosaic.o: $(SRCROOT)shared/mosaic/read_mosaic.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/read_mosaic.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic	$(SRCROOT)shared/mosaic/read_mosaic.c
sat_vapor_pres.o: $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres.F90 constants.o fms.o mpp_io.o mpp.o sat_vapor_pres_k.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres.F90
sat_vapor_pres_k.o: $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres_k.F90
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres_k.F90
shallow_conv.o: $(SRCROOT)atmos_param/shallow_conv/shallow_conv.F90 sat_vapor_pres.o mpp.o fms.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/shallow_conv/shallow_conv.F90
spec_mpp.o: $(SRCROOT)atmos_spectral/tools/spec_mpp.F90 fms.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/tools/spec_mpp.F90
spectral_damping.o: $(SRCROOT)atmos_spectral/model/spectral_damping.F90 fms.o transforms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/spectral_damping.F90
spectral_dynamics.o: $(SRCROOT)atmos_spectral/model/spectral_dynamics.F90 mpp.o fms.o constants.o time_manager.o field_manager.o tracer_manager.o diag_manager.o transforms.o vert_advection.o implicit.o press_and_geopot.o spectral_damping.o leapfrog.o fv_advection.o water_borrowing.o global_integral.o spectral_init_cond.o tracer_type.o every_step_diagnostics.o mpp_domains.o polvani_2004.o polvani_2007.o jablonowski_2006.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/spectral_dynamics.F90
spectral_init_cond.o: $(SRCROOT)atmos_spectral/init/spectral_init_cond.F90 mpp.o fms.o mpp_domains.o constants.o vert_coordinate.o transforms.o press_and_geopot.o spectral_initialize_fields.o ic_from_external_file.o topog_regularization.o topography.o tracer_type.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/spectral_init_cond.F90
spectral_initialize_fields.o: $(SRCROOT)atmos_spectral/init/spectral_initialize_fields.F90 fms.o constants.o transforms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/spectral_initialize_fields.F90
spherical.o: $(SRCROOT)atmos_spectral/tools/spherical.F90 fms.o spec_mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/tools/spherical.F90
spherical_fourier.o: $(SRCROOT)atmos_spectral/tools/spherical_fourier.F90 fms.o mpp.o mpp_domains.o constants.o spec_mpp.o spherical.o gauss_and_legendre.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/tools/spherical_fourier.F90
stable_bl_turb.o: $(SRCROOT)atmos_param/stable_bl_turb/stable_bl_turb.F90 mpp.o fms.o diag_manager.o time_manager.o constants.o monin_obukhov.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/stable_bl_turb/stable_bl_turb.F90
strat_cloud.o: $(SRCROOT)atmos_param/strat_cloud/null/strat_cloud.F90 time_manager.o rad_utilities.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/strat_cloud/null/strat_cloud.F90
surface_flux.o: $(SRCROOT)coupler/surface_flux.F90 fms.o monin_obukhov.o sat_vapor_pres.o constants.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)coupler/surface_flux.F90
test_fms_io.o: $(SRCROOT)shared/fms/test_fms_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o mpp_domains.o mpp_io.o fms_io.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/fms/test_fms_io.F90
test_mpp.o: $(SRCROOT)shared/mpp/test_mpp.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/mpp/test_mpp.F90
test_mpp_domains.o: $(SRCROOT)shared/mpp/test_mpp_domains.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o mpp_domains.o mpp_memutils.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/mpp/test_mpp_domains.F90
test_mpp_io.o: $(SRCROOT)shared/mpp/test_mpp_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o mpp_domains.o mpp_io.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/mpp/test_mpp_io.F90
test_mpp_pset.o: $(SRCROOT)shared/mpp/test_mpp_pset.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o mpp_pset.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/mpp/test_mpp_pset.F90
threadloc.o: $(SRCROOT)shared/mpp/threadloc.c
	$(CC) $(CPPDEFS) $(CPPFLAGS) $(CFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/mpp/threadloc.c
time_interp.o: $(SRCROOT)shared/time_interp/time_interp.F90 time_manager.o fms.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/time_interp/time_interp.F90
time_interp_external.o: $(SRCROOT)shared/time_interp/time_interp_external.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h mpp.o mpp_io.o time_manager.o get_cal_time.o mpp_domains.o time_interp.o axis_utils.o fms.o platform.o horiz_interp.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c -I/panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include	$(SRCROOT)shared/time_interp/time_interp_external.F90
time_manager.o: $(SRCROOT)shared/time_manager/time_manager.F90 constants.o fms.o mpp.o fms_io.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/time_manager/time_manager.F90
topo_drag.o: $(SRCROOT)atmos_param/topo_drag/topo_drag.f90 fms.o constants.o
	$(FC) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/topo_drag/topo_drag.f90
topog_regularization.o: $(SRCROOT)atmos_spectral/init/topog_regularization.F90 fms.o mpp.o constants.o transforms.o mpp_domains.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/topog_regularization.F90
topography.o: $(SRCROOT)shared/topography/topography.F90 gaussian_topog.o horiz_interp.o fms.o fms_io.o constants.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/topography/topography.F90
tracer_manager.o: $(SRCROOT)shared/tracer_manager/tracer_manager.F90 mpp.o mpp_io.o fms.o field_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/tracer_manager/tracer_manager.F90
tracer_type.o: $(SRCROOT)atmos_spectral/model/tracer_type.F90
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/tracer_type.F90
transforms.o: $(SRCROOT)atmos_spectral/tools/transforms.F90 mpp.o fms.o mpp_domains.o spec_mpp.o constants.o spherical_fourier.o grid_fourier.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/tools/transforms.F90
tridiagonal.o: $(SRCROOT)shared/tridiagonal/tridiagonal.F90
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)shared/tridiagonal/tridiagonal.F90
two_stream_gray_rad.o: $(SRCROOT)atmos_param/two_stream_gray_rad/two_stream_gray_rad.F90 fms.o constants.o diag_manager.o time_manager.o astronomy.o interpolator.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/two_stream_gray_rad/two_stream_gray_rad.F90
vert_advection.o: $(SRCROOT)atmos_shared/vert_advection/vert_advection.F90 fms.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_shared/vert_advection/vert_advection.F90
vert_coordinate.o: $(SRCROOT)atmos_spectral/init/vert_coordinate.F90 mpp.o fms.o constants.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/init/vert_coordinate.F90
vert_diff.o: $(SRCROOT)atmos_param/vert_diff/vert_diff.F90 constants.o fms.o field_manager.o tracer_manager.o mpp.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/vert_diff/vert_diff.F90
vert_turb_driver.o: $(SRCROOT)atmos_param/vert_turb_driver/vert_turb_driver.F90 my25_turb.o diffusivity.o edt.o strat_cloud.o shallow_conv.o stable_bl_turb.o entrain.o diag_manager.o time_manager.o constants.o mpp.o fms.o field_manager.o tracer_manager.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_param/vert_turb_driver/vert_turb_driver.F90
water_borrowing.o: $(SRCROOT)atmos_spectral/model/water_borrowing.F90 fms.o transforms.o
	$(FC) $(CPPDEFS) $(CPPFLAGS) $(FPPFLAGS) $(FFLAGS) $(OTHERFLAGS) -c	$(SRCROOT)atmos_spectral/model/water_borrowing.F90
./constants.F90: $(SRCROOT)shared/constants/constants.F90
	cp $(SRCROOT)shared/constants/constants.F90 .
./mpp_io_misc.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_misc.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_misc.inc .
./mpp_comm_mpi.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_mpi.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_mpi.inc .
./shallow_conv.F90: $(SRCROOT)atmos_param/shallow_conv/shallow_conv.F90
	cp $(SRCROOT)atmos_param/shallow_conv/shallow_conv.F90 .
./mpp_do_update_nonblock.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nonblock.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nonblock.h .
./interpolator.F90: $(SRCROOT)atmos_shared/interpolator/interpolator.F90
	cp $(SRCROOT)atmos_shared/interpolator/interpolator.F90 .
./mpp_define_nest_domains.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_define_nest_domains.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_define_nest_domains.inc .
./mpp_domains_reduce.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_reduce.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_reduce.inc .
./mpp_io_util.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_util.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_util.inc .
./memuse.c: $(SRCROOT)shared/memutils/memuse.c
	cp $(SRCROOT)shared/memutils/memuse.c .
./affinity.c: $(SRCROOT)shared/mpp/affinity.c
	cp $(SRCROOT)shared/mpp/affinity.c .
./MersenneTwister.F90: $(SRCROOT)shared/random_numbers/MersenneTwister.F90
	cp $(SRCROOT)shared/random_numbers/MersenneTwister.F90 .
./entrain.F90: $(SRCROOT)atmos_param/entrain/entrain.F90
	cp $(SRCROOT)atmos_param/entrain/entrain.F90 .
./spec_mpp.F90: $(SRCROOT)atmos_spectral/tools/spec_mpp.F90
	cp $(SRCROOT)atmos_spectral/tools/spec_mpp.F90 .
./global_integral.F90: $(SRCROOT)atmos_spectral/model/global_integral.F90
	cp $(SRCROOT)atmos_spectral/model/global_integral.F90 .
./tracer_type.F90: $(SRCROOT)atmos_spectral/model/tracer_type.F90
	cp $(SRCROOT)atmos_spectral/model/tracer_type.F90 .
./diag_data.F90: $(SRCROOT)shared/diag_manager/diag_data.F90
	cp $(SRCROOT)shared/diag_manager/diag_data.F90 .
./diag_util.F90: $(SRCROOT)shared/diag_manager/diag_util.F90
	cp $(SRCROOT)shared/diag_manager/diag_util.F90 .
./mpp_do_update_nest.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nest.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nest.h .
./dry_convection.f90: $(SRCROOT)atmos_param/dry_convection/dry_convection.f90
	cp $(SRCROOT)atmos_param/dry_convection/dry_convection.f90 .
./mpp_global_sum.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum.h .
./constant.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h .
./every_step_diagnostics.F90: $(SRCROOT)atmos_spectral/model/every_step_diagnostics.F90
	cp $(SRCROOT)atmos_spectral/model/every_step_diagnostics.F90 .
./test_mpp.F90: $(SRCROOT)shared/mpp/test_mpp.F90
	cp $(SRCROOT)shared/mpp/test_mpp.F90 .
./spectral_dynamics.F90: $(SRCROOT)atmos_spectral/model/spectral_dynamics.F90
	cp $(SRCROOT)atmos_spectral/model/spectral_dynamics.F90 .
./jablonowski_2006.F90: $(SRCROOT)atmos_spectral/init/jablonowski_2006.F90
	cp $(SRCROOT)atmos_spectral/init/jablonowski_2006.F90 .
./vert_coordinate.F90: $(SRCROOT)atmos_spectral/init/vert_coordinate.F90
	cp $(SRCROOT)atmos_spectral/init/vert_coordinate.F90 .
./mpp_pset.F90: $(SRCROOT)shared/mpp/mpp_pset.F90
	cp $(SRCROOT)shared/mpp/mpp_pset.F90 .
./time_interp.F90: $(SRCROOT)shared/time_interp/time_interp.F90
	cp $(SRCROOT)shared/time_interp/time_interp.F90 .
./gauss_and_legendre.F90: $(SRCROOT)atmos_spectral/tools/gauss_and_legendre.F90
	cp $(SRCROOT)atmos_spectral/tools/gauss_and_legendre.F90 .
./atmosphere.F90: $(SRCROOT)atmos_spectral/driver/solo/atmosphere.F90
	cp $(SRCROOT)atmos_spectral/driver/solo/atmosphere.F90 .
./read_data_4d.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_4d.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_4d.inc .
./lscale_cond.F90: $(SRCROOT)atmos_param/lscale_cond/lscale_cond.F90
	cp $(SRCROOT)atmos_param/lscale_cond/lscale_cond.F90 .
./mixed_layer.F90: $(SRCROOT)atmos_spectral/driver/solo/mixed_layer.F90
	cp $(SRCROOT)atmos_spectral/driver/solo/mixed_layer.F90 .
./edt.F90: $(SRCROOT)atmos_param/edt/edt.F90
	cp $(SRCROOT)atmos_param/edt/edt.F90 .
./press_and_geopot.F90: $(SRCROOT)atmos_spectral/model/press_and_geopot.F90
	cp $(SRCROOT)atmos_spectral/model/press_and_geopot.F90 .
./ic_from_external_file.F90: $(SRCROOT)atmos_spectral/init/ic_from_external_file.F90
	cp $(SRCROOT)atmos_spectral/init/ic_from_external_file.F90 .
./mpp_error_s_s.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_s.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_s.h .
./strat_cloud.F90: $(SRCROOT)atmos_param/strat_cloud/null/strat_cloud.F90
	cp $(SRCROOT)atmos_param/strat_cloud/null/strat_cloud.F90 .
./create_xgrid.c: $(SRCROOT)shared/mosaic/create_xgrid.c
	cp $(SRCROOT)shared/mosaic/create_xgrid.c .
./mpp_error_a_s.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_s.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_s.h .
./test_fms_io.F90: $(SRCROOT)shared/fms/test_fms_io.F90
	cp $(SRCROOT)shared/fms/test_fms_io.F90 .
./qflux.f90: $(SRCROOT)atmos_param/qflux/qflux.f90
	cp $(SRCROOT)atmos_param/qflux/qflux.f90 .
./horiz_interp_bilinear.F90: $(SRCROOT)shared/horiz_interp/horiz_interp_bilinear.F90
	cp $(SRCROOT)shared/horiz_interp/horiz_interp_bilinear.F90 .
./mosaic.F90: $(SRCROOT)shared/mosaic/mosaic.F90
	cp $(SRCROOT)shared/mosaic/mosaic.F90 .
./diffusivity.F90: $(SRCROOT)atmos_param/diffusivity/diffusivity.F90
	cp $(SRCROOT)atmos_param/diffusivity/diffusivity.F90 .
./fms.F90: $(SRCROOT)shared/fms/fms.F90
	cp $(SRCROOT)shared/fms/fms.F90 .
./my25_turb.F90: $(SRCROOT)atmos_param/my25_turb/my25_turb.F90
	cp $(SRCROOT)atmos_param/my25_turb/my25_turb.F90 .
./mpp_util_nocomm.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_nocomm.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_nocomm.inc .
./cloud_simple.F90: $(SRCROOT)atmos_param/cloud_simple/cloud_simple.F90
	cp $(SRCROOT)atmos_param/cloud_simple/cloud_simple.F90 .
./mpp_util.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util.inc .
./mpp_do_check.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_check.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_check.h .
./fft99.F90: $(SRCROOT)shared/fft/fft99.F90
	cp $(SRCROOT)shared/fft/fft99.F90 .
./mpp_do_updateV_nonblock.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV_nonblock.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV_nonblock.h .
./spectral_damping.F90: $(SRCROOT)atmos_spectral/model/spectral_damping.F90
	cp $(SRCROOT)atmos_spectral/model/spectral_damping.F90 .
./lcl.F90: $(SRCROOT)atmos_param/cloud_simple/lcl.F90
	cp $(SRCROOT)atmos_param/cloud_simple/lcl.F90 .
./mpp_domains_define.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_define.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_define.inc .
./mpp_io.F90: $(SRCROOT)shared/mpp/mpp_io.F90
	cp $(SRCROOT)shared/mpp/mpp_io.F90 .
./system_clock.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/system_clock.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/system_clock.h .
./horiz_interp_conserve.F90: $(SRCROOT)shared/horiz_interp/horiz_interp_conserve.F90
	cp $(SRCROOT)shared/horiz_interp/horiz_interp_conserve.F90 .
./mpp_do_get_boundary.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_get_boundary.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_get_boundary.h .
./horiz_interp_spherical.F90: $(SRCROOT)shared/horiz_interp/horiz_interp_spherical.F90
	cp $(SRCROOT)shared/horiz_interp/horiz_interp_spherical.F90 .
./diag_axis.F90: $(SRCROOT)shared/diag_manager/diag_axis.F90
	cp $(SRCROOT)shared/diag_manager/diag_axis.F90 .
./stable_bl_turb.F90: $(SRCROOT)atmos_param/stable_bl_turb/stable_bl_turb.F90
	cp $(SRCROOT)atmos_param/stable_bl_turb/stable_bl_turb.F90 .
./mpp_domains.F90: $(SRCROOT)shared/mpp/mpp_domains.F90
	cp $(SRCROOT)shared/mpp/mpp_domains.F90 .
./hs_forcing_rest.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc .
./grid.F90: $(SRCROOT)shared/mosaic/grid.F90
	cp $(SRCROOT)shared/mosaic/grid.F90 .
./matrix_invert.F90: $(SRCROOT)atmos_spectral/model/matrix_invert.F90
	cp $(SRCROOT)atmos_spectral/model/matrix_invert.F90 .
./mpp_reduce_nocomm.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_nocomm.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_nocomm.h .
./vert_diff.F90: $(SRCROOT)atmos_param/vert_diff/vert_diff.F90
	cp $(SRCROOT)atmos_param/vert_diff/vert_diff.F90 .
./test_mpp_io.F90: $(SRCROOT)shared/mpp/test_mpp_io.F90
	cp $(SRCROOT)shared/mpp/test_mpp_io.F90 .
./mpp_do_update.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update.h .
./topography.F90: $(SRCROOT)shared/topography/topography.F90
	cp $(SRCROOT)shared/topography/topography.F90 .
./test_mpp_pset.F90: $(SRCROOT)shared/mpp/test_mpp_pset.F90
	cp $(SRCROOT)shared/mpp/test_mpp_pset.F90 .
./mpp_sum_sma.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_sma.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_sma.h .
./field_manager.F90: $(SRCROOT)shared/field_manager/field_manager.F90
	cp $(SRCROOT)shared/field_manager/field_manager.F90 .
./rad_utilities.F90: $(SRCROOT)atmos_param/sea_esf_rad/null/rad_utilities.F90
	cp $(SRCROOT)atmos_param/sea_esf_rad/null/rad_utilities.F90 .
./fv_advection.F90: $(SRCROOT)atmos_spectral/model/fv_advection.F90
	cp $(SRCROOT)atmos_spectral/model/fv_advection.F90 .
./test_mpp_domains.F90: $(SRCROOT)shared/mpp/test_mpp_domains.F90
	cp $(SRCROOT)shared/mpp/test_mpp_domains.F90 .
./threadloc.c: $(SRCROOT)shared/mpp/threadloc.c
	cp $(SRCROOT)shared/mpp/threadloc.c .
./spectral_init_cond.F90: $(SRCROOT)atmos_spectral/init/spectral_init_cond.F90
	cp $(SRCROOT)atmos_spectral/init/spectral_init_cond.F90 .
./mosaic_util.c: $(SRCROOT)shared/mosaic/mosaic_util.c
	cp $(SRCROOT)shared/mosaic/mosaic_util.c .
./mpp_reduce_mpi.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_mpi.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_mpi.h .
./nsclock.c: $(SRCROOT)shared/mpp/nsclock.c
	cp $(SRCROOT)shared/mpp/nsclock.c .
./spherical.F90: $(SRCROOT)atmos_spectral/tools/spherical.F90
	cp $(SRCROOT)atmos_spectral/tools/spherical.F90 .
./diag_manager.F90: $(SRCROOT)shared/diag_manager/diag_manager.F90
	cp $(SRCROOT)shared/diag_manager/diag_manager.F90 .
./parse.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/field_manager/parse.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/field_manager/parse.inc .
./atmos_model.F90: $(SRCROOT)atmos_solo/atmos_model.F90
	cp $(SRCROOT)atmos_solo/atmos_model.F90 .
./mpp_global_field.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_field.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_field.h .
./horiz_interp_bicubic.F90: $(SRCROOT)shared/horiz_interp/horiz_interp_bicubic.F90
	cp $(SRCROOT)shared/horiz_interp/horiz_interp_bicubic.F90 .
./mpp_util_mpi.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_mpi.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_mpi.inc .
./vert_turb_driver.F90: $(SRCROOT)atmos_param/vert_turb_driver/vert_turb_driver.F90
	cp $(SRCROOT)atmos_param/vert_turb_driver/vert_turb_driver.F90 .
./mpp_memutils.F90: $(SRCROOT)shared/mpp/mpp_memutils.F90
	cp $(SRCROOT)shared/mpp/mpp_memutils.F90 .
./gradient.F90: $(SRCROOT)shared/mosaic/gradient.F90
	cp $(SRCROOT)shared/mosaic/gradient.F90 .
./read_data_2d.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_2d.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_2d.inc .
./mpp_transmit.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit.inc .
./horiz_interp_type.F90: $(SRCROOT)shared/horiz_interp/horiz_interp_type.F90
	cp $(SRCROOT)shared/horiz_interp/horiz_interp_type.F90 .
./axis_utils.F90: $(SRCROOT)shared/axis_utils/axis_utils.F90
	cp $(SRCROOT)shared/axis_utils/axis_utils.F90 .
./two_stream_gray_rad.F90: $(SRCROOT)atmos_param/two_stream_gray_rad/two_stream_gray_rad.F90
	cp $(SRCROOT)atmos_param/two_stream_gray_rad/two_stream_gray_rad.F90 .
./monin_obukhov_interfaces.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/atmos_param/monin_obukhov/monin_obukhov_interfaces.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/atmos_param/monin_obukhov/monin_obukhov_interfaces.h .
./mpp_global_reduce.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_reduce.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_reduce.h .
./random_numbers.F90: $(SRCROOT)shared/random_numbers/random_numbers.F90
	cp $(SRCROOT)shared/random_numbers/random_numbers.F90 .
./mpp_read_2Ddecomp.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_read_2Ddecomp.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_read_2Ddecomp.h .
./diag_output.F90: $(SRCROOT)shared/diag_manager/diag_output.F90
	cp $(SRCROOT)shared/diag_manager/diag_output.F90 .
./qe_moist_convection.F90: $(SRCROOT)atmos_param/qe_moist_convection/qe_moist_convection.F90
	cp $(SRCROOT)atmos_param/qe_moist_convection/qe_moist_convection.F90 .
./mpp_comm_nocomm.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_nocomm.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_nocomm.inc .
./surface_flux.F90: $(SRCROOT)coupler/surface_flux.F90
	cp $(SRCROOT)coupler/surface_flux.F90 .
./mpp_transmit_nocomm.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_nocomm.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_nocomm.h .
./mpp_error_a_a.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_a.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_a.h .
./damping_driver.f90: $(SRCROOT)atmos_param/damping_driver/damping_driver.f90
	cp $(SRCROOT)atmos_param/damping_driver/damping_driver.f90 .
./hs_forcing.F90: $(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90
	cp $(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90 .
./mpp_domains_util.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_util.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_util.inc .
./mpp_utilities.F90: $(SRCROOT)shared/mpp/mpp_utilities.F90
	cp $(SRCROOT)shared/mpp/mpp_utilities.F90 .
./time_manager.F90: $(SRCROOT)shared/time_manager/time_manager.F90
	cp $(SRCROOT)shared/time_manager/time_manager.F90 .
./mpp_parameter.F90: $(SRCROOT)shared/mpp/mpp_parameter.F90
	cp $(SRCROOT)shared/mpp/mpp_parameter.F90 .
./spectral_initialize_fields.F90: $(SRCROOT)atmos_spectral/init/spectral_initialize_fields.F90
	cp $(SRCROOT)atmos_spectral/init/spectral_initialize_fields.F90 .
./ras.f90: $(SRCROOT)atmos_param/ras/ras.f90
	cp $(SRCROOT)atmos_param/ras/ras.f90 .
./gaussian_topog.F90: $(SRCROOT)shared/topography/gaussian_topog.F90
	cp $(SRCROOT)shared/topography/gaussian_topog.F90 .
./idealized_moist_phys.F90: $(SRCROOT)atmos_spectral/driver/solo/idealized_moist_phys.F90
	cp $(SRCROOT)atmos_spectral/driver/solo/idealized_moist_phys.F90 .
./interp.c: $(SRCROOT)shared/mosaic/interp.c
	cp $(SRCROOT)shared/mosaic/interp.c .
./rayleigh_bottom_drag.F90: $(SRCROOT)atmos_param/rayleigh_bottom_drag/rayleigh_bottom_drag.F90
	cp $(SRCROOT)atmos_param/rayleigh_bottom_drag/rayleigh_bottom_drag.F90 .
./platform.F90: $(SRCROOT)shared/platform/platform.F90
	cp $(SRCROOT)shared/platform/platform.F90 .
./cloud_spookie.F90: $(SRCROOT)atmos_param/cloud_simple/cloud_spookie.F90
	cp $(SRCROOT)atmos_param/cloud_simple/cloud_spookie.F90 .
./cloud_cover_diags.F90: $(SRCROOT)atmos_param/cloud_simple/cloud_cover_diags.F90
	cp $(SRCROOT)atmos_param/cloud_simple/cloud_cover_diags.F90 .
./mpp_io_connect.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_connect.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_connect.inc .
./interp.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/interp.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/interp.h .
./gradient_c2l.c: $(SRCROOT)shared/mosaic/gradient_c2l.c
	cp $(SRCROOT)shared/mosaic/gradient_c2l.c .
./vert_advection.F90: $(SRCROOT)atmos_shared/vert_advection/vert_advection.F90
	cp $(SRCROOT)atmos_shared/vert_advection/vert_advection.F90 .
./mpp_update_nest_domains.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_nest_domains.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_nest_domains.h .
./read_data_3d.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_3d.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_3d.inc .
./memutils.F90: $(SRCROOT)shared/memutils/memutils.F90
	cp $(SRCROOT)shared/memutils/memutils.F90 .
./polvani_2007.F90: $(SRCROOT)atmos_spectral/init/polvani_2007.F90
	cp $(SRCROOT)atmos_spectral/init/polvani_2007.F90 .
./mpp_get_boundary.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_get_boundary.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_get_boundary.h .
./mpp_chksum.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum.h .
./horiz_interp.F90: $(SRCROOT)shared/horiz_interp/horiz_interp.F90
	cp $(SRCROOT)shared/horiz_interp/horiz_interp.F90 .
./monin_obukhov.F90: $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov.F90
	cp $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov.F90 .
./mpp_comm.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm.inc .
./marine_strat_cloud.F90: $(SRCROOT)atmos_param/cloud_simple/marine_strat_cloud.F90
	cp $(SRCROOT)atmos_param/cloud_simple/marine_strat_cloud.F90 .
./mpp_sum_mpi.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_mpi.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_mpi.h .
./polvani_2004.F90: $(SRCROOT)atmos_spectral/init/polvani_2004.F90
	cp $(SRCROOT)atmos_spectral/init/polvani_2004.F90 .
./mpp_domains_misc.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_misc.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_misc.inc .
./mpp_data.F90: $(SRCROOT)shared/mpp/mpp_data.F90
	cp $(SRCROOT)shared/mpp/mpp_data.F90 .
./topo_drag.f90: $(SRCROOT)atmos_param/topo_drag/topo_drag.f90
	cp $(SRCROOT)atmos_param/topo_drag/topo_drag.f90 .
./diag_grid.F90: $(SRCROOT)shared/diag_manager/diag_grid.F90
	cp $(SRCROOT)shared/diag_manager/diag_grid.F90 .
./mosaic_util.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h .
./mpp_update_domains2D_nonblock.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D_nonblock.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D_nonblock.h .
./betts_miller.f90: $(SRCROOT)atmos_param/betts_miller/betts_miller.f90
	cp $(SRCROOT)atmos_param/betts_miller/betts_miller.f90 .
./diag_table.F90: $(SRCROOT)shared/diag_manager/diag_table.F90
	cp $(SRCROOT)shared/diag_manager/diag_table.F90 .
./mpp_data_nocomm.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_nocomm.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_nocomm.inc .
./mpp_write_2Ddecomp.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write_2Ddecomp.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write_2Ddecomp.h .
./mpp_error_s_a.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_a.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_a.h .
./mpp_data_mpi.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_mpi.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_mpi.inc .
./gradient_c2l.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/gradient_c2l.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/gradient_c2l.h .
./topog_regularization.F90: $(SRCROOT)atmos_spectral/init/topog_regularization.F90
	cp $(SRCROOT)atmos_spectral/init/topog_regularization.F90 .
./leapfrog.F90: $(SRCROOT)atmos_spectral/model/leapfrog.F90
	cp $(SRCROOT)atmos_spectral/model/leapfrog.F90 .
./mpp_util_sma.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_sma.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_sma.inc .
./fft.F90: $(SRCROOT)shared/fft/fft.F90
	cp $(SRCROOT)shared/fft/fft.F90 .
./fm_util.F90: $(SRCROOT)shared/field_manager/fm_util.F90
	cp $(SRCROOT)shared/field_manager/fm_util.F90 .
./mpp_io_read.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_read.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_read.inc .
./large_scale_cloud.F90: $(SRCROOT)atmos_param/cloud_simple/large_scale_cloud.F90
	cp $(SRCROOT)atmos_param/cloud_simple/large_scale_cloud.F90 .
./mpp_chksum_scalar.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_scalar.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_scalar.h .
./grid_fourier.F90: $(SRCROOT)atmos_spectral/tools/grid_fourier.F90
	cp $(SRCROOT)atmos_spectral/tools/grid_fourier.F90 .
./mpp_reduce_sma.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_sma.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_sma.h .
./mpp_update_domains2D.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D.h .
./fms_io.F90: $(SRCROOT)shared/fms/fms_io.F90
	cp $(SRCROOT)shared/fms/fms_io.F90 .
./mpp_do_global_field.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_global_field.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_global_field.h .
./mg_drag.f90: $(SRCROOT)atmos_param/mg_drag/mg_drag.f90
	cp $(SRCROOT)atmos_param/mg_drag/mg_drag.f90 .
./mpp_io_write.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_write.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_write.inc .
./fms_platform.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h .
./create_xgrid.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/create_xgrid.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/create_xgrid.h .
./cg_drag.f90: $(SRCROOT)atmos_param/cg_drag/cg_drag.f90
	cp $(SRCROOT)atmos_param/cg_drag/cg_drag.f90 .
./tridiagonal.F90: $(SRCROOT)shared/tridiagonal/tridiagonal.F90
	cp $(SRCROOT)shared/tridiagonal/tridiagonal.F90 .
./mpp_sum_nocomm.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_nocomm.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_nocomm.h .
./mpp_gather.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_gather.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_gather.h .
./read_mosaic.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/read_mosaic.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/read_mosaic.h .
./spherical_fourier.F90: $(SRCROOT)atmos_spectral/tools/spherical_fourier.F90
	cp $(SRCROOT)atmos_spectral/tools/spherical_fourier.F90 .
./mpp_transmit_mpi.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_mpi.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_mpi.h .
./tracer_manager.F90: $(SRCROOT)shared/tracer_manager/tracer_manager.F90
	cp $(SRCROOT)shared/tracer_manager/tracer_manager.F90 .
./sat_vapor_pres.F90: $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres.F90
	cp $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres.F90 .
./mpp_comm_sma.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_sma.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_sma.inc .
./time_interp_external.F90: $(SRCROOT)shared/time_interp/time_interp_external.F90
	cp $(SRCROOT)shared/time_interp/time_interp_external.F90 .
./mpp_domains_comm.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_comm.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_comm.inc .
./sat_vapor_pres_k.F90: $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres_k.F90
	cp $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres_k.F90 .
./get_cal_time.F90: $(SRCROOT)shared/time_manager/get_cal_time.F90
	cp $(SRCROOT)shared/time_manager/get_cal_time.F90 .
./write_data.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/write_data.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/write_data.inc .
./astronomy.f90: $(SRCROOT)shared/astronomy/astronomy.f90
	cp $(SRCROOT)shared/astronomy/astronomy.f90 .
./mpp_global_sum_tl.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum_tl.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum_tl.h .
./transforms.F90: $(SRCROOT)atmos_spectral/tools/transforms.F90
	cp $(SRCROOT)atmos_spectral/tools/transforms.F90 .
./implicit.F90: $(SRCROOT)atmos_spectral/model/implicit.F90
	cp $(SRCROOT)atmos_spectral/model/implicit.F90 .
./mpp_transmit_sma.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_sma.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_sma.h .
./mpp.F90: $(SRCROOT)shared/mpp/mpp.F90
	cp $(SRCROOT)shared/mpp/mpp.F90 .
./read_mosaic.c: $(SRCROOT)shared/mosaic/read_mosaic.c
	cp $(SRCROOT)shared/mosaic/read_mosaic.c .
./mpp_data_sma.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_sma.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_sma.inc .
./mpp_do_updateV.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV.h .
./mpp_sum.inc: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum.inc
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum.inc .
./mpp_chksum_int.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_int.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_int.h .
./mpp_write.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write.h .
./monin_obukhov_kernel.F90: $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov_kernel.F90
	cp $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov_kernel.F90 .
./water_borrowing.F90: $(SRCROOT)atmos_spectral/model/water_borrowing.F90
	cp $(SRCROOT)atmos_spectral/model/water_borrowing.F90 .
./mpp_do_redistribute.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_redistribute.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_redistribute.h .
./mpp_do_checkV.h: /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_checkV.h
	cp /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_checkV.h .
SRC = $(SRCROOT)shared/memutils/memutils.F90 $(SRCROOT)shared/diag_manager/diag_axis.F90 $(SRCROOT)shared/mosaic/create_xgrid.c $(SRCROOT)shared/horiz_interp/horiz_interp_conserve.F90 $(SRCROOT)shared/mpp/mpp_io.F90 $(SRCROOT)shared/mosaic/mosaic.F90 $(SRCROOT)atmos_param/cloud_simple/marine_strat_cloud.F90 $(SRCROOT)shared/mpp/affinity.c $(SRCROOT)shared/mpp/mpp_domains.F90 $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov_kernel.F90 $(SRCROOT)shared/diag_manager/diag_util.F90 $(SRCROOT)atmos_param/cg_drag/cg_drag.f90 $(SRCROOT)shared/diag_manager/diag_manager.F90 $(SRCROOT)atmos_param/betts_miller/betts_miller.f90 $(SRCROOT)atmos_spectral/tools/grid_fourier.F90 $(SRCROOT)atmos_param/strat_cloud/null/strat_cloud.F90 $(SRCROOT)atmos_param/damping_driver/damping_driver.f90 $(SRCROOT)shared/horiz_interp/horiz_interp_bilinear.F90 $(SRCROOT)shared/random_numbers/MersenneTwister.F90 $(SRCROOT)atmos_param/stable_bl_turb/stable_bl_turb.F90 $(SRCROOT)shared/field_manager/fm_util.F90 $(SRCROOT)atmos_param/cloud_simple/cloud_simple.F90 $(SRCROOT)shared/mpp/threadloc.c $(SRCROOT)atmos_param/diffusivity/diffusivity.F90 $(SRCROOT)shared/diag_manager/diag_grid.F90 $(SRCROOT)atmos_param/cloud_simple/cloud_spookie.F90 $(SRCROOT)atmos_spectral/driver/solo/mixed_layer.F90 $(SRCROOT)atmos_spectral/driver/solo/atmosphere.F90 $(SRCROOT)atmos_spectral/model/spectral_dynamics.F90 $(SRCROOT)atmos_spectral/init/vert_coordinate.F90 $(SRCROOT)atmos_spectral/init/spectral_init_cond.F90 $(SRCROOT)atmos_param/cloud_simple/lcl.F90 $(SRCROOT)atmos_param/dry_convection/dry_convection.f90 $(SRCROOT)shared/random_numbers/random_numbers.F90 $(SRCROOT)shared/mosaic/read_mosaic.c $(SRCROOT)coupler/surface_flux.F90 $(SRCROOT)atmos_spectral/tools/spherical_fourier.F90 $(SRCROOT)shared/mosaic/gradient.F90 $(SRCROOT)atmos_param/shallow_conv/shallow_conv.F90 $(SRCROOT)shared/mpp/test_mpp_domains.F90 $(SRCROOT)shared/mosaic/mosaic_util.c $(SRCROOT)shared/mpp/mpp_memutils.F90 $(SRCROOT)shared/time_manager/get_cal_time.F90 $(SRCROOT)shared/mpp/test_mpp.F90 $(SRCROOT)shared/fft/fft.F90 $(SRCROOT)atmos_spectral/model/implicit.F90 $(SRCROOT)atmos_param/entrain/entrain.F90 $(SRCROOT)atmos_spectral/tools/spec_mpp.F90 $(SRCROOT)shared/mpp/mpp.F90 $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov.F90 $(SRCROOT)atmos_param/rayleigh_bottom_drag/rayleigh_bottom_drag.F90 $(SRCROOT)atmos_spectral/model/tracer_type.F90 $(SRCROOT)shared/tridiagonal/tridiagonal.F90 $(SRCROOT)atmos_param/topo_drag/topo_drag.f90 $(SRCROOT)atmos_param/my25_turb/my25_turb.F90 $(SRCROOT)shared/topography/topography.F90 $(SRCROOT)shared/horiz_interp/horiz_interp_bicubic.F90 $(SRCROOT)atmos_spectral/init/topog_regularization.F90 $(SRCROOT)shared/diag_manager/diag_data.F90 $(SRCROOT)atmos_spectral/model/spectral_damping.F90 $(SRCROOT)shared/time_interp/time_interp_external.F90 $(SRCROOT)atmos_param/mg_drag/mg_drag.f90 $(SRCROOT)atmos_spectral/driver/solo/idealized_moist_phys.F90 $(SRCROOT)shared/field_manager/field_manager.F90 $(SRCROOT)atmos_param/qe_moist_convection/qe_moist_convection.F90 $(SRCROOT)atmos_spectral/init/spectral_initialize_fields.F90 $(SRCROOT)atmos_spectral/init/polvani_2004.F90 $(SRCROOT)atmos_spectral/model/fv_advection.F90 $(SRCROOT)shared/tracer_manager/tracer_manager.F90 $(SRCROOT)shared/mpp/test_mpp_pset.F90 $(SRCROOT)shared/horiz_interp/horiz_interp_spherical.F90 $(SRCROOT)atmos_spectral/model/leapfrog.F90 $(SRCROOT)shared/fms/fms.F90 $(SRCROOT)atmos_param/ras/ras.f90 $(SRCROOT)atmos_shared/interpolator/interpolator.F90 $(SRCROOT)atmos_spectral/init/ic_from_external_file.F90 $(SRCROOT)shared/constants/constants.F90 $(SRCROOT)atmos_spectral/model/water_borrowing.F90 $(SRCROOT)shared/mpp/mpp_utilities.F90 $(SRCROOT)atmos_param/edt/edt.F90 $(SRCROOT)atmos_spectral/tools/spherical.F90 $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres_k.F90 $(SRCROOT)shared/fms/test_fms_io.F90 $(SRCROOT)atmos_param/vert_diff/vert_diff.F90 $(SRCROOT)shared/mpp/mpp_pset.F90 $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres.F90 $(SRCROOT)shared/mpp/test_mpp_io.F90 $(SRCROOT)shared/mpp/mpp_data.F90 $(SRCROOT)atmos_spectral/init/polvani_2007.F90 $(SRCROOT)atmos_spectral/model/matrix_invert.F90 $(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90 $(SRCROOT)atmos_param/vert_turb_driver/vert_turb_driver.F90 $(SRCROOT)shared/platform/platform.F90 $(SRCROOT)shared/memutils/memuse.c $(SRCROOT)shared/astronomy/astronomy.f90 $(SRCROOT)atmos_spectral/model/every_step_diagnostics.F90 $(SRCROOT)shared/time_interp/time_interp.F90 $(SRCROOT)shared/time_manager/time_manager.F90 $(SRCROOT)shared/axis_utils/axis_utils.F90 $(SRCROOT)atmos_param/lscale_cond/lscale_cond.F90 $(SRCROOT)atmos_solo/atmos_model.F90 $(SRCROOT)shared/horiz_interp/horiz_interp.F90 $(SRCROOT)shared/mpp/mpp_parameter.F90 $(SRCROOT)atmos_param/sea_esf_rad/null/rad_utilities.F90 $(SRCROOT)atmos_shared/vert_advection/vert_advection.F90 $(SRCROOT)shared/mosaic/interp.c $(SRCROOT)shared/topography/gaussian_topog.F90 $(SRCROOT)atmos_spectral/tools/gauss_and_legendre.F90 $(SRCROOT)shared/mosaic/gradient_c2l.c $(SRCROOT)atmos_param/qflux/qflux.f90 $(SRCROOT)atmos_spectral/init/jablonowski_2006.F90 $(SRCROOT)atmos_param/cloud_simple/large_scale_cloud.F90 $(SRCROOT)shared/mpp/nsclock.c $(SRCROOT)shared/fms/fms_io.F90 $(SRCROOT)shared/fft/fft99.F90 $(SRCROOT)atmos_param/cloud_simple/cloud_cover_diags.F90 $(SRCROOT)atmos_spectral/model/global_integral.F90 $(SRCROOT)shared/mosaic/grid.F90 $(SRCROOT)atmos_spectral/model/press_and_geopot.F90 $(SRCROOT)shared/diag_manager/diag_output.F90 $(SRCROOT)shared/horiz_interp/horiz_interp_type.F90 $(SRCROOT)shared/diag_manager/diag_table.F90 $(SRCROOT)atmos_param/two_stream_gray_rad/two_stream_gray_rad.F90 $(SRCROOT)atmos_spectral/tools/transforms.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_check.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D_nonblock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV_nonblock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_define.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_nocomm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write_2Ddecomp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_a.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_nocomm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_misc.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_mpi.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_get_boundary.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_s.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_s.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_4d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_nest_domains.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_3d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nest.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_connect.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/interp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_misc.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_nocomm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nonblock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_define_nest_domains.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_reduce.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_a.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/atmos_param/monin_obukhov/monin_obukhov_interfaces.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_redistribute.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_reduce.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_checkV.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_read_2Ddecomp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_2d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_int.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_field.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum_tl.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_comm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/write_data.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/field_manager/parse.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/create_xgrid.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/read_mosaic.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_gather.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_mpi.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_mpi.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_write.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_scalar.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_global_field.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/gradient_c2l.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/system_clock.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_get_boundary.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_read.inc
OBJ = memutils.o diag_axis.o create_xgrid.o horiz_interp_conserve.o mpp_io.o mosaic.o marine_strat_cloud.o affinity.o mpp_domains.o monin_obukhov_kernel.o diag_util.o cg_drag.o diag_manager.o betts_miller.o grid_fourier.o strat_cloud.o damping_driver.o horiz_interp_bilinear.o MersenneTwister.o stable_bl_turb.o fm_util.o cloud_simple.o threadloc.o diffusivity.o diag_grid.o cloud_spookie.o mixed_layer.o atmosphere.o spectral_dynamics.o vert_coordinate.o spectral_init_cond.o lcl.o dry_convection.o random_numbers.o read_mosaic.o surface_flux.o spherical_fourier.o gradient.o shallow_conv.o test_mpp_domains.o mosaic_util.o mpp_memutils.o get_cal_time.o test_mpp.o fft.o implicit.o entrain.o spec_mpp.o mpp.o monin_obukhov.o rayleigh_bottom_drag.o tracer_type.o tridiagonal.o topo_drag.o my25_turb.o topography.o horiz_interp_bicubic.o topog_regularization.o diag_data.o spectral_damping.o time_interp_external.o mg_drag.o idealized_moist_phys.o field_manager.o qe_moist_convection.o spectral_initialize_fields.o polvani_2004.o fv_advection.o tracer_manager.o test_mpp_pset.o horiz_interp_spherical.o leapfrog.o fms.o ras.o interpolator.o ic_from_external_file.o constants.o water_borrowing.o mpp_utilities.o edt.o spherical.o sat_vapor_pres_k.o test_fms_io.o vert_diff.o mpp_pset.o sat_vapor_pres.o test_mpp_io.o mpp_data.o polvani_2007.o matrix_invert.o hs_forcing.o vert_turb_driver.o platform.o memuse.o astronomy.o every_step_diagnostics.o time_interp.o time_manager.o axis_utils.o lscale_cond.o atmos_model.o horiz_interp.o mpp_parameter.o rad_utilities.o vert_advection.o interp.o gaussian_topog.o gauss_and_legendre.o gradient_c2l.o qflux.o jablonowski_2006.o large_scale_cloud.o nsclock.o fms_io.o fft99.o cloud_cover_diags.o global_integral.o grid.o press_and_geopot.o diag_output.o horiz_interp_type.o diag_table.o two_stream_gray_rad.o transforms.o
OFF = $(SRCROOT)shared/constants/constants.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_misc.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_mpi.inc $(SRCROOT)atmos_param/shallow_conv/shallow_conv.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nonblock.h $(SRCROOT)atmos_shared/interpolator/interpolator.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_define_nest_domains.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_reduce.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_util.inc $(SRCROOT)shared/memutils/memuse.c $(SRCROOT)shared/mpp/affinity.c $(SRCROOT)shared/random_numbers/MersenneTwister.F90 $(SRCROOT)atmos_param/entrain/entrain.F90 $(SRCROOT)atmos_spectral/tools/spec_mpp.F90 $(SRCROOT)atmos_spectral/model/global_integral.F90 $(SRCROOT)atmos_spectral/model/tracer_type.F90 $(SRCROOT)shared/diag_manager/diag_data.F90 $(SRCROOT)shared/diag_manager/diag_util.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update_nest.h $(SRCROOT)atmos_param/dry_convection/dry_convection.f90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/constant.h $(SRCROOT)atmos_spectral/model/every_step_diagnostics.F90 $(SRCROOT)shared/mpp/test_mpp.F90 $(SRCROOT)atmos_spectral/model/spectral_dynamics.F90 $(SRCROOT)atmos_spectral/init/jablonowski_2006.F90 $(SRCROOT)atmos_spectral/init/vert_coordinate.F90 $(SRCROOT)shared/mpp/mpp_pset.F90 $(SRCROOT)shared/time_interp/time_interp.F90 $(SRCROOT)atmos_spectral/tools/gauss_and_legendre.F90 $(SRCROOT)atmos_spectral/driver/solo/atmosphere.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_4d.inc $(SRCROOT)atmos_param/lscale_cond/lscale_cond.F90 $(SRCROOT)atmos_spectral/driver/solo/mixed_layer.F90 $(SRCROOT)atmos_param/edt/edt.F90 $(SRCROOT)atmos_spectral/model/press_and_geopot.F90 $(SRCROOT)atmos_spectral/init/ic_from_external_file.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_s.h $(SRCROOT)atmos_param/strat_cloud/null/strat_cloud.F90 $(SRCROOT)shared/mosaic/create_xgrid.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_s.h $(SRCROOT)shared/fms/test_fms_io.F90 $(SRCROOT)atmos_param/qflux/qflux.f90 $(SRCROOT)shared/horiz_interp/horiz_interp_bilinear.F90 $(SRCROOT)shared/mosaic/mosaic.F90 $(SRCROOT)atmos_param/diffusivity/diffusivity.F90 $(SRCROOT)shared/fms/fms.F90 $(SRCROOT)atmos_param/my25_turb/my25_turb.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_nocomm.inc $(SRCROOT)atmos_param/cloud_simple/cloud_simple.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_check.h $(SRCROOT)shared/fft/fft99.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV_nonblock.h $(SRCROOT)atmos_spectral/model/spectral_damping.F90 $(SRCROOT)atmos_param/cloud_simple/lcl.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_define.inc $(SRCROOT)shared/mpp/mpp_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/system_clock.h $(SRCROOT)shared/horiz_interp/horiz_interp_conserve.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_get_boundary.h $(SRCROOT)shared/horiz_interp/horiz_interp_spherical.F90 $(SRCROOT)shared/diag_manager/diag_axis.F90 $(SRCROOT)atmos_param/stable_bl_turb/stable_bl_turb.F90 $(SRCROOT)shared/mpp/mpp_domains.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/extra/local_overrides/hs_forcing/hs_forcing_rest.inc $(SRCROOT)shared/mosaic/grid.F90 $(SRCROOT)atmos_spectral/model/matrix_invert.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_nocomm.h $(SRCROOT)atmos_param/vert_diff/vert_diff.F90 $(SRCROOT)shared/mpp/test_mpp_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_update.h $(SRCROOT)shared/topography/topography.F90 $(SRCROOT)shared/mpp/test_mpp_pset.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_sma.h $(SRCROOT)shared/field_manager/field_manager.F90 $(SRCROOT)atmos_param/sea_esf_rad/null/rad_utilities.F90 $(SRCROOT)atmos_spectral/model/fv_advection.F90 $(SRCROOT)shared/mpp/test_mpp_domains.F90 $(SRCROOT)shared/mpp/threadloc.c $(SRCROOT)atmos_spectral/init/spectral_init_cond.F90 $(SRCROOT)shared/mosaic/mosaic_util.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_mpi.h $(SRCROOT)shared/mpp/nsclock.c $(SRCROOT)atmos_spectral/tools/spherical.F90 $(SRCROOT)shared/diag_manager/diag_manager.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/field_manager/parse.inc $(SRCROOT)atmos_solo/atmos_model.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_field.h $(SRCROOT)shared/horiz_interp/horiz_interp_bicubic.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_mpi.inc $(SRCROOT)atmos_param/vert_turb_driver/vert_turb_driver.F90 $(SRCROOT)shared/mpp/mpp_memutils.F90 $(SRCROOT)shared/mosaic/gradient.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_2d.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit.inc $(SRCROOT)shared/horiz_interp/horiz_interp_type.F90 $(SRCROOT)shared/axis_utils/axis_utils.F90 $(SRCROOT)atmos_param/two_stream_gray_rad/two_stream_gray_rad.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/atmos_param/monin_obukhov/monin_obukhov_interfaces.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_reduce.h $(SRCROOT)shared/random_numbers/random_numbers.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_read_2Ddecomp.h $(SRCROOT)shared/diag_manager/diag_output.F90 $(SRCROOT)atmos_param/qe_moist_convection/qe_moist_convection.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_nocomm.inc $(SRCROOT)coupler/surface_flux.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_a_a.h $(SRCROOT)atmos_param/damping_driver/damping_driver.f90 $(SRCROOT)extra/local_overrides/hs_forcing/hs_forcing.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_util.inc $(SRCROOT)shared/mpp/mpp_utilities.F90 $(SRCROOT)shared/time_manager/time_manager.F90 $(SRCROOT)shared/mpp/mpp_parameter.F90 $(SRCROOT)atmos_spectral/init/spectral_initialize_fields.F90 $(SRCROOT)atmos_param/ras/ras.f90 $(SRCROOT)shared/topography/gaussian_topog.F90 $(SRCROOT)atmos_spectral/driver/solo/idealized_moist_phys.F90 $(SRCROOT)shared/mosaic/interp.c $(SRCROOT)atmos_param/rayleigh_bottom_drag/rayleigh_bottom_drag.F90 $(SRCROOT)shared/platform/platform.F90 $(SRCROOT)atmos_param/cloud_simple/cloud_spookie.F90 $(SRCROOT)atmos_param/cloud_simple/cloud_cover_diags.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_connect.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/interp.h $(SRCROOT)shared/mosaic/gradient_c2l.c $(SRCROOT)atmos_shared/vert_advection/vert_advection.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_nest_domains.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/read_data_3d.inc $(SRCROOT)shared/memutils/memutils.F90 $(SRCROOT)atmos_spectral/init/polvani_2007.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_get_boundary.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum.h $(SRCROOT)shared/horiz_interp/horiz_interp.F90 $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm.inc $(SRCROOT)atmos_param/cloud_simple/marine_strat_cloud.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_mpi.h $(SRCROOT)atmos_spectral/init/polvani_2004.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_misc.inc $(SRCROOT)shared/mpp/mpp_data.F90 $(SRCROOT)atmos_param/topo_drag/topo_drag.f90 $(SRCROOT)shared/diag_manager/diag_grid.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/mosaic_util.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D_nonblock.h $(SRCROOT)atmos_param/betts_miller/betts_miller.f90 $(SRCROOT)shared/diag_manager/diag_table.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_nocomm.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write_2Ddecomp.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_error_s_a.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_mpi.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/gradient_c2l.h $(SRCROOT)atmos_spectral/init/topog_regularization.F90 $(SRCROOT)atmos_spectral/model/leapfrog.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_util_sma.inc $(SRCROOT)shared/fft/fft.F90 $(SRCROOT)shared/field_manager/fm_util.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_read.inc $(SRCROOT)atmos_param/cloud_simple/large_scale_cloud.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_scalar.h $(SRCROOT)atmos_spectral/tools/grid_fourier.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_reduce_sma.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_update_domains2D.h $(SRCROOT)shared/fms/fms_io.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_global_field.h $(SRCROOT)atmos_param/mg_drag/mg_drag.f90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_io_write.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/include/fms_platform.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/create_xgrid.h $(SRCROOT)atmos_param/cg_drag/cg_drag.f90 $(SRCROOT)shared/tridiagonal/tridiagonal.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum_nocomm.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_gather.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mosaic/read_mosaic.h $(SRCROOT)atmos_spectral/tools/spherical_fourier.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_mpi.h $(SRCROOT)shared/tracer_manager/tracer_manager.F90 $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_comm_sma.inc $(SRCROOT)shared/time_interp/time_interp_external.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_domains_comm.inc $(SRCROOT)shared/sat_vapor_pres/sat_vapor_pres_k.F90 $(SRCROOT)shared/time_manager/get_cal_time.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/fms/write_data.inc $(SRCROOT)shared/astronomy/astronomy.f90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_global_sum_tl.h $(SRCROOT)atmos_spectral/tools/transforms.F90 $(SRCROOT)atmos_spectral/model/implicit.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_transmit_sma.h $(SRCROOT)shared/mpp/mpp.F90 $(SRCROOT)shared/mosaic/read_mosaic.c /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_data_sma.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_updateV.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_sum.inc /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_chksum_int.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_write.h $(SRCROOT)atmos_param/monin_obukhov/monin_obukhov_kernel.F90 $(SRCROOT)atmos_spectral/model/water_borrowing.F90 /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_redistribute.h /panfs/ccds02/nobackup/people/jli30/workspace/GFDL_atmos_cubed_sphere/hybrid_experiments/held_suarez_cpp_force/builddir/code/src/shared/mpp/include/mpp_do_checkV.h
clean: neat
	-rm -f .held_suarez.x.cppdefs $(OBJ) held_suarez.x
neat:
	-rm -f $(TMPFILES)
localize: $(OFF)
	cp $(OFF) .
TAGS: $(SRC)
	etags $(SRC)
tags: $(SRC)
	ctags $(SRC)
held_suarez.x: $(OBJ) 
	$(LD) $(OBJ) -o held_suarez.x  $(LDFLAGS)
