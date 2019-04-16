Accelerating the diskless initrd and rootimg generating
========================================================

Generating diskless initrd with ``genimage`` and compressed rootimg with ``packimage`` and ``liteimg`` is a time-consuming process, it can be accelerated by enabling parallel compression tool ``pigz`` on the management node with multiple processors and cores. See :ref:`Appendix <pigz_example>` for an example on ``packimage`` performance optimized with ``pigz`` enabled.



Enabling the ``pigz`` for diskless initrd and rootimg generating
----------------------------------------------------------------

The parallel compression tool ``pigz`` can be enabled by installing ``pigz`` package on the management server or diskless rootimg. Depending on the method of generating the initrd and compressed rootimg, the steps differ in different Linux distributions.

* **[RHEL]**

  The package ``pigz`` is shipped in Extra Packages for Enterprise Linux (or EPEL) instead of RedHat iso, this involves some complexity.

  Extra Packages for Enterprise Linux (or EPEL) is a Fedora Special Interest Group that creates, maintains, and manages a high quality set of additional packages for Enterprise Linux, including, but not limited to, Red Hat Enterprise Linux (RHEL), CentOS and Scientific Linux (SL), Oracle Linux (OL).

  EPEL has an ``epel-release`` package that includes gpg keys for package signing and repository information. Installing this package for your Enterprise Linux version should allow you to use normal tools such as ``yum`` to install packages and their dependencies.

  Refer to the http://fedoraproject.org/wiki/EPEL for more details on EPEL

  1) Enabling the ``pigz`` in ``genimage`` (only supported in RHEL 7 or above)

     ``pigz`` should be installed in the diskless rootimg. Download ``pigz`` package from https://dl.fedoraproject.org/pub/epel/ , then customize the diskless osimage to install ``pigz`` as the additional packages, see :doc:`Install Additional Other Packages</guides/admin-guides/manage_clusters/ppc64le/diskless/customize_image/additional_pkg>` for more details.

  2) Enabling the ``pigz`` in ``packimage``

     ``pigz`` should be installed on the management server. Download ``pigz`` package from https://dl.fedoraproject.org/pub/epel/ , then install the ``pigz`` with  ``yum`` or ``rpm``.

* **[UBUNTU]**

  Make sure the ``pigz`` is installed on the management node with the following command::

     dpkg -l|grep pigz

  If not, ``pigz`` can be installed with the following command::

     apt-get install pigz

* **[SLES]**

  1) Enabling the ``pigz`` in ``genimage`` (only supported in SLES12 or above)

     ``pigz`` should be installed in the diskless rootimg, since``pigz`` is shipped in the SLES iso, this can be done by adding ``pigz`` into the ``pkglist`` of diskless osimage.

  2) Enabling the ``pigz`` in ``packimage``

     Make sure the ``pigz`` is installed on the management node with the following command::

        rpm -qa|grep pigz

     If not, ``pigz`` can be installed with the following command::

        zypper install pigz


.. _pigz_example:

Appendix: An example on ``packimage`` performance optimization with "pigz" enabled
----------------------------------------------------------------------------------

This is an example on performance optimization with ``pigz`` enabled.

In this example, a xCAT command ``packimage rhels7-ppc64-netboot-compute`` is run on a Power 7 machine with 4 cores.

The system info: ::

    # uname -a
    Linux c910f03c01p03 3.10.0-123.el7.ppc64 #1 SMP Mon May 5 11:18:37 EDT 2014 ppc64 ppc64 ppc64 GNU/Linux

    # cat /etc/os-release
    NAME="Red Hat Enterprise Linux Server"
    VERSION="7.0 (Maipo)"
    ID="rhel"
    ID_LIKE="fedora"
    VERSION_ID="7.0"
    PRETTY_NAME="Red Hat Enterprise Linux Server 7.0 (Maipo)"
    ANSI_COLOR="0;31"
    CPE_NAME="cpe:/o:redhat:enterprise_linux:7.0:GA:server"
    HOME_URL="https://www.redhat.com/"
    BUG_REPORT_URL="https://bugzilla.redhat.com/"

    REDHAT_BUGZILLA_PRODUCT="Red Hat Enterprise Linux 7"
    REDHAT_BUGZILLA_PRODUCT_VERSION=7.0
    REDHAT_SUPPORT_PRODUCT="Red Hat Enterprise Linux"
    REDHAT_SUPPORT_PRODUCT_VERSION=7.0

The CPU info: ::

    # cat /proc/cpuinfo
    processor       : 0
    cpu             : POWER7 (architected), altivec supported
    clock           : 3550.000000MHz
    revision        : 2.0 (pvr 003f 0200)

    processor       : 1
    cpu             : POWER7 (architected), altivec supported
    clock           : 3550.000000MHz
    revision        : 2.0 (pvr 003f 0200)

    processor       : 2
    cpu             : POWER7 (architected), altivec supported
    clock           : 3550.000000MHz
    revision        : 2.0 (pvr 003f 0200)

    processor       : 3
    cpu             : POWER7 (architected), altivec supported
    clock           : 3550.000000MHz
    revision        : 2.0 (pvr 003f 0200)

    timebase        : 512000000
    platform        : pSeries
    model           : IBM,8233-E8B
    machine         : CHRP IBM,8233-E8B

The time spent on ``packimage`` with ``gzip``: ::

    # time packimage rhels7-ppc64-netboot-compute
    Packing contents of /install/netboot/rhels7/ppc64/compute/rootimg
    compress method:gzip


    real    1m14.896s
    user    0m0.159s
    sys     0m0.019s

The time spent on ``packimage`` with ``pigz``: ::

    # time packimage rhels7-ppc64-netboot-compute
    Packing contents of /install/netboot/rhels7/ppc64/compute/rootimg
    compress method:pigz

    real    0m23.177s
    user    0m0.176s
    sys     0m0.016s



