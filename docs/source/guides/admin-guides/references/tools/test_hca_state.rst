test_hca_state
==============

::

    test_hca_state (part of the BEF_Scripts for xCAT) v3.2.27

    Usage: test_hca_state NODERANGE [FILTER] | xcoll

        --help  Display this help output.

        NODERANGE
            An xCAT noderange on which to operate.

        FILTER
            A string to match in the output, filtering out everything else.  This
            is passed to "egrep" and can be a simple string or a regular
            expression.

    Purpose:  
    
        This tool provides a quick and easily repeatable method of
        validating key InfiniBand adapter (HCA) and node based InfiniBand
        settings across an entire cluster.  
        
        Having consistent OFED settings, and even HCA firmware, can be very
        important for a properly functioning InfiniBand fabric.  This tool
        can help you confirm that your nodes are using the settings you
        want, and if any nodes have settings discrepancies.


    Example output:

        #
        # This example shows that all of rack 14 has the same settings.
        #
        root@mgt1:~ # test_hca_state rack14 | xcoll
        ====================================
        rack14
        ====================================
        OFED Version: MLNX_OFED_LINUX-2.0-3.0.0.3 (OFED-2.0-3.0.0):
        mlx4_0
          PCI: Gen3
          Firmware installed: 2.30.3200
          Firmware active:    2.30.3200
          log_num_mtt:      20
          log_mtts_per_seg: 3
          Port 1: InfiniBand    phys_state: 5: LinkUp
            state: 4: ACTIVE
            rate: 40 Gb/sec (4X FDR10)
            symbol_error: 0
            port_rcv_errors: 0
          Port 2: InfiniBand    phys_state: 3: Disabled
            state: 1: DOWN
            rate: 10 Gb/sec (4X)
            symbol_error: 0
            port_rcv_errors: 0
        
          IPoIB
            recv_queue_size: 8192
            send_queue_size: 8192
            ib0:
              Mode: datagram
              MTU:  4092
              Mode: up
            ib1:
              Mode: datagram
              MTU:  4092
              Mode: up
    
    
        #
        # This example uses a FILTER on the word 'firmware'.  In this case, we've
        # upgraded the firmware across rack11 and rack12.  
        #
        #   - On rack11, we've also restarted the IB stack (/etc/init.d/openibd
        #     restart) to activate the new firmware.  
        #
        #   - Rack 12 has also been updated, as we can see from the 'Firmware
        #     installed' line, but it's nodes are still running with their prior
        #     level of firmware and must reload the IB stack to have it take effect.
        #
        root@mgt1:~ # test_hca_state rack11,rack12 firmware | xcoll
        ====================================
        rack11
        ====================================
          Firmware installed: 2.30.3200
          Firmware active:    2.30.3200
        
        ====================================
        rack12
        ====================================
          Firmware installed: 2.30.3200
          Firmware active:    2.11.1260
    
    
Author:  Brian Finley
