!-----------------------BEGIN NOTICE -- DO NOT EDIT-----------------------
! NASA Goddard Space Flight Center
! Land Information System Framework (LISF)
! Version 7.4
!
! Copyright (c) 2022 United States Government as represented by the
! Administrator of the National Aeronautics and Space Administration.
! All Rights Reserved.
!-------------------------END NOTICE -- DO NOT EDIT-----------------------
#include "LIS_misc.h"
!BOP
! !ROUTINE: read_SMOPS_AMSR2sm
! \label{read_SMOPS_AMSR2sm}
!
! !REVISION HISTORY:
!  17 Jun 2010: Sujay Kumar; Updated for use with LPRM AMSRE Version 5. 
!  20 Sep 2012: Sujay Kumar; Updated to the NETCDF version of the data. 
!  28 Sep 2017: Mahdi Navari; Updated to read AMSR2 from SMOPS V3
!
! !INTERFACE: 
subroutine read_SMOPS_AMSR2sm(n, k, OBS_State, OBS_Pert_State)
! !USES: 
  use ESMF
  use LIS_mpiMod
  use LIS_coreMod
  use LIS_logMod
  use LIS_timeMgrMod
  use LIS_dataAssimMod
  use LIS_DAobservationsMod
  use map_utils
  use LIS_pluginIndices
  use LIS_constantsMod, only : LIS_CONST_PATH_LEN
  use SMOPS_AMSR2sm_Mod, only : SMOPS_AMSR2sm_struc

  implicit none
! !ARGUMENTS: 
  integer, intent(in) :: n 
  integer, intent(in) :: k
  type(ESMF_State)    :: OBS_State
  type(ESMF_State)    :: OBS_Pert_State
!
! !DESCRIPTION:
!  
!  reads the AMSRE soil moisture observations 
!  from NETCDF files and applies the spatial masking for dense
!  vegetation, rain and RFI. The data is then rescaled
!  to the land surface model's climatology using rescaling
!  algorithms. 
!  
!  The arguments are: 
!  \begin{description}
!  \item[n] index of the nest
!  \item[OBS\_State] observations state
!  \end{description}
!
!EOP
  real, parameter        ::  minssdev = 0.05
  real, parameter        ::  maxssdev = 0.11
  real,  parameter       :: MAX_SM_VALUE=0.45, MIN_SM_VALUE=0.0001
  integer                :: status
  integer                :: grid_index
  character(len=LIS_CONST_PATH_LEN) :: smobsdir
  character(len=LIS_CONST_PATH_LEN) :: fname
  logical                :: alarmCheck, file_exists
  integer                :: t,c,r,i,j,p,jj
  real,          pointer :: obsl(:)
  type(ESMF_Field)       :: smfield, pertField

  integer                :: gid(LIS_rc%obs_ngrid(k))
  integer                :: assimflag(LIS_rc%obs_ngrid(k))
  real                   :: obs_unsc(LIS_rc%obs_ngrid(k))
  logical                :: data_update
  logical                :: data_upd_flag(LIS_npes)
  logical                :: data_upd_flag_local
  logical                :: data_upd
  real                   :: smobs(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k))
  real                   :: smtime(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k))
  real                   :: sm_current(LIS_rc%obs_lnc(k),LIS_rc%obs_lnr(k))
  real                   :: dt
  integer                :: fnd
  real, allocatable      :: ssdev(:)
  integer                :: lis_julss
  real                   :: smvalue
  real                   :: model_delta(LIS_rc%obs_ngrid(k))
  real                   :: obs_delta(LIS_rc%obs_ngrid(k))
  
  call ESMF_AttributeGet(OBS_State,"Data Directory",&
       smobsdir, rc=status)
  call LIS_verify(status)
  call ESMF_AttributeGet(OBS_State,"Data Update Status",&
       data_update, rc=status)
  call LIS_verify(status)

  data_upd = .false. 
  obs_unsc = LIS_rc%udef
!-------------------------------------------------------------------------
!   Read both ascending and descending passes at 0Z and then store
!   the overpass time as 1.30AM for the descending pass and 1.30PM 
!   for the ascending pass. 
!-------------------------------------------------------------------------
  alarmCheck = LIS_isAlarmRinging(LIS_rc, "SMOPS read alarm")
  
  if(alarmCheck.or.SMOPS_AMSR2sm_struc(n)%startMode) then 
     SMOPS_AMSR2sm_struc(n)%startMode = .false.

     SMOPS_AMSR2sm_struc(n)%smobs = LIS_rc%udef
     SMOPS_AMSR2sm_struc(n)%smtime = -1

     smobs = LIS_rc%udef
     smtime = LIS_rc%udef

     
     call create_SMOPS_AMSR2sm_filename(smobsdir, &
          SMOPS_AMSR2sm_struc(n)%useRealtime, &
          LIS_rc%yr, LIS_rc%mo, &
          LIS_rc%da, LIS_rc%hr, SMOPS_AMSR2sm_struc(n)%conv, fname)

     inquire(file=fname,exist=file_exists)

     if(file_exists) then 
        write(LIS_logunit,*) '[INFO] Reading ',trim(fname)
        call read_RTSMOPS_AMSR2_data(n,k,fname,smobs,smtime)
     else
        write(LIS_logunit,*) '[WARN] Missing SMOPS ',trim(fname)
     endif

     SMOPS_AMSR2sm_struc(n)%smobs  = LIS_rc%udef
     SMOPS_AMSR2sm_struc(n)%smtime = -1

     do r=1,LIS_rc%obs_lnr(k)
        do c=1,LIS_rc%obs_lnc(k)
           grid_index = LIS_obs_domain(n,k)%gindex(c,r)
           if(grid_index.ne.-1) then 
              if(smobs(c+(r-1)*LIS_rc%obs_lnc(k)).ne.-9999.0) then 
                 SMOPS_AMSR2sm_struc(n)%smobs(c,r) = &
                      smobs(c+(r-1)*LIS_rc%obs_lnc(k))                 
                 SMOPS_AMSR2sm_struc(n)%smtime(c,r) = &
                      smtime(c+(r-1)*LIS_rc%obs_lnc(k))
              endif
           endif
        enddo
     enddo

  endif
  
  call ESMF_StateGet(OBS_State,"Observation01",smfield,&
       rc=status)
  call LIS_verify(status, 'Error: StateGet Observation01')
  
  call ESMF_FieldGet(smfield,localDE=0,farrayPtr=obsl,rc=status)
  call LIS_verify(status, 'Error: FieldGet')

  fnd = 0 
  sm_current = LIS_rc%udef
 
! dt is not defined as absolute value of the time difference to avoid
! double counting of the data in assimilation. 

  call LIS_get_timeoffset_sec(LIS_rc%yr, LIS_rc%mo, LIS_rc%da, &
       LIS_rc%hr, LIS_rc%mn, LIS_rc%ss, lis_julss)

  do r=1,LIS_rc%obs_lnr(k)
     do c=1,LIS_rc%obs_lnc(k)
        if(LIS_obs_domain(n,k)%gindex(c,r).ne.-1) then 
           if(SMOPS_AMSR2sm_struc(n)%smtime(c,r).ge.0) then 
              dt = (lis_julss-SMOPS_AMSR2sm_struc(n)%smtime(c,r))
              if(dt.ge.0.and.dt.lt.LIS_rc%ts) then 
                 sm_current(c,r) = & 
                      SMOPS_AMSR2sm_struc(n)%smobs(c,r)
                 fnd = 1
              endif           
           endif
        endif
     enddo
  enddo

!-------------------------------------------------------------------------
!  Transform data to the LSM climatology using a CDF-scaling approach
!-------------------------------------------------------------------------     

  if(fnd.ne.0) then        
     ! Store the unscaled obs (ie, before the rescaling)
     do r =1,LIS_rc%obs_lnr(k)
        do c =1,LIS_rc%obs_lnc(k)
           if (LIS_obs_domain(n,k)%gindex(c,r) .ne. -1)then
              obs_unsc(LIS_obs_domain(n,k)%gindex(c,r)) = &
                   sm_current(c,r)
           end if
        end do
     end do
     
     call LIS_rescale_with_CDF_matching(    &
          n,k,                              & 
          SMOPS_AMSR2sm_struc(n)%nbins,         & 
          SMOPS_AMSR2sm_struc(n)%ntimes,         & 
          MAX_SM_VALUE,                        & 
          MIN_SM_VALUE,                        & 
          SMOPS_AMSR2sm_struc(n)%model_xrange,  &
          SMOPS_AMSR2sm_struc(n)%obs_xrange,    &
          SMOPS_AMSR2sm_struc(n)%model_cdf,     &
          SMOPS_AMSR2sm_struc(n)%obs_cdf,       &
          sm_current)
  endif

  obsl = LIS_rc%udef 
  if(fnd.ne.0) then 
     do r=1, LIS_rc%obs_lnr(k)
        do c=1, LIS_rc%obs_lnc(k)
           if(LIS_obs_domain(n,k)%gindex(c,r).ne.-1) then 
              obsl(LIS_obs_domain(n,k)%gindex(c,r))=sm_current(c,r)
           endif
        enddo
     enddo
  endif

  !-------------------------------------------------------------------------
  !  Apply LSM based QC and screening of observations
  !-------------------------------------------------------------------------  
  call lsmdaqcobsstate(trim(LIS_rc%lsm)//"+"&
       //trim(LIS_SMOPS_AMSR2smobsId)//char(0),n,k,OBS_state)

  call LIS_checkForValidObs(n,k,obsl,fnd,sm_current)

  if(fnd.eq.0) then 
     data_upd_flag_local = .false. 
  else
     data_upd_flag_local = .true. 
  endif
        
#if (defined SPMD)
  call MPI_ALLGATHER(data_upd_flag_local,1, &
       MPI_LOGICAL, data_upd_flag(:),&
       1, MPI_LOGICAL, LIS_mpi_comm, status)
#endif
  data_upd = .false.
  do p=1,LIS_npes
     data_upd = data_upd.or.data_upd_flag(p)
  enddo

!-------------------------------------------------------------------------
!  Depending on data update flag...
!-------------------------------------------------------------------------     
  
  if(data_upd) then 

     do t=1,LIS_rc%obs_ngrid(k)
        gid(t) = t
        if(obsl(t).ne.-9999.0) then 
           assimflag(t) = 1
        else
           assimflag(t) = 0
        endif
     enddo
  
     call ESMF_AttributeSet(OBS_State,"Data Update Status",&
          .true. , rc=status)
     call LIS_verify(status)

     if(LIS_rc%obs_ngrid(k).gt.0) then 
        call ESMF_AttributeSet(smField,"Grid Number",&
             gid,itemCount=LIS_rc%obs_ngrid(k),rc=status)
        call LIS_verify(status)
        
        call ESMF_AttributeSet(smField,"Assimilation Flag",&
             assimflag,itemCount=LIS_rc%obs_ngrid(k),rc=status)
        call LIS_verify(status)

        call ESMF_AttributeSet(smfield, "Unscaled Obs",&
             obs_unsc, itemCount=LIS_rc%obs_ngrid(k), rc=status)
        call LIS_verify(status, 'Error in setting Unscaled Obs attribute')
     endif

     if(SMOPS_AMSR2sm_struc(n)%useSsdevScal.eq.1) then
        call ESMF_StateGet(OBS_Pert_State,"Observation01",pertfield,&
             rc=status)
        call LIS_verify(status, 'Error: StateGet Observation01')
        
        allocate(ssdev(LIS_rc%obs_ngrid(k)))
        ssdev = SMOPS_AMSR2sm_struc(n)%ssdev_inp 

        if(SMOPS_AMSR2sm_struc(n)%ntimes.eq.1) then 
           jj = 1
        else
           jj = LIS_rc%mo
        endif
        do t=1,LIS_rc%obs_ngrid(k)
           if(SMOPS_AMSR2sm_struc(n)%obs_sigma(t,jj).gt.0) then 
              ssdev(t) = ssdev(t)*SMOPS_AMSR2sm_struc(n)%model_sigma(t,jj)/&
                   SMOPS_AMSR2sm_struc(n)%obs_sigma(t,jj)
              if(ssdev(t).lt.minssdev) then 
                 ssdev(t) = minssdev
              endif
           endif
        enddo
        
        if(LIS_rc%obs_ngrid(k).gt.0) then 
           call ESMF_AttributeSet(pertField,"Standard Deviation",&
                ssdev,itemCount=LIS_rc%obs_ngrid(k),rc=status)
           call LIS_verify(status)
        endif
        deallocate(ssdev)
     endif
  else
     call ESMF_AttributeSet(OBS_State,"Data Update Status",&
          .false., rc=status)
     call LIS_verify(status)     
  endif

end subroutine read_SMOPS_AMSR2sm

!BOP
! 
! !ROUTINE: read_RTSMOPS_data
! \label{read_RTSMOPS_data}
!
! !INTERFACE:
subroutine read_RTSMOPS_AMSR2_data(n, k, fname, smobs_ip, smtime_ip)
! 
! !USES:   
#if(defined USE_GRIBAPI)
  use grib_api
#endif
  use LIS_coreMod,  only : LIS_rc, LIS_domain
  use LIS_logMod
  use LIS_timeMgrMod
  use SMOPS_AMSR2sm_Mod, only : SMOPS_AMSR2sm_struc

  implicit none
!
! !INPUT PARAMETERS: 
! 
  integer                       :: n 
  integer                       :: k
  character (len=*)             :: fname
  real                          :: smobs_ip(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k))
  real                          :: smtime_ip(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k))


! !OUTPUT PARAMETERS:
!
!
! !DESCRIPTION: 
!  This subroutine reads the RTSMOPS grib2 file and applies the data
!  quality flags to filter the data. The retrievals are rejected when 
!  the estimated error is above a predefined threshold (the recommeded
!  value is 5%). 
!
!  The arguments are: 
!  \begin{description}
!  \item[n]            index of the nest
!  \item[fname]        name of the RTSMOPS AMSR-E file
!  \item[smobs\_ip]    soil moisture data processed to the LIS domain
! \end{description}
!
!
!EOP
  INTEGER*2, PARAMETER :: FF = 255
  real,    parameter  :: err_threshold = 5 ! in percent
  integer             :: param_AMSR2, param_AMSR2_qa
  integer             :: param_AMSR2_hr, param_AMSR2_mn

  real                :: sm_AMSR2(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  real                :: sm_AMSR2_t(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  real                :: sm_AMSR2_hr(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  real                :: sm_AMSR2_mn(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)

  real                :: sm_AMSR2_qa(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  integer*2           :: sm_AMSR2_qa_t(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  real                :: sm_data(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  real                :: sm_time(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  logical*1           :: sm_data_b(SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr)
  logical*1           :: smobs_b_ip(LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k))
  integer             :: hr_val, mn_val, julss
  integer             :: c,r,ios
  integer             :: ftn,iret,igrib,nvars
  integer             :: param_num
  logical             :: var_found
  real                :: err, ql
  logical             :: smDataNotAvailable
  integer             :: updoy,yr1,mo1,da1,hr1,mn1,ss1
  real                :: upgmt
  real*8              :: timenow

smDataNotAvailable = .false. 

#if(defined USE_GRIBAPI)
  yr1 = LIS_rc%yr
  mo1 = LIS_rc%mo
  da1 = LIS_rc%da
  hr1 = LIS_rc%hr
  mn1 = LIS_rc%mn
  ss1 = 0
  call LIS_date2time(timenow,updoy,upgmt,yr1,mo1,da1,hr1,mn1,ss1)
  if ( timenow < SMOPS_AMSR2sm_struc(n)%version2_time ) then
!     param_AMSR2 = 213; param_AMSR2_qa = 234
!     param_AMSR2_hr = 223; param_AMSR2_mn = 224
     write(LIS_logunit,*) '[Warning] AMSR2 is not availabe in SMOPS version: 1.3'
     smDataNotAvailable = .true.
     smobs_ip = LIS_rc%udef
     smtime_ip = LIS_rc%udef
  elseif ( timenow >= SMOPS_AMSR2sm_struc(n)%version2_time .and. &
           timenow <  SMOPS_AMSR2sm_struc(n)%version3_time ) then
     param_AMSR2 = 215; param_AMSR2_qa = 236
     param_AMSR2_hr = 227; param_AMSR2_mn = 228
  elseif ( timenow >= SMOPS_AMSR2sm_struc(n)%version3_time ) then
     param_AMSR2 = 215; param_AMSR2_qa = 245
     param_AMSR2_hr = 230; param_AMSR2_mn = 231
  else
     write(LIS_logunit,*) '[ERR] Invalid times for SMOPS versions'
     write(LIS_logunit,*) '      ', timenow
     write(LIS_logunit,*) '      ', SMOPS_AMSR2sm_struc(n)%version2_time
     write(LIS_logunit,*) '      ', SMOPS_AMSR2sm_struc(n)%version3_time
     call LIS_endrun()
  endif

  if ( smDataNotAvailable .eqv. .false. ) then
  call grib_open_file(ftn,trim(fname), 'r',iret)
  if(iret.ne.0) then 
     write(LIS_logunit,*) '[ERR] Could not open file: ',trim(fname)
     call LIS_endrun()
  endif
  call grib_multi_support_on

  do
     call grib_new_from_file(ftn,igrib,iret)

     if ( iret == GRIB_END_OF_FILE ) then
        exit
     endif

     call grib_get(igrib, 'parameterNumber',param_num, iret)
     call LIS_verify(iret, &
          'grib_get: parameterNumber failed in readSMOPS_AMSR2sm_struc')

     var_found = .false. 
     if(SMOPS_AMSR2sm_struc(n)%useAMSR2.eq.1) then
        if(param_num.eq.param_AMSR2) then
           var_found = .true.
        endif
     endif

     if(var_found) then
        call grib_get(igrib, 'values',sm_AMSR2,iret)
        call LIS_warning(iret,'error in grib_get:values in readRTSMOPS_AMSR2smObs')
        
        do r=1,SMOPS_AMSR2sm_struc(n)%nr
           do c=1,SMOPS_AMSR2sm_struc(n)%nc
              sm_AMSR2_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = &
                   sm_AMSR2(c+((SMOPS_AMSR2sm_struc(n)%nr-r+1)-1)*&
                   SMOPS_AMSR2sm_struc(n)%nc)
           enddo
        enddo     
        
     endif

     var_found = .false. 
     if(SMOPS_AMSR2sm_struc(n)%useAMSR2.eq.1) then
        if(param_num.eq.param_AMSR2_qa) then
           var_found = .true.
        endif
     endif
     
     if(var_found) then
        call grib_get(igrib, 'values',sm_AMSR2_qa,iret)
        call LIS_warning(iret,'error in grib_get:values in readRTSMOPS_AMSR2smObs')
        
        do r=1,SMOPS_AMSR2sm_struc(n)%nr
           do c=1,SMOPS_AMSR2sm_struc(n)%nc
              sm_AMSR2_qa_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = &
                   INT(sm_AMSR2_qa(c+((SMOPS_AMSR2sm_struc(n)%nr-r+1)-1)*&
                   SMOPS_AMSR2sm_struc(n)%nc))
           enddo
        enddo       
     endif

     var_found = .false. 
     if(SMOPS_AMSR2sm_struc(n)%useAMSR2.eq.1) then 
        if(param_num.eq.param_AMSR2_hr) then
           var_found = .true.
        endif
     endif
     
     if(var_found) then
        call grib_get(igrib, 'values',sm_AMSR2_hr,iret)
        call LIS_warning(iret,'error in grib_get:values in readRTSMOPS_AMSR2smObs')
     endif
     
     var_found = .false. 
     if(SMOPS_AMSR2sm_struc(n)%useAMSR2.eq.1) then
        if(param_num.eq.param_AMSR2_mn) then
           var_found = .true.
        endif
     endif
     
     if(var_found) then
        call grib_get(igrib, 'values',sm_AMSR2_mn,iret)
        call LIS_warning(iret,'error in grib_get:values in readRTSMOPS_AMSR2smObs')
     endif

     call grib_release(igrib,iret)
     call LIS_verify(iret, 'error in grib_release in readRTSMOPS_AMSR2smObs')
  enddo

  call grib_close_file(ftn)

  sm_time = LIS_rc%udef

  do r=1, SMOPS_AMSR2sm_struc(n)%nr
     do c=1, SMOPS_AMSR2sm_struc(n)%nc
        if(sm_AMSR2_qa_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc).ne.9999) then 
           !estimated error
           err = ISHFT(sm_AMSR2_qa_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc),-8)
           !quality flag - not used currently
           ql = IAND(sm_AMSR2_qa_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc),FF)

           if(err.lt.err_threshold) then 
              hr_val = nint(sm_AMSR2_hr(c+&
                   ((SMOPS_AMSR2sm_struc(n)%nr-r+1)-1)*&
                   SMOPS_AMSR2sm_struc(n)%nc))
              mn_val =  nint(sm_AMSR2_mn(c+&
                   ((SMOPS_AMSR2sm_struc(n)%nr-r+1)-1)*&
                   SMOPS_AMSR2sm_struc(n)%nc))
              call LIS_get_timeoffset_sec(LIS_rc%yr, LIS_rc%mo, LIS_rc%da, &
                   hr_val, mn_val, 0, julss)
              sm_time(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = julss
              sm_data_b(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = .true. 
           else
              sm_data_b(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = .false.
              sm_AMSR2_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = LIS_rc%udef
           endif
        else
           sm_AMSR2_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = LIS_rc%udef
           sm_data_b(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = .false. 
        endif
        if(sm_AMSR2_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc).lt.0.001) then 
           sm_AMSR2_t(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = LIS_rc%udef
           sm_data_b(c+(r-1)*SMOPS_AMSR2sm_struc(n)%nc) = .false.
        endif
     enddo
  enddo

!--------------------------------------------------------------------------
! Interpolate to the LIS running domain
!-------------------------------------------------------------------------- 
  call neighbor_interp(LIS_rc%obs_gridDesc(k,:),&
       sm_data_b, sm_AMSR2_t, smobs_b_ip, smobs_ip, &
       SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr, &
       LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k), &
       SMOPS_AMSR2sm_struc(n)%rlat, SMOPS_AMSR2sm_struc(n)%rlon, &
       SMOPS_AMSR2sm_struc(n)%n11,  LIS_rc%udef, ios)

  call neighbor_interp(LIS_rc%obs_gridDesc(k,:),&
       sm_data_b, sm_time, smobs_b_ip, smtime_ip, &
       SMOPS_AMSR2sm_struc(n)%nc*SMOPS_AMSR2sm_struc(n)%nr, &
       LIS_rc%obs_lnc(k)*LIS_rc%obs_lnr(k), &
       SMOPS_AMSR2sm_struc(n)%rlat, SMOPS_AMSR2sm_struc(n)%rlon, &
       SMOPS_AMSR2sm_struc(n)%n11,  LIS_rc%udef, ios)
   endif

#endif
  
end subroutine read_RTSMOPS_AMSR2_data


!BOP
! !ROUTINE: create_SMOPS_AMSR2sm_filename
! \label{create_SMOPS_AMSR2sm_filename}
! 
! !INTERFACE: 
subroutine create_SMOPS_AMSR2sm_filename(ndir, useRT, yr, mo,da, hr, conv, filename)
! !USES:   

  implicit none
! !ARGUMENTS: 
  character(len=*)  :: filename
  integer           :: useRT
  integer           :: yr, mo, da,hr
  character (len=*) :: ndir
  character (len=*) :: conv
! 
! !DESCRIPTION: 
!  This subroutine creates the SMOPS filename based on the time and date 
! 
!  The arguments are: 
!  \begin{description}
!  \item[ndir] name of the SMOPS soil moisture data directory
!  \item[yr]  current year
!  \item[mo]  current month
!  \item[da]  current day
!  \item[conv] naming convention for the SMOPS data
!  \item[filename] Generated SMOPS filename
! \end{description}
!EOP

  character (len=4) :: fyr
  character (len=2) :: fmo,fda,fhr
  
  write(unit=fyr, fmt='(i4.4)') yr
  write(unit=fmo, fmt='(i2.2)') mo
  write(unit=fda, fmt='(i2.2)') da
  write(unit=fhr, fmt='(i2.2)') hr
 
  if(useRT.eq.1) then 
     if ( conv == "LIS" ) then
        filename = trim(ndir)//'/'//trim(fyr)//'/NPR_SMOPS_CMAP_D' &
                   //trim(fyr)//trim(fmo)//trim(fda)//trim(fhr)//'.gr2'     
     else
        filename = trim(ndir)//'/smops_d' &
                   //trim(fyr)//trim(fmo)//trim(fda)//'_s'//trim(fhr)//'0000_cness.gr2'
     endif
  else
     filename = trim(ndir)//'/'//trim(fyr)//'/NPR_SMOPS_CMAP_D' &
          //trim(fyr)//trim(fmo)//trim(fda)//'.gr2'
  endif

end subroutine create_SMOPS_AMSR2sm_filename




