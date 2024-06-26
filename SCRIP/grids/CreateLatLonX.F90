!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

 program CreateLatLon

!BOP
! !PROGRAM: CreateLatLon
!
! !DESCRIPTION:
!  This program creates a global grid with equally-spaced longitude
!  points and Gaussian-spaced latitude points (typical of spherical
!  spectral grids).  The resulting grid is written to a file in
!  SCRIP format.
!
! !REVISION HISTORY:
!  SVN:$Id: $

! !USES:

   use SCRIP_KindsMod
   use SCRIP_IOUnitsMod
   use SCRIP_NetcdfMod
   use netcdf

!EOP
!***********************************************************************
!
!     This version is a derivative work from the official version
!     of CreateLatLon.F90
!
!     The modification is maintained by SAITO Fuyuki, and the credit
!     of the modification part is as follows
!
!     Copyright (C) 2024
!          Japan Agency for Marine-Earth Science and Technology
!
!     Licensed under the Apache License, Version 2.0
!           (https://www.apache.org/licenses/LICENSE-2.0)
!
!     All the other part follows the official.
!
!     See git repository to check the modification.
!
!BOC
!-----------------------------------------------------------------------
!
!  variables that describe the grid
!
!-----------------------------------------------------------------------
   implicit none

   integer (SCRIP_i4) :: &
      nx, ny,      &! size in each direction (x is longitude)
      gridSize      ! total size of grid

   integer (SCRIP_i4), parameter :: &
      gridRank = 2,         &! number of dimensions in grid arrays
      numCorners = 4       ! number of corners for each grid cell

   character (SCRIP_charLength) :: & 
      gridName = 'Lat/lon 1 degree Grid', &! name for this grid
      gridFilename = 'll1deg_grid.nc'      ! file where grid is written

   integer (SCRIP_i4), dimension(gridRank) :: &
      gridDims

   real (SCRIP_r8) :: &
        offset_lon,   &   ! longitude offset of origin
        shift_midlon, &   ! mid-longitude shift mainly for test
        abs_midlon        ! absolute longitude choice in mid-longitude for test
!-----------------------------------------------------------------------
!
!  grid coordinates and masks
!
!-----------------------------------------------------------------------

   integer (SCRIP_i4), dimension(:),allocatable :: &
      gridMask

   real (SCRIP_r8), dimension(:),allocatable :: &
      centerLat,     &! lat/lon coordinates for
      centerLon       ! each grid center in degrees

   real (SCRIP_r8), dimension(:,:),allocatable :: &
      cornerLat,     &! lat/lon coordinates for
      cornerLon       ! each grid corner in degrees

!-----------------------------------------------------------------------
!
!  other local variables
!
!-----------------------------------------------------------------------
   real (SCRIP_r8),parameter :: zero = 0.0_SCRIP_r8

   integer (SCRIP_i4) :: &
      i,j,               &! loop indices
      errorCode,         &! error code for SCRIP error handling
      nCell               ! cell number in linear storage 

   integer (SCRIP_i4) :: &
      ncstat,            &! general netCDF status variable
      ncFileID,          &! netCDF grid dataset id
      ncGridSizeID,      &! netCDF grid size dim id
      ncGridCornerID,    &! netCDF grid corner dim id
      ncGridRankID,      &! netCDF grid rank dim id
      ncGridDimsID,      &! netCDF grid dimension size id
      ncCenterLatID,     &! netCDF grid center lat id
      ncCenterLonID,     &! netCDF grid center lon id
      ncGridMaskID,      &! netCDF grid mask id
      ncCornerLatID,     &! netCDF grid corner lat id
      ncCornerLonID       ! netCDF grid corner lon id

   integer (SCRIP_i4), dimension(2) :: &
      ncDims2dID          ! netCDF dim id array for 2-d arrays

   real (SCRIP_r8) ::    &
      dLon, dLat,        &! grid spacing in lat, lon
      minLon, maxLon,    &! lon range for each cell
      minLat, maxLat,    &! lat range for each cell
      midLat, midLon      ! latitude,longitude of cell center

   character (12), parameter :: &
      rtnName = 'CreateLatLon'

   integer (SCRIP_i4),parameter :: larg = 256
   integer (SCRIP_i4) :: jarg, narg
   character (larg) :: arg

!-----------------------------------------------------------------------
!
!  compute longitudes and latitudes of cell centers and corners.
!
!-----------------------------------------------------------------------
   narg = COMMAND_ARGUMENT_COUNT()
   jarg = 1
   if (narg.lt.3) then
      print *, 'Need paramaters: FILE NLON NLAT [OFFSET] [SHIFT]'
      stop
   endif

   ! mandatory
   call GET_COMMAND_ARGUMENT(jarg, gridFilename)
   jarg = jarg + 1
   call GET_COMMAND_ARGUMENT(jarg, arg)
   read(arg, *) nx
   jarg = jarg + 1
   call GET_COMMAND_ARGUMENT(jarg, arg)
   read(arg, *) ny
   jarg = jarg + 1

   if (gridFilename.eq.' '.or.nx.le.0.or.ny.le.0) then
      print *, 'Invalid parameter(s):', trim(gridFilename), nx, ny
      stop
   endif

   ! optional
   if (jarg.le.narg) then
      call GET_COMMAND_ARGUMENT(jarg, arg)
      read(arg, *) offset_lon
      jarg = jarg + 1
   else
      offset_lon = zero
   endif
   if (jarg.le.narg) then
      call GET_COMMAND_ARGUMENT(jarg, arg)
      read(arg, *) shift_midlon
      jarg = jarg + 1
   else
      shift_midlon = zero
   endif
   if (jarg.le.narg) then
      call GET_COMMAND_ARGUMENT(jarg, arg)
      read(arg, *) abs_midlon
      jarg = jarg + 1
   else
      abs_midlon = -9999.   ! disabled default
   endif

   if (abs_midlon.gt.-1000.) then
      write(gridName, &
           & '(''Lat/lon '', I0, ''x'', I0, 1x, F9.6, '' /'', F9.6, '' Grid'')') &
           nx, ny, offset_lon, abs_midlon
   else if (shift_midlon.eq.zero) then
      write(gridName, &
           & '(''Lat/lon '', I0, ''x'', I0, 1x, F9.6, '' Grid'')') &
           nx, ny, offset_lon
   else
      write(gridName, &
           & '(''Lat/lon '', I0, ''x'', I0, 1x, F9.6, 1x, F9.6, '' Grid'')') &
           nx, ny, offset_lon, shift_midlon
   endif

   gridDims(1) = nx
   gridDims(2) = ny

   gridSize = nx * ny
   allocate(gridMask(gridSize), &
            centerLat(gridSize), centerLon(gridSize))
   allocate(cornerLat(numCorners,gridSize), &
        &   cornerLon(numCorners,gridSize))

   dLon = 360.0_SCRIP_r8/nx
   dLat = 180.0_SCRIP_r8/ny

   do j=1,ny

      minLat = -90.0_SCRIP_r8 + (j-1)*dLat
      maxLat = -90.0_SCRIP_r8 +  j   *dLat
      midLat = minLat + 0.5_SCRIP_r8*dLat

      do i=1,nx
         midLon = (i-1)*dLon + offset_lon * dLon  ! reference
         minLon = midLon - 0.5_SCRIP_r8*dLon
         maxLon = midLon + 0.5_SCRIP_r8*dLon
         ! final adjustment
         if (abs_midlon.gt.-1000.) then
            midLon = abs_midlon
         else
            midLon = midLon + shift_midlon * dLon
         endif

         nCell = (j-1)*nx + i

         centerLat(nCell  ) = midLat
         cornerLat(1,nCell) = minLat
         cornerLat(2,nCell) = minLat
         cornerLat(3,nCell) = maxLat
         cornerLat(4,nCell) = maxLat

         centerLon(nCell  ) = midLon
         cornerLon(1,nCell) = minLon
         cornerLon(2,nCell) = maxLon
         cornerLon(3,nCell) = maxLon
         cornerLon(4,nCell) = minLon
      end do
   end do

!-----------------------------------------------------------------------
!
!  define mask
!
!-----------------------------------------------------------------------

   gridMask = 1

!-----------------------------------------------------------------------
!
!  set up attributes for netCDF file
!
!-----------------------------------------------------------------------

   !***
   !*** create netCDF dataset for this grid
   !***

   ncstat = nf90_create (trim(gridFilename), NF90_CLOBBER, ncFileID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
            'error opening file')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_att(ncFileID, NF90_GLOBAL, 'title', trim(gridName))
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
            'error writing grid name')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid size dimension
   !***

   ncstat = nf90_def_dim(ncFileID, 'grid_size', gridSize, ncGridSizeID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
            'error defining grid size')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid corner dimension
   !***

   ncstat = nf90_def_dim(ncFileID, 'grid_corners', numCorners, ncGridCornerID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
            'error defining num corners')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid rank dimension
   !***

   ncstat = nf90_def_dim(ncFileID, 'grid_rank', gridRank, ncGridRankID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
            'error defining grid rank')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid dimension size array
   !***

   ncstat = nf90_def_var(ncFileID, 'grid_dims', nf90_int, &
                         ncGridRankID, ncGridDimsID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
            'error defining grid dims')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid center latitude array
   !***

   ncstat = nf90_def_var(ncFileID, 'grid_center_lat', nf90_double, &
                         ncGridSizeID, ncCenterLatID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error defining grid center lats')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_att(ncFileID, ncCenterLatID, 'units', 'degrees')
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing grid units')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid center longitude array
   !***

   ncstat = nf90_def_var(ncFileID, 'grid_center_lon', nf90_double, &
                         ncGridSizeID, ncCenterLonID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error defining grid center lons')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_att(ncFileID, ncCenterLonID, 'units', 'degrees')
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing grid units')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid mask
   !***

   ncstat = nf90_def_var (ncFileID, 'grid_imask', nf90_int, &
                          ncGridSizeID, ncGridMaskID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error defining grid mask')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_att(ncFileID, ncGridMaskID, 'units', 'unitless')
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing mask units')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid corner latitude array
   !***

   ncDims2dID(1) = ncGridCornerID
   ncDims2dID(2) = ncGridSizeID

   ncstat = nf90_def_var(ncFileID, 'grid_corner_lat', nf90_double, &
                         ncDims2dID, ncCornerLatID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error defining corner lats')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_att(ncFileID, ncCornerLatID, 'units', 'degrees')
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing corner lat units')) call CreateLatLonExit(errorCode)

   !***
   !*** define grid corner longitude array
   !***

   ncstat = nf90_def_var(ncFileID, 'grid_corner_lon', nf90_double, &
                         ncDims2dID, ncCornerLonID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error defining corner lons')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_att(ncFileID, ncCornerLonID, 'units', 'degrees')
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing corner lon units')) call CreateLatLonExit(errorCode)

   !***
   !*** end definition stage
   !***

   ncstat = nf90_enddef(ncFileID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error ending define stage')) call CreateLatLonExit(errorCode)

!-----------------------------------------------------------------------
!
!  write grid data
!
!-----------------------------------------------------------------------

   ncstat = nf90_put_var(ncFileID, ncGridDimsID, gridDims)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing grid dims')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_var(ncFileID, ncGridMaskID, gridMask)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing grid mask')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_var(ncFileID, ncCenterLatID, centerLat)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing center lats')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_var(ncFileID, ncCenterLonID, centerLon)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing center lons')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_var(ncFileID, ncCornerLatID, cornerLat)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing corner lats')) call CreateLatLonExit(errorCode)

   ncstat = nf90_put_var(ncFileID, ncCornerLonID, cornerLon)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error writing corner lons')) call CreateLatLonExit(errorCode)

   ncstat = nf90_close(ncFileID)
   if (SCRIP_NetcdfErrorCheck(ncstat, errorCode, rtnName, &
       'error closing file')) call CreateLatLonExit(errorCode)

!-----------------------------------------------------------------------
!EOC

 end program CreateLatLon

!***********************************************************************
!BOP
! !IROUTINE: CreateLatLonExit
! !INTERFACE:

   subroutine CreateLatLonExit(errorCode)

! !DESCRIPTION:
!  This program exits the CreateLatLon program. It first calls the 
!  SCRIP error print function to print any errors encountered and then
!  stops the execution.
!
! !REVISION HISTORY:
!  SVN:$Id: $

! !USES:

   use SCRIP_KindsMod
   use SCRIP_ErrorMod

! !INPUT PARAMETERS:

   integer (SCRIP_i4), intent(in) :: &
      errorCode        ! error flag to detect any errors encountered

!EOP
!BOC
!-----------------------------------------------------------------------
!
!  call SCRIP error print function to output any logged errors that
!  were encountered during execution.  Then stop.
!
!-----------------------------------------------------------------------

   call SCRIP_ErrorPrint(errorCode)

   stop

!-----------------------------------------------------------------------
!EOC

   end subroutine CreateLatLonExit

!|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
