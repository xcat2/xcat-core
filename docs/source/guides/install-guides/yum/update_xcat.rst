Updating xCAT
=============

If at a later date you want to update xCAT on the Management Node, first, update the software repositories and then run: ::

    yum clean metadata # or, yum clean all
    yum update '*xCAT*'

    # To check and update the packages provided by xcat-dep:
    yum update '*xcat*'

If running in a hierarchical environment, Service Nodes must be the same xCAT version as the Management Node. To update Service Nodes: `Diskless <https://xcat-docs.readthedocs.io/en/stable/advanced/hierarchy/provision/diskless_sn.html#update-service-node-stateless-image>`_ or `Diskful <https://xcat-docs.readthedocs.io/en/stable/advanced/hierarchy/provision/diskful_sn.html#update-service-node-diskful-image>`_ 
