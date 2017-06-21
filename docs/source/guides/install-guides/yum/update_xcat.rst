Updating xCAT
=============

If at a later date you want to update xCAT, first, update the software repositories and then run: ::

    yum clean metadata # or, yum clean all
    yum update '*xCAT*'

    # To check and update the packages provided by xcat-dep:
    yum update '*xcat*'
