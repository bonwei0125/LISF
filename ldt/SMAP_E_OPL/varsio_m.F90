MODULE varsio_m
       IMPLICIT NONE
       REAL*8, PARAMETER :: RE_KM = 6371.228, PI = acos(-1.0), d2r = PI/180.0
       REAL*4, PARAMETER :: FillValue_float32=-9999, Q=0, freq=1.41, inc=40
       REAL*4 :: bulkdensity, tbv, tau, clay, h, Ts, omega
       INTEGER*1 :: topigbptype 
END MODULE varsio_m
