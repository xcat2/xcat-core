Virtual I/O Server (vioserver)
==============================

Expand the space of a logical volume
------------------------------------

#. SSH into the VIO server: ::

    ssh padmin@<vioserver hostname>  # Default password is padmin

    # If you need to get to the root user, once logged in: 
    $ oem_setup_env

#. List out the physical volumes: ``lspv`` ::

    $ lspv
    NAME             PVID                                 VG               STATUS
    hdisk0           00f60e599ff13987                     rootvg           active
    hdisk1           00f60e59afa94070                     vdiskvg          active

#. List out the volume groups: ``lsvg`` ::

    $ lsvg
    rootvg
    vdiskvg
    
#. Get more information about a specific volume group: ``lsvg <volume_group>`` ::

    $ lsvg vdiskvg
    VOLUME GROUP:       vdiskvg                  VG IDENTIFIER:  00f60e5900004c0000000147afa9411f
    VG STATE:           active                   PP SIZE:        256 megabyte(s)
    VG PERMISSION:      read/write               TOTAL PPs:      546 (139776 megabytes)
    MAX LVs:            256                      FREE PPs:       10 (2560 megabytes)
    LVs:                29                       USED PPs:       536 (137216 megabytes)
    OPEN LVs:           29                       QUORUM:         2 (Enabled)
    TOTAL PVs:          1                        VG DESCRIPTORS: 2
    STALE PVs:          0                        STALE PPs:      0
    ACTIVE PVs:         1                        AUTO ON:        yes
    MAX PPs per VG:     32512
    MAX PPs per PV:     1016                     MAX PVs:        32
    LTG size (Dynamic): 1024 kilobyte(s)         AUTO SYNC:      no
    HOT SPARE:          no                       BB POLICY:      relocatable
    PV RESTRICTION:     none                     INFINITE RETRY: no
    DISK BLOCK SIZE:    512                      CRITICAL VG:    no

#. List out the volume groups using the -lv option on lsvg:  ``lsvg -lv <volume_group>`` ::

    $ lsvg -lv vdiskvg
    vdiskvg:
    LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
    vdisk00n02          jfs        160     160     1    open/syncd    N/A
    vdisk00n03          jfs        160     160     1    open/syncd    N/A
    vdisk00n04          jfs        40      40      1    open/syncd    N/A
    vdisk00n05          jfs        40      40      1    open/syncd    N/A
    vdisk00n06          jfs        40      40      1    open/syncd    N/A
    vdisk00n07          jfs        4       4       1    open/syncd    N/A
    vdisk00n08          jfs        4       4       1    open/syncd    N/A
    vdisk00n09          jfs        4       4       1    open/syncd    N/A
    vdisk00n10          jfs        4       4       1    open/syncd    N/A
    ....
    vdisk00n29          jfs        4       4       1    open/syncd    N/A
    vdisk00n30          jfs        4       4       1    open/syncd    N/A
    
#. The lsvg command shows how many PPs there are in the volume group.

#. Remove a LV vdev to change from open/syncd to closed/syncd: ``rmvdev -vdev <lv_name>`` ::

    $ rmvdev -vdev vdisk00n30
    vtscsi28 deleted

    $ lsvg -lv vdiskvg
    vdiskvg:
    LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
    vdisk00n02          jfs        160     160     1    open/syncd    N/A
    vdisk00n03          jfs        160     160     1    open/syncd    N/A
    vdisk00n04          jfs        40      40      1    open/syncd    N/A
    ...
    ...
    vdisk00n29          jfs        4       4       1    open/syncd    N/A
    vdisk00n30          jfs        4       4       1    closed/syncd  N/A

#. Now remove the lv using rmlv to free up the PP:  ``rmlv <logical volume>`` ::

    $ lsvg vdiskvg | grep FREE
    MAX LVs:            256                      FREE PPs:       10 (2560 megabytes)

    $ rmlv vdisk00n30
    Warning, all data contained on logical volume vdisk00n30 will be destroyed.
    rmlv: Do you wish to continue? y(es) n(o)? y
    rmlv: Logical volume vdisk00n30 is removed.

    $ lsvg vdiskvg | grep FREE
    MAX LVs:            256                      FREE PPs:       14 (3584 megabytes)
    

#. Extend the Logical Volume: ::

    $ extendlv vdisk00n07 40

    $ lsvg -lv vdiskvg
    vdiskvg:
    LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
    vdisk00n02          jfs        160     160     1    open/syncd    N/A
    ...
    vdisk00n07          jfs        44      44      1    open/syncd    N/A
    ...
    

Add a physical volume into a volume group
-----------------------------------------

#. List out the physical volumes: ``lspv`` ::

    $ lspv
    NAME             PVID                                 VG               STATUS
    hdisk0           00f60e599ff13987                     rootvg           active
    hdisk1           00f60e59afa94070                     vdiskvg          active
    hdisk2           none                                 None              
    hdisk3           none                                 None              
    hdisk4           none                                 None              
    hdisk5           none                                 None              
    hdisk6           none                                 None              
    hdisk7           none                                 None              

#. Get details for a volume group (VG) using: ``lsvg <volume_group>`` :: 

    $ lsvg vdiskvg
    VOLUME GROUP:       vdiskvg                  VG IDENTIFIER:  00f60e5900004c0000000147afa9411f
    VG STATE:           active                   PP SIZE:        256 megabyte(s)
    VG PERMISSION:      read/write               TOTAL PPs:      546 (139776 megabytes)
    MAX LVs:            256                      FREE PPs:       18 (4608 megabytes)
    LVs:                7                        USED PPs:       528 (135168 megabytes)
    OPEN LVs:           7                        QUORUM:         2 (Enabled)
    TOTAL PVs:          1                        VG DESCRIPTORS: 2
    STALE PVs:          0                        STALE PPs:      0
    ACTIVE PVs:         1                        AUTO ON:        yes
    MAX PPs per VG:     32512                                     
    MAX PPs per PV:     1016                     MAX PVs:        32
    LTG size (Dynamic): 1024 kilobyte(s)         AUTO SYNC:      no
    HOT SPARE:          no                       BB POLICY:      relocatable 
    PV RESTRICTION:     none                     INFINITE RETRY: no
    DISK BLOCK SIZE:    512                      CRITICAL VG:    no

#. Extend the volume group: ``extendvg <volume_group> <device_name>`` ::

    $ extendvg vdiskvg hdisk2
    Changing the PVID in the ODM.
    
    Unable to add at least one of the specified physical volumes to the
    volume group. The maximum number of physical partitions (PPs) supported 
    by the volume group must be increased.  Use the lsvg command to display
    the current maximum number of physical partitions (MAX PPs per PV:) and
    chvg -factor to change the value.
    
    extendvg: Unable to extend volume group.
    
    $ lspv
    NAME             PVID                                 VG               STATUS
    hdisk0           00f60e599ff13987                     rootvg           active
    hdisk1           00f60e59afa94070                     vdiskvg          active
    hdisk2           00f60e59529c77f2                     None              
    hdisk3           none                                 None              
    hdisk4           none                                 None              
    hdisk5           none                                 None              
    hdisk6           none                                 None              
    hdisk7           none                                 None              
    

#. now what?....
$ lsvg vdiskvg
...
MAX PPs per PV:     1016                     MAX PVs:        32

$ chvg -factor 2 vdiskvg 
$ lsvg vdiskvg
...
MAX PPs per PV:     2032                     MAX PVs:        16

Now let's take a look at doing the extend... 

$ lsvg vdiskvg
...

VG PERMISSION:      read/write               TOTAL PPs:      546 (139776 megabytes)
MAX LVs:            256                      FREE PPs:       18 (4608 megabytes)
LVs:                7                        USED PPs:       528 (135168 megabytes)

$ extendvg vdiskvg hdisk2

$ lsvg vdiskvg 
VG PERMISSION:      read/write               TOTAL PPs:      1663 (425728 megabytes)
MAX LVs:            256                      FREE PPs:       1135 (290560 megabytes)  <=== SUCCESS!
LVs:                7                        USED PPs:       528 (135168 megabytes)


$ lsvg -lv vdiskvg
vdiskvg:
LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
vdisk00n02          jfs        160     160     1    open/syncd    N/A
vdisk00n03          jfs        160     160     1    open/syncd    N/A
vdisk00n04          jfs        40      40      1    open/syncd    N/A
vdisk00n05          jfs        40      40      1    open/syncd    N/A
vdisk00n06          jfs        80      80      1    open/syncd    N/A
vdisk00n07          jfs        44      44      1    open/syncd    N/A
vdisk00n11          jfs        4       4       1    open/syncd    N/A
$ extendlv vdisk00n06 270


Some error messages may contain invalid information
for the Virtual I/O Server environment.

0516-622 extendlv: Warning, cannot write lv control block data.
0516-622 extendlv: Warning, cannot write lv control block data.
$ lsvg -lv vdiskvg
vdiskvg:
LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
vdisk00n02          jfs        160     160     1    open/syncd    N/A
vdisk00n03          jfs        160     160     1    open/syncd    N/A
vdisk00n04          jfs        40      40      1    open/syncd    N/A
vdisk00n05          jfs        40      40      1    open/syncd    N/A
vdisk00n06          jfs        350     350     2    open/syncd    N/A <============ 
vdisk00n07          jfs        44      44      1    open/syncd    N/A
vdisk00n11          jfs        4       4       1    open/syncd    N/A


Create multiple SCSI profile for an LPAR
----------------------------------------

In this scenario, we are going to create another virtual SCSI profile for our management node  ``c910f02c06p23`` so that we are able to switch profiles between AIX and Linux. 

#. The current vhost for the server holding the AIX partition is: ::

        SVSA            Physloc                                      Client Partition ID
        --------------- -------------------------------------------- ------------------
        vhost21         U8233.E8B.100E58P-V1-C23                     0x00000017

        VTD                   vtdisk_p23
        Status                Available
        LUN                   0x8100000000000000
        Backing device        vg5lv1
        Physloc               
        Mirrored              N/A
 
#. Locate a physical volume to create the new volume group for LINUX.  ::

        $ lspv
        NAME             PVID                                 VG               STATUS
        hdisk0           00f60e589feeb90a                     rootvg           active
        hdisk1           00f60e58afa65a6e                     vdiskvg          active
        hdisk2           00f60e58286f497c                     vdisk2vg         active
        hdisk3           00f60e5828740e18                     vdisk3vg         active
        hdisk4           00f60e5828755bf1                     vdisk4vg         active
        hdisk5           00f60e582875fcbd                     vdisk5vg         active
        hdisk6           none                                 None              
        hdisk7           none                                 None              

   Will be using ``hdisk6`` to create the volume group


#. Create the new volume group using the ``mkvg`` command: ::

        $ mkvg -vg vdisk6vg hdisk6
        vdisk6vg
        0516-1254 mkvg: Changing the PVID in the ODM. 

    Verify the volume group was created: ::

        $ lspv
        NAME             PVID                                 VG               STATUS
        hdisk0           00f60e589feeb90a                     rootvg           active
        ...
        hdisk6           00f60e586479d7ec                     vdisk6vg         active
        hdisk7           none                                 None              

#. Create a logical volume of 1GB using 400PP: ::

        $ mklv -lv vg6p23 vdisk6vg 400 
        vg6p23

        $ lsvg -lv vdisk6vg
        vdisk6vg:
        LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
        vg6p23              jfs        400     400     1    closed/syncd  N/A



#. From the HMC GUI:


Went into VIOSERVER profile
- create new virtual adapter, and save the profile, number 32

Go to the LPAR profile, Virtual Adapter
- duplicated the AIX to Linux
- increased the max virtual adapter to 20
- assigned the CLIENT SCSI to 12, and set the adapter to 32, which was the new virtual adapter ID created in the virtual server 

Back in the vioserver profile, -> virtual adapter

- Only selected client partition can connect, select client partition p23 and give it client adapter 12

Select "this adapter is required for partition activition" so the "required=yes"


lsdev -virtual 

