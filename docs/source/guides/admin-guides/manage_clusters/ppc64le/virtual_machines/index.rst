Virtual Machines
================


The **Kernel-based Virtual Machine (KVM)** is a full virtualization solution for for Enterprise Linux distributions. KVM is known as the *de facto* open source virtualization mechanism. It is currently used by many software companies.

**IBM PowerKVM** is a product that leverages the Power resilience and performance with the openness of KVM, which provides several advantages:

*  Higher workload consolidation with processors overcommitment and memory sharing
*  Dynamic addition and removal of virtual devices
*  Microthreading scheduling granularity
*  Integration with **IBM PowerVC** and **OpenStack**
*  Simplified management using open source software
*  Avoids vendor lock-in
*  Uses POWER8 hardware features, such as SMT8 and microthreading

The xCAT based KVM solution offers users the ability to:

*  provision the hypervisor on bare metal nodes
*  provision virtual machines
*  migrate virtual machines to different hosts
*  install all versions of Linux supported in the standard xCAT provisioning methods (you can install stateless virtual machines, iSCSI, and scripted install virtual machines)
*  install copy on write instances of virtual machines
*  copy virtual machines


This section introduces the steps of management node preparation, KVM hypervisor setup and virtual machine management, and presents some typical problems and solutions on xCAT kvm support.

.. toctree::
   :maxdepth: 2

   kvmMN.rst
   powerKVM.rst
   manage_vms.rst
   FAQ.rst
