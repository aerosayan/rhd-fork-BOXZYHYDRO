! Written by Nora Bolig (updated 19 Nov 2010)
! See Pathria for questions.  This uses E=NkT^2 d ln Z /d T to calculate internal energies.
! However, the zero point energies are subtracted out (relevant for orthohydrogen
! and for the vibrational states).  The 16.78 in the metals
! term is from cameron 1968. This takes into account rotational states for 
! hydrogen and 1 vibrational state. zp is the parahydrogen partition function
! and dzpdt and ddzpdtt are its derivatives, *e for equilibrium, and *o for ortho.
! Updated again throughout 2011.  Now contains dissociation of molecular hydrogen.
module eos
 use parameters
 use derived_types
 use grid_commons
 implicit none

 type(units)::scl
 real(pre)::eul,log_rho_eos_low
 real(pre),parameter::kb=1.38065d-16
 real(pre),parameter::hplanck=6.626d-27
 real(pre),parameter::clight=3d10
 real(pre),parameter::melec=9.10934d-28
 integer::NEOS

 contains

!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Initialize the EOS, including all tables.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine initialize_eos()

     call get_units(scl)
     NEOS_T=int((tk_eos_cutoff-tk_bgrnd)/dTk_eos)+1
     drho_eos=(log10(rho_eos_high)-log10(rho_eos_low))/(NEOS_RHO-1)
     print *,"NEOS_T for large table  = ",NEOS_T
     print *,"drho_eos for large table = ",drho_eos
     NEOS=NEOS_T

     allocate(gamma_table(NEOS_T,NEOS_RHO))
     allocate(gamma_table2(NEOS_T,NEOS_RHO))
     allocate(eng_table(NEOS_T,NEOS_RHO))
     allocate(eng_table2(NEOS_T,NEOS_RHO))
     allocate(tk_table(NEOS_T))
     allocate(p_table(NEOS_T,NEOS_RHO))
     allocate(tk_table2(NEOS_T,NEOS_RHO))
     allocate(rho_table(NEOS_RHO))
     allocate(muc_table(NEOS_T,NEOS_RHO))
     allocate(muc_table2(NEOS_T,NEOS_RHO))
     allocate(deng_eos_array(NEOS_RHO))

   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Clean up memory.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine clean_eos()
     deallocate(gamma_table,tk_table,eng_table,gamma_table2,eng_table2,tk_table2,muc_table,muc_table2,rho_table)
   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Full partition function for H2, excluding translation.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine h2_partition(t,zp,zo,ze,zoprime,dzpdt,dzodt,dzedt,dzoprimedt)
     real(pre),intent(in)::t
     real(pre),intent(out)::zp,zo,ze,zoprime,dzpdt,dzodt,dzedt,dzoprimedt
     real(pre)::f1,f2,f3,f4,sumo,sump,erro,errp
     integer::j
     zp=zero
     zo=zero
     ze=zero
     zoprime=zero 
     sumo=zero
     sump=zero
     dzpdt=zero
     dzodt=zero
     dzedt=zero
     dzoprimedt=zero
     do j=0,100,2
       f1=dble(2*j+1)
       f2=dble(j*(j+1))
       f3=dble(2*(j+1)+1)
       f4=dble((j+1)*(j+2))
       zp=zp+f1*exp(-f2*brot/t)
       zo=zo+three*f3*exp(-f4*brot/t)
       zoprime=zoprime+three*f3*exp(-(f4-two)*brot/t)
       dzpdt=dzpdt+f1*f2*brot*exp(-f2*brot/t)/t**2
       dzodt=dzodt+three*f3*f4*brot*exp(-f4*brot/t)/t**2
       dzoprimedt=dzoprimedt+three*f3*(f4-two)*brot*exp(-(f4-two)*brot/t)/t**2
       erro=(abs(sumo-zo)/zo)
       errp=(abs(sump-zp)/zp)
       if ( erro < 1d-33 .and. errp < 1d-33 )exit
       sumo=zo
       sump=zp
     enddo
     !print *,"Iterations for j in internal partion H2",j,erro,errp
     ze=zp+zo
     dzedt=dzpdt+dzodt
     return
   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! General function for translational partition function
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   real(pre) function translate(m,t,n)
     real(pre)::m,t,n
     translate=eul*(sqrt(two*pi*m*mp*kB*t/hplanck**2))**3/n
     return
   end function
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Debroglie wavelength
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   real(pre) function debroglie(m,t)
     real(pre)::m,t
     debroglie=hplanck/sqrt(two*pi*m*mp*kB*t)
     return
   end function
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Main function for generating the EOS tables.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine calc_eos_table()
     real(pre)::t0,tm,tp,denm,denp,den0,logdenp,logdenm,logden0
     real(pre)::logt0,logtm,gamu=zero,gaml=zero,xh1,apot
     real(pre)::zp,zo,ze,dzpdt,dzodt,dzedt,zoprime,dzoprimedt
     real(pre)::nh,nh2,nhe,nz,trans_h,trans_he,trans_h2,trans_z,zh2_int,rhs
     real(pre)::trans_e,mebymp,xionize,press_p,press_m,chiT,chiR,cv
     real(pre)::den,gam,s0,s1,s2,s3,tk,log_eng_low

     real(pre),dimension(:),allocatable::xh1_a,xionize_a
     real(pre),dimension(:,:),allocatable::sent,report_table

     integer i,irho,itk,irhop,irhom,irho_m,irho_p,itk_m,itk_p

     call get_units(scl)
     !eul=exp(one)
     eul=one
   
     muc = one/(xabun*half + yabun*quarter + zabun/mu_z)
!
!
#ifdef VERBOSE
     print *, "muc is:", muc
#endif
!
!
     allocate(sent(NEOS_T,NEOS_RHO))
     allocate(report_table(NEOS_T,NEOS_RHO))
     allocate(xh1_a(NEOS_T))
     allocate(xionize_a(NEOS_T))

     do i = 1,NEOS_T
       tk_table(i)=tk_bgrnd + dble(i-1)*dTk_eos
     enddo
     log_rho_eos_low=log10(rho_eos_low)
     do i = 1,NEOS_RHO
       rho_table(i)=ten**(log_rho_eos_low+dble(i-1)*drho_eos)
     enddo
!
!***
! we've done the easy part.  Now we need to make the large table. 
! Same idea, but must be done for each rho and for each.
!***
!
     mebymp=melec/mp
     xionize_a=zero
     do irho=1,NEOS_RHO
       den=rho_table(irho)
       nh=xabun*den/(mp)
       nh2=nh*half
       nhe=yabun*den/(four*mp)
       nz=zabun*den/(mu_z*mp)
    
       select case(H2STAT)
       case(0) ! fixed ortho-para ratio
         do itk=1,NEOS_T
           tk=tk_table(itk) 
           trans_he=one
           trans_z=one
      
           trans_h=translate(one,tk,nh)
           trans_h2=translate(two,tk,nh2)
           trans_e=translate(mebymp,tk,nh)
           if(yabun>zero)trans_he=translate(four,tk,nhe)
           if(zabun>zero)trans_z=translate(mu_z,tk,nz)
            
           call h2_partition(tk,zp,zo,ze,zoprime,dzpdt,dzodt,dzedt,dzoprimedt)

           zh2_int=zp**(ac/(ac+bc))*zoprime**(bc/(ac+bc))/(one-exp(-vib/tk))

           xh1=half*translate(half,tk,nh) * exp(-diss/tk)/zh2_int ! See Tatum 1966
           if (xh1>1d8)then
             xh1=one
           else
              xh1=-half*xh1 + half*sqrt(xh1**2+4*xh1)
           endif
           xh1_a(itk) = xh1


           xionize=trans_e * exp(-ionize/tk)
           if(xionize>1d8)then
             xionize=one
           else
             xionize = -half*xionize + half*sqrt(xionize*xionize+4*xionize)
           endif
           xionize_a(itk) = xionize
           
           eng_table(itk,irho)=rgasCGS*tk*(xabun* ( xh1*(1.5d0 &
               + xionize*1.5d0) & 
               + half*(one-xh1)*(1.5d0+tk*(ac/(ac+bc)*dzpdt/zp+bc/(ac+bc)*(dzoprimedt/zoprime) &
               + vib/tk**2*exp(-vib/tk)/(one-exp(-vib/tk)) ) ) ) &
               + yabun*0.25d0*1.5d0 + zabun*1.5d0/mu_z) &
               + rgasCGS*xabun*xh1*(xionize*ionize+half*diss)
! for the electron component, we divide by mebymp for the mean molecular weight, but then multiply by mebymp for the mass abundance ratio.  As such, they term appears to not be scaled.
           apot=-rgasCGS*tk*( xabun * ( xh1*(log(trans_h) &
               + xionize*log(trans_e) ) + &
              half*(one-xh1)*( log(trans_h2) + ac/(ac+bc)*log(zp) + bc/(ac+bc)*log(zoprime) &
              - log(one-exp(-vib/tk))) ) + yabun*0.25d0*log(trans_he) + zabun*log(trans_z)/mu_z) &
              + rgasCGS*xabun*xh1*(xionize*ionize+half*diss)
           sent(itk,irho)=(eng_table(itk,irho)-apot)/tk
         enddo
!
       case(1) ! equilibrium ratio
!
         do itk=1,NEOS_T
           tk=tk_table(itk) 
           trans_he=one
           trans_z=one
      
           trans_h=translate(one,tk,nh)
           trans_e=translate(mebymp,tk,nh)
           trans_h2=translate(two,tk,nh2)
           if(yabun>zero)trans_he=translate(four,tk,nhe)
           if(zabun>zero)trans_z=translate(mu_z,tk,nz)
            
           call h2_partition(tk,zp,zo,ze,zoprime,dzpdt,dzodt,dzedt,dzoprimedt)

           zh2_int=ze/(one-exp(-vib/tk))

           xh1=half*translate(half,tk,nh) * exp(-diss/tk)/zh2_int
           if (xh1>1d8)then
             xh1=one
           else
              xh1=-half*xh1 + half*sqrt(xh1**2+4*xh1)
           endif
           xh1_a(itk) = xh1


           xionize=trans_e * exp(-ionize/tk)
           if(xionize>1d8)then
             xionize=one
           else
             xionize = -half*xionize + half*sqrt(xionize*xionize+4*xionize)
           endif
           xionize_a(itk) = xionize
           
           eng_table(itk,irho)=rgasCGS*tk*(xabun* ( xh1*(1.5d0+half*diss/tk  &
               +  xionize*ionize/tk + xionize*1.5d0 ) &
               + half*(one-xh1)*(1.5d0+tk*(dzedt/ze &
               + vib/tk**2*exp(-vib/tk)/(one-exp(-vib/tk)) ) ) ) &
               + yabun*0.25d0*1.5d0 + zabun*1.5d0/mu_z)
           apot=-rgasCGS*tk*( xabun * ( xh1*(log(trans_h)-half*diss/tk &
              - xionize*ionize/tk + xionize*log(trans_e)) + &
              half*(one-xh1)*( log(trans_h2) + log(ze)     &
              - log(one-exp(-vib/tk))) ) + yabun*0.25d0*log(trans_he) + zabun*log(trans_z)/mu_z)
           sent(itk,irho)=(eng_table(itk,irho)-apot)/tk
         enddo
!
       case(-1) ! Single gamma.  Generating table for completeness, but it is not used.
!
         do itk =1,NEOS_T
           tk=tk_table(itk) 
           eng_table(itk,irho)=rgasCGS*tk/(gammafix-one)/muc
           apot=-rgasCGS*tk/muc
           xh1_a(itk)=one
           sent(itk,irho)=(eng_table(itk,irho)-apot)/tk
           gamma_table(itk,irho)=gammafix
         enddo
       end select
       do itk=1,NEOS_T
         muc_table(itk,irho)=(one/(xabun*(one-half*(one-xh1_a(itk))+ xionize_a(itk)) &
                            + yabun*0.25d0 + zabun/mu_z))
         report_table(itk,irho)=xh1_a(itk)
       enddo
     enddo ! loop over density 
!
!***
! This part is a pain, but it is a straight-forward way to derive the adiabatic index
!***
!

      if(H2STAT>=0)then
        do irho=1,NEOS_RHO
           if (irho==1)then
             irho_m=1
           else   
             irho_m=irho-1
           endif
           if (irho==NEOS_RHO)then
             irho_p = NEOS_RHO
           else
             irho_p = irho+1
           endif
 
           do itk=1,NEOS_T

             if(itk==1)then
               itk_m = 1
             else
               itk_m = itk-1
             endif
             if(itk==NEOS_T)then
               itk_p=NEOS_T
             else
               itk_p=itk+1
             endif

             chiT = one -tk_table(itk)* (muc_table(itk_p,irho)-muc_table(itk_m,irho)) &
                        / ( muc_table(itk,irho)*(tk_table(itk_p)-tk_table(itk_m)) )

             chiR = one -rho_table(irho)* (muc_table(itk,irho_p)-muc_table(itk,irho_m)) &
                        / ( muc_table(itk,irho)*(rho_table(irho_p)-rho_table(irho_m)) )


!             press_p = rho_table(irho)*tk_table(itk_p)*rgasCGS/muc_table(itk_p,irho)
!             press_m = rho_table(irho)*tk_table(itk_m)*rgasCGS/muc_table(itk_m,irho) 

              
!             gamma_table(itk,irho) = one + ( press_p - press_m )/ ( rho_table(irho) &
!                                         * ( eng_table(itk_p,irho)-eng_table(itk_m,irho) )  )

             cv = (eng_table(itk_p,irho)-eng_table(itk_m,irho))/(tk_table(itk_p)-tk_table(itk_m))

             ! gamma3 gamma_table(itk,irho) = one + rgasCGS*chiT/(cv*muc_table(itk,irho))
!gamma1
             gamma_table(itk,irho) = rgasCGS*chiT/(cv*muc_table(itk,irho)) * chiT + chiR

          enddo
        enddo

      endif


!     if(H2STAT>=0)then
!     do irho=1,NEOS_RHO
!       irhop=min(irho+1,NEOS_RHO)
!       irhom=max(irho-1,1)
!       den0=rho_table(irho)
!       logden0=log(den0)
!       denm=rho_table(irhom)
!       logdenm=log(denm)
!       denp=rho_table(irhop)
!       logdenp=log(denp)
!       
!       if(irho==1)then
!         do itk=1,NEOS_T
!           if(itk<NEOS_T)then
!             s0=sent(itk,irho)
!             s1=sent(itk,irhop)
!             s2=sent(itk+1,irho)
!             s3=sent(itk+1,irhop)
!             t0=tk_table(itk)
!             logt0=log(t0)
!             tp=(s0-s1)*( log(tk_table(itk+1))-logt0)/(s3-s1)+logt0
!             if (s1 < s0 .and. s0 < s3)then
!              gam=one+(tp-logt0)/(logdenp-logden0)
!             else
!              tp=tk_table(itk+1)
!              den=(s0-s2)*(logdenp-logden0)/(s3-s2)+logden0
!              gam=one+(log(tp)-logt0)/(den-logden0)
!             endif
!           else
!             s0=sent(itk-1,irho)
!             s1=sent(itk-1,irhop)
!             s2=sent(itk,irho)
!             s3=sent(itk,irhop)
!             t0=tk_table(itk-1)
!             logt0=log(t0)
!             tp=(s0-s1)*( log(tk_table(itk))-logt0)/(s3-s1)+logt0
!             if (s1 < s0 .and. s0 < s3)then
!              gam=one+(tp-logt0)/(logdenp-logden0)
!             else
!              tp=tk_table(itk)
!              den=(s0-s2)*(logdenp-logden0)/(s3-s2)+logden0
!              gam=one+(log(tp)-logt0)/(den-logden0)
!             endif
!           endif
!           gamma_table(itk,irho)=gam
!         enddo     
!         cycle ! cycle rho
!       endif
!       if(irho==NEOS_RHO)then
!         do itk=1,NEOS_T
!          if(itk<NEOS_T)then
!            s0=sent(itk,irhom)
!            s1=sent(itk,irho)
!            s2=sent(itk+1,irhom)
!            s3=sent(itk+1,irho)
!            t0=tk_table(itk+1)
!            tm=tk_table(itk)
!            logt0=log(t0)
!            logtm=log(tm)
!            tp=logtm-(s1-s0)*(logt0-logtm)/(s2-s0)
!            if(s1<s0.and.s0<s3)then
!              gam=one+(tp-logtm)/(logden0-logdenm)
!            else
!              den=logdenm-(s3-s1)*(logdenm-logden0)/(s0-s1)
!              gam=one+(logt0-logtm)/(den-logdenm)
!            endif
!          else
!            s3=sent(itk,irho)
!            s1=sent(itk-1,irho)
!            s0=sent(itk-1,irhom)
!            s2=sent(itk,irhom)
!            t0=tk_table(itk)
!            tm=tk_table(itk-1)
!            logt0=log(t0)
!            logtm=log(tm)
!            tp=logtm-(s3-s2)*(logtm-logt0)/(s0-s2)
!            if(s0<s3.and.s3<s2)then
!              gam=one+(tp-logtm)/(logden0-logdenm)
!            else
!              den=logdenm-(s3-s1)*(logdenm-logden0)/(s0-s1)
!              gam=one+(logt0-logtm)/(den-logdenm)
!            endif
!          endif
!          gamma_table(itk,irho)=gam
!         enddo
!         cycle ! cycle rho
!       endif
!       do itk=1,NEOS_T
!          if(itk<NEOS_T)then
!            s0=sent(itk,irho)
!            s1=sent(itk,irhop)
!            s2=sent(itk+1,irho)
!            s3=sent(itk+1,irhop)
!            t0=tk_table(itk)
!            logt0=log(t0)
!            tp=(s0-s1)*(log(tk_table(itk+1))-logt0)/(s3-s1)+logt0
!            if(s1<s0.and.s0<s3)then
!              gamu=one+(tp-logt0)/(logdenp-logden0) 
!            else
!              tp=tk_table(itk+1)
!              den=(s0-s2)*(logdenp-logden0)/(s3-s2)+logden0
!              gamu=one+(log(tp)-logt0)/(den-logden0)
!            endif
!          endif
!          if(itk>1)then
!            s3=sent(itk,irho)
!            s1=sent(itk-1,irho)
!            s0=sent(itk-1,irhom)
!            s2=sent(itk,irhom)
!            t0=tk_table(itk)
!            tm=tk_table(itk-1)
!            logt0=log(t0)
!            logtm=log(tm)
!            tp=logtm-(s3-s2)*(logtm-logt0)/(s0-s2)
!            if(s1<s0.and.s0<s3)then
!              gaml=one+(tp-logtm)/(logden0-logdenm) 
!            else
!              den=logdenm-(s3-s1)*(logdenm-logden0)/(s0-s1)
!              gaml=one+(logt0-logtm)/(den-logdenm)
!            endif
!          endif
!          if(itk<NEOS_T.and.itk>1)then 
!            gam=half*(gamu+gaml)
!          elseif(itk<NEOS_T)then
!            gam=gamu
!          else
!            gam=gaml
!          endif
!          gamma_table(itk,irho)=gam 
!       enddo
!     enddo
!     endif
!
!
#ifdef VERBOSE
  print *, "H2STAT set to ",H2STAT
  print *, "#EOS table initialized.  XABUN, YABUN, ZABUN, MU_Z, MUC ",xabun,yabun,zabun,mu_z,muc
#endif
!
!
     gamma_table(:,1)=gamma_table(:,2)
     gamma_table(:,NEOS_RHO)=gamma_table(:,NEOS_RHO-1)
     do irho=1,NEOS_RHO
      deng_eos=(log10(eng_table(NEOS_T,irho))-log10(eng_table(1,irho)))/dble(NEOS_T-1)
      deng_eos_array(irho)=deng_eos
      log_eng_low=log10(eng_table(1,irho))
      do itk=1,NEOS_T
        eng_table2(itk,irho)=ten**(log_eng_low+dble(itk-1)*deng_eos)
        call get_gamma_norho(eng_table2(itk,irho),tk_table2(itk,irho), &
                 muc_table2(itk,irho),gamma_table2(itk,irho),irho)
      enddo
     enddo

     open(unit=102,file="eostable.dat")
     do irho=1,NEOS_RHO
      write(102,"(A,1X,1pe15.8)")"#den: ",rho_table(irho)
      do itk=1,NEOS_T
        p_table(itk,irho)=rho_table(irho)/scl%density*scl%rgas*tk_table(itk)/muc_table(itk,irho)
        write(102,"(11(1X,1pe15.8))")rho_table(irho),tk_table(itk), &
              eng_table(itk,irho),muc_table(itk,irho),gamma_table(itk,irho), &
              tk_table2(itk,irho),eng_table2(itk,irho),muc_table2(itk,irho),gamma_table2(itk,irho),p_table(itk,irho),&
              report_table(itk,irho)
        eng_table(itk,irho)=eng_table(itk,irho)*(scl%time/scl%length)**2
        eng_table2(itk,irho)=eng_table2(itk,irho)*(scl%time/scl%length)**2
      enddo
      rho_table(irho)=rho_table(irho)/scl%density
     enddo
     close(102)

     deallocate(sent)

   end subroutine calc_eos_table
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! The following functions are used to interpolate from the tables
! to find the appropriate quantites.  Sometimes the lookup is done
! starting from the energy, but it can also use temperature. In tables
! without a number, the standard lookup is done in energy space.
! For functions with a number 2, the lookup is done in temperature space.
! The first of these does not take the density as an argument, and instead
! takes the density column integer.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine get_gamma_norho(eng,tk,m,gam,irho)
    real(pre)::eng,tk,gam,m
    integer::ientry,jump,flag,inext,irho
    
    ientry=1
    jump=NEOS/4 ! we are usually at low T, so take a small jump.
    flag=0
    do
      inext=min(ientry+1,NEOS)
      if(eng_table(ientry,irho)<=eng.and.eng<eng_table(inext,irho))exit
      if(eng_table(ientry,irho)>eng)then
        ientry=ientry-jump
        jump=max(int(jump*.75),1)
        if(ientry<1)then
          ientry=1
          if(eng<=eng_table(ientry,irho))then
            flag=1
            exit
          endif
        endif
      else
        ientry=ientry+jump
        jump=max(int(jump*.75),1)
        if(ientry>NEOS-1)then
         ientry=NEOS-1
         if(eng>=eng_table(ientry,irho))then
            flag=2
            exit
         endif
        endif
      endif
    enddo
   if(flag>1)then
     eng=eng_table(NEOS,irho)
   elseif(flag>0)then
     eng=eng_table(1,irho)
   endif
   tk=tk_table(ientry)+(tk_table(ientry+1)-tk_table(ientry)) &
     /(eng_table(ientry+1,irho)-eng_table(ientry,irho))*(eng-eng_table(ientry,irho))
   gam=gamma_table(ientry,irho)+(gamma_table(ientry+1,irho)-gamma_table(ientry,irho)) &
     /(eng_table(ientry+1,irho)-eng_table(ientry,irho))*(eng-eng_table(ientry,irho))
   m=muc_table(ientry,irho)+(muc_table(ientry+1,irho)-muc_table(ientry,irho)) &
     /(eng_table(ientry+1,irho)-eng_table(ientry,irho))*(eng-eng_table(ientry,irho))
   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Get gamma from energy
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine get_gamma(eps,rho,tk,m,gam)
    real(pre)::eng,tk,gam,eps,rho,m,slope,mp,gamp,tkp
    integer::ientry,jump,flag,inext,irho,irhop
    
    irho=min(int( (log10(rho*scl%density)-log_rho_eos_low)/drho_eos) + 1 ,NEOS_RHO)
    if(irho<1)irho=1
    irhop=irho+1
    if(irhop>NEOS_RHO)irhop=irho
 
    eng=eps/rho
    ientry=1
    jump=NEOS/4 ! we are usually at low T, so take a small jump.
    flag=0
    do
      inext=min(ientry+1,NEOS)
      if(eng_table(ientry,irho)<=eng.and.eng<eng_table(inext,irho))exit
      if(eng_table(ientry,irho)>eng)then
        ientry=ientry-jump
        jump=max(int(jump*.75),1)
        if(ientry<1)then
          ientry=1
          if(eng<=eng_table(ientry,irho))then
            flag=1
            exit
          endif
        endif
      else
        ientry=ientry+jump
        jump=max(int(jump*.75),1)
        if(ientry>NEOS-1)then
         ientry=NEOS-1
         if(eng>=eng_table(ientry,irho))then
            flag=2
            exit
         endif
        endif
      endif
    enddo
   if(flag>1)then
     eng=eng_table(NEOS,irho)
     eps=eng*rho ! note that this does change the energy
   elseif(flag>0)then
     eng=eng_table(1,irho)
     eps=eng*rho ! note that this does change the energy
   endif
   tk=tk_table(ientry)+(tk_table(ientry+1)-tk_table(ientry)) &
     /(eng_table(ientry+1,irho)-eng_table(ientry,irho))*(eng-eng_table(ientry,irho))
   gam=gamma_table(ientry,irho)+(gamma_table(ientry+1,irho)-gamma_table(ientry,irho)) &
     /(eng_table(ientry+1,irho)-eng_table(ientry,irho))*(eng-eng_table(ientry,irho))
   m=muc_table(ientry,irho)+(muc_table(ientry+1,irho)-muc_table(ientry,irho)) &
     /(eng_table(ientry+1,irho)-eng_table(ientry,irho))*(eng-eng_table(ientry,irho))

   if(.not.(rho_table(irho)==rho_table(irhop)))then
      gamp=gamma_table(ientry,irhop)+(gamma_table(ientry+1,irhop)-gamma_table(ientry,irhop))&
            /(eng_table(ientry+1,irhop)-eng_table(ientry,irhop))*(eng-eng_table(ientry,irhop))
      mp=muc_table(ientry,irhop)+(muc_table(ientry+1,irhop)-muc_table(ientry,irhop))&
            /(eng_table(ientry+1,irhop)-eng_table(ientry,irhop))*(eng-eng_table(ientry,irhop))
      tkp=tk_table(ientry)+(tk_table(ientry+1)-tk_table(ientry))&
            /(eng_table(ientry+1,irhop)-eng_table(ientry,irhop))*(eng-eng_table(ientry,irhop))

      slope=one/(rho_table(irhop)-rho_table(irho))*(rho-rho_table(irho))
      gam=gam+(gamp-gam)*slope
      m=m+(mp-m)*slope
      tk=tk+(tkp-tk)*slope
   endif

   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Get gamma from energy with temperature spacing
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine get_gamma2(eps,rho,tk,m,gam)
    real(pre)::eng,tk,gam,eps,rho,m,mp,tkp,gamp,slope
    integer::ientry,irho,irhop
 
    irho=min(int( (log10(rho*scl%density)-log_rho_eos_low)/drho_eos) + 1 ,NEOS_RHO)
    if(irho<1)irho=1
    irhop=irho+1
    if(irhop>NEOS_RHO)irhop=irho

    eng=eps/rho
    !print *, rho,eng,eps,irho
    ientry=int( (log10(eng)-log10(eng_table2(1,irho)))/deng_eos_array(irho)) + 1
    if (ientry>NEOS-1)then
         ientry=NEOS-1
         eng=eng_table2(NEOS,irho)
         eps=eng*rho
    endif
    if(ientry<1.or.eng<eng_table2(1,irho))then
      !print *, rho,eng,eps,irho
        ientry=1
        eng=eng_table2(1,irho)
        eps=eng*rho
    endif
   
    gam=gamma_table2(ientry,irho)+(gamma_table2(ientry+1,irho)-gamma_table2(ientry,irho))&
            /(eng_table2(ientry+1,irho)-eng_table2(ientry,irho))*(eng-eng_table2(ientry,irho))
    m=muc_table2(ientry,irho)+(muc_table2(ientry+1,irho)-muc_table2(ientry,irho))&
            /(eng_table2(ientry+1,irho)-eng_table2(ientry,irho))*(eng-eng_table2(ientry,irho))
    tk=tk_table2(ientry,irho)+(tk_table2(ientry+1,irho)-tk_table2(ientry,irho))&
            /(eng_table2(ientry+1,irho)-eng_table2(ientry,irho))*(eng-eng_table2(ientry,irho))

    if(.not.(rho_table(irho)==rho_table(irhop)))then
      gamp=gamma_table2(ientry,irhop)+(gamma_table2(ientry+1,irhop)-gamma_table2(ientry,irhop))&
            /(eng_table2(ientry+1,irhop)-eng_table2(ientry,irhop))*(eng-eng_table2(ientry,irhop))
      mp=muc_table2(ientry,irhop)+(muc_table2(ientry+1,irhop)-muc_table2(ientry,irhop))&
            /(eng_table2(ientry+1,irhop)-eng_table2(ientry,irhop))*(eng-eng_table2(ientry,irhop))
      tkp=tk_table2(ientry,irhop)+(tk_table2(ientry+1,irhop)-tk_table2(ientry,irhop))&
            /(eng_table2(ientry+1,irhop)-eng_table2(ientry,irhop))*(eng-eng_table2(ientry,irhop))

      slope=one/(rho_table(irhop)-rho_table(irho))*(rho-rho_table(irho))
      gam=gam+(gamp-gam)*slope
      m=m+(mp-m)*slope
      tk=tk+(tkp-tk)*slope
    endif


   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Get gamma from temperature.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine get_gamma_from_tk(eps,rho,tk,m,gam)
    real(pre)::tk,gam,eps,rho,m,slope,mp,epsp,gamp
    integer::ientry,irho,irhop
  
    irho=min(int( (log10(rho*scl%density)-log_rho_eos_low)/drho_eos) + 1 ,NEOS_RHO)
    if(irho<1)irho=1
    irhop=irho+1
    if(irhop>NEOS_RHO)irhop=irho
   
    ientry=int( (tk-tk_bgrnd)/dTk_eos)+1
    if (ientry>NEOS-1)ientry=NEOS-1
    if(ientry<1)ientry=1
 
    eps=rho*(eng_table(ientry,irho)+(eng_table(ientry+1,irho)-eng_table(ientry,irho))/dTK_eos*(tk-tk_table(ientry)))
    gam=(gamma_table(ientry,irho)+(gamma_table(ientry+1,irho)-gamma_table(ientry,irho))/dTK_eos*(tk-tk_table(ientry)))
    m=(muc_table(ientry,irho)+(muc_table(ientry+1,irho)-muc_table(ientry,irho))/dTK_eos*(tk-tk_table(ientry)))
    if(.not.(rho_table(irho)==rho_table(irhop)))then
       epsp=rho*(eng_table(ientry,irhop)+(eng_table(ientry+1,irhop)-eng_table(ientry,irhop))/dTK_eos*(tk-tk_table(ientry)))
       gamp=(gamma_table(ientry,irhop)+(gamma_table(ientry+1,irhop)-gamma_table(ientry,irhop))/dTK_eos*(tk-tk_table(ientry)))
       mp=(muc_table(ientry,irhop)+(muc_table(ientry+1,irhop)-muc_table(ientry,irhop))/dTK_eos*(tk-tk_table(ientry)))
 
       slope=one/(rho_table(irhop)-rho_table(irho))*(rho-rho_table(irho))
       gam=gam+(gamp-gam)*slope
       m=m+(mp-m)*slope
       eps=eps+(epsp-eps)*slope
    endif

   end subroutine
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Get gamma from pressure
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   subroutine get_gamma_from_p(eps,rho,p_loc,m,gam)
    real(pre)::p_loc,gam,eps,rho,m
    integer::ientry,jump,flag,inext,irho,i,irhop,irho0
    real(pre)::eps0,eps1,m0,m1,gam0,gam1
    
    irho0=min(int( (log10(rho*scl%density)-log_rho_eos_low)/drho_eos) + 1 ,NEOS_RHO)
    if(irho0<1)irho0=1
    irhop=min(irho0+1,NEOS_RHO)
    m0=zero
    gam0=zero
    eps0=zero
    m1=zero
    gam1=zero
    eps1=zero
 
    do i=1,2
    irho=irho0
    if(i==2)irho=irhop
    ientry=1
    jump=NEOS/4 ! we are usually at low T, so take a small jump.
    flag=0
    do
      inext=min(ientry+1,NEOS)
      if(p_table(ientry,irho)<=p_loc.and.p_loc<p_table(inext,irho))exit
      if(p_table(ientry,irho)>p_loc)then
        ientry=ientry-jump
        jump=max(int(jump*.75),1)
        if(ientry<1)then
          ientry=1
          if(p_loc<=p_table(ientry,irho))then
            flag=1
            exit
          endif
        endif
      else
        ientry=ientry+jump
        jump=max(int(jump*.75),1)
        if(ientry>NEOS-1)then
         ientry=NEOS-1
         if(p_loc>=p_table(ientry,irho))then
            flag=2
            exit
         endif
        endif
      endif
    enddo
   if(flag>1)then
     p_loc=p_table(NEOS,irho)
   elseif(flag>0)then
     p_loc=p_table(1,irho)
   endif
   select case(i)
   case(1)
   eps0=eng_table(ientry,irho)+(eng_table(ientry+1,irho)-eng_table(ientry,irho)) &
     /(p_table(ientry+1,irho)-p_table(ientry,irho))*(p_loc-p_table(ientry,irho))
   gam0=gamma_table(ientry,irho)+(gamma_table(ientry+1,irho)-gamma_table(ientry,irho)) &
     /(p_table(ientry+1,irho)-p_table(ientry,irho))*(p_loc-p_table(ientry,irho))
   m0=muc_table(ientry,irho)+(muc_table(ientry+1,irho)-muc_table(ientry,irho)) &
     /(p_table(ientry+1,irho)-p_table(ientry,irho))*(p_loc-p_table(ientry,irho))

   case(2)
   eps1=eng_table(ientry,irho)+(eng_table(ientry+1,irho)-eng_table(ientry,irho)) &
     /(p_table(ientry+1,irho)-p_table(ientry,irho))*(p_loc-p_table(ientry,irho))
   gam1=gamma_table(ientry,irho)+(gamma_table(ientry+1,irho)-gamma_table(ientry,irho)) &
     /(p_table(ientry+1,irho)-p_table(ientry,irho))*(p_loc-p_table(ientry,irho))
   m1=muc_table(ientry,irho)+(muc_table(ientry+1,irho)-muc_table(ientry,irho)) &
     /(p_table(ientry+1,irho)-p_table(ientry,irho))*(p_loc-p_table(ientry,irho))
   end select
   enddo

   if (irhop>irho0)then
   eps=(eps0+(eps1-eps0)*(rho-rho_table(irho0))/(rho_table(irhop)-rho_table(irho0)))*rho
   gam=gam0+(gam1-gam0)*(rho-rho_table(irho0))/(rho_table(irhop)-rho_table(irho0))
   m=m0+(m1-m0)*(rho-rho_table(irho0))/(rho_table(irhop)-rho_table(irho0))
   else
     eps=eps0*rho
     m=m0
     gam=gam0
   endif 

  end subroutine

end module
