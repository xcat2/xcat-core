
#######
rscan.1
#######

.. highlight:: perl


****
NAME
****


\ **rscan**\  - Collects node information from one or more hardware control points.


********
SYNOPSIS
********


\ **rscan [-h|-**\ **-help]**\ 

\ **rscan [-v|-**\ **-version]**\ 

\ **rscan [-V|-**\ **-verbose]**\  \ *noderange*\   \ **[-u][-w][-x|-z]**\ 


***********
DESCRIPTION
***********


The rscan command lists hardware information for each node managed by the hardware control points specified in noderange.

For the management module of blade, if the blade server is a Flex system P node, the fsp belongs to the blade server also will be scanned.

For the KVM host, all the KVM guests on the specified KVM host will be scanned.

Note: The first line of the output always contains information about the hardware control point. When using the rscan command to generate output for HMC or IVM hardware control points, it provides the FSPs and BPAs as part of the output. The only exception is the rscan -u flag which provides updates made hardware control point in the xCAT database.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\           Display usage message.

\ **-v|-**\ **-version**\           Command Version.

\ **-V|-**\ **-verbose**\           Verbose output.

\ **-u**\           Updates and then prints out node definitions in the xCAT database for CEC/BPA. It updates the existing nodes that contain the same mtms and serial number for nodes managed by the specified hardware control point. This primarily works with CEC/FSP and frame/BPA nodes when the node name is not the same as the managed system name on hardware control point (HMC), This flag will update the BPA/FSP node name definitions to be listed as the managed system name in the xCAT database.

For the Flex system manager, both the blade server and fsp object of xCAT will be updated if the mpa and slot id are matched to the object which has been defined in the xCAT database.

For KVM host, the information of the KVM guests which have been defined in xCAT database will be updated.

Note: only the matched object will be updated.

\ **-n**\           For KVM host, the information of the KVM guests, which are not defined in xCAT database yet, will be written into xCAT database.

\ **-w**\           Writes output to xCAT database.

For KVM host, updates the information of the KVM guests which have been defined in xCAT database with the same node name and KVM host, creates the definition of the KVM guests which do not exist in xCAT database , and notifies user about the conflicting KVM guests that the name exist in xCAT database but the kvm host is different.

\ **-x**\           XML format.

\ **-z**\           Stanza formated output.

Note: For KVM host, -z is not a valid option for rscan.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To list all nodes managed by HMC hmc01 in tabular format, enter:


.. code-block:: perl

  rscan hmc01


Output is similar to:


.. code-block:: perl

   type    name                       id   type-model  serial-number  address
 
   hmc     hmc01                           7310-C05    10F426A        hmc01
   fsp     Server-9117-MMA-SN10F6F3D       9117-MMA    10F6F3D        3.3.3.197
   lpar    lpar3                       4   9117-MMA    10F6F3D
   lpar    lpar2                       3   9117-MMA    10F6F3D
   lpar    lpar1                       2   9117-MMA    10F6F3D
   lpar    p6vios                      1   9117-MMA    10F6F3D


2. To list all nodes managed by IVM ivm02 in XML format and write the output to the xCAT database, enter:


.. code-block:: perl

  rscan ivm02 -x -w


Output is similar to:


.. code-block:: perl

  <Node>
    <cons></cons>
    <profile></profile>
    <parent></parent>
    <serial>10B7D1G</serial>
    <model>9133-55A</model>
    <node>Server-9133-55A-10B7D1G</node>
    <mgt>ivm</mgt>
    <nodetype>fsp</nodetype>
    <hcp>ivm02</hcp>
    <groups>fsp,all</groups>
    <id>10</id>
  </Node>
 
  <Node>
    <cons>ivm</cons>
    <profile>lpar01</profile>
    <parent>Server-9133-55A-10B7D1G</parent>
    <serial></serial>
    <model></model>
    <node>lpar01</node>
    <mgt>ivm</mgt>
    <nodetype>lpar,osi</nodetype>
    <hcp>ivm02</hcp>
    <groups>lpar,all</groups>
    <id>1</id>
  <Node>
 
  </Node>
    <cons>ivm</cons>
    <profile>lpar02</profile>
    <parent>Server-9133-55A-10B7D1G</parent>
    <serial></serial>
    <model></model>
    <node>lpar02</node>
    <mgt>ivm</mgt>
    <nodetype>lpar,osi</nodetype>
    <hcp>ivm02</hcp>
    <groups>lpar,all</groups>
    <id>2</id>
  </Node>


3. To list all nodes managed by HMC hmc02 in stanza format and write the output to the xCAT database, enter:


.. code-block:: perl

  rscan hmc02 -z -w


Output is similar to:


.. code-block:: perl

   Server-9458-100992001Y_B:
     objtype=node
     nodetype=bpa
     id=2
     model=9458-100
     serial=992001Y
     hcp=hmc02
     profile=
     parent=
     groups=bpa,all
     mgt=hmc
     cons=
 
   Server-9119-590-SN02C5F9E:
     objtype=node
     type=fsp
     id=10
     model=9119-590
     serial=02C5F9E
     hcp=hmc02
     profile=
     parent=Server-9458-100992001Y_B
     groups=fsp,all
     mgt=hmc
     cons=
 
   lpar01:
     objtype=node
     nodetype=lpar,osi
     id=1
     model=
     serial=
     hcp=hmc02
     profile=lpar01
     parent=Server-9119-590-SN02C5F9E
     groups=lpar,all
     mgt=hmc
     cons=hmc
 
   lpar02:
     objtype=node
     nodetype=lpar,osi
     id=2
     model=
     serial=
     hcp=hmc02
     profile=lpar02
     parent=Server-9119-590-SN02C5F9E
     groups=lpar,all
     mgt=hmc
     cons=hmc


4. To update definitions of nodes, which is managed by hmc03, enter:


.. code-block:: perl

  rscan hmc03 -u


Output is similar to:


.. code-block:: perl

   #Updated following nodes:
   type    name                           id      type-model  serial-number  address
   fsp     Server-9125-F2A-SN0262672-B    3       9125-F2A    0262672        192.168.200.243


5. To collects the node information from one or more hardware control points on zVM AND populate the database with details collected by rscan:


.. code-block:: perl

  rscan gpok2 -w


Output is similar to:


.. code-block:: perl

   gpok2:
     objtype=node
     arch=s390x
     os=sles10sp3
     hcp=gpok3.endicott.ibm.com
     userid=LINUX2
     nodetype=vm
     parent=POKDEV61
     groups=all
     mgt=zvm


6. To scan the Flex system cluster:


.. code-block:: perl

  rscan cmm01


Output is similar to:


.. code-block:: perl

   type    name                  id      type-model  serial-number  mpa        address
   cmm     AMM680520153          0       789392X     100048A        cmm01      cmm01
   blade   SN#YL10JH184067       1       789542X     10F752A        cmm01      12.0.0.9
   xblade  SN#YL10JH184068       2       789542X     10F652A        cmm01      12.0.0.10
   blade   SN#YL10JH184079       3       789542X     10F697A        cmm01      12.0.0.11


7. To update the Flex system cluster:


.. code-block:: perl

  rscan cmm01 -u


Output is similar to:


.. code-block:: perl

   cmm    [AMM680520153]         Matched To =>[cmm01]
   blade  [SN#YL10JH184067]      Matched To =>[cmm01node01]
   blade  [SN#YL10JH184079]      Matched To =>[cmm01node03]


8. To scan the KVM host "hyp01", write the KVM guest information into xCAT database:


.. code-block:: perl

  rscan hyp01 -w


9. To update definitions of kvm guest, which is managed by hypervisor hyp01, enter:


.. code-block:: perl

  rscan hyp01 -u


Output is similar to:


.. code-block:: perl

   type    name     hypervisor     id     cpu     memory     nic     disk
   kvm     kvm2     hyp01          12     2       1024       virbr0  /install/vms/kvm2.hda.qcow2
   kvm     kvm1     hyp01          10     1       1024       virbr0  /install/vms/kvm1.hda.qcow2



*****
FILES
*****


/opt/xcat/bin/rscan


********
SEE ALSO
********


lsslp(1)|lsslp.1

