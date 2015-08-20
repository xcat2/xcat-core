Install PostgreSQL
==================

PostgreSQL packages are shipped as part of most Linux Distributions.


Redhat Enterprise Linux
-----------------------

Using yum, install the following rpms: ::

    yum install postgresql-libs-* postgresql-server-* postgresql-*
    yum install perl-DBD-Pg*


Suse Linux Enterprise Server
----------------------------

**Note:** On SLES, ``perl-DBD`` packages are provided on the SDK iso images. 

Using zyppr, install the following rpms: ::

    zyppr install postgresql-libs-* postgresql-server-* postgresql-*
    zyppr install perl-DBD-Pg*


Debian/Ubuntu 
-------------

Using apt, install the following packages: ::

    apt install postgresql libdbd-pg-perl


