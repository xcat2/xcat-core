.. BEGIN_Overview

By default, xCAT will attempt to determine the first physical disk and use a generic default partition scheme for the operating system.  You may require a more customized disk partitioning scheme and can accomplish this in one of the following methods:

    * partition definition file
    * partition definition script

.. note:: **partition definition file** can be used for RedHat, SLES, and Ubuntu.  However, disk configuration for Ubuntu is different from RedHat/SLES, there may be some special sections required for Ubuntu.

.. warning:: **partition  definition script** has only been verified on RedHat and Ubuntu, use at your own risk for SLES.

.. END_Overview


.. BEGIN_partition_definition_file_Overview

The following steps are required for this method:

   #. Create a partition file
   #. Associate the partition file with an xCAT osimage

The ``nodeset`` command will then insert the contents of this partition file into the generated autoinst config file that will be used by the operation system installer. 

.. END_partition_definition_file_Overview


.. BEGIN_partition_definition_file_content

The partition file must follow the partitioning syntax of the respective installer 

   * Redhat: `Kickstart documentation  <http://fedoraproject.org/wiki/Anaconda/Kickstart#part_or_partition>`_ 

     * The file ``/root/anaconda-ks.cfg`` is a sample kickstart file created by RedHat installing during the installation process based on the options that you selected.
     * system-config-kickstart is a tool with graphical interface for creating kickstart files

   * SLES: `Autoyast documentation  <https://doc.opensuse.org/projects/autoyast/#CreateProfile-Partitioning>`_ 

     * Use yast2 autoyast in GUI or CLI mode to customize the installation options and create autoyast file
     * Use yast2 clone_system to create autoyast configuration file ``/root/autoinst.xml`` to clone an existing system

   * Ubuntu: `Preseed documentation  <https://www.debian.org/releases/stable/i386/apbs04.en.html#preseed-partman>`_ 

     * For detailed information see the files ``partman-auto-recipe.txt`` and ``partman-auto-raid-recipe.txt`` included in the debian-installer package. Both files are also available from the debian-installer source repository. 

.. note:: Supported functionality may change between releases of the Operating System, always refer to the latest documentation provided by the operating system.

.. END_partition_definition_file_content

.. BEGIN_partition_definition_file_example_RedHat_Standard_Partitions_for_IBM_Power_machines

Here is partition definition file example for RedHat standard partition in IBM Power machines

::
    # Uncomment this PReP line for IBM Power servers
    part None --fstype "PPC PReP Boot" --size 8 --ondisk sda
    # Uncomment this efi line for x86_64 servers
    #part /boot/efi --size 50 --ondisk /dev/sda --fstype efi
    part /boot --size 256 --fstype ext4
    part swap --recommended --ondisk sda
    part / --size 1 --grow --fstype ext4 --ondisk sda

.. END_partition_definition_file_example_RedHat_Standard_Partitions_for_IBM_Power_machines

.. BEGIN_partition_definition_file_example_RedHat_LVM_for_IBM_Power_machines

Here is partition definition file example for RedHat LVM partition in IBM Power machines

::
    # Uncomment this PReP line for IBM Power servers
    part None --fstype "PPC PReP Boot" --ondisk /dev/sda --size 8
    # Uncomment this efi line for x86_64 servers
    #part /boot/efi --size 50 --ondisk /dev/sda --fstype efi
    part /boot --size 256 --fstype ext4 --ondisk /dev/sda
    part swap --recommended --ondisk /dev/sda
    part pv.01 --size 1 --grow --ondisk /dev/sda
    volgroup system pv.01
    logvol / --vgname=system --name=root --size 1 --grow --fstype ext4

.. END_partition_definition_file_example_RedHat_LVM_for_IBM_Power_machines

.. BEGIN_partition_definition_file_example_RedHat_RAID1_for_IBM_Power_machines

To partition definition file example for RedHat RAID1 refer to :doc:`Configure RAID before Deploy OS </guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/raid_cfg>`

.. END_partition_definition_file_example_RedHat_RAID1_for_IBM_Power_machines

.. BEGIN_partition_definition_file_example_SLES_Standard_Partitions_for_X86_64

Here is partition definition file example for SLES standard partition in X86_64 machines

.. code-block:: xml

    <drive>
        <device>/dev/sda</device>
        <initialize config:type="boolean">true</initialize>
        <use>all</use>
        <partitions config:type="list">
            <partition>
                <create config:type="boolean">true</create>
                <filesystem config:type="symbol">swap</filesystem>
                <format config:type="boolean">true</format>
                <mount>swap</mount>
                <mountby config:type="symbol">path</mountby>
                <partition_nr config:type="integer">1</partition_nr>
                <partition_type>primary</partition_type>
                <size>32G</size>
            </partition>
            <partition>
                <create config:type="boolean">true</create>
                <filesystem config:type="symbol">ext4</filesystem>
                <format config:type="boolean">true</format>
                <mount>/</mount>
                <mountby config:type="symbol">path</mountby>
                <partition_nr config:type="integer">2</partition_nr>
                <partition_type>primary</partition_type>
                <size>64G</size>
            </partition>
        </partitions>
    </drive>
	
.. END_partition_definition_file_example_SLES_Standard_Partitions_for_X86_64

.. BEGIN_partition_definition_file_example_SLES_LVM_for_ppc64

The following is an example of a partition definition file for a SLES LVM Partition on Power Server:  ::

	<drive>
	  <device>/dev/sda</device>
	  <initialize config:type="boolean">true</initialize>
	  <partitions config:type="list">
		<partition>
		  <create config:type="boolean">true</create>
		  <crypt_fs config:type="boolean">false</crypt_fs>
		  <filesystem config:type="symbol">ext4</filesystem>
		  <format config:type="boolean">true</format>
		  <loop_fs config:type="boolean">false</loop_fs>
		  <mountby config:type="symbol">device</mountby>
		  <partition_id config:type="integer">65</partition_id>
		  <partition_nr config:type="integer">1</partition_nr>
		  <pool config:type="boolean">false</pool>
		  <raid_options/>
		  <resize config:type="boolean">false</resize>
		  <size>8M</size>
		  <stripes config:type="integer">1</stripes>
		  <stripesize config:type="integer">4</stripesize>
		  <subvolumes config:type="list"/>
		</partition>
		<partition>
		  <create config:type="boolean">true</create>
		  <crypt_fs config:type="boolean">false</crypt_fs>
		  <filesystem config:type="symbol">ext4</filesystem>
		  <format config:type="boolean">true</format>
		  <loop_fs config:type="boolean">false</loop_fs>
		  <mount>/boot</mount>
		  <mountby config:type="symbol">device</mountby>
		  <partition_id config:type="integer">131</partition_id>
		  <partition_nr config:type="integer">2</partition_nr>
		  <pool config:type="boolean">false</pool>
		  <raid_options/>
		  <resize config:type="boolean">false</resize>
		  <size>256M</size>
		  <stripes config:type="integer">1</stripes>
		  <stripesize config:type="integer">4</stripesize>
		  <subvolumes config:type="list"/>
		</partition>
		<partition>
		  <create config:type="boolean">true</create>
		  <crypt_fs config:type="boolean">false</crypt_fs>
		  <format config:type="boolean">false</format>
		  <loop_fs config:type="boolean">false</loop_fs>
		  <lvm_group>vg0</lvm_group>
		  <mountby config:type="symbol">device</mountby>
		  <partition_id config:type="integer">142</partition_id>
		  <partition_nr config:type="integer">3</partition_nr>
		  <pool config:type="boolean">false</pool>
		  <raid_options/>
		  <resize config:type="boolean">false</resize>
		  <size>max</size>
		  <stripes config:type="integer">1</stripes>
		  <stripesize config:type="integer">4</stripesize>
		  <subvolumes config:type="list"/>
		</partition>
	  </partitions>
	  <pesize></pesize>
	  <type config:type="symbol">CT_DISK</type>
	  <use>all</use>
	</drive>
	<drive>
	  <device>/dev/vg0</device>
	  <initialize config:type="boolean">true</initialize>
	  <partitions config:type="list">
		<partition>
		  <create config:type="boolean">true</create>
		  <crypt_fs config:type="boolean">false</crypt_fs>
		  <filesystem config:type="symbol">swap</filesystem>
		  <format config:type="boolean">true</format>
		  <loop_fs config:type="boolean">false</loop_fs>
		  <lv_name>swap</lv_name>
		  <mount>swap</mount>
		  <mountby config:type="symbol">device</mountby>
		  <partition_id config:type="integer">130</partition_id>
		  <partition_nr config:type="integer">5</partition_nr>
		  <pool config:type="boolean">false</pool>
		  <raid_options/>
		  <resize config:type="boolean">false</resize>
		  <size>auto</size>
		  <stripes config:type="integer">1</stripes>
		  <stripesize config:type="integer">4</stripesize>
		  <subvolumes config:type="list"/>
		</partition>
		<partition>
		  <create config:type="boolean">true</create>
		  <crypt_fs config:type="boolean">false</crypt_fs>
		  <filesystem config:type="symbol">ext4</filesystem>
		  <format config:type="boolean">true</format>
		  <loop_fs config:type="boolean">false</loop_fs>
		  <lv_name>root</lv_name>
		  <mount>/</mount>
		  <mountby config:type="symbol">device</mountby>
		  <partition_id config:type="integer">131</partition_id>
		  <partition_nr config:type="integer">1</partition_nr>
		  <pool config:type="boolean">false</pool>
		  <raid_options/>
		  <resize config:type="boolean">false</resize>
		  <size>max</size>
		  <stripes config:type="integer">1</stripes>
		  <stripesize config:type="integer">4</stripesize>
		  <subvolumes config:type="list"/>
		</partition>
	  </partitions>
	  <pesize></pesize>
	  <type config:type="symbol">CT_LVM</type>
	  <use>all</use>
	</drive>
	
.. END_partition_definition_file_example_SLES_LVM_for_ppc64

.. BEGIN_partition_definition_file_example_SLES_Standard_partition_for_ppc64

Here is partition definition file example for SLES standard partition in ppc64 machines

.. code-block:: xml

    <drive>
        <device>/dev/sda</device>
        <initialize config:type="boolean">true</initialize>
        <partitions config:type="list">
            <partition>
                <create config:type="boolean">true</create>
                <crypt_fs config:type="boolean">false</crypt_fs>
                <filesystem config:type="symbol">ext4</filesystem>
                <format config:type="boolean">false</format>
                <loop_fs config:type="boolean">false</loop_fs>
                <mountby config:type="symbol">device</mountby>
                <partition_id config:type="integer">65</partition_id>
                <partition_nr config:type="integer">1</partition_nr>
                <resize config:type="boolean">false</resize>
                <size>auto</size>
            </partition>
            <partition>
                <create config:type="boolean">true</create>
                <crypt_fs config:type="boolean">false</crypt_fs>
                <filesystem config:type="symbol">swap</filesystem>
                <format config:type="boolean">true</format>
                <fstopt>defaults</fstopt>
                <loop_fs config:type="boolean">false</loop_fs>
                <mount>swap</mount>
                <mountby config:type="symbol">id</mountby>
                <partition_id config:type="integer">130</partition_id>
                <partition_nr config:type="integer">2</partition_nr>
                <resize config:type="boolean">false</resize>
                <size>auto</size>
            </partition>
            <partition>
                <create config:type="boolean">true</create>
                <crypt_fs config:type="boolean">false</crypt_fs>
                <filesystem config:type="symbol">ext4</filesystem>
                <format config:type="boolean">true</format>
                <fstopt>acl,user_xattr</fstopt>
                <loop_fs config:type="boolean">false</loop_fs>
                <mount>/</mount>
                <mountby config:type="symbol">id</mountby>
                <partition_id config:type="integer">131</partition_id>
                <partition_nr config:type="integer">3</partition_nr>
                <resize config:type="boolean">false</resize>
                <size>max</size>
            </partition>
        </partitions>
        <pesize></pesize>
        <type config:type="symbol">CT_DISK</type>
        <use>all</use>
    </drive>
	
.. END_partition_definition_file_example_SLES_Standard_partition_for_ppc64

.. BEGIN_partition_definition_file_example_SLES_RAID1

To partition definition file example for SLES RAID1 refer to `Configure RAID before Deploy OS <http://xcat-docs.readthedocs.org/en/latest/guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/raid_cfg.html>`_

.. END_partition_definition_file_example_SLES_RAID1

.. BEGIN_partition_definition_file_example_Ubuntu_Standard_partition_for_PPC64le

Here is partition definition file example for Ubuntu standard partition in ppc64le machines ::

	ubuntu-boot ::
	8 1 1 prep
		$primary{ } $bootable{ } method{ prep }
		.
	500 10000 1000000000 ext4
		method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ / }
		.
	2048 512 300% linux-swap
		method{ swap } format{ }
		.
		
.. END_partition_definition_file_example_Ubuntu_Standard_partition_for_PPC64le

.. BEGIN_partition_definition_file_example_Ubuntu_Standard_partition_for_x86_64

Here is partition definition file example for Ubuntu standard partition in x86_64 machines: ::

	256 256 512 vfat
			$primary{ }
			method{ format }
			format{ }
			use_filesystem{ }
			filesystem{ vfat }
			mountpoint{ /boot/efi } .

	256 256 512 ext4
			$primary{ }
			method{ format }
			format{ }
			use_filesystem{ }
			filesystem{ ext4 }
			mountpoint{ /boot } .

	64 512 300% linux-swap
			method{ swap }
			format{ } .

	512 1024 4096 ext4
			$primary{ }
			method{ format }
			format{ }
			use_filesystem{ }
			filesystem{ ext4 }
			mountpoint{ / } .

	100 10000 1000000000 ext4
			method{ format }
			format{ }
			use_filesystem{ }
			filesystem{ ext4 }
			mountpoint{ /home } .
			
.. END_partition_definition_file_example_Ubuntu_Standard_partition_for_x86_64

.. BEGIN_partition_definition_file_Associate_partition_file_with_osimage_common

If your custom partition file is located at: ``/install/custom/my-partitions``, run the following command to associate the partition file with an osimage: ::

      chdef -t osimage <osimagename> partitionfile=/install/custom/my-partitions

To generate the configuration, run the ``nodeset`` command: ::

      nodeset <nodename> osimage=<osimagename>

.. note:: **RedHat:** Running ``nodeset`` will generate the ``/install/autoinst`` file for the node.  It will replace the ``#XCAT_PARTITION_START#`` and ``#XCAT_PARTITION_END#`` directives with the contents of your custom partition file.

.. note:: **SLES:** Running ``nodeset`` will generate the ``/install/autoinst`` file for the node.  It will replace the ``#XCAT-PARTITION-START#`` and ``#XCAT-PARTITION-END#`` directives with the contents of your custom partition file. Do not include ``<partitioning config:type="list">`` and ``</partitioning>`` tags, they will be added by xCAT.

.. note:: **Ubuntu:** Running ``nodeset`` will generate the ``/install/autoinst`` file for the node. It will write the partition file to ``/tmp/partitionfile`` and replace the ``#XCA_PARTMAN_RECIPE_SCRIPT#`` directive in ``/install/autoinst/<node>.pre`` with the contents of your custom partition file. 

.. END_partition_definition_file_Associate_partition_file_with_osimage_common


.. BEGIN_Partition_Definition_Script_overview

Create a shell script that will be run on the node during the install process to dynamically create the disk partitioning definition. This script will be run during the OS installer %pre script on RedHat or preseed/early_command on Unbuntu execution and must write the correct partitioning definition into the file ``/tmp/partitionfile`` on the node

.. END_Partition_Definition_Script_overview

.. BEGIN_Partition_Definition_Script_Create_partition_script_content

The purpose of the partition script is to create the ``/tmp/partionfile`` that will be inserted into the kickstart/autoyast/preseed template, the script could include complex logic like select which disk to install and even configure RAID, etc

.. note:: the partition script feature is not thoroughly tested on SLES, there might be problems, use this feature on SLES at your own risk.

.. END_Partition_Definition_Script_Create_partition_script_content

.. BEGIN_Partition_Definition_Script_Create_partition_script_example_redhat_sles

Here is an example of the partition script on RedHat and SLES, the partitioning script is ``/install/custom/my-partitions.sh``: ::

    instdisk="/dev/sda"

    modprobe ext4 >& /dev/null
    modprobe ext4dev >& /dev/null
    if grep ext4dev /proc/filesystems > /dev/null; then
        FSTYPE=ext3
    elif grep ext4 /proc/filesystems > /dev/null; then
        FSTYPE=ext4
    else
        FSTYPE=ext3
    fi
    BOOTFSTYPE=ext4
    EFIFSTYPE=vfat
    if uname -r|grep ^3.*el7 > /dev/null; then
        FSTYPE=xfs
        BOOTFSTYPE=xfs
        EFIFSTYPE=efi
    fi

    if [ `uname -m` = "ppc64" ]; then
        echo 'part None --fstype "PPC PReP Boot" --ondisk '$instdisk' --size 8' >> /tmp/partitionfile
    fi
    if [ -d /sys/firmware/efi ]; then
        echo 'bootloader --driveorder='$instdisk >> /tmp/partitionfile
        echo 'part /boot/efi --size 50 --ondisk '$instdisk' --fstype $EFIFSTYPE' >> /tmp/partitionfile
    else
        echo 'bootloader' >> /tmp/partitionfile
    fi

    echo "part /boot --size 512 --fstype $BOOTFSTYPE --ondisk $instdisk" >> /tmp/partitionfile
    echo "part swap --recommended --ondisk $instdisk" >> /tmp/partitionfile
    echo "part / --size 1 --grow --ondisk $instdisk --fstype $FSTYPE" >> /tmp/partitionfile

.. END_Partition_Definition_Script_Create_partition_script_example_redhat_sles

.. BEGIN_Partition_Definition_Script_Create_partition_script_example_ubuntu

The following is an example of the partition script on Ubuntu, the partitioning script is ``/install/custom/my-partitions.sh``: ::

	if [ -d /sys/firmware/efi ]; then
		echo "ubuntu-efi ::" > /tmp/partitionfile
		echo "    512 512 1024 fat32" >> /tmp/partitionfile
		echo '    $iflabel{ gpt } $reusemethod{ } method{ efi } format{ }' >> /tmp/partitionfile
		echo "    ." >> /tmp/partitionfile
	else
		echo "ubuntu-boot ::" > /tmp/partitionfile
		echo "100 50 100 ext4" >> /tmp/partitionfile
		echo '    $primary{ } $bootable{ } method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ /boot }' >> /tmp/partitionfile
		echo "    ." >> /tmp/partitionfile
	fi
	echo "500 10000 1000000000 ext4" >> /tmp/partitionfile
	echo "    method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ / }" >> /tmp/partitionfile
	echo "    ." >> /tmp/partitionfile
	echo "2048 512 300% linux-swap" >> /tmp/partitionfile
	echo "    method{ swap } format{ }" >> /tmp/partitionfile
	echo "    ." >> /tmp/partitionfile

.. END_Partition_Definition_Script_Create_partition_script_example_ubuntu

.. BEGIN_Partition_Definition_Script_Associate_partition_script_with_osimage_common

Run below commands to associate partition script with osimage: ::

        chdef -t osimage <osimagename> partitionfile='s:/install/custom/my-partitions.sh'
        nodeset <nodename> osimage=<osimage>

- The ``s:`` preceding the filename tells nodeset that this is a script.
- For RedHat, when nodeset runs and generates the ``/install/autoinst`` file for a node, it will add the execution of the contents of this script to the %pre section of that file. The ``nodeset`` command will then replace the ``#XCAT_PARTITION_START#...#XCAT_PARTITION_END#`` directives from the osimage template file with ``%include /tmp/partitionfile`` to dynamically include the tmp definition file your script created.
- For Ubuntu, when nodeset runs and generates the ``/install/autoinst`` file for a node, it will replace the ``#XCA_PARTMAN_RECIPE_SCRIPT#`` directive and add the execution of the contents of this script to the ``/install/autoinst/<node>.pre``, the ``/install/autoinst/<node>.pre`` script will be run in the preseed/early_command.

.. END_Partition_Definition_Script_Associate_partition_script_with_osimage_common

.. BEGIN_Partition_Disk_File_ubuntu_only

The disk file contains the name of the disks to partition in traditional, non-devfs format and delimited with space " ", for example : ::

    /dev/sda /dev/sdb

If not specified, the default value will be used.

**Associate partition disk file with osimage** ::

    chdef -t osimage <osimagename> -p partitionfile='d:/install/custom/partitiondisk'
    nodeset <nodename> osimage=<osimage>

- the ``d:`` preceding the filename tells nodeset that this is a partition disk file.
- For Ubuntu, when nodeset runs and generates the ``/install/autoinst`` file for a node, it will generate a script to write the content of the partition disk file to ``/tmp/install_disk``, this context to run the script will replace the ``#XCA_PARTMAN_DISK_SCRIPT#`` directive in ``/install/autoinst/<node>.pre``.

.. END_Partition_Disk_File_ubuntu_only

.. BEGIN_Partition_Disk_Script_ubuntu_only

The disk script contains a script to generate a partitioning disk file named ``/tmp/install_disk``. for example: ::

    rm /tmp/devs-with-boot 2>/dev/null || true;
    for d in $(list-devices partition); do
        mkdir -p /tmp/mymount;
        rc=0;
        mount $d /tmp/mymount || rc=$?;
        if [[ $rc -eq 0 ]]; then
            [[ -d /tmp/mymount/boot ]] && echo $d >>/tmp/devs-with-boot;
            umount /tmp/mymount;
        fi
    done;
    if [[ -e /tmp/devs-with-boot ]]; then
        head -n1 /tmp/devs-with-boot | egrep  -o '\S+[^0-9]' > /tmp/install_disk;
        rm /tmp/devs-with-boot 2>/dev/null || true;
    else
        DEV=`ls /dev/disk/by-path/* -l | egrep -o '/dev.*[s|h|v]d[^0-9]$' | sort -t : -k 1 -k 2 -k 3 -k 4 -k 5 -k 6 -k 7 -k 8 -g | head -n1 | egrep -o '[s|h|v]d.*$'`;
        if [[ "$DEV" == "" ]]; then DEV="sda"; fi;
        echo "/dev/$DEV" > /tmp/install_disk;
    fi;

If not specified, the default value will be used.

**Associate partition disk script with osimage** ::

    chdef -t osimage <osimagename> -p partitionfile='s:d:/install/custom/partitiondiskscript'
    nodeset <nodename> osimage=<osimage>

- the ``s:`` prefix tells ``nodeset`` that is a script, the ``s:d:`` preceding the filename tells ``nodeset`` that this is a script to generate the partition disk file.
- For Ubuntu, when nodeset runs and generates the ``/install/autoinst`` file for a node, this context to run the script will replace the ``#XCA_PARTMAN_DISK_SCRIPT#`` directive in ``/install/autoinst/<node>.pre``.

.. END_Partition_Disk_Script_ubuntu_only


.. BEGIN_Additional_preseed_configuration_file_ubuntu_only

To support other specific partition methods such as RAID or LVM in Ubuntu, some additional preseed configuration entries should be specified.

If using file way, ``c:<the absolute path of the additional preseed config file>``, the additional preseed config file contains the additional preseed entries in ``d-i ...`` syntax. When ``nodeset``, the ``#XCA_PARTMAN_ADDITIONAL_CFG#`` directive in ``/install/autoinst/<node>`` will be replaced with content of the config file.  For example: ::

    d-i partman-auto/method string raid
    d-i partman-md/confirm boolean true
	
If not specified, the default value will be used.
.. END_Additional_preseed_configuration_file_ubuntu_only

.. BEGIN_Additional_preseed_configuration_script_ubuntu_only

To support other specific partition methods such as RAID or LVM in Ubuntu, some additional preseed configuration entries should be specified.

If using script way, 's:c:<the absolute path of the additional preseed config script>',  the additional preseed config script is a script to set the preseed values with "debconf-set". When "nodeset", the #XCA_PARTMAN_ADDITIONAL_CONFIG_SCRIPT# directive in /install/autoinst/<node>.pre will be replaced with the content of the script.  For example: ::

    debconf-set partman-auto/method string raid
    debconf-set partman-md/confirm boolean true
	
If not specified, the default value will be used.
.. END_Additional_preseed_configuration_script_ubuntu_only
