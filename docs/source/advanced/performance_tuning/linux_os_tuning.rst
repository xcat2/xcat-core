System Tuning Settings for Linux
==================================

Adjusting Operating System tunables can improve large scale cluster performance, avoid bottlenecks, and prevent failures. The following sections are a collection of suggestions that have been gathered from various large scale HPC clusters. You should investigate and evaluate the validity of each suggestion before applying them to your cluster.


#. Tuning Linux ulimits:

    The open file limits are important to high concurrence network services, such as ``xcatd``. For a large cluster, it is required to increase the number of open file limit to avoid **Too many open files** error. The default value is *1024* in most OS distributions, to add below configuration in ``/etc/security/limits.conf`` to increase to *14096*.
    ::

        *   soft    nofile     14096
        *   hard    nofile     14096


#. Tuning Network kernel parameters:

    There might be hundreds of hosts in a big network for large cluster, tuning the network kernel parameters for optimum throughput and latency could improve the performance of distributed application. For example, adding below configuration in ``/etc/sysctl.conf`` to increase the buffer size and queue length of **xCAT SSL listener** service access point ( port **3001** ).

    ::

        net.core.rmem_max = 33554432
        net.core.wmem_max = 33554432
        net.core.rmem_default = 65536
        net.core.wmem_default = 65536
        net.core.somaxconn = 8192

        net.ipv4.tcp_rmem = 4096 33554432 33554432
        net.ipv4.tcp_wmem = 4096 33554432 33554432
        net.ipv4.tcp_mem= 33554432 33554432 33554432
        net.ipv4.route.flush=1
        net.core.netdev_max_backlog=1500


    And if you encounter **Neighbour table overflow** error, it meams there are two many ARP requests and the server cannot reply. Tune the ARP cache with below parameters.

    ::

        net.ipv4.conf.all.arp_filter      = 1
        net.ipv4.conf.all.rp_filter       = 1
        net.ipv4.neigh.default.gc_thresh1 = 30000
        net.ipv4.neigh.default.gc_thresh2 = 32000
        net.ipv4.neigh.default.gc_thresh3 = 32768
        net.ipv4.neigh.ib0.gc_stale_time  = 2000000


    For more tunable parameters, you can refer to `Linux System Tuning Recommendations <https://www.ibm.com/developerworks/community/wikis/home?lang=en#!/wiki/Welcome%20to%20High%20Performance%20Computing%20(HPC)%20Central/page/Linux%20System%20Tuning%20Recommendations>`_.
