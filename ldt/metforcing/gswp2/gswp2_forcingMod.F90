!-----------------------BEGIN NOTICE -- DO NOT EDIT-----------------------
! NASA Goddard Space Flight Center
! Land Information System Framework (LISF)
! Version 7.4
!
! Copyright (c) 2022 United States Government as represented by the
! Administrator of the National Aeronautics and Space Administration.
! All Rights Reserved.
!-------------------------END NOTICE -- DO NOT EDIT-----------------------
module gswp2_forcingMod
!BOP
! !MODULE: gswp2_forcingMod
!
! !DESCRIPTION: 
!  This module contains variables and data structures that are used
!  for the implementation of the forcing data from the Global Soil
!  Wetness Project (GSWP2). GSWP2 forcing variables are produced
!  on a latlon 1degree grid at 3 hour intervals. 
!
!  The implemenatation in LDT has the derived data type {\tt gswp2\_struc} that
!  includes the variables that specify the runtime options
!  They are described below: 
!  \begin{description}
!  \item[nc]
!    Number of columns (along the east west dimension) for the input data
!  \item[nr]
!    Number of rows (along the north south dimension) for the input data
!  \item[nmif]
!    Number of forcing variables in the GSWP2 data
!  \item[gswp2time1]
!    The nearest, previous 3 hour instance of the incoming 
!    data (as a real time). 
!  \item[gswp2time2]
!    The nearest, next 3 hour instance of the incoming 
!    data (as a real time).
!  \item[tair]
!    Directory containing the 2m air temperature data
!  \item[qair]
!    Directory containing the 2m specific humidity data
!  \item[psurf]
!    Directory containing the surface pressure data
!  \item[wind]
!    Directory containing the wind data
!  \item[rainf]
!    Directory containing the total precipitation data
!  \item[snowf]
!    Directory containing the total snowfall data
!  \item[swdown]
!    Directory containing the downward shortwave radiation data
!  \item[swdown]
!    Directory containing the downward longwave radiation data
!  \item[mi]
!    Number of points in the input grid
!  \item[findtime1, findtime2]
!   boolean flags to indicate which time is to be read for 
!   temporal interpolation.
!  \end{description}
!
! !USES: 
  use LDT_constantsMod, only : LDT_CONST_PATH_LEN
  implicit none
  
  PRIVATE
!-----------------------------------------------------------------------------
! !PUBLIC MEMBER FUNCTIONS:
!-----------------------------------------------------------------------------
  public :: init_GSWP2      !defines the native resolution of 
                                  !the input data
!-----------------------------------------------------------------------------
! !PUBLIC TYPES:
!-----------------------------------------------------------------------------
  public :: gswp2_struc
!EOP

  type, public ::  gswp2_type_dec
     real    :: ts
     integer :: nc, nr, vector_len   !AWIPS 212 dimensions
     integer :: nmif
     real*8  :: gswp2time1,gswp2time2
     character(len=LDT_CONST_PATH_LEN) :: mfile
     character(len=LDT_CONST_PATH_LEN) :: tair
     character(len=LDT_CONST_PATH_LEN) :: qair
     character(len=LDT_CONST_PATH_LEN) :: psurf
     character(len=LDT_CONST_PATH_LEN) :: wind
     character(len=LDT_CONST_PATH_LEN) :: rainf
     character(len=LDT_CONST_PATH_LEN) :: snowf
     character(len=LDT_CONST_PATH_LEN) :: swdown
     character(len=LDT_CONST_PATH_LEN) :: lwdown
     character(len=LDT_CONST_PATH_LEN) :: rainf_c

     integer, allocatable   :: gindex(:,:)

     integer :: mi
  !Suffixes 1 are for bilinear 
     integer, allocatable   :: n111(:)
     integer, allocatable   :: n121(:)
     integer, allocatable   :: n211(:)
     integer, allocatable   :: n221(:)
     real, allocatable      :: w111(:),w121(:)
     real, allocatable      :: w211(:),w221(:)
     
  !Suffixes 2 are for conservative 
     integer, allocatable   :: n112(:,:)
     integer, allocatable   :: n122(:,:)
     integer, allocatable   :: n212(:,:)
     integer, allocatable   :: n222(:,:)
     real, allocatable      :: w112(:,:),w122(:,:)
     real, allocatable      :: w212(:,:),w222(:,:)

     integer, allocatable   :: smask1(:,:)
     logical                :: fillflag1

     integer                :: findtime1, findtime2
  end type gswp2_type_dec
  
  type(gswp2_type_dec), allocatable :: gswp2_struc(:)
!EOP
contains
  
!BOP
!
! !ROUTINE: init_GSWP2
! \label{init_GSWP2}
! 
! !REVISION HISTORY: 
! 11Dec2003: Sujay Kumar; Initial Specification
! 
! !INTERFACE:
  subroutine init_GSWP2(findex)
! !USES: 
    use LDT_coreMod,    only : LDT_rc
    use LDT_timeMgrMod, only : LDT_update_timestep
    use LDT_logMod,     only : LDT_logunit, LDT_endrun

    implicit none
! !USES: 
    integer, intent(in)  :: findex
! 
! !DESCRIPTION: 
!  Defines the native resolution of the input forcing for GSWP2
!  data. The grid description arrays are based on the decoding
!  schemes used by NCEP and followed in the LDT interpolation
!  schemes \ref{interp}
!
!  The routines invoked are: 
!  \begin{description}
!   \item[readcrd\_gswp2](\ref{readcrd_gswp2}) \newline
!     reads the runtime options specified for GSWP2 data
!   \item[bilinear\_interp\_input](\ref{bilinear_interp_input}) \newline
!    computes the neighbor, weights for bilinear interpolation
!   \item[conserv\_interp\_input](\ref{conserv_interp_input}) \newline
!    computes the neighbor, weights for conservative interpolation
!   \item[gswp2\_mask](\ref{gswp2_mask}) \newline
!    reads the GSWP2 mask
!  \end{description}
!EOP

    integer :: n 
    real    :: gridDesci(20)
    
    allocate(gswp2_struc(LDT_rc%nnest))

   write(LDT_logunit,fmt=*)"MSG: Initializing GSWP-2 forcing grid ... "

!    call readcrd_gswp2()

    LDT_rc%met_nf(findex) = 10
    LDT_rc%met_ts(findex) = 3600*3
    LDT_rc%met_zterp(findex) = .false.

    gswp2_struc%nc = 360
    gswp2_struc%nr = 150
    LDT_rc%met_nc(findex) = gswp2_struc(1)%nc
    LDT_rc%met_nr(findex) = gswp2_struc(1)%nr

 !- GSWP1 Grid description:
    LDT_rc%met_proj(findex)        = "latlon"
    LDT_rc%met_gridDesc(findex,1)  = 0
    LDT_rc%met_gridDesc(findex,2)  = gswp2_struc(1)%nc
    LDT_rc%met_gridDesc(findex,3)  = gswp2_struc(1)%nr
    LDT_rc%met_gridDesc(findex,4)  = -59.500
    LDT_rc%met_gridDesc(findex,5)  = -179.500
    LDT_rc%met_gridDesc(findex,6)  = 128
    LDT_rc%met_gridDesc(findex,7)  = 89.500
    LDT_rc%met_gridDesc(findex,8)  = 179.500
    LDT_rc%met_gridDesc(findex,9)  = 1.000
    LDT_rc%met_gridDesc(findex,10) = 1.000
    LDT_rc%met_gridDesc(findex,20) = 0.

    gridDesci(:) = LDT_rc%met_gridDesc(findex,:)

    gswp2_struc%mi = gswp2_struc%nc*gswp2_struc%nr

 !- If only processing parameters, then return to main routine calls ...
    if( LDT_rc%runmode == "LSM parameter processing" ) return

    do n=1,LDT_rc%nnest

       call LDT_update_timestep(LDT_rc, n, gswp2_struc(n)%ts)

       gswp2_struc(n)%gswp2time1 = 3000.0
       gswp2_struc(n)%gswp2time2 = 0.0

      !Setting up weights for Interpolation
       if(trim(LDT_rc%met_gridtransform(findex)).eq."bilinear") then 
          allocate(gswp2_struc(n)%n111(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%n121(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%n211(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%n221(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w111(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w121(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w211(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w221(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          call bilinear_interp_input(n, gridDesci(:),&
               gswp2_struc(n)%n111,gswp2_struc(n)%n121,&
               gswp2_struc(n)%n211,gswp2_struc(n)%n221,&
               gswp2_struc(n)%w111,gswp2_struc(n)%w121,&
               gswp2_struc(n)%w211,gswp2_struc(n)%w221)

          allocate(gswp2_struc(n)%smask1(LDT_rc%lnc(n),LDT_rc%lnr(n)))
          gswp2_struc(n)%fillflag1 = .true. 

       elseif(trim(LDT_rc%met_gridtransform(findex)).eq."budget-bilinear") then 
          allocate(gswp2_struc(n)%n111(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%n121(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%n211(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%n221(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w111(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w121(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w211(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          allocate(gswp2_struc(n)%w221(LDT_rc%lnc(n)*LDT_rc%lnr(n)))
          call bilinear_interp_input(n, gridDesci(:),&
               gswp2_struc(n)%n111,gswp2_struc(n)%n121,&
               gswp2_struc(n)%n211,gswp2_struc(n)%n221,&
               gswp2_struc(n)%w111,gswp2_struc(n)%w121,&
               gswp2_struc(n)%w211,gswp2_struc(n)%w221)
          allocate(gswp2_struc(n)%n112(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%n122(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%n212(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%n222(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%w112(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%w122(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%w212(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          allocate(gswp2_struc(n)%w222(LDT_rc%lnc(n)*LDT_rc%lnr(n),25))
          call conserv_interp_input(n, gridDesci(:),&
               gswp2_struc(n)%n112,gswp2_struc(n)%n122,&
               gswp2_struc(n)%n212,gswp2_struc(n)%n222,&
               gswp2_struc(n)%w112,gswp2_struc(n)%w122,&
               gswp2_struc(n)%w212,gswp2_struc(n)%w222)
       elseif(trim(LDT_rc%met_gridtransform(findex)).eq."neighbor") then 
          write(LDT_logunit,*) 'Neighbor interpolation is not supported'
          write(LDT_logunit,*) 'for GSWP2 forcing... Program stopping..'
          call LDT_endrun()
       endif

    enddo
    
!    call gswp2_mask
    
  end subroutine init_GSWP2
end module gswp2_forcingMod
