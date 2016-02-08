
#############
bmcdiscover.1
#############

.. highlight:: perl


****
NAME
****


\ **bmcdiscover**\  - Discover Baseboard Management Controllers (BMCs) using a scan method


********
SYNOPSIS
********


\ **bmcdiscover**\  [\ **-h**\ |\ **--help**\ ] [\ **-v**\ |\ **--version**\ ]

\ **bmcdiscover**\  [\ **-s**\  \ *scan_method*\ ] \ **--range**\  \ *ip_ranges*\  [\ **-z**\ ] [\ **-w**\ ] [\ **-t**\ ]

\ **bmcdiscover**\  \ **-i**\ |\ **--bmcip**\  \ *bmc_ip*\  [\ **-u**\ |\ **--bmcuser**\  \ *bmcusername*\ ] \ **-p**\ |\ **--bmcpwd**\  \ *bmcpassword*\  \ **-c**\ |\ **--check**\ 

\ **bmcdiscover**\  \ **-i**\ |\ **--bmcip**\  \ *bmc_ip*\  [\ **-u**\ |\ **--bmcuser**\  \ *bmcusername*\ ] \ **-p**\ |\ **--bmcpwd**\  \ *bmcpassword*\  \ **--ipsource**\ 


***********
DESCRIPTION
***********


The \ **bmcdiscover**\  command will discover Baseboard Management Controllers (BMCs) using a scan mathod.

The command uses \ **nmap**\  to scan active nodes over a specified IP range.  The IP range format should be a format that is acceptable by \ **nmap**\ .

The \ **bmcdiscover**\  command can also obtain some information about the BMC. (Check username/password, IP address source, DHCP/static configuration)

Note: The scan method currently support is \ **nmap**\ .


*******
OPTIONS
*******



\ **--range**\ 
 
 Specify one or more IP ranges acceptable to nmap.  IP rance can be hostnames, IP addresses, networks, etc.  A single IP address (10.1.2.3) or an IP range (10.1.2.0/24) can be specified.  If the range is very large, the \ **bmcdiscover**\  command may take a long time to return.
 


\ **-s**\ 
 
 Scan method  (The only supported scan method at this time is 'nmap')
 


\ **-z**\ 
 
 List the data returned in xCAT stanza format
 


\ **-w**\ 
 
 Write to the xCAT database
 


\ **-t**\ 
 
 Generate a BMC type node object
 


\ **-i|--bmcip**\ 
 
 BMC IP
 


\ **-u|--bmcuser**\ 
 
 BMC user name.
 


\ **-p|--bmcpwd**\ 
 
 BMC user password.
 


\ **-c|--check**\ 
 
 Check
 


\ **--ipsource**\ 
 
 BMC IP source
 


\ **-h|--help**\ 
 
 Display usage message
 


\ **-v|--version**\ 
 
 Display version information
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To get all bmc from IP range


.. code-block:: perl

  bmcdiscover -s nmap --range "10.4.23.100-254 50.3.15.1-2"


Output is similar to:


.. code-block:: perl

  10.4.23.254
  50.3.15.1


Note: input for IP range can also be like scanme.nmap.org, microsoft.com/24, 192.168.0.1; 10.0.0-255.1-254.

2. After discover bmc, list the stanza format data

bmcdiscover -s nmap --range "10.4.22-23.100-254" -z

Output is similar to:


.. code-block:: perl

  node10422254:
         objtype=node
         groups=all
         bmc=10.4.22.254
         cons=ipmi
         mgt=ipmi
 
  node10423254:
         objtype=node
         groups=all
         bmc=10.4.23.254
         cons=ipmi
         mgt=ipmi


3. After discover bmc, write host node definition into the database, and the same time, give out stanza format data


.. code-block:: perl

  bmcdiscover -s nmap --range "10.4.22-23.100-254" -w


Output is similar to:


.. code-block:: perl

  node10422254:
         objtype=node
         groups=all
         bmc=10.4.22.254
         cons=ipmi
         mgt=ipmi
 
  node10423254:
         objtype=node
         groups=all
         bmc=10.4.23.254
         cons=ipmi
         mgt=ipmi


4. To check if user name or password is correct or not for bmc


.. code-block:: perl

  bmcdiscover -i 10.4.23.254 -u USERID -p PASSW0RD -c


Output is similar to:


.. code-block:: perl

  Correct ADMINISTRATOR
 
  bmcdiscover -i 10.4.23.254 -u USERID -p PASSW0RD1 -c


Output is similar to:


.. code-block:: perl

  Error: Wrong bmc password
 
  bmcdiscover -i 10.4.23.254 -u USERID1 -p PASSW0RD1 -c


Output is similar to:


.. code-block:: perl

  Error: Wrong bmc user
 
  bmcdiscover -i 10.4.23.2541234 -u USERID -p PASSW0RD -c


Output is similar to:


.. code-block:: perl

  Error: Not bmc


5. Get BMC IP Address source, DHCP Address or static Address


.. code-block:: perl

  bmcdiscover -i 10.4.23.254 -u USERID -p PASSW0RD --ipsource


Output is similar to:


.. code-block:: perl

  Static Address



********
SEE ALSO
********


lsslp(1)|lsslp.1

