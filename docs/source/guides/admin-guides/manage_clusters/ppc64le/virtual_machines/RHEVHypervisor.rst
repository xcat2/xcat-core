
   Red Hat Virtualization (formally known as RHEV or Red Hat Enterprise Virtualization) is a virtualization solution provided by Red Hat.  

   At the time of this writing there is no RHEV-H prebuilt hypervisor image on Power LE.  The method for creating a Red Hat Hypervisor on Power LE is to first install RHEL and apply the KVM support on top with the provided RPMs. 

   Obtain and download the RHEV RPM packages from the Red Hat download site.  

       * Management-Agent-Power-7
       * Power_Tools-7 

   In the following example, the RPMs are downloaded to ``/install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA``

   * Create a yum repository for the downloaded RPMs ::

      createrepo /install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA

   * Create new osimage definition based on an existing RHEL7 osimage definition ::

      mkdef -t osimage -o rhels7.3-ppc64le-RHEV4-install-compute \
         --template rhels7.3-ppc64le-install-compute

   * Modify ``otherpkgdir`` attribute to point to the package directory with downloaded RPMs ::

      chdef -t osimage rhels7.3-ppc64le-RHEV4-install-compute \
         otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA

   * Create a new package list file ``/install/custom/rhels7.3/ppc64le/rhelv4.pkglist`` to include necessary packages provided from the OS. :: 

      #INCLUDE:/opt/xcat/share/xcat/install/rh/compute.rhels7.pkglist#
      libvirt
      screen 
      bridge-utils

   * Modify ``pkglist`` attribute to point to the package list file from the step above ::

      chdef -t osimage rhels7.3-snap3-ppc64le-RHEV4-install-compute \
         pkglist=/install/custom/rhels7.3/ppc64le/rhelv4.pkglist

   * Create a new package list file ``/install/custom/rhels7.3/ppc64le/rhev4.otherpkgs.pkglist`` to list required packages ::

      qemu-kvm-rhev 
      qemu-kvm-tools-rhev 
      virt-manager-common 
      virt-install

   * Modify ``otherpkglist`` attribute to point to the package list file from the step above ::

      chdef -t osimage rhels7.3-snap3-ppc64le-RHEV4-install-compute \
         otherpkglist=/install/custom/rhels7.3/ppc64le/rhev4.otherpkgs.pkglist

   * The RHEV osimage should look similar to: ::

      Object name: rhels7.3-ppc64le-RHEV4-install-compute
          imagetype=linux
          osarch=ppc64le
          osdistroname=rhels7.3-ppc64le
          osname=Linux
          osvers=rhels7.3
          otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le/RHEV4/4.0-GA
          otherpkglist=/install/custom/rhels7.3/ppc64le/rhev4.otherpkgs.pkglist
          pkgdir=/install/rhels7.3/ppc64le
          pkglist=/install/custom/rhels7.3/ppc64le/rhelv4.pkglist
          profile=compute
          provmethod=install
          template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl

