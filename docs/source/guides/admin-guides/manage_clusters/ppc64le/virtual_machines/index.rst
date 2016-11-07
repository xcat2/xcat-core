Virtual Machines
================


xCAT supports the following virtualization infrastructures:
 
**Kernel-based Virtual Machine (KVM)**: 
  A full virtualization solution for Enterprise Linux distributions, known as the *de facto* open source virtualization mechanism and currently used by many software companies.

**IBM PowerKVM**: 
  A product that leverages the Power resilience and performance with the openness of KVM, which provides several advantages:

  *  Higher workload consolidation with processors overcommitment and memory sharing
  *  Dynamic addition and removal of virtual devices
  *  Microthreading scheduling granularity
  *  Integration with **IBM PowerVC** and **OpenStack**
  *  Simplified management using open source software
  *  Avoids vendor lock-in
  *  Uses POWER8 hardware features, such as SMT8 and microthreading

The xCAT based KVM solution offers users the ability to:

*  provision the hypervisor on bare metal nodes
*  provision virtual machines with the any OS supported in xCAT
*  migrate virtual machines to different hosts
*  install copy on write instances of virtual machines
*  clone virtual machines

This section introduces the steps of management node preparation, hypervisor setup and virtual machine management, and presents some typical problems and solutions on xCAT kvm support.

.. toctree::
   :maxdepth: 2

   kvmMN.rst
   hypervisorKVM.rst
   manage_vms.rst
   FAQ.rst
