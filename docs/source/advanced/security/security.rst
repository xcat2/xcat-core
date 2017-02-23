Transmission Channel
--------------------

The xCAT daemon uses SSL to only allow authorized users to run xCAT commands. All xCAT commands are initiated as an xCAT **client**, even when run commands from the xCAT management node. This **client** opens an SSL socket to the xCAT daemon, sends the command and receives responses through this one socket. xCAT has configured the certificate for root, if you nee to authorize other users, refer to the section below.


.. toctree::
   :maxdepth: 2

   certs.rst

Commands Access Control
-----------------------

Except SSL channel, xCAT only authorize root on the management node to run **xCAT** commands by default. But xCAT can be configured to allow both **non-root users** and **remote users** to run limited xCAT commands. For remote users, we mean the users who triggers the xCAT commands from other nodes and not have to login to the management node. xCAT uses the **policy** table to control who has authority to run specific xCAT commands. For a full explanation of the **policy** table, refer to :doc:`policy </guides/admin-guides/references/man5/policy.5>` man page. 


Granting Users xCAT Privileges
``````````````````````````````

To give a non-root user all xCAT commands privileges, run ``tabedit policy`` and add a line: ::

    "6","<username>",,,,,,"allow",,

Where <username> is the name of the user that you are granting privileges to. In the above case, this user can now perform all xCAT commands, including changing the ``policy`` table to grant right to other users, so this should be used with caution.

You may only want to grant users limited access. One example is that one user may only be allowed to run ``nodels``. This can be done as follows: ::

    "6","<username>",,"nodels",,,,"allow",,

If you want to grant all users the ability to run nodels, add this line:  ::

    "6.1","*",,"nodels",,,,"allow",,

You also can do this by running: ::

    chdef -t policy -o 6.1 name=* commands=nodels rule=allow

**Note** Make sure the directories that contain the xCAT commands are in the user's ``$PATH``. If not, add them to ``$PATH`` as appropriate way in your system. ::

    echo $PATH | grep xcat
    /opt/xcat/bin:/opt/xcat/sbin: ....... 

Extra Setup for Remote Commands
```````````````````````````````

To give a user the ability to run remote commands (xdsh, xdcp, psh, pcp) in some node, except above steps, also need to run below steps:  ::
  
    su - <username>
    xdsh <noderange> -K

This will setup the user and root ssh keys for the user under the ``$HOME/.ssh`` directory of the user on the nodes. The root ssh keys are needed for the user to run the xCAT commands under the xcatd daemon, where the user will be running as root. **Note**: the uid for the user should match the uid on the management node and a password for the user must have been set on the nodes. 


Set Up Login Node (Remote Client)
`````````````````````````````````

In some cases, you don't want your **non-root** user login to management node but still can run some xCAT commands. This time, you need setup a login node(i.e. remote client) for these users.

Below are the steps of how to set up a login node.

1. Install the xCAT client

  In order to avoid dependency problems on different distros, we recommend creating repository first by referring to links below.

  * :doc:`Configure xCAT Software Repository in RHEL</guides/install-guides/yum/configure_xcat>`

  * `Configure the Base OS Repository in SUSE <http://xcat-docs.readthedocs.org/en/latest/guides/install-guides/zypper/prepare_mgmt_node.html#configure-the-base-os-repository>`_
 
  * `Configure the Base OS Repository in Ubuntu <http://xcat-docs.readthedocs.org/en/latest/guides/install-guides/apt/prepare_mgmt_node.html#configure-the-base-os-repository>`_


  Then install ``xCAT-client``.

  **[RHEL]** ::
  
      yum install  xCAT-client

  **[SUSE]** ::
      
      zypper install  xCAT-client

  **[Ubuntu]** ::

      apt-get install  xCAT-client

2. Configure login node 

  When running on the login node, the environment variable **XCATHOST** must be export to the name or address of the management node and the port for connections (usually 3001). ::

     export XCATHOST=<myManagmentServer>:3001

  Using below command to add xCAT commands to your path.  ::

    source /etc/profile.d/xcat.sh

  The userids and groupids of the non-root users should be kept the same on the login node, the management node, service nodes and compute nodes.

  The remote not-root user still needs to set up the credentials for communication with management node. By running the ``/opt/xcat/share/xcat/scripts/setup-local-client.sh <username>`` command as root in management node, the credentials are generated in <username>'s ``$HOME/.xcat`` directory in management node. These credential files must be copied to the <username>'s ``$HOME/.xcat`` directory on the login node.  **Note**: After ``scp``, in the login node, you must make sure the owner of the credentials is <username>.

  Setup your ``policy`` table on the management node with the permissions that you would like the non-root id to have. 

  At this time, the non-root id should be able to execute any commands that have been set in the ``policy`` table from the Login Node.

  If any remote shell commands (psh,xdsh) are needed, then you need to follow `Extra Setup For Remote Commands`_. 


Auditing
--------

xCAT logs all xCAT commands run by the xcatd daemon to both the syslog and the auditlog table in the xCAT database. The commands that are audited can be "ALL" xCAT commands or a list provided by the admin. The auditlog table allows the admin to monitor any attacks against the system or simply over use of resources. The auditlog table is store in the xCAT database and contains the following record. ::

    # tabdump -d auditlog
    recid:i     The record id.
    audittime:	The timestamp for the audit entry.
    userid:	The user running the command.
    clientname:	The client machine, where the command originated.
    clienttype:	Type of command: cli,java,webui,other.
    command:	Command executed.
    noderange:	The noderange on which the command was run.
    args:	The command argument list.
    status:	Allowed or Denied.
    comments:	Any user-provided notes.
    disable:	Do not use.  tabprune will not work if set to yes or 1 


Password Management
-------------------

xCAT is required to store passwords for various logons so that the application can login to the devices without having to prompt for a password. The issue is how to securely store these passwords.

Currently xCAT stores passwords in ``passwd`` table. You can store them as plain text, you can also store them as MD5 ciphertext.  

Here is an example about how to store a MD5 encrypted password for root in ``passwd`` table.  ::

    tabch key=system passwd.username=root passwd.password=`openSSL passwd -1 <password>`



Nodes Inter-Access in The Cluster
---------------------------------


xCAT performs the setup for root to be able to ssh without password from the Management Node(MN) to all the nodes in the cluster. All nodes are able to ssh to each other without password or being prompted for a ``known_host`` entry, unless restricted. Nodes cannot ssh back to the Management Node or Service Nodes without a password by default. 

xCAT generates, on the MN, a new set of ssh hostkeys for the nodes to share, which are distributed to all the nodes during install. If ssh keys do not already exist for root on the MN, it will generate an id_rsa public and private key pair.

During node install, xCAT sends the ssh hostkeys to ``/etc/ssh`` on the node, the id_rsa private key and authorized_keys file to root's .ssh directory on the node to allow root on the MN to ssh to the nodes without password. This key setup on the node allows the MN to ssh to the node with no password prompting.

On the MN and the nodes, xCAT sets the ssh configuration file to ``strictHostKeyChecking no``, so that a ``known_host`` file does not have to be built in advanced. Each node can ssh to every other cluster node without being prompted for a password, and because they share the same ssh host keys there will be no prompting to add entries to ``known_hosts``.

On the MN, you will be prompted to add entries to ``known_hosts`` file for each node once. See makeknownhosts command for a quick way to build a ``known_hosts`` file on the MN, if your nodes are defined in the xCAT database.
   

Restricting Node to Node SSH
````````````````````````````

By default, all nodes installed by one management node are able to ssh to each without password. But there is an attribute ``sshbetweennodes`` in ``site`` table. This attributes defaults to ALLGROUPS, which means we setup ssh between all nodes during the install or when you run ``xdsh -K``, or ``updatenode -k`` as in the past. This attribute can be used to define a comma-separated list of groups and only the nodes in those groups will be setup with ssh between the nodes. The attribute can be set to NOGROUPS, to indicate no nodes (groups) will be setup. Service Nodes will always be setup with ssh between service nodes and all nodes. It is unaffected by this attribute. This also only affects root userid setup and does not affect the setup of devices.

This setting of site.sshbetweennodes will only enable root ssh between nodes of the compute1 and compute 2 groups and all service nodes. ::

    "sshbetweennodes","compute1,compute2",, 


Secure Zones
````````````

You can set up multiple zones in an xCAT cluster. A node in the zone can ssh without password to any other node in the zone, but not to nodes in other zones. Refer to :doc:`Zones </advanced/zones/index>` for more information.

