Performance Tuning
==================

xCAT supports clusters of all sizes. This document is a collection of hints, tips, and special considerations when working with large clusters, especially a single server (management node or service node) manages more than 128 nodes.

The information in this document should be viewed as example data only. Many of the suggestions are based on anecdotal experiences and may not apply to your particular environment. Suggestions in different sections of this document may recommend different or conflicting settings since they may have been provided by different people for different cluster environments. Often there is a significant amount of flexiblity in most of these settings -- you will need to resolve these differences in a way that works best for your cluster.

.. toctree::
   :maxdepth: 2

   linux_os_tuning.rst
   xcatd_tuning.rst
   database_tuning.rst
   httpd_tuning.rst
