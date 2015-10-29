Deploy CUDA nodes
=================

Diskful 
-------

* To provision diskful nodes using osimage ``rhels7.2-ppc64le-install-cudafull``: ::

    nodeset <noderange> osimage=rhels7.2-ppc64le-install-cudafull
    rsetboot <noderange> net
    rpower <noderange> boot 


Diskless
--------

* To provision diskless nodes using osimage ``rhels7.2-ppc64le-netboot-cudafull``: ::

    nodeset <noderange> osimage=rhels7.2-ppc64le-netboot-cudafull
    rsetboot <noderange> net
    rpower <noderange> boot 

