xCAT2 Release Information
=========================

The following table is a summary of the new operating system (OS), hardware, and features that are added to each xCAT release.   The OS and hardware listed in the table have been fully tested with xCAT.   For a more detailed list of new function, bug fixes, restrictions and known problems, refer to the individual release notes for a specific release. 

* **RHEL** - Red Hat Enterprise Linux
* **SLES** - Suse Linux Enterprise Server
* **UBT** - Ubuntu

xCAT 2.13.x
-----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.13.1                    |               |             |- ONIE switch support             |
|| 2017/1/13                      |               |             |- refine xcatprobe subcommand:    |
||                                |               |             |  xcatmn, osdeploy                |
| `2.13.1 Release Notes <https:// |               |             |- add utp-wait for genesis-base   |
| github.com/xcat2/xcat-core/wiki |               |             |                                  |
| /XCAT_2.13.1_Release_Notes>`_   |               |             |                                  |
|                                 |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.13                      |- SLES 12.2    |             |- update drivers for genesis-base |
|| 2016/12/09                     |               |             |  mlx4-en 3.2-1.0.1.1             |
||                                |               |             |  i40e 1.5.16                     |
| `2.13 Release Notes <https://   |               |             |- rflash saving flashing progress |
| github.com/xcat2/xcat-core/wiki |               |             |- Update configureRAID document   |
| /XCAT_2.13_Release_Notes>`_     |               |             |- statelite image create by copyds|
|                                 |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+

xCAT 2.12.x
-----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.12.4                    |- RHEL 7.3 LE  |             |- `noboot` added to dhcpinterface |
|| 2016/11/11                     |- RHEV 4.0     |             |- new xcatprobe subcommand:       |
||                                |               |             |  xcatmn, deploy and discover     |
| `2.12.4 Release Notes <https:// |               |             |                                  |
| github.com/xcat2/xcat-core/wiki |               |             |                                  |
| /XCAT_2.12.4_Release_Notes>`_   |               |             |                                  |
|                                 |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.12.3                    |               |             |- GitHub Issues resolved          |
|| 2016/09/30                     |               |             |- rinv options for OpenPower      |
||                                |               |             |- switch based switch discovery   |
| `2.12.3 Release Notes <https:// |               |             |- additional options added to     |
| github.com/xcat2/xcat-core/wiki |               |             |  xcatprobe command               |
| /XCAT_2.12.3_Release_Notes>`_   |               |             |- mkdef takes file redirection    |
|                                 |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.12.2                    |- UBT 16.04.1  |             |- nodeset <noderange> offline     |
|| 2016/08/19                     |               |             |- Enhance: node status update     |
||                                |               |             |- Support Bond for install nics   |
| `2.12.2 Release Notes <https:// |               |             |- xcatprobe osdeploy -r (BETA)    |
| github.com/xcat2/xcat-core/wiki |               |             |- New opt: packimage -m -c        |
| /XCAT_2.12.2_Release_Notes>`_   |               |             |                                  |
|                                 |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.12.1                    |               |             |- New xCAT install tool: go-xcat  |
|| 2016/07/08                     |               |             |- New opt: mkdef/lsdef --template |
||                                |               |             |- Support rinstall for all OS/ARCH|
| `2.12.1 Release Notes <https:// |               |             |- site.xcatdebugmode for diskless |
| github.com/xcat2/xcat-core/wiki |               |             |- Refine discovery framework      |
| /XCAT_2.12.1_Release_Notes>`_   |               |             |- rscan <kvmhost>                 |
|                                 |               |             |- New: xcatprobe (experimental)   |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.12                      |- RHEL 6.8     |             |- Docker: xCAT in Docker          |
|| 2016/5/20                      |- UBT 14.4.4 LE|             |- Docker: container life cycle mgt|
||                                |- UBT 16.04    |             |- Docker: Set up Docker Registry  |
| `2.12 Release Notes <https://   |               |             |- New command: getadapter         |
| github.com/xcat2/xcat-core/     |               |             |- Add get_install_disk (diskful)  |
| wiki/XCAT_2.12_Release_Notes>`_ |               |             |- Add site.xcatdebugmode          |
|                                 |               |             |- Add switchdiscover -s snmp      |
|                                 |               |             |- Disable auditlog by default     |
|                                 |               |             |- Add site.hierarchicalattrs      |
+---------------------------------+---------------+-------------+----------------------------------+


xCAT 2.11.x
-----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.11.1                    |               |             |- Bug fix                         |
|| 2016/04/22                     |               |             |                                  |
||                                |               |             |                                  |
| `2.11.1 Release Notes <https:// |               |             |                                  |
| github.com/xcat2/xcat-core/wiki |               |             |                                  |
| /XCAT_2.11.1_Release_Notes>`_   |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.11                      |- RHEL 7.2 LE  |- S822LC(GCA)|- NVIDIA GPU for OpenPOWER        |
|| 2015/12/11                     |- UBT 14.4.3 LE|- S822LC(GTA)|- Infiniband for OpenPOWER        |
||                                |- UBT 15.10 LE |- S812LC     |- SW KIT support for OpenPOWER    |
| `2.11 Release Notes <https://   |- PowerKVM 3.1 |- NeuCloud OP|- renergy command for OpenPOWER   |
| github.com/xcat2/xcat-core/     |               |- ZoomNet RP |- rflash command for OpenPower    |
| wiki/XCAT_2.11_Release_Notes>`_ |               |             |- Add xCAT Troubleshooting Log    |
|                                 |               |             |- xCAT Log Classification         |
|                                 |               |             |- RAID Configuration              |
|                                 |               |             |- Accelerate genimage process     |
|                                 |               |             |- Add bmcdiscover Command         |
|                                 |               |             |- Enhance xcatdebugmode           |
|                                 |               |             |- new xCAT doc in ReadTheDocs     |
+---------------------------------+---------------+-------------+----------------------------------+


xCAT 2.10.x
-----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.10                      |- RHEL 7.1 LE  |- Power 8 LE |- Ubuntu LE -> RH 7.1 Mix         |
|| 2015/07/31                     |- UBT 15.4 LE  |             |- Cuda install for Ubuntu 14.4.2  |
||                                |- SLES 12 LE   |             |- additional kernel parameters    |
| `2.10 Release Notes <https://   |- RHEL 6.7     |             |- customized disk part (Ubuntu)   |
| github.com/xcat2/xcat-core/wiki |- CentOS 7.1   |             |- RAID configure base iprconfig   |
| /XCAT_2.10_Release_Notes/>`_    |- SLES 11 SP4  |             |- New command: switchdiscover     |
|                                 |               |             |- New command: makentp            |
|                                 |               |             |- New command: bmcdiscovery       |
|                                 |               |             |- Support getmacs --noping        |
|                                 |               |             |- site.xcatdebugmode              |
|                                 |               |             |- validate netboot attribute      |
|                                 |               |             |- buildcore on local server       |
|                                 |               |             |- copycds generates fewer osimage |
|                                 |               |             |- nodeset only accepts osimage=   |
+---------------------------------+---------------+-------------+----------------------------------+

xCAT 2.9.x
----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.9.3 for AIX             |- AIX 7.2.0    |             |- new format in synclist (node)   |
|| 2016/03/11                     |- AIX 7.1.4.1  |             |                                  |
||                                |               |             |                                  |
| `2.9.3 Release Notes <https://  |               |             |                                  |
| github.com/xcat2/xcat-core/     |               |             |                                  |
| wiki/XCAT_2.9.3_Release_Notes>`_|               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.9.2 for AIX             |- AIX 6.1.8.6  |- Power 8    |- ssl version control in xcatd    |
|| 2015/11/11                     |- AIX 6.1.9.5  |  for AIX    |                                  |
||                                |- AIX 7.1.3.5  |             |                                  |
| `2.9.2 Release Notes <https://  |               |             |                                  |
| github.com/xcat2/xcat-core/     |               |             |                                  |
| wiki/XCAT_2.9.2_Release_Notes>`_|               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.9.1 [#]_                |- RHEL 7.1     |             |- Nvidia GPU                      |
|| 2015/03/20                     |- UBT 14.04.2  |             |- Ubuntu Local Mirror             |
||                                |- SLES 11 SP3  |             |- SLES12 diskless                 |
| `2.9.1 Release Notes <https://  |  and later    |             |- Energy management for Power 8   |
| sourceforge.net/p/xcat/wiki/    |  ONLY         |             |- RHEL 7.1 LE -> BE mix cluster   |
| XCAT_2.9.1_Release_Notes/>`_    |               |             |- nics.nicextraparams             |
|                                 |               |             |- xCAT in Docker Image            |
|                                 |               |             |- confluent replaces conserver    |
|                                 |               |             |- TLSv1 in xcatd                  |
|                                 |               |             |- New GPG key for xCAT packages   |
|                                 |               |             |- fast restart xcatd (systemd)    |
|                                 |               |             |- netboot method: grub2-tftp      |
|                                 |               |             |- netboot method: grub2-http      |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.9                       |- UBT 14.4 LE  |- Power 8 LE |- sysclone enhancements           |
|| 2014/12/12                     |- UBT 14.4.1 LE|             |- site.auditnosyslog              |
||                                |- UBT 14.10    |             |- site.nmapoptions                |
| `2.9 Release Notes <https://    |- SLES 12      |             |- customize postscripts           |
| sourceforge.net/p/xcat/wiki/    |- RHEL 6.6     |             |- Power 8 LE hw discover          |
| XCAT_2.9_Release_Notes/>`_      |- AIX 7.1.3.15 |             |- IB support for P8 LE            |
|                                 |- PowerKVM     |             |                                  |
|                                 |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+

.. [#] xCAT 2.9.1 onwards provides support for Kernel-based Virtual Machines (KVM) and requires an operating system that ships the ``perl-Sys-Virt`` package.  

xCAT 2.8.x 
----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.8.4                     |- RHEL 6.5     |             |- RHEL 7 experimental,            |
|| 2014/03/23                     |- RHEL 5.10    |             |- support xCAT clusterzones       |
||                                |               |             |- commands enhancements           |
| `2.8.4 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.8.4_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.8.3                     |- AIX 7.3.1.1  |- Xeon Phi   |- xcatd flow control              |
|| 2013/11/15                     |- AIX 7.3.1.0  |  (P2)       |- sysclone x86_64 image           |
||                                |- AIX 7.1.2    |- NS nx360M4 |- enhance genitird and nodeset    |
| `2.8.3 Release Notes <https://  |               |             |- enhance confignics, KIT         |
| sourceforge.net/p/xcat/wiki/    |               |             |- enhance sequential discovery    |
| XCAT_2.8.3_Release_Notes/>`_    |               |             |- deploy OpenStack on Ubuntu      |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.8.2                     |- SLES 11 SP3  |- Xeon Phi   |- HPC KIT for ppc64               |
|| 2013/06/26                     |               |  (P1)       |- sysclone x86_64 image (P1)      |
||                                |               |             |- enhance xdsh, updatenode        |
| `2.8.2 Release Notes <https://  |               |             |- localdisk for diskless          |
| sourceforge.net/p/xcat/wiki/    |               |             |- enhance sequential discovery    |
| XCAT_2.8.2_Release_Notes/>`_    |               |             |- deploy OpenStack on Ubuntu      |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.8.1                     |- RHEL 6.4     |             |- energy management for flex      |
|| 2013/06/26                     |- RHEL 5.9     |             |- sequential discovery            |
||                                |               |             |- KIT enhancements                |
| `2.8.1 Release Notes <https://  |               |             |- osimage enhancements            |
| sourceforge.net/p/xcat/wiki/    |               |             |- IPv6 enhancements               |
| XCAT_2.8.1_Release_Notes/>`_    |               |             |- def/xdsh/xdcp enhancements      |
|                                 |               |             |- updatenode enhancements         |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.8                       |- UBT 12.04    |             |- Flex IMM setup                  |
|| 2013/02/28                     |- WIN S 2012   |             |- Multiple Hostname               |
||                                |- WIN 8 Hv     |             |- KIT support                     |
| `2.8 Release Notes <https://    |               |             |- KVM/zVM enhancements            |
| sourceforge.net/p/xcat/wiki/    |               |             |- RHEV Support                    |
| XCAT_2.8_Release_Notes/>`_      |               |             |- Localdisk for statelite         |
|                                 |               |             |- Manage MN itslef                |
|                                 |               |             |- site auditskipcmds              |
|                                 |               |             |- precreate postscripts           |
|                                 |               |             |- mypostscript templates          |
|                                 |               |             |- pasu command                    |
|                                 |               |             |- postscripts on stateful boot    |
|                                 |               |             |- node update status attrs        |
|                                 |               |             |- updatenode enhancements         |
+---------------------------------+---------------+-------------+----------------------------------+

xCAT 2.7.x
----------

+---------------------------------+---------------+-------------+----------------------------------+
|xCAT                             |New OS         |New          |New Feature                       |
|Version                          |               |Hardware     |                                  |
+=================================+===============+=============+==================================+
|| xCAT 2.7.8                     |- AIX 7.1.3.1  |             |                                  |
|| 2014/01/24                     |- AIX 7.1.3.0  |             |                                  |
||                                |- AIX 6.1.9.1  |             |                                  |
| `2.7.8 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.8_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.7                     |- RHEL 6.4     |             |- sinv for devices                |
|| 2013/03/17                     |               |             |- Flex energy mgt and rbeacon     |
||                                |               |             |                                  |
| `2.7.7 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.7_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.6                     |- SLES 10 SP4  |             |- HPC Integration updates         |
|| 2012/11/30                     |- AIX 6.1.8    |             |                                  |
||                                |- AIX 7.1.2    |             |                                  |
| `2.7.6 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.6_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.5                     |- RHEL 6.3     |             |- virtualization with RHEV        |
|| 2012/10/29                     |               |             |- hardware discovery for x Flex   |
||                                |               |             |- enhanced AIX HASN               |
| `2.7.5 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.5_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.4                     |- SLES11 SP2   |- Flex       |- improved IPMI for large systems |
|| 2012/08/27                     |               |             |                                  |
||                                |               |             |                                  |
| `2.7.4 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.4_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.3                     |- SLES11 SP2   |- Flex       |- HPC Integration updates         |
|| 2012/06/22                     |- RHEL 6.2     |             |                                  |
||                                |               |             |                                  |
| `2.7.3 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.3_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.2                     |- AIX 7.1.1.3  |- Power 775  |- SLES 11 kdump                   |
|| 2012/05/25                     |               |- Flex for P |- HPC Integration updates         |
||                                |               |             |                                  |
| `2.7.2 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.2_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7.1                     |- RHEL 6.3     |             |- minor enhancements              |
|| 2012/04/20                     |               |             |- bug fixes                       |
||                                |               |             |                                  |
| `2.7.1 Release Notes <https://  |               |             |                                  |
| sourceforge.net/p/xcat/wiki/    |               |             |                                  |
| XCAT_2.7.1_Release_Notes/>`_    |               |             |                                  |
+---------------------------------+---------------+-------------+----------------------------------+
|| xCAT 2.7                       |- RHEL 6.2     |             |- xcatd memory usage reduced      |
|| 2012/03/19                     |               |             |- xcatdebug for xcatd and plugins |
||                                |               |             |- lstree command                  |
| `2.7 Release Notes <https://    |               |             |- x86_64 genesis boot image       |
| sourceforge.net/p/xcat/wiki/    |               |             |- ipmi throttles                  |
| XCAT_2.7_Release_Notes/>`_      |               |             |- rpower suspend select IBM hw    |
|                                 |               |             |- stateful ESXi5                  |
|                                 |               |             |- xnba UEFI boot                  |
|                                 |               |             |- httpd for postscripts           |
|                                 |               |             |- rolling updates                 |
|                                 |               |             |- Nagios monitoring plugin        |
+---------------------------------+---------------+-------------+----------------------------------+
