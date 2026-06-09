! Remainder of original hs_forcing.F90: routines after hs_forcing_end
! This include contains the original implementation for the helper routines
! (newtonian_damping, rayleigh_damping, tracer_source_sink, local_heating, etc.)

subroutine newtonian_damping ( Time, lat, lon, ps, p_full, p_half, t, tdt, teq, mask )

type(time_type), intent(in)         :: Time
real, intent(in),  dimension(:,:)   :: lat, ps, lon
real, intent(in),  dimension(:,:,:) :: p_full, t, p_half
real, intent(out), dimension(:,:,:) :: tdt, teq
real, intent(in),  dimension(:,:,:), optional :: mask

!-----------------------------------------------------------------------

          real, dimension(size(t,1),size(t,2)) :: &
     sin_lat, cos_lat, sin_lat_2, cos_lat_2, t_star, cos_lat_4, &
     tstr, sigma, the, tfactr, rps, p_norm, sin_sublon_2, coszen, fracday

       real, dimension(size(t,1),size(t,2),size(t,3)) :: tdamp
       real, dimension(size(t,2),size(t,3)) :: tz
       real :: rrsun

       integer :: k, i, j
       real    :: tcoeff, pref

!-----------------------------------------------------------------------
!------------latitudinal constants--------------------------------------

      sin_lat  (:,:) = sin(lat(:,:))
      cos_lat (:,:) = cos(lat(:,:))
      sin_lat_2(:,:) = sin_lat(:,:)*sin_lat(:,:)
      cos_lat_2(:,:) = 1.0-sin_lat_2(:,:)
      cos_lat_4(:,:) = cos_lat_2(:,:)*cos_lat_2(:,:)

      t_star(:,:) = t_zero - delh*sin_lat_2(:,:) - eps*sin_lat(:,:)
      tstr  (:,:) = t_strat - eps*sin_lat(:,:)

!-----------------------------------------------------------------------
      if(trim(equilibrium_t_option) == 'from_file') then
         call get_zonal_mean_temp(Time, p_half, tz)
      endif
      tcoeff = (tks-tka)/(1.0-sigma_b)
      pref = P00
      rps  = 1./ps

      do k = 1, size(t,3)

!  ----- compute equilibrium temperature (teq) -----

      if(equilibrium_t_option == 'from_file') then
         do i=1, size(t,1)
         do j=1, size(t,2)
           teq(i,j,k)=tz(j,k)
         enddo
         enddo
      else if(trim(equilibrium_t_option) == 'Held_Suarez') then
         p_norm(:,:) = p_full(:,:,k)/pref
         the   (:,:) = t_star(:,:) - delv*cos_lat_2(:,:)*log(p_norm(:,:))
         teq(:,:,k) = the(:,:)*(p_norm(:,:))**KAPPA
         teq(:,:,k) = max( teq(:,:,k), tstr(:,:) )
      else if(uppercase(trim(equilibrium_t_option)) == 'EXOPLANET') then
         call diurnal_exoplanet(lat, lon, Time, coszen, fracday, rrsun)
         t_star(:,:) = t_zero - delh*(1 - coszen(:,:)) - eps*sin_lat(:,:)
         p_norm(:,:) = p_full(:,:,k)/pref
         the   (:,:) = t_star(:,:) - delv*coszen(:,:)*log(p_norm(:,:))
         teq(:,:,k) = the(:,:)*(p_norm(:,:))**KAPPA
         teq(:,:,k) = max( teq(:,:,k), tstr(:,:) )
      else if(uppercase(trim(equilibrium_t_option)) == 'EXOPLANET2') then
         call diurnal_exoplanet(lat, lon, Time, coszen, fracday, rrsun)
         t_star(:,:) = t_strat
         p_norm(:,:) = p_full(:,:,k)/p_trop
         teq(:,:,k) = t_star(:,:)*(p_norm(:,:))**alpha
         teq(:,:,k) = max( teq(:,:,k), t_strat )
      else
         call error_mesg ('hs_forcing_nml', &
         '"'//trim(equilibrium_t_option)//'"  is not a valid value for equilibrium_t_option',FATAL)
      endif

!  ----- compute damping -----
      sigma(:,:) = p_full(:,:,k)*rps(:,:)
      where (sigma(:,:) <= 1.0 .and. sigma(:,:) > sigma_b)
        tfactr(:,:) = tcoeff*(sigma(:,:)-sigma_b)
        tdamp(:,:,k) = tka + cos_lat_4(:,:)*tfactr(:,:)
      elsewhere
        tdamp(:,:,k) = tka
      endwhere

      enddo

      do k=1,size(t,3)
         tdt(:,:,k) = -tdamp(:,:,k)*(t(:,:,k)-teq(:,:,k))
      enddo

      if (present(mask)) then
         tdt = tdt * mask
         teq = teq * mask
      endif

!-----------------------------------------------------------------------

 end subroutine newtonian_damping

!#######################################################################

 subroutine rayleigh_damping ( Time, ps, p_full, p_half, u, v, udt, vdt, mask )

type(time_type), intent(in)         :: Time
real, intent(in),  dimension(:,:)   :: ps
real, intent(in),  dimension(:,:,:) :: p_full, p_half, u, v
real, intent(out), dimension(:,:,:) :: udt, vdt
real, intent(in),  dimension(:,:,:), optional :: mask

!-----------------------------------------------------------------------

real, dimension(size(u,1),size(u,2)) :: sigma, vfactr, rps

integer :: i,j,k
real    :: vcoeff
real, dimension(size(u,2),size(u,3)) :: uz, vz
real :: umean, vmean

!-----------------------------------------------------------------------
!----------------compute damping----------------------------------------

      if(relax_to_specified_wind) then
        call get_zonal_mean_flow(Time, p_half, uz, vz)
      endif

      vcoeff = -vkf/(1.0-sigma_b)
      rps = 1./ps

      do k = 1, size(u,3)
      if (relax_to_specified_wind) then
         do j=1, size(u,2)
            umean=sum(u(:,j,k))/size(u,1)
            vmean=sum(v(:,j,k))/size(v,1)
            udt(:,j,k) = (uz(j,k)-umean)*vkf
            vdt(:,j,k) = (vz(j,k)-vmean)*vkf
         enddo
      else

         sigma(:,:) = p_full(:,:,k)*rps(:,:)

         where (sigma(:,:) <= 1.0 .and. sigma(:,:) > sigma_b)
            vfactr(:,:) = vcoeff*(sigma(:,:)-sigma_b)
            udt(:,:,k)  = vfactr(:,:)*u(:,:,k)
            vdt(:,:,k)  = vfactr(:,:)*v(:,:,k)
         elsewhere
            udt(:,:,k) = 0.0
            vdt(:,:,k) = 0.0
         endwhere

      endif
      enddo

      if (present(mask)) then
          udt = udt * mask
          vdt = vdt * mask
      endif

!-----------------------------------------------------------------------

 end subroutine rayleigh_damping

!#######################################################################

 subroutine tracer_source_sink ( flux, damp, p_half, r, rdt, kbot )

!-----------------------------------------------------------------------
      real, intent(in)  :: flux, damp, p_half(:,:,:), r(:,:,:)
      real, intent(out) :: rdt(:,:,:)
   integer, intent(in), optional :: kbot(:,:)
!-----------------------------------------------------------------------
      real, dimension(size(r,1),size(r,2),size(r,3)) :: source, sink
      real, dimension(size(r,1),size(r,2))           :: pmass

      integer :: i, j, kb
      real    :: rdamp
!-----------------------------------------------------------------------

      rdamp = damp
      if (rdamp < 0.) rdamp = -86400.*rdamp   ! convert days to seconds
      if (rdamp > 0.) rdamp = 1./rdamp

!------------ simple surface source and global sink --------------------

      source(:,:,:)=0.0

   if (present(kbot)) then
      do j=1,size(r,2)
      do i=1,size(r,1)
         kb = kbot(i,j)
         pmass (i,j)    = p_half(i,j,kb+1) - p_half(i,j,kb)
         source(i,j,kb) = flux/pmass(i,j)
      enddo
      enddo
   else
         kb = size(r,3)
         pmass (:,:)    = p_half(:,:,kb+1) - p_half(:,:,kb)
         source(:,:,kb) = flux/pmass(:,:)
   endif

     sink(:,:,:) = rdamp*r(:,:,:)
     rdt(:,:,:) = source(:,:,:)-sink(:,:,:)

!-----------------------------------------------------------------------

 end subroutine tracer_source_sink

!#######################################################################

subroutine local_heating ( Time, is, js, lon, lat, ps, p_full, p_half, tdt )

type(time_type), intent(in)         :: Time
integer, intent(in)                 :: is,js
real, intent(in),  dimension(:,:)   :: lon, lat, ps
real, intent(in),  dimension(:,:,:) :: p_full
real, intent(in),  dimension(:,:,:) :: p_half
real, intent(out), dimension(:,:,:) :: tdt

integer :: i, j, k
real :: lon_temp, x_temp, p_factor
real, dimension(size(lon,1),size(lon,2)) :: lon_factor
real, dimension(size(lat,1),size(lat,2)) :: lat_factor
real, dimension(size(p_half,1),size(p_half,2),size(p_half,3)) :: p_half2
do i=1,size(p_half,3)
  p_half2(:,:,i)=p_half(:,:,size(p_half,3)-i+1)
enddo

tdt(:,:,:)=0.

if(trim(local_heating_option) == 'from_file') then
   call interpolator( heating_source_interp, p_half, tdt, trim(local_heating_file))
else if(trim(local_heating_option) == 'Isidoro') then
   do j=1,size(lon,2)
   do i=1,size(lon,1)
     lon_temp = lon(i,j)
     ! Make sure lon_temp falls in the range zero to 2*PI
     x_temp = floor(lon_temp/twopi)
     lon_temp = lon_temp - twopi*x_temp
     lon_factor(i,j) = exp(-.5*((lon_temp-xcenter)/xwidth)**2)
     lat_factor(i,j) = exp(-.5*((lat(i,j)-ycenter)/ywidth)**2)
     do k=1,size(p_full,3)
       p_factor = exp((p_full(i,j,k)-ps(i,j))/local_heating_vert_decay)
       tdt(i,j,k) = srfamp*lon_factor(i,j)*lat_factor(i,j)*p_factor
     enddo
   enddo
   enddo
else
  call error_mesg ('hs_forcing_nml','"'//trim(local_heating_option)//'"  is not a valid value for local_heating_option',FATAL)
endif

end subroutine local_heating

!#######################################################################

subroutine update_orbit(current_time, dec, orb_dist)

integer, intent(in)                 :: current_time
real, intent(out)                   :: dec, orb_dist

real :: theta, mean_anomaly, ecc_anomaly, true_anomaly

mean_anomaly = 2*pi/(orbital_period*86400)*(current_time-peri_time*orbital_period*86400)
call calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly)
true_anomaly = 2*atan(((1 + ecc)/(1 - ecc))**0.5 * tan(ecc_anomaly/2))
orb_dist = smaxis * (1 - ecc**2)/(1 + ecc*cos(true_anomaly))
theta = 2*pi*current_time/(orbital_period*86400)
dec = asin(sin(obliq*pi/180)*sin(theta))

end subroutine update_orbit

!#######################################################################

subroutine calc_hour_angle(lat, dec, hour_angle)

real, intent(in)                    :: dec
real, intent(in), dimension(:,:)    :: lat
real, intent(out), dimension(:,:)   :: hour_angle

real, dimension(size(lat,1), size(lat,2)) :: inv_hour_angle

inv_hour_angle = -tan(lat(:,:))*tan(dec)
where (inv_hour_angle > 1)
   inv_hour_angle = 1
endwhere
where (inv_hour_angle < -1)
   inv_hour_angle = -1
endwhere

hour_angle = acos(inv_hour_angle)

end subroutine calc_hour_angle

!#######################################################################

subroutine calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly)

real, intent(in) :: mean_anomaly, ecc
real, intent(out) :: ecc_anomaly
real :: dE, d
integer, parameter :: maxiter = 30
real, parameter :: tol = 1.d-10
integer :: k

ecc_anomaly = mean_anomaly
d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly
do k=1,maxiter
   dE = d/(1 - ecc*cos(ecc_anomaly))
   ecc_anomaly = ecc_anomaly - dE
   d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly
   if (abs(d) < tol) then
      exit
   endif
enddo

if (k > maxiter) then
   if (abs(d) > tol) then
      print *, '*** Warning: eccentric anomaly has not converged'
   endif
endif

end subroutine calc_ecc_anomaly

!#######################################################################
