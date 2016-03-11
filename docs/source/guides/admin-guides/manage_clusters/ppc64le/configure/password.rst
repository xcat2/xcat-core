Configure passwords
===================

#. Configure the system password for the ``root`` user on the compute nodes.

     * Set using the :doc:`chtab </guides/admin-guides/references/man8/chtab.8>` command: (**Recommended**) ::

          chtab key=system passwd.username=root passwd.password=abc123

       To encrypt the password using ``openssl``, use the following command: ::

          chtab key=system passwd.username=root passwd.password=`openssl passwd -1 abc123`

     * Directly edit the passwd table using the :doc:`tabedit </guides/admin-guides/references/man8/tabedit.8>` command. 


#. Configure the passwords for Management modules of the compute nodes.

   * For IPMI/BMC managed systems: ::

         chtab key=ipmi passwd.username=USERID passwd.password=PASSW0RD

   * For HMC managed systems: ::

         chtab key=hmc passwd.username=hscroot passwd.password=abc123 

     The username and password for the HMC can be assigned directly to the HMC node object definition in xCAT. This is needed when the HMC username/password is different for each HMC. ::
      
         mkdef -t node -o hmc1 groups=hmc,all nodetype=ppc hwtype=hmc mgt=hmc \
         username=hscroot password=hmcPassw0rd

   * For Blade managed systems: ::

         chtab key=blade passwd.username=USERID passwd.password=PASSW0RD 

   * For FSP/BPA (Flexible Service Processor/Bulk Power Assembly), if the passwords are set to the factory defaults, you must change them before running and commands to them. ::

         rspconfig frame general_passwd=general,<newpassword>
         rspconfig frame admin_passwd=admin,<newpassword>
         rspconfig frame HMC_passwd=,<newpassword>


#. If the REST API is being used configure a user and set a policy rule in xCAT.

    #. Create a non root user that will be used to make the REST API calls. ::

        useradd xcatws
        passwd xcatws # set the password

    #. Create an entry for the user into the xCAT ``passwd`` table. ::

        chtab key=xcat passwd.username=xcatws passwd.password=<xcatws_password>

    #. Set a policy in the xCAT ``policy`` table to allow the user to make calls against xCAT. ::

        mkdef -t policy 6 name=xcatws rule=allow 


   When making calls to the xCAT REST API, pass in the credentials using the following attributes: ``userName`` and ``userPW``
