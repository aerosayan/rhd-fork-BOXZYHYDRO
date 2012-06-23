subroutine flux()
 use parameters
 use derived_types
 use grid_commons
 use utils
 implicit none

 real(pre),allocatable,dimension(:,:)::fluxtmp

 integer :: igrid,b(6),idim,flag
 real(pre)::fxl,fxr,fyt,fyb,fzt,fzb,areaxy,areayz,areaxz
 real(pre)::vol,v,f2,f1,f0,fm1,slopef,slopeb,left,right
 real(pre)::x,y,z,r,angmom,rmom,r_ang_min
 real(pre)::u1,u2,u0,um1,fleft,fright

 logical :: active,assoc_con
 type(units)::scale

 call get_units(scale)

 allocate(fluxtmp(5,ngrid))

!$OMP PARALLEL DEFAULT(SHARED) &
!$OMP&PRIVATE(areaxy,areayz,areaxz,u1,u2,u0,um1,fleft,fright) &
!$OMP&private(v,f2,f1,f0,fm1,slopef,slopeb,flag) &
!$OMP&private(fzt,fzb,fxr,fxl,fyt,fyb,left,right) &
!$OMP&private(b,active,angmom,rmom,x,y,z,r,assoc_con)

 areaxy=dy*dx
 areayz=dy*dz
 areaxz=dx*dz
 vol=dx*dy*dz
 assoc_con=associated(cons_pt,target=cons) ! if target is cons, don't double operate

!$OMP DO SCHEDULE(STATIC)
 do igrid=1,ngrid
  cons(5,igrid)=cons(5,igrid)+p(igrid)
 enddo
!$OMP ENDDO
 if(.not.assoc_con)then
!$OMP DO SCHEDULE(STATIC)
 do igrid=1,ngrid
  cons_pt(5,igrid)=cons_pt(5,igrid)+p(igrid)
 enddo
!$OMP ENDDO
 endif
 if(fluxangmom)then
!$OMP DO SCHEDULE(STATIC)
  do igrid=1,ngrid
     x=grid(igrid)%x;y=grid(igrid)%y+yoffset
     r=sqrt(x*x+y*y)
     angmom=x*cons(3,igrid)-y*cons(2,igrid)
     rmom=cons(2,igrid)*x/r+cons(3,igrid)*y/r
     cons(2,igrid)=rmom
     cons(3,igrid)=angmom
  enddo
!$OMP ENDDO
  if(.not.assoc_con)then
!$OMP DO SCHEDULE(STATIC) private(x,y,r,angmom,rmom)
   do igrid=1,ngrid
     x=grid(igrid)%x;y=grid(igrid)%y+yoffset
     r=sqrt(x*x+y*y)
     angmom=x*cons_pt(3,igrid)-y*cons_pt(2,igrid)
     rmom=cons_pt(2,igrid)*x/r+cons_pt(3,igrid)*y/r
     cons_pt(2,igrid)=rmom
     cons_pt(3,igrid)=angmom
   enddo
!$OMP ENDDO
  endif
 endif

!$OMP DO SCHEDULE(static)
 do igrid=1,ngrid

  if(grid(igrid)%anchor)cycle

  call get_boundary_wb(igrid,b,active)
  x=grid(igrid)%x;y=grid(igrid)%y+yoffset;z=grid(igrid)%z
  r=sqrt(x*x+y*y)

  do idim=1,5

      v=half*(u(2,igrid)+u(2,b(1)))

      u1=cons(idim,b(1))
      u0=cons(idim,igrid)
      um1=cons(idim,b(2))
      f1=u1*u(2,b(1))
      f0=u0*u(2,igrid)
      fm1=um1*u(2,b(2))

     flag=0
     if(grid(b(1))%anchor)then
#ifdef FREEFLOW
       v=u(2,igrid) 
       u2=u1
       f2=f1
#else
       v=zero
       f2=zero
       f1=zero
       u2=zero
       flag=1
#endif
     else
         u2=cons(idim,grid(b(1))%ineigh(1))
         f2=u2*u(2,grid(b(1))%ineigh(1))
     endif
 
#ifdef UPWIND
     fyt=v*upwind(u2,u1,u0,um1,v,dy,dt)
#else
#ifdef TCDIFFERENCE
     call left_right_states(f2,f1,f0,fm1,fleft,fright)
     call left_right_states(u2,u1,u0,um1,left,right)

     fyt=half*(fleft+fright)-abs(v)*(right-left)
#else
     stop"Unknown flux type"
#endif
#endif
     if(flag==1)fyt=zero

     v=-half*(u(2,igrid)+u(2,b(2)))

     u1=cons(idim,b(2))
     u0=cons(idim,igrid)
     um1=cons(idim,b(1))
     f1=-u1*u(2,b(2))
     f0=-u0*u(2,igrid)
     fm1=-um1*u(2,b(1))
     flag=0
     if(grid(b(2))%anchor)then
#ifdef FREEFLOW
       v=-u(2,igrid)
       f2=f1
       u2=u1
#else
       v=zero
       f1=zero
       f2=zero
       u2=zero
       flag=1
#endif
     else
       u2=cons(idim,grid(b(2))%ineigh(2))
       f2=-u2*u(2,grid(b(2))%ineigh(2))
     endif
       
#ifdef UPWIND
     fyb=v*upwind(u2,u1,u0,um1,v,dy,dt)
#else
#ifdef TCDIFFERENCE
     call left_right_states(f2,f1,f0,fm1,fleft,fright)
     call left_right_states(u2,u1,u0,um1,left,right)

     fyb=half*(fleft+fright)-abs(v)*(right-left)
#endif
#endif
     if(flag==1)fyb=zero

!!!!X 3 and 4

      v=half*(u(1,igrid)+u(1,b(3)))

      u1=cons(idim,b(3))
      u0=cons(idim,igrid)
      um1=cons(idim,b(4))
      f1=u1*u(1,b(3))
      f0=u0*u(1,igrid)
      fm1=um1*u(1,b(4))
 
     flag=0
     if(grid(b(3))%anchor)then
#ifdef FREEFLOW
       v=u(1,igrid) 
       f2=f1
       u2=u1
#else
       v=zero
       f2=zero
       f1=zero
       u2=zero
       flag=1
#endif
     else
         u2=cons(idim,grid(b(3))%ineigh(3))
         f2=u2*u(1,grid(b(3))%ineigh(3))
     endif
 
#ifdef UPWIND
     fxr=v*upwind(u2,u1,u0,um1,v,dx,dt)
#else
#ifdef TCDIFFERENCE
     call left_right_states(f2,f1,f0,fm1,fleft,fright)
     call left_right_states(u2,u1,u0,um1,left,right)

     fxr=half*(fleft+fright)-abs(v)*(right-left)
#endif
#endif
 
     if(flag==1)fxr=zero

     v=-half*(u(1,igrid)+u(1,b(4)))

     u1=cons(idim,b(4))
     u0=cons(idim,igrid)
     um1=cons(idim,b(3))
     f1=-u1*u(1,b(4))
     f0=-u0*u(1,igrid)
     fm1=-um1*u(1,b(3))

     flag=0
     if(grid(b(4))%anchor)then
#ifdef FREEFLOW
       v=-u(1,igrid)
       f2=f1
       u2=u1
#else
       v=zero
       f1=zero
       f2=zero
       u2=zero
       flag=1
#endif
     else
         u2=cons(idim,grid(b(4))%ineigh(4))
         f2=-u2*u(1,grid(b(4))%ineigh(4))
     endif
       

#ifdef UPWIND
     fxl=v*upwind(u2,u1,u0,um1,v,dx,dt)
#else
#ifdef TCDIFFERENCE
     call left_right_states(f2,f1,f0,fm1,fleft,fright)
     call left_right_states(u2,u1,u0,um1,left,right)

     fxl=half*(fleft+fright)-abs(v)*(right-left)
#endif
#endif
 
     if(flag==1)fxl=zero

!!!Z 5 and 6

      v=half*(u(3,igrid)+u(3,b(5)))

      u1=cons(idim,b(5))
      u0=cons(idim,igrid)
      um1=cons(idim,b(6))
      f1=u1*u(3,b(5))
      f0=u0*u(3,igrid)
      fm1=um1*u(3,b(6))
 
     flag=0
     if(grid(b(5))%anchor)then
#ifdef FREEFLOW
       v=u(3,igrid) 
       f2=f1
       u2=u1
#else
       v=zero
       f2=zero
       f1=zero
       u2=zero
       flag=1
#endif
     else
         u2=cons(idim,grid(b(5))%ineigh(5))
         f2=u2*u(3,grid(b(5))%ineigh(5))
     endif

#ifdef UPWIND
     fzt=v*upwind(u2,u1,u0,um1,v,dz,dt)
#else
#ifdef TCDIFFERENCE
     call left_right_states(f2,f1,f0,fm1,fleft,fright)
     call left_right_states(u2,u1,u0,um1,left,right)

     fzt=half*(fleft+fright)-abs(v)*(right-left)
#endif
#endif
     if(flag==1)fzt=zero

     v=-half*(u(3,igrid)+u(3,b(6)))

     u1=cons(idim,b(6))
     u0=cons(idim,igrid)
     um1=cons(idim,b(5))
     f1=-u1*u(3,b(6))
     f0=-u0*u(3,igrid)
     fm1=-um1*u(3,b(5))

     flag=0
     if(grid(b(6))%anchor)then
#ifdef FREEFLOW
       v=-u(3,igrid)
       f2=f1
       u2=u1
#else
       v=zero
       f1=zero
       f2=zero
       u2=zero
       flag=1
#endif
     else
         u2=cons(idim,grid(b(6))%ineigh(6))
         f2=-u2*u(3,grid(b(6))%ineigh(6))
     endif
       
#ifdef UPWIND
     fzb=v*upwind(u2,u1,u0,um1,v,dz,dt)
#else
#ifdef TCDIFFERENCE
     call left_right_states(f2,f1,f0,fm1,fleft,fright)
     call left_right_states(u2,u1,u0,um1,left,right)

     fzb=half*(fleft+fright)-abs(v)*(right-left)
#endif
#endif
     if(flag==1)fzb=zero

     fluxtmp(idim,igrid)=-( areaxy*(fzt+fzb)+areayz*(fxr+fxl)+areaxz*(fyt+fyb))&
                     /(vol)*dt
 enddo
 enddo
!$OMP ENDDO 
!$OMP BARRIER
!$OMP DO SCHEDULE(STATIC)
 do igrid=1,ngrid
  do idim=1,5
   cons_pt(idim,igrid)=cons_pt(idim,igrid)+fluxtmp(idim,igrid)
  enddo
 enddo
!$OMP ENDDO
 
!$OMP DO SCHEDULE(STATIC)
 do igrid=1,ngrid
  cons(5,igrid)=cons(5,igrid)-p(igrid)
  if(cons(5,igrid)<zero)then
    cons(5,igrid)=half*(cons(2,igrid)**2+cons(3,igrid)**2+cons(4,igrid)**2)/cons(1,igrid)
  endif
 enddo
!$OMP ENDDO
 if(.not.assoc_con)then
!$OMP DO SCHEDULE(STATIC)
 do igrid=1,ngrid
  cons_pt(1,igrid)=max(cons_pt(1,igrid),small_rho)
  cons_pt(5,igrid)=cons_pt(5,igrid)-p(igrid)
  if(cons_pt(5,igrid)<zero)then
    cons_pt(5,igrid)=half*(cons_pt(2,igrid)**2+cons_pt(3,igrid)**2+cons_pt(4,igrid)**2) &
                    /cons_pt(1,igrid)
  endif
 enddo
!$OMP ENDDO
 endif
 if(fluxangmom)then
!$OMP DO SCHEDULE(STATIC) private(x,y,r,angmom,rmom) !!!private(ekin)
 do igrid=1,ngrid
    x=grid(igrid)%x;y=grid(igrid)%y+yoffset
    r=sqrt(x*x+y*y)
    angmom=cons(3,igrid)
    rmom=cons(2,igrid)
    cons(3,igrid)=(rmom*y+x*angmom/r)/(x*x/r+y*y/r) 
    if(y==zero)then
      cons(2,igrid)=(rmom-y/r*cons(3,igrid))*r/x
    else
      cons(2,igrid)=(x*cons(3,igrid)-angmom)/y
    endif
 enddo
!$OMP ENDDO
 if(.not.assoc_con)then
!$OMP DO SCHEDULE(STATIC) private(x,y,r,angmom,rmom) !!!private(ekin)
 do igrid=1,ngrid
    x=grid(igrid)%x;y=grid(igrid)%y+yoffset
    r=sqrt(x*x+y*y)
    cons_pt(1,igrid)=max(cons_pt(1,igrid),small_rho)
    if(r>=r_ang_min)then
     angmom=cons_pt(3,igrid)
     rmom=cons_pt(2,igrid)
     cons_pt(3,igrid)=(rmom*y+x*angmom/r)/(x*x/r+y*y/r) 
     if(y==zero)then
       cons_pt(2,igrid)=(rmom-y/r*cons_pt(3,igrid))*r/x
     else
       cons_pt(2,igrid)=(x*cons_pt(3,igrid)-angmom)/y
     endif
    endif
 enddo
!$OMP ENDDO NOWAIT
 endif
 endif
 
!$OMP DO SCHEDULE(STATIC)
  do igrid=1,nbound
#ifdef FREEFLOW
    !print *, "unsupported at the moment"
    !stop
    cons_pt(1,indx_bound(igrid))=small_rho
    cons_pt(2,indx_bound(igrid))=zero 
    cons_pt(3,indx_bound(igrid))=zero 
    cons_pt(4,indx_bound(igrid))=zero 
    cons_pt(5,indx_bound(igrid))=small_eps

#else
    cons_pt(1,indx_bound(igrid))=small_rho
    cons_pt(2,indx_bound(igrid))=zero 
    cons_pt(3,indx_bound(igrid))=zero 
    cons_pt(4,indx_bound(igrid))=zero 
    cons_pt(5,indx_bound(igrid))=small_eps
#endif
  enddo
!$OMP ENDDO

#ifdef EXTRAANCHORS

!$OMP DO SCHEDULE(STATIC)
  do igrid=1,nanchor
#ifdef FREEFLOW
    !print *, "unsupported at the moment"
    !stop
    cons_pt(1,indx_anchor(igrid))=small_rho
    cons_pt(2,indx_anchor(igrid))=zero 
    cons_pt(3,indx_anchor(igrid))=zero 
    cons_pt(4,indx_anchor(igrid))=zero 
    cons_pt(5,indx_anchor(igrid))=small_eps

#else
    cons_pt(1,indx_anchor(igrid))=small_rho
    cons_pt(2,indx_anchor(igrid))=zero 
    cons_pt(3,indx_anchor(igrid))=zero 
    cons_pt(4,indx_anchor(igrid))=zero 
    cons_pt(5,indx_anchor(igrid))=small_eps
#endif
  enddo
!$OMP ENDDO

#endif

!$OMP END PARALLEL

 deallocate(fluxtmp)

!deallocate(ekin,ekin_old)

end subroutine