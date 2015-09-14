Accelerating the diskless initrd and rootimg generating
========================================================

Generating diskless initrd with ``genimage`` and compressed rootimg with ``packimage`` and ``liteimg`` is a time-comsuming process, it can be accelerated by enabling paralell compression tool ``pigz`` on the management node with multiple processors and cores.

The paralell compression tool ``pigz`` can be enabled by installing ``pigz`` package on the management server or diskless rootimg. Depending on the method of generating the initrd and compressed rootimg, the steps differ in different Linux distributions. 


* Enabling the ``pigz`` on :ref:`Ubuntu Server LTS<ubuntu-os-support-label>`
--------------------------------------------------------------------------

Make sure the ``pigz`` is installed on the management node with the following command::

   dpkg -l|grep pigz

If not, ``pigz`` can be installed with the following command::
   
   apt-get install pigz


* Enabling the ``pigz`` on :ref:`Suse Linux Enterprise Server (SLES)<sles-os-support-label>`
------------------------------------------------------------------------------------------

1) Enabling the ``pigz`` in ``genimage`` (only supported in SLES12 or above) 

``pigz`` should be installed in the diskless rootimg, since``pigz`` is shipped in the SLES iso, this can be done by adding ``pigz`` into the ``pkglist`` of diskless osimage.

2) Enabling the ``pigz`` in ``packimage``

Make sure the ``pigz`` is installed on the management node with the following command::

   rpm -qa|grep pigz

If not, ``pigz`` can be installed with the following command::

   zypper install pigz


* Enabling the ``pigz`` on :ref:`Red Hat Enterprise Linux (RHEL)<rhels-os-support-label>`
---------------------------------------------------------------------------------------

The package ``pigz`` is shipped in Extra Packages for Enterprise Linux (or EPEL) instead of Redhat iso, this involves some complexity.

Extra Packages for Enterprise Linux (or EPEL) is a Fedora Special Interest Group that creates, maintains, and manages a high quality set of additional packages for Enterprise Linux, including, but not limited to, Red Hat Enterprise Linux (RHEL), CentOS and Scientific Linux (SL), Oracle Linux (OL).

EPEL has an ``epel-release`` package that includes gpg keys for package signing and repository information. Installing this package for your Enterprise Linux version should allow you to use normal tools such as ``yum`` to install packages and their dependencies. 

Please refer to the http://fedoraproject.org/wiki/EPEL for more details on EPEL

1) Enabling the ``pigz`` in ``genimage`` (only supported in RHELS6 or above)

``pigz`` should be installed in the diskless rootimg. Please download ``pigz`` package from https://dl.fedoraproject.org/pub/epel/ , then customize the diskless osimage to install ``pigz`` as the additional packages, see :doc:`Install Additional Other Packages</guides/admin-guides/manage_clusters/ppc64le/diskless/customize_image/additional_pkg>` for more details.

2) Enabeling the ``pigz`` in ``packimage``

``pigz`` should be installed on the management server. Please download ``pigz`` package from https://dl.fedoraproject.org/pub/epel/ , then install the ``pigz`` with  ``yum`` or ``rpm``.




