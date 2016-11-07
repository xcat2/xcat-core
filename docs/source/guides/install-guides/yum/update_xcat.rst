Updating xCAT
=============

If at a later date you want to update xCAT, first, update the software repositories and then run: ::

    yum clean metadata # or, yum clean all
    yum update '*xCAT*'

If you upgraded xCAT on a management node in hierachy environment (with service node), Please run "updatenode <service node> -P servicenode" to update the xCAT credentials on service node.

