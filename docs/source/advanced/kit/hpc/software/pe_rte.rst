Parallel Environment Runtime Edition (PE RTE)
=============================================

xCAT software kits for PE RTE for Linux is available on: [#]_

    * PE RTE 1.3 1 and newer



PE RTE and ``mlnxofed_ib_install`` Conflict 
-------------------------------------------

PPE requires the 32-bit version of ``libibverbs``.  The default behavior of the ``mlnxofed_ib_install`` postscript used to install the Mellanox OFED Infiniband (IB) driver is to remove any of the old IB related packages when installing.  To bypass this behavior, set the variable ``mlnxofed_options=--force`` when running the ``mlnxofed_ib_install`` script.


Install Multiple Versions
-------------------------

Beginning with **PE RTE 1.2.0.10**, the packages are designed to allow for multiple versions of PE RTE to coexist on the same machine.

The default behavior of xCAT software kits is to only allow one version of a ``kitcomponent`` to be associated with an xCAT osimage.  
When using ``addkitcomp`` to add a newer version of a kit component, xCAT will first remove the old version of the kit component before adding the new one.  

To add multiple versions of PE RTE kit components to the same osimage, use the ``-n | --noupgrade`` option.  For example, to add PE RTE 1.3.0.1 and PE RTE 1.3.0.2 to the ``compute`` osimage: ::

    addkitcomp -i compute pperte_compute-1.3.0.1-0-rhels-6-x86_64
    addkitcomp -i compute -n pperte_compute-1.3.0.2-0-rhels-6-x86_64

POE hostlist
------------

When running parallel jobs, POE requires the user pass it a host list file.  xCAT can help to create this hostlist file by running the ``nodels`` command against the desired node range and redirecting to a file. ::

      nodels compute > /tmp/hostlist

Known Issues
------------

* **[PE RTE 1.3.0.7]** - For developers creating the complete software kit.  The src rpm is no longer required.   It is recommended to create the new software kit for PE RTE 1.3.0.7 from scratch and not to use the older kits as a starting point. 

* **[PE RTE 1.3.0.7]** - When upgrading ``ppe_rte_man`` in a diskless image, there may be errors reported during the genimage process.  The new packages are actually upgraded, so the errors can be ignored with low risk. 

* **[PE RTE 1.3.0.1 to 1.3.0.6]** - When uninstalling or upgrading ppe_rte_man in an diskless image, ``genimage <osimage>`` may fail and stop an an error.  To workaround, simply rerun ``genimage <osimage>`` to finish the creation of the diskless image 



.. [#] If using older releases of PE RTE, refer to  `IBM HPC Stack in an xCAT Cluster <https://sourceforge.net/p/xcat/wiki/IBM_HPC_Stack_in_an_xCAT_Cluster/>`_
