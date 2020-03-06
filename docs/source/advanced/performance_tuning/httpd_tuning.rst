Tuning httpd for xCAT node deployments
======================================

In xCAT, the Operation System provisioning over network is heavily relying on the web server (Apache 2.x). However, Apache 2.x is a general-purpose web server, the default settings may not allow enough simultaneous HTTP client connections to support a large cluster.


#. Tuning MaxRequestWorkers directive

By default, httpd is configured to use ``prefork`` module for **MPM**, which has a limit of 256 simultaneous requests. If slow httpd response observed during OS provisioning, you can increase **MaxRequestWorkers** directive for better performance.

For example, to avoid some nodes provisioning failure when rebooting all nodes in a large hierarchy stateless cluster ( one service node is serving 270 compute nodes ), increase the value from 256 to 1000.

    On Red Hat, change (or add) these directives in
    ::

        /etc/httpd/conf/httpd.conf


    On SLES (with Apache2), change (or add) these directives in
    ::

        /etc/apache2/server-tuning.conf


#. Having httpd Cache the Files It Is Serving

.. note:: this information was contributed by Jonathan Dye and is provided here as an example. The details may have to be changed for distro or apache version.

This is simplest if you set ``noderes.nfsserver`` to a separate apache server, and then you can configure it to reverse proxy and cache. For some reason ``mod_mem_cache`` doesn't seem to behave as expected, so you can use ``mod_disk_cache`` to achieve a similar result: make a ``tmpfs`` on the apache server and configure its mountpoint to be the directory that ``CacheRoot`` points to. Also tell it to ignore ``/install/autoinst`` since the caching settings are really aggressive. Do a recursive ``wget`` to warm the cache and watch the ``tmpfs`` fill up. Then do a bunch of kickstart installs. Before this, the apache server on the xcat management node may have been a bottleneck during kickstart installs. After this change, it no longer should be.

Here is the apache config file:
::

    ProxyRequests Off # don't be a proxy, just allow the reverse proxy

    CacheIgnoreCacheControl On
    CacheStoreNoStore On
    CacheIgnoreNoLastMod On

    CacheRoot /var/cache/apache2/tmpfs
    CacheEnable disk /install
    CacheDisable /install/autoinst
    CacheMaxFileSize 1073741824

    # CacheEnable mem /                   # failed attempt to do in-memory caching
    # MCacheSize 20971520
    # MCacheMaxObjectSize 524288000

    # through ethernet network
    # ProxyPass /install http://172.21.254.201/install

    # through IB network
    ProxyPass /install http://192.168.111.2/install


For more Apache 2.x tuning, see the external web page: `Apache Performance Tuning <http://httpd.apache.org/docs/2.4/misc/perf-tuning.html>`_

