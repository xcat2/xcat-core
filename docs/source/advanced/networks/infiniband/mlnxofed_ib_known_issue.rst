Known Issues
============

Preventing upgrade of the Mellanox Drivers
------------------------------------------

On RedHat operating systems, after the Mellanox drivers are installed, you may have a requirement to update your operating system to a later version. 
Some operating systems may ship InfiniBand drivers that are higher version than the Mellanox drivers you have installed and therefor may update the existing drivers. 

To prevent this from happening, add the following in the ``/etc/yum.conf`` ::

    exclude=dapl* libib* ibacm infiniband* libmlx* librdma* opensm* ibutils*


Development packages in SLES 
----------------------------

If using the ``--add-kernel-support`` attribute on SLES operating systems, you may find problems with installing some dependency packages which are not shipped by the SLES server DVDs.  The development rpms are provided by the SDK DVDs.  Refer to :doc:`Add Additional Software Packages </guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/additional_pkg>` to configure the SDK repositories. 

