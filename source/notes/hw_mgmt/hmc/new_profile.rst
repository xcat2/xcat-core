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

Create AIX cluster (cluster 4)

Cluster 1: 
        c910f02c06p02 - RHELS 6.6 
        ...
        c910f02c06p08

Cluster 2:
        c910f02c06p09 - SLES 11.3
        ...
        c910f02c06p15

Cluster 3:
        c910f02c06p16 - RHELS 7.1
        ...
        c910f02c06p22

c910f02c06p23 - 29
1 mgmt node
2 service node
4 compute


AIX DISK: 

SVSA            Physloc                                      Client Partition ID
--------------- -------------------------------------------- ------------------
vhost21         U8233.E8B.100E58P-V1-C23                     0x00000017

VTD                   vtdisk_p23
Status                Available
LUN                   0x8100000000000000
Backing device        vg5lv1
Physloc               
Mirrored              N/A

LINUX DISK:

$ mkvg -help
Usage: mkvg [-f] [-vg VolumeGroup] PhysicalVolume ...

       The mkvg command creates a new volume group, using the physical
       volumes represented by the PhysicalVolume parameter.

       -f     Forces the volume group to be created on the specified
              physical volume

       -vg    Specifies the volume group name rather than
              having the name generated automatically.

$ mkvg -vg vdisk6vg hdisk6
vdisk6vg
0516-1254 mkvg: Changing the PVID in the ODM. 

$ lspv
NAME             PVID                                 VG               STATUS
hdisk0           00f60e589feeb90a                     rootvg           active
hdisk1           00f60e58afa65a6e                     vdiskvg          active
hdisk2           00f60e58286f497c                     vdisk2vg         active
hdisk3           00f60e5828740e18                     vdisk3vg         active
hdisk4           00f60e5828755bf1                     vdisk4vg         active
hdisk5           00f60e582875fcbd                     vdisk5vg         active
hdisk6           00f60e586479d7ec                     vdisk6vg         active
hdisk7           none                                 None              

Create a logical volume of 1GB using 400PP

$ mklv -help
Usage: mklv [-mirror] [-lv LogicalVolume | -prefix Prefix]
            [-type Type] VolumeGroup Size [PhysicalVolume ...]

       Creates a logical volume.

       -mirror    Turns on mirroring.

       -lv        Specifies the logical volume name to use instead of
                  using a system-generated name.

       -prefix    Specifies the Prefix to use instead of the prefix
                  in a system-generated name for the new logical
                  volume.

       -type      Sets the logical volume type.

$ mklv -lv vg6p23 vdisk6vg 400 
vg6p23

$ lsvg -lv vdisk6vg
vdisk6vg:
LV NAME             TYPE       LPs     PPs     PVs  LV STATE      MOUNT POINT
vg6p23              jfs        400     400     1    closed/syncd  N/A



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

