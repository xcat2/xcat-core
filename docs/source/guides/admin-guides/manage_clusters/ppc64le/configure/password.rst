Configure passwords
===================

#. Configure the system password for the ``root`` user on the compute nodes.

   * Set using the :doc:`chtab </guides/admin-guides/references/man8/chtab.8>` command:  ::

       chtab key=system passwd.username=root passwd.password=abc123

     To encrypt the password using ``openssl``, use the following command: ::

       chtab key=system passwd.username=root passwd.password=`openssl passwd -1 abc123`


#. Configure the passwords for Management modules of the compute nodes.

   * For OpenBMC managed systems: ::

         chtab key=openbmc passwd.username=root passwd.password=0penBmc

   * For IPMI/BMC managed systems: ::

         chtab key=ipmi passwd.username=ADMIN passwd.password=admin

   * For HMC managed systems: ::

         chtab key=hmc passwd.username=hscroot passwd.password=abc123

     If the username/password is different for multiple HMCs, set the ``username`` and ``password`` attribute for each HMC node object in xCAT

   * For Blade managed systems: ::

         chtab key=blade passwd.username=USERID passwd.password=PASSW0RD

   * For FSP/BPA (Flexible Service Processor/Bulk Power Assembly) the factory default passwords must be changed before running commands against them. ::

         rspconfig frame general_passwd=general,<newpassword>
         rspconfig frame admin_passwd=admin,<newpassword>
         rspconfig frame HMC_passwd=,<newpassword>


#. If using the xCAT REST API

    #. Create a non-root user that will be used to make the REST API calls. ::

        useradd xcatws
        passwd xcatws # set the password

    #. Create an entry for the user into the xCAT ``passwd`` table. ::

        chtab key=xcat passwd.username=xcatws passwd.password=<xcatws_password>

    #. Set a policy in the xCAT ``policy`` table to allow the user to make calls against xCAT. ::

        mkdef -t policy 6 name=xcatws rule=allow


    When making calls to the xCAT REST API, pass in the credentials using the following attributes: ``userName`` and ``userPW``
