Install PostgreSQL
==================

PostgreSQL packages are shipped as part of most Linux Distributions.


Red Hat Enterprise Linux
------------------------

Using yum, install the following rpms: ::

    yum install postgresql*
    yum install perl-DBD-Pg


Suse Linux Enterprise Server
----------------------------

**Note:** On SLES, ``perl-DBD`` packages are provided on the SDK iso images. 

Using zyppr, install the following rpms: ::

    zypper install postgresql*
    zypper install perl-DBD-Pg


Debian/Ubuntu 
-------------

Using apt, install the following packages: ::

    apt install postgresql libdbd-pg-perl


