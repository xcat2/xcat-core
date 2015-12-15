osimage
=======

Description
-----------

A logical definition of image which can be used to provision the node.

Key Attributes
--------------

* imagetype:
   The type of operating system this definition represents (linux, AIX).

* osarch:
   The hardware architecture of the nodes this image supports. Valid values: x86_64, ppc64, ppc64le. 
 
* osvers:
   The Linux distribution name and release number of the image. Valid values: rhels*, rhelc*, rhas*, centos*, SL*, fedora*, sles* (where * is the version #).

* pkgdir:
   The name of the directory where the copied OS distro content are stored.

* pkglist:
   The fully qualified name of a file, which contains the list of packages shipped in Linux distribution ISO which will be installed on the node.

* otherpkgdir
   When xCAT user needs to install some additional packages not shipped in Linux distribution ISO, those packages can be placed in the directory specified in this attribute. xCAT user should take care of dependency problems themselves, by putting all the dependency packages not shipped in Linux distribution ISO in this directory and creating repository in this directory.


* otherpkglist:
   The fully qualified name of a file, which contains the list of user specified additional packages not shipped in Linux distribution ISO which will be installed on the node.

* template:
   The fully qualified name of the template file that will be used to create the OS installer configuration file for stateful installation (e.g. kickstart for RedHat, autoyast for SLES and preseed for Ubuntu).


Use Cases
---------

* Case 1: 

List all the osimage objects ::

   lsdef -t osimage

* Case 2: 

Create a osimage definition "customized-rhels7-ppc64-install-compute" based on an existing osimage "rhels7-ppc64-install-compute", the osimage "customized-rhels7-ppc64-install-compute" will inherit all the attributes of "rhels7-ppc64-install-compute" except installing the additional packages specified in the file "/tmp/otherpkg.list":

*step 1* : write the osimage definition "rhels7-ppc64-install-compute" to a stanza file "osimage.stanza" ::

   lsdef -z -t osimage -o rhels7-ppc64-install-compute > /tmp/osimage.stanza

The content will look like ::

   # <xCAT data object stanza file>
   
   rhels7-ppc64-install-compute:
       objtype=osimage
       imagetype=linux
       osarch=ppc64
       osdistroname=rhels7-ppc64
       osname=Linux
       osvers=rhels7
       otherpkgdir=/install/post/otherpkgs/rhels7/ppc64
       pkgdir=/install/rhels7/ppc64
       pkglist=/opt/xcat/share/xcat/install/rh/compute.rhels7.pkglist
       profile=compute
       provmethod=install
       template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl
 
*step 2* : modify the stanza file according to the attributes of "customized-rhels7-ppc64-install-compute" ::
  
   # <xCAT data object stanza file>
   
   customized-rhels7-ppc64-install-compute:
       objtype=osimage
       imagetype=linux
       osarch=ppc64
       osdistroname=rhels7-ppc64
       osname=Linux
       osvers=rhels7
       otherpkglist=/tmp/otherpkg.list
       otherpkgdir=/install/post/otherpkgs/rhels7/ppc64
       pkgdir=/install/rhels7/ppc64
       pkglist=/opt/xcat/share/xcat/install/rh/compute.rhels7.pkglist
       profile=compute
       provmethod=install
       template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl

*step 3* : create the osimage "customized-rhels7-ppc64-install-compute" from the stanza file ::

   cat /tmp/osimage.stanza |mkdef -z
