* new OpenBMC python version installation steps:

    * install dependent packages for **Redhat**:

      yum install -y gcc python-devel libffi-devel openssl-devel libssh2-devel

    * install dependent packages for **ubuntu**:

      apt-get install gcc libffi-dev python-dev libssh2-1-dev

    * Install pip related packages:

      pip install gevent greenlet certifi chardet idna urllib3 requests paramiko cryptography ssh2-python==0.8.0 parallel-ssh scp
    
    * Install openbmc-python:
    
        * For **Redhat**, the package is available on xcat.org on-line repo, so install it directly:

        yum install xCAT-openbmc-py.noarch

        * For **ubuntu**:
          
        wget https://xcat.org/files/xcat/xcat-dep/2.x_Ubuntu/beta/xcat-openbmc-py_2.13.11-snap201802230441_all.deb

        dpkg -i xcat-openbmc-py_2.13.11-snap201802230441_all.deb

    * enable OpenBMC python version:

      export XCAT_OPENBMC_PYTHON=YES

      rpower cn1 status
