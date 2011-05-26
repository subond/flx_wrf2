      subroutine calcpv_nests(l,n,uuhn,vvhn,pvhn)
C                             i i  i    i    o
********************************************************************************
*                                                                              *
*     Note:  This is the FLEXPART_WRF version of subroutine calcpv_nests.      *
*            The computational grid is the WRF x-y grid rather than lat-lon.   *
*                                                                              *
*  Calculation of potential vorticity on 3-d nested grid                       *
*                                                                              *
*     Author: P. James                                                         *
*     22 February 2000                                                         *
*                                                                              *
*    11 Nov 2005, R. Easter - changes associated with WRF horizontal grid.     *
*                             For pressure use pph instead of (akz + bkz*ps)   *
*    *** Note -- see ??? comments below regarding the pvh calculation.         *
*                                                                              *
********************************************************************************
*                                                                              *
* Variables:                                                                   *
* n                  temporal index for meteorological fields (1 to 2)         *
* l                  index of current nest                                     *
*                                                                              *
* Constants:                                                                   *
*                                                                              *
********************************************************************************

      include 'includepar'
      include 'includecom'

      integer n,ix,jy,i,j,k,kl,ii,jj,klvrp,klvrm,klpt,kup,kdn,kch
      integer jyvp,jyvm,ixvp,ixvm,jumpx,jumpy,jux,juy,ivrm,ivrp,ivr
      integer nlck,l
      real vx(2),uy(2),phi,tanphi,cosphi,dvdx,dudy,f
      real theta,thetap,thetam,dthetadp,dt1,dt2,dt,ppmk
      real altit(nuvzmax),ppml(nuvzmax)
      real thup,thdn,eps,p0
      parameter(eps=1.e-5,p0=101325)
      real thhn(0:nxmaxn-1,0:nymaxn-1,nuvzmax,maxnests)
      real uuhn(0:nxmaxn-1,0:nymaxn-1,nuvzmax,maxnests)
      real vvhn(0:nxmaxn-1,0:nymaxn-1,nuvzmax,maxnests)
      real pvhn(0:nxmaxn-1,0:nymaxn-1,nuvzmax,maxnests)
      real dumlon,dumlat

C Set number of levels to check for adjacent theta
      nlck=nuvz/3
c FLEXPART_WRF -- altit is never used, so don't calculate it
c      do 5 k=1,nuvz
c        altit(k)=akz(k)/p0+bkz(k)
c5     continue
C *** Precalculate all theta levels for efficiency
        do 9 jy=0,nyn(l)-1
        do 14 kl=1,nuvz
        do 13 ix=0,nxn(l)-1
c FLEXPART_WRF -- use pph here
c         ppmk=akz(kl)+bkz(kl)*psn(ix,jy,1,n,l)
          ppmk=pphn(ix,jy,kl,n,l)
          thhn(ix,jy,kl,l)=tthn(ix,jy,kl,n,l)*(100000./ppmk)**kappa
13      continue
14      continue
9       continue
C
C Loop over entire grid
***********************
      do 10 jy=0,nyn(l)-1
c for FLEXPART_WRF, x & y coords are in meters
c and true latitude varies with both i and j
c       phi = (ylat0n(l) + jy * dyn(l)) * pi / 180.
c       f = 0.00014585 * sin(phi)
c       tanphi = tan(phi)
c       cosphi = cos(phi)
C Provide a virtual jy+1 and jy-1 in case we are on domain edge (Lat)
          jyvp=jy+1
          jyvm=jy-1
          if (jy.eq.0) jyvm=0
          if (jy.eq.nyn(l)-1) jyvp=nyn(l)-1
C Define absolute gap length
          jumpy=2
          if (jy.eq.0.or.jy.eq.nyn(l)-1) jumpy=1
          juy=jumpy
C
        do 11 ix=0,nxn(l)-1

c for FLEXPART_WRF, x & y coords are in meters
c and true latitude varies with both i and j
          call xyindex_to_ll_wrf( 
     &            l, float(ix), float(jy), dumlon, dumlat )
          phi = dumlat * pi / 180.
          f = 0.00014585 * sin(phi)
          tanphi = tan(phi)
          cosphi = cos(phi)

C Provide a virtual ix+1 and ix-1 in case we are on domain edge (Long)
          ixvp=ix+1
          ixvm=ix-1
          jumpx=2
          if (ix.eq.0) ixvm=0
          if (ix.eq.nxn(l)-1) ixvp=nxn(l)-1
          ivrp=ixvp
          ivrm=ixvm
C Define absolute gap length
          if (ix.eq.0.or.ix.eq.nxn(l)-1) jumpx=1
          jux=jumpx
C Precalculate pressure values for efficiency
          do 8 kl=1,nuvz
c FLEXPART_WRF -- use pph here
c           ppml(kl)=akz(kl)+bkz(kl)*psn(ix,jy,1,n,l)
            ppml(kl)=pphn(ix,jy,kl,n,l)
8         continue
C
C Loop over the vertical
************************

          do 12 kl=1,nuvz
            theta=thhn(ix,jy,kl,l)
            klvrp=kl+1
            klvrm=kl-1
            klpt=kl
C If top or bottom level, dthetadp is evaluated between the current
C level and the level inside, otherwise between level+1 and level-1
C
            if (klvrp.gt.nuvz) klvrp=nuvz
            if (klvrm.lt.1) klvrm=1
            thetap=thhn(ix,jy,klvrp,l)
            thetam=thhn(ix,jy,klvrm,l)
            dthetadp=(thetap-thetam)/(ppml(klvrp)-ppml(klvrm))
            
C Compute vertical position at pot. temperature surface on subgrid
C and the wind at that position
******************************************************************
C a) in x direction
            ii=0
            do 20 i=ixvm,ixvp,jumpx
              ivr=i
              ii=ii+1
C Search adjacent levels for current theta value
C Spiral out from current level for efficiency
              kup=klpt-1
              kdn=klpt
              kch=0
40            continue
C Upward branch
              kup=kup+1
              if (kch.ge.nlck) goto 21     ! No more levels to check, 
C                                            ! and no values found
              if (kup.ge.nuvz) goto 41
              kch=kch+1
              k=kup
              thdn=thhn(ivr,jy,k,l)
              thup=thhn(ivr,jy,k+1,l)
          if (((thdn.ge.theta).and.(thup.le.theta)).or.
     +    ((thdn.le.theta).and.(thup.ge.theta))) then
                  dt1=abs(theta-thdn)
                  dt2=abs(theta-thup)
                  dt=dt1+dt2
                  if (dt.lt.eps) then   ! Avoid division by zero error
                    dt1=0.5             ! G.W., 10.4.1996
                    dt2=0.5
                    dt=1.0
                  endif
        vx(ii)=(vvhn(ivr,jy,k,l)*dt2+vvhn(ivr,jy,k+1,l)*dt1)/dt
                  goto 20
                endif
41            continue
C Downward branch
              kdn=kdn-1
              if (kdn.lt.1) goto 40
              kch=kch+1
              k=kdn
              thdn=thhn(ivr,jy,k,l)
              thup=thhn(ivr,jy,k+1,l)
          if (((thdn.ge.theta).and.(thup.le.theta)).or.
     +    ((thdn.le.theta).and.(thup.ge.theta))) then
                  dt1=abs(theta-thdn)
                  dt2=abs(theta-thup)
                  dt=dt1+dt2
                  if (dt.lt.eps) then   ! Avoid division by zero error
                    dt1=0.5             ! G.W., 10.4.1996
                    dt2=0.5
                    dt=1.0
                  endif
        vx(ii)=(vvhn(ivr,jy,k,l)*dt2+vvhn(ivr,jy,k+1,l)*dt1)/dt
                  goto 20
                endif
                goto 40
C This section used when no values were found
21          continue
C Must use vv at current level and long. jux becomes smaller by 1
            vx(ii)=vvhn(ix,jy,kl,l)
            jux=jux-1
C Otherwise OK
20          continue
          if (jux.gt.0) then
c for FLEXPART_WRF, dx & dy are in meters.
c         dvdx=(vx(2)-vx(1))/float(jux)/(dxn(l)*pi/180.)
          dvdx=(vx(2)-vx(1))/float(jux)/dxn(l)
          else
          dvdx=vvhn(ivrp,jy,kl,l)-vvhn(ivrm,jy,kl,l)
c         dvdx=dvdx/float(jumpx)/(dxn(l)*pi/180.)
          dvdx=dvdx/float(jumpx)/dxn(l)
C Only happens if no equivalent theta value
C can be found on either side, hence must use values
C from either side, same pressure level.
          end if

C b) in y direction

            jj=0
            do 50 j=jyvm,jyvp,jumpy
              jj=jj+1
C Search adjacent levels for current theta value
C Spiral out from current level for efficiency
              kup=klpt-1
              kdn=klpt
              kch=0
70            continue
C Upward branch
              kup=kup+1
              if (kch.ge.nlck) goto 51     ! No more levels to check, 
C                                          ! and no values found
              if (kup.ge.nuvz) goto 71
              kch=kch+1
              k=kup
              thdn=thhn(ix,j,k,l)
              thup=thhn(ix,j,k+1,l)
          if (((thdn.ge.theta).and.(thup.le.theta)).or.
     +    ((thdn.le.theta).and.(thup.ge.theta))) then
                  dt1=abs(theta-thdn)
                  dt2=abs(theta-thup)
                  dt=dt1+dt2
                  if (dt.lt.eps) then   ! Avoid division by zero error
                    dt1=0.5             ! G.W., 10.4.1996
                    dt2=0.5
                    dt=1.0
                  endif
            uy(jj)=(uuhn(ix,j,k,l)*dt2+uuhn(ix,j,k+1,l)*dt1)/dt
                  goto 50
                endif
71            continue
C Downward branch
              kdn=kdn-1
              if (kdn.lt.1) goto 70
              kch=kch+1
              k=kdn
              thdn=thhn(ix,j,k,l)
              thup=thhn(ix,j,k+1,l)
          if (((thdn.ge.theta).and.(thup.le.theta)).or.
     +    ((thdn.le.theta).and.(thup.ge.theta))) then
                  dt1=abs(theta-thdn)
                  dt2=abs(theta-thup)
                  dt=dt1+dt2
                  if (dt.lt.eps) then   ! Avoid division by zero error
                    dt1=0.5             ! G.W., 10.4.1996
                    dt2=0.5
                    dt=1.0
                  endif
            uy(jj)=(uuhn(ix,j,k,l)*dt2+uuhn(ix,j,k+1,l)*dt1)/dt
                  goto 50
                endif
                goto 70
C This section used when no values were found
51          continue
C Must use uu at current level and lat. juy becomes smaller by 1
            uy(jj)=uuhn(ix,jy,kl,l)
            juy=juy-1
C Otherwise OK
50          continue
          if (juy.gt.0) then
c for FLEXPART_WRF, dx & dy are in meters.
c         dudy=(uy(2)-uy(1))/float(juy)/(dyn(l)*pi/180.)
          dudy=(uy(2)-uy(1))/float(juy)/dyn(l)
          else
          dudy=uuhn(ix,jyvp,kl,l)-uuhn(ix,jyvm,kl,l)
c         dudy=dudy/float(jumpy)/(dyn(l)*pi/180.)
          dudy=dudy/float(jumpy)/dyn(l)
          end if
C
c for FLEXPART_WRF, dx & dy are in meters.
c   don't need to divide by r_earth when doing d/dy
c   don't need to divide by r_earth*cosphi when doing d/dx
c ??? I don't understand the uuhn*tanphi term, but leave it in for now ???
c ??? What is the "-1.e6" factor ???
c
c         pvhn(ix,jy,kl,l)=dthetadp*(f+(dvdx/cosphi-dudy
c    +    +uuhn(ix,jy,kl,l)*tanphi)/r_earth)*(-1.e6)*9.81
          pvhn(ix,jy,kl,l)=dthetadp*( f + dvdx - dudy
     +    + (uuhn(ix,jy,kl,l)*tanphi/r_earth) )*(-1.e6)*9.81
C
C Resest jux and juy
          jux=jumpx
          juy=jumpy
12        continue
11        continue                                                            
10        continue
C
      end
