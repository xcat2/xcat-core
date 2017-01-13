
   Obtain a PowerKVM ISO and create PowerKVM osimages with it: :: 

     copycds ibm-powerkvm-3.1.0.0-39.0-ppc64le-gold-201511041419.iso
    
   The following PowerKVM osimage will be created ::
     
     # lsdef -t osimage -o pkvm3.1-ppc64le-install-compute
     Object name: pkvm3.1-ppc64le-install-compute
         imagetype=linux
         osarch=ppc64le
         osdistroname=pkvm3.1-ppc64le
         osname=Linux
         osvers=pkvm3.1
         otherpkgdir=/install/post/otherpkgs/pkvm3.1/ppc64le
         pkgdir=/install/pkvm3.1/ppc64le
         profile=compute
         provmethod=install
         template=/opt/xcat/share/xcat/install/pkvm/compute.pkvm3.ppc64le.tmpl

