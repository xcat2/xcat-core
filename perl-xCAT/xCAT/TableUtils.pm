#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::TableUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
        use lib "/usr/opt/perl5/lib/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/5.8.2";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2";
}

use lib "$::XCATROOT/lib/perl";
use strict;
require xCAT::Table;
require xCAT::Zone;
use File::Path;
#-----------------------------------------------------------------------

=head3
 list_all_nodes

	Arguments:

	Returns:
	    an array of all define nodes from the nodelist table
	Globals:
		none
	Error:
		undef
	Example:
	   @nodes=xCAT::TableUtils->list_all_nodes;
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub list_all_nodes
{
    my @nodes;
    my @nodelist;
    my $nodelisttab;
    if ($nodelisttab = xCAT::Table->new("nodelist"))
    {
        my @attribs = ("node");
        @nodes = $nodelisttab->getAllAttribs(@attribs);
        foreach my $node (@nodes)
        {
            push @nodelist, $node->{node};
        }
    }
    else
    {
        xCAT::MsgUtils->message("E", " Could not read the nodelist table\n");
    }
    return @nodelist;
}

#-----------------------------------------------------------------------

=head3
 list_all_nodegroups

	Arguments:

	Returns:
	    an array of all define node groups from the nodelist and nodegroup
            table
	Globals:
		none
	Error:
		undef
	Example:
	   @nodegrps=xCAT::TableUtils->list_all_nodegroups;
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub list_all_node_groups
{
    my @grouplist;
    my @grouplist2;
    my @distinctgroups;
    my $nodelisttab;
    if ($nodelisttab = xCAT::Table->new("nodelist"))
    {
        my @attribs = ("groups");
        @grouplist = $nodelisttab->getAllAttribs(@attribs);

        # build a distinct list of unique group names
        foreach my $group (@grouplist)
        {
            my $gnames = $group->{groups};
            my @groupnames = split ",", $gnames;
            foreach my $groupname (@groupnames)
            {
                if (!grep(/^$groupname$/, @distinctgroups))
                {    # not already in list
                    push @distinctgroups, $groupname;
                }
            }
        }
    }
    else
    {
        xCAT::MsgUtils->message("E", " Could not read the nodelist table\n");
    }
    $nodelisttab->close;
    # now read the nodegroup table
    if ($nodelisttab = xCAT::Table->new("nodegroup"))
     {
         my @attribs = ("groupname");
         @grouplist = $nodelisttab->getAllAttribs(@attribs);
 
         # build a distinct list of unique group names
         foreach my $group (@grouplist)
         {
             my $groupname = $group->{groupname};
             if (!grep(/^$groupname$/, @distinctgroups))
             {    # not already in list
                 push @distinctgroups, $groupname;
             }
         }
         $nodelisttab->close;
     }
     else
     {
         xCAT::MsgUtils->message("E", " Could not read the nodegroup table\n");
     }

    return @distinctgroups;
}
#-------------------------------------------------------------------------------- 	 
	  	 
=head3   bldnonrootSSHFiles 	 
	  	 
	            Builds authorized_keyfiles for the non-root id 	 
	            It must not only contain the public keys for the non-root id 	 
	                    but also the public keys for root 	 
	  	 
	         Arguments: 	 
	               from_userid -current id running xdsh from the command line 	 
	         Returns: 	 
	  	 
	         Globals: 	 
	               $::CALLBACK 	 
	         Error: 	 
	  	 
	         Example: 	 
	                 xCAT::TableUtils->bldnonrootSSHFiles; 	 
	  	 
	         Comments: 	 
	                 none 	 
	  	 
=cut 	 
	  	 
#-------------------------------------------------------------------------------- 	 
	  	 
sub bldnonrootSSHFiles 	 
{ 	 
    my ($class, $from_userid) = @_; 	 
    my ($cmd, $rc); 	 
    my $rsp = {}; 	 
    if ($::VERBOSE) 	 
    { 	 
        $rsp->{data}->[0] = "Building  SSH Keys for $from_userid"; 	 
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK); 	 
    } 	 
    my $home     = xCAT::Utils->getHomeDir($from_userid); 	 
    # Handle non-root userid may not be in /etc/passwd maybe LDAP 	 
    if (!$home) { 	 
        $home=`su - $from_userid -c pwd`; 	 
        chop $home; 	 
    } 	 
    my $roothome = xCAT::Utils->getHomeDir("root"); 	 
    if (xCAT::Utils->isMN()) {    # if on Management Node 	 
        if (!(-e "$home/.ssh/id_rsa.pub")) 	 
        { 	 
            return 1; 	 
        } 	 
    } 	 
    # make tmp directory to hold authorized_keys for node transfer 	 
    if (!(-e "$home/.ssh/tmp")) { 	 
        $cmd = " mkdir $home/.ssh/tmp"; 	 
        xCAT::Utils->runcmd($cmd, 0); 	 
        $rsp = {}; 	 
        if ($::RUNCMD_RC != 0) 	 
        { 	 
            $rsp->{data}->[0] = "$cmd failed.\n"; 	 
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK); 	 
            return (1); 	 

        } 	 
    } 	 
    # create authorized_key file in tmp directory for transfer 	 
    if (xCAT::Utils->isMN()) {    # if on Management Node 	 
        $cmd = " cp $home/.ssh/id_rsa.pub $home/.ssh/tmp/authorized_keys"; 	 
    } else {  # SN 	 
        $cmd = " cp $home/.ssh/authorized_keys $home/.ssh/tmp/authorized_keys"; 	 
    } 	 
    xCAT::Utils->runcmd($cmd, 0); 	 
    $rsp = {}; 	 
    if ($::RUNCMD_RC != 0) 	 
    { 	 
        $rsp->{data}->[0] = "$cmd failed.\n"; 	 
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK); 	 
        return (1); 	 

    } 	 
    else 	 
    { 	 
        chmod 0600, "$home/.ssh/tmp/authorized_keys"; 	 
        if ($::VERBOSE) 	 
        { 	 
            $rsp->{data}->[0] = "$cmd succeeded.\n"; 	 
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK); 	 
        } 	 
    } 	 
    if (xCAT::Utils->isMN()) {    # if on Management Node 	 
        # if cannot access, warn and continue 	 
        $rsp = {}; 	 
        $cmd = "cat $roothome/.ssh/id_rsa.pub >> $home/.ssh/tmp/authorized_keys"; 	 
        xCAT::Utils->runcmd($cmd, 0); 	 
        if ($::RUNCMD_RC != 0) 	 
        { 	 
            $rsp->{data}->[0] = "Warning: Cannot give $from_userid root ssh authority. \n"; 	 
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK); 	 

        } 	 
        else 	 
        { 	 
            if ($::VERBOSE) 	 
            { 	 
                $rsp->{data}->[0] = "$cmd succeeded.\n"; 	 
                xCAT::MsgUtils->message("I", $rsp, $::CALLBACK); 	 
            } 	 
        } 	 
    } 	 


    return (0); 	 
}
#--------------------------------------------------------------------------------

=head3   setupSSH

        Generates if needed and Transfers the ssh keys 
		fOr a userid to setup ssh to the input nodes.

        Arguments:
               Array of nodes
               Timeout for expect call (optional)
        Returns:

        Env Variables: $DSH_FROM_USERID,  $DSH_TO_USERID, $DSH_REMOTE_PASSWORD
          the ssh keys are transferred from the $DSH_FROM_USERID to the $DSH_TO_USERID
          on the node(s).  The DSH_REMOTE_PASSWORD and the DSH_FROM_USERID 
               must be obtained by
		         the calling script or from the xdsh client

        Globals:
              $::XCATROOT  ,  $::CALLBACK
        Error:
             0=good,  1=error
        Example:
                xCAT::TableUtils->setupSSH(@target_nodes,$expecttimeout);
        Comments:
			Does not setup known_hosts.  Assumes automatically
			setup by SSH  ( ssh config option StrictHostKeyChecking no should
			   be set in the ssh config file).

=cut

#--------------------------------------------------------------------------------
sub setupSSH
{
    my ($class, $ref_nodes,$expecttimeout) = @_;
    my @nodes    = $ref_nodes;
    my @badnodes = ();
    my $n_str    = $nodes[0];
    my $SSHdir   = xCAT::TableUtils->getInstallDir() . "/postscripts/_ssh";
    if (!($ENV{'DSH_REMOTE_PASSWORD'}))
    {
        my $rsp = ();
        $rsp->{data}->[0] =
          "User password for the ssh key exchange has not been input. xdsh -K cannot complete.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        return;

    }

    # setup who the keys are coming from and who they are going to
    my $from_userid;
    my $to_userid;
    if (!($ENV{'DSH_FROM_USERID'}))
    {
        my $rsp = ();
        $rsp->{data}->[0] =
          "DSH From Userid  has not been input. xdsh -K cannot complete.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        return;

    }
    else
    {
        $from_userid = $ENV{'DSH_FROM_USERID'};
    }
    if (!($ENV{'DSH_TO_USERID'}))
    {
        my $rsp = ();
        $rsp->{data}->[0] =
          "DSH to Userid  has not been input. xdsh -K cannot complete.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        return;

    }
    else
    {
        $to_userid = $ENV{'DSH_TO_USERID'};
    }


    #
    # if we are running as root
    # for non-root users, keys were generated in the xdsh client code
    #

    $::REMOTE_SHELL = "/usr/bin/ssh";
    my $rsp = {};
    

    # Get the home directory
    my $home = xCAT::Utils->getHomeDir($from_userid);
    $ENV{'DSH_FROM_USERID_HOME'} = $home;
    if ($from_userid eq "root")
    {
        # make the directory to hold keys to transfer to the nodes
        if (!-d $SSHdir)
        {
            mkpath("$SSHdir", { mode => 0755 });
        }

        # generates new keys for root, if they do not already exist ~/.ssh

        # nodes not used on this option but in there to preserve the interface
        my $rc=
          xCAT::RemoteShellExp->remoteshellexp("k",$::CALLBACK,$::REMOTE_SHELL,$n_str,$expecttimeout);
       if ($rc != 0) {
            $rsp->{data}->[0] = "remoteshellexp failed generating keys.";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
       }
    }
    
    # build the shell copy script, needed Perl not always there
    # for root and non-root ids
    open(FILE, ">$home/.ssh/copy.sh")
      or die "cannot open file $home/.ssh/copy.sh\n";
    print FILE "#!/bin/sh
umask 0077
home=`egrep \"^$to_userid:\" /etc/passwd | cut -f6 -d :`
if [ $home ]; then
  dest_dir=\"\$home/.ssh\"
else
  home=`su - root -c pwd`
  dest_dir=\"\$home/.ssh\"
fi
mkdir -p \$dest_dir
cat /tmp/$to_userid/.ssh/authorized_keys >> \$home/.ssh/authorized_keys 2>&1
cat /tmp/$to_userid/.ssh/id_rsa.pub >> \$home/.ssh/authorized_keys 2>&1
cp /tmp/$to_userid/.ssh/id_rsa  \$home/.ssh/id_rsa 2>&1
cp /tmp/$to_userid/.ssh/id_rsa.pub  \$home/.ssh/id_rsa.pub 2>&1
chmod 0600 \$home/.ssh/id_* 2>&1
rm -f /tmp/$to_userid/.ssh/* 2>&1
rmdir \"/tmp/$to_userid/.ssh\"
rmdir \"/tmp/$to_userid\" \n";

    close FILE;
    chmod 0777,"$home/.ssh/copy.sh";
    my $auth_key=0;
    my $auth_key2=0;
    if ($from_userid eq "root")
    {
       # this will put the root/.ssh/id_rsa.pub key in the authorized keys file to put on the node
       my $rc = xCAT::TableUtils->cpSSHFiles($SSHdir);
       if ($rc != 0)
       {    # error
                $rsp->{data}->[0] = "Error running cpSSHFiles.\n";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                return 1;

       }
       if (xCAT::Utils->isMN()) {    # if on Management Node
            # copy the copy install file to the install directory, if from and
            # to userid are root
            if ($to_userid eq "root")
            {

                my $cmd = " cp $home/.ssh/copy.sh $SSHdir/copy.sh";
                xCAT::Utils->runcmd($cmd, 0);
                my $rsp = {};
                if ($::RUNCMD_RC != 0)
                {
                    $rsp->{data}->[0] = "$cmd failed.\n";
                    xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                    return (1);

                }
            }
        }  # end is MN
    }
    else {    # from_userid is not root
                # build the authorized key files for non-root user
            xCAT::TableUtils->bldnonrootSSHFiles($from_userid);
    }

    # send the keys 
    # For root user and not to devices only to nodes 
    if (($from_userid eq "root") && (!($ENV{'DEVICETYPE'}))) {
      # Need to check if nodes are in a zone.  
      my @zones;
      my $tab = xCAT::Table->new("zone"); 
      my @zones; 
      if ($tab) 
      {
          # if we have zones, need to send the zone keys to each node in the zone
          my @attribs = ("zonename");
          @zones = $tab->getAllAttribs(@attribs);
          $tab->close();
      } else {
         $rsp->{data}->[0] = "Could not open zone table.\n";
         xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
         return 1;
      }
      # check for zones,  key send is different if zones defined or not
      
      if (@zones) {  # we have zones defined
         my $rc = xCAT::TableUtils->sendkeysTOzones($ref_nodes,$expecttimeout);
         if ($rc != 0)
         {   
                $rsp->{data}->[0] = "Error sending ssh keys to the zones.\n";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                exit 1;

         }
      } else { # no zones
      
         #  if no zone table  defined, do it the old way , keys are in  ~/.ssh 
         my $rc = xCAT::TableUtils->sendkeysNOzones($ref_nodes,$expecttimeout);
         if ($rc != 0)
         {   
            $rsp->{data}->[0] = "Error sending ssh keys to the nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

         }
      }

    } else { # from user is not root or it is a device , always send private key
       $ENV{'DSH_ENABLE_SSH'} = "YES";
       my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$n_str,$expecttimeout);
       if ($rc != 0)
       {
           $rsp->{data}->[0] = "remoteshellexp failed sending keys.";
           xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

       }
    }

    # must always check to see if worked, run test
    my @testnodes=  split(",", $nodes[0]);
    foreach my $n (@testnodes)
    {
       my $rc=
     xCAT::RemoteShellExp->remoteshellexp("t",$::CALLBACK,"/usr/bin/ssh",$n,$expecttimeout);
        if ($rc != 0)
        {
            push @badnodes, $n;
        }
    }

    if (@badnodes)
    {
        my $nstring = join ',', @badnodes;
        $rsp->{data}->[0] =
          "SSH setup failed for the following nodes: $nstring.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return @badnodes;
    }
    else
    {
        $rsp->{data}->[0] = "$::REMOTE_SHELL setup is complete.";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }
}

#--------------------------------------------------------------------------------

=head3  sendkeysNOzones 

        Transfers the ssh keys 
		for the root id on the nodes no zones 
          key from ~/.ssh   site.sshbetweennodes honored


        Arguments:
               Array of nodes
               Timeout for expect call (optional)
        Returns:

        Env Variables: $DSH_FROM_USERID,  $DSH_TO_USERID, $DSH_REMOTE_PASSWORD
          the ssh keys are transferred from the $DSH_FROM_USERID to the $DSH_TO_USERID
          on the node(s).  The DSH_REMOTE_PASSWORD and the DSH_FROM_USERID 
               must be obtained by
		         the calling script or from the xdsh client

        Globals:
              $::XCATROOT  ,  $::CALLBACK
        Error:
             0=good,  1=error
        Example:
                xCAT::TableUtils->sendkeysNOzones($ref_nodes,$expecttimeout);
        Comments:
			Does not setup known_hosts.  Assumes automatically
			setup by SSH  ( ssh config option StrictHostKeyChecking no should
			   be set in the ssh config file).

=cut

#--------------------------------------------------------------------------------
sub sendkeysNOzones 
{
      my ($class, $ref_nodes,$expecttimeout) = @_;
      my @nodes=$ref_nodes;
      my $enablenodes;
      my $disablenodes;
      my $n_str    = $nodes[0];
      my @nodelist=  split(",", $n_str);
      my $rsp = ();
      foreach my $n (@nodelist)
      {
         my $enablessh=xCAT::TableUtils->enablessh($n);
         if ($enablessh == 1) {
           $enablenodes .= $n;
           $enablenodes .= ","; 
         } else {
           $disablenodes .= $n;
           $disablenodes .= ","; 
         }

      }
      if ($enablenodes) {  # node on list to setup nodetonodessh
         chop $enablenodes;  # remove last comma
         $ENV{'DSH_ENABLE_SSH'} = "YES";
         # send the keys to the nodes
         my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$enablenodes,$expecttimeout);
         if ($rc != 0)
         {
          $rsp->{data}->[0] = "remoteshellexp failed sending keys to enablenodes.";
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

          }
      }
      if ($disablenodes) {  # node on list to disable nodetonodessh
         chop $disablenodes;  # remove last comma
         # send the keys to the nodes
         my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$disablenodes,$expecttimeout);
         if ($rc != 0)
         {
          $rsp->{data}->[0] = "remoteshellexp failed sending keys to disablenodes.";
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

         }
      }
}
#--------------------------------------------------------------------------------

=head3  sendkeysTOzones 

        Transfers the ssh keys 
		for the root id on the nodes using the zone table.
       If in a zone, then root ssh keys for the node will be taken from the zones ssh keys not ~/.ssh
       zones are only supported on nodes that are not a service node.
       Also for the call to  RemoteShellExp,  we must group the nodes that are in the same zone 


        Arguments:
               Array of nodes
               Timeout for expect call (optional)
        Returns:

        Env Variables: $DSH_FROM_USERID,  $DSH_TO_USERID, $DSH_REMOTE_PASSWORD
          the ssh keys are transferred from the $DSH_FROM_USERID to the $DSH_TO_USERID
          on the node(s).  The DSH_REMOTE_PASSWORD and the DSH_FROM_USERID 
               must be obtained by
		         the calling script or from the xdsh client

        Globals:
              $::XCATROOT  ,  $::CALLBACK
        Error:
             0=good,  1=error
        Example:
                xCAT::TableUtils->sendkeysTOzones($ref_nodes,$expecttimeout);
        Comments:
			Does not setup known_hosts.  Assumes automatically
			setup by SSH  ( ssh config option StrictHostKeyChecking no should
			   be set in the ssh config file).

=cut

#--------------------------------------------------------------------------------
sub sendkeysTOzones 
{
      my ($class, $ref_nodes,$expecttimeout) = @_;
      my @nodes=$ref_nodes;
      my $n_str    = $nodes[0];
      my @nodes=  split(",", $n_str);
      my $rsp = ();
      my $cmd;
      my $roothome = xCAT::Utils->getHomeDir("root");
      my $zonehash =xCAT::Zone->getzoneinfo($::CALLBACK,\@nodes);
      foreach my $zonename (keys %$zonehash) {
        # build list of nodes
        my $zonenodelist="";
        foreach my $node (@{$zonehash->{$zonename}->{nodes}}) {
          $zonenodelist .= $node;
          $zonenodelist .= ",";
               
        }
        $zonenodelist =~ s/,$//;   # remove last comma
        # if any nodes defined for the zone
        if ($zonenodelist) {
          # check to see if we enable passwordless ssh between the nodes
          if (!(defined($zonehash->{$zonename}->{sshbetweennodes}))|| 
            (($zonehash->{$zonename}->{sshbetweennodes} =~ /^yes$/i )
             || ($zonehash->{$zonename}->{sshbetweennodes} eq "1"))) {
 
             $ENV{'DSH_ENABLE_SSH'} = "YES";
          } else { 
             delete $ENV{'DSH_ENABLE_SSH'};  # do not enable passwordless ssh
          }
          # point to the ssh keys to send for this zone
          my $keydir = $zonehash->{$zonename}->{sshkeydir} ;

          # check to see if the id_rsa and id_rsa.pub key is in the directory
          my $key="$keydir/id_rsa";
          my $key2="$keydir/id_rsa.pub";
          # Check to see if empty
          if (!(-e $key)) {
            my $rsp = {};
             $rsp->{error}->[0] =
            "The $key file does not exist for $zonename. Need to use chzone to regenerate the keys.";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
            return 1;
          }
          if (!(-e $key2)) {
             my $rsp = {};
             $rsp->{error}->[0] =
             "The $key2 file does not exist for $zonename. Need to use chzone to regenerate the keys.";
             xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
             return 1;

          }
          
          # now put copy.sh in the zone directory from ~/.ssh
          my $rootkeydir="$roothome/.ssh";
          if ($rootkeydir ne $keydir) {  # the zone keydir is not the same as ~/.ssh.  
            $cmd="cp $rootkeydir/copy.sh $keydir";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
               my $rsp = {};
               $rsp->{error}->[0] =
               "Could not copy copy.sh to the zone key dir";
               xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
               return 1;
            }
          }
          # Also create  $keydir/tmp and put root's id_rsa.pub (in authorized_keys) for the transfer
          $cmd="mkdir -p $keydir/tmp";
          xCAT::Utils->runcmd($cmd, 0);
          if ($::RUNCMD_RC != 0)
          {
             my $rsp = {};
             $rsp->{error}->[0] =
             "Could not mkdir the zone $keydir/tmp";
             xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
             return 1;
          }
          # create authorized_keys file 
          if (xCAT::Utils->isMN()) {    # if on Management Node
             $cmd = " cp $roothome/.ssh/id_rsa.pub $keydir/tmp/authorized_keys";
          } else {  # SN
             $cmd = " cp $roothome/.ssh/authorized_keys $keydir/tmp/authorized_keys";
          }
          xCAT::Utils->runcmd($cmd, 0);
          if ($::RUNCMD_RC != 0)
          {
            $rsp->{data}->[0] = "$cmd failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return (1);
          }
          else
          {
             chmod 0600, "$keydir/.ssh/tmp/authorized_keys";
          }
          # strip off .ssh
          my ($newkeydir,$ssh) = (split(/\.ssh/, $keydir));
          $ENV{'DSH_ZONE_SSHKEYS'} =$newkeydir ;
          # send the keys to the nodes
           my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",
           $zonenodelist,$expecttimeout);
           if ($rc != 0)
           {
             $rsp = {};
             $rsp->{data}->[0] = "remoteshellexp failed sending keys to $zonename.";
             xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

           }
        } # end nodes in the zone
          
       }  # end for each zone

    return (0);
}
#-------------------------------------------------------------------------------

=head3   GetNodeOSARCH

          
          # strip off .ssh
          my ($newhome,$ssh) = (split(/\/\.ssh/, $keydir));
          $ENV{'DSH_FROM_USERID_HOME'} =$newhome ;
          # send the keys to the nodes
           my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$zonenodelist,$expecttimeout);
           if ($rc != 0)
           {
             $rsp->{data}->[0] = "remoteshellexp failed sending keys to $zonename.";
             xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
       
           }
       } # endforeach zone

    return 0;
}
#--------------------------------------------------------------------------------

=head3    cpSSHFiles

           Builds authorized_keyfiles for root 

        Arguments:
               install directory path
        Returns:

        Globals:
              $::CALLBACK
        Error:

        Example:
                xCAT::TableUtils->cpSSHFiles($dir);

        Comments:
                none

=cut

#--------------------------------------------------------------------------------


sub cpSSHFiles
{
    my ($class, $SSHdir) = @_;
    my ($cmd, $rc);
    my $rsp = {};
    if ($::VERBOSE)
    {
        $rsp->{data}->[0] = "Copying SSH Keys";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
    }
    my $home = xCAT::Utils->getHomeDir("root");


    if (xCAT::Utils->isMN()) {    # if on Management Node
      if (!(-e "$home/.ssh/id_rsa.pub"))   # only using rsa
      {
          $rsp->{data}->[0] = "Public key id_rsa.pub was missing in the .ssh directory.";
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
          return 1;
      }
      # copy to id_rsa public key to authorized_keys in the install directory
      my $authorized_keys = "$SSHdir/authorized_keys";
      # changed from  identity.pub
      $cmd = " cp $home/.ssh/id_rsa.pub $authorized_keys";
      xCAT::Utils->runcmd($cmd, 0);
      $rsp = {};
      if ($::RUNCMD_RC != 0)
      {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

      }
      else
      {
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
      }
    } # end is MN

    # on MN and SN
    # make tmp directory to hold authorized_keys for node transfer
    if (!(-e "$home/.ssh/tmp")) {
      $cmd = " mkdir $home/.ssh/tmp";
      xCAT::Utils->runcmd($cmd, 0);
      $rsp = {};
      if ($::RUNCMD_RC != 0)
      {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

      }
    }
    # create authorized_keys file 
    if (xCAT::Utils->isMN()) {    # if on Management Node
      $cmd = " cp $home/.ssh/id_rsa.pub $home/.ssh/tmp/authorized_keys";
    } else {  # SN
      $cmd = " cp $home/.ssh/authorized_keys $home/.ssh/tmp/authorized_keys";
    }
    xCAT::Utils->runcmd($cmd, 0);
    $rsp = {};
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        chmod 0600, "$home/.ssh/tmp/authorized_keys";
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    return (0);
}
#-------------------------------------------------------------------------------

=head3   GetNodeOSARCH
        Reads the database for the OS and Arch of the input Node
    Arguments:
		 Node
    Returns:
        $et->{'os'}
		$et->{'arch'}
    Globals:
        none
    Error:
        none
    Example:
         $master=(xCAT::TableUtils->GetNodeOSARCH($node))
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub GetNodeOSARCH
{
    my ($class, $node) = @_;
    my $typetab    = xCAT::Table->new('nodetype');
    unless ($typetab)
    {
        xCAT::MsgUtils->message('S',
                                "Unable to open nodetype table.\n");
        return 1;
    }
    my $et = $typetab->getNodeAttribs($node, ['os', 'arch']);
    unless ($et and $et->{'os'} and $et->{'arch'})
    {
        xCAT::MsgUtils->message('S',
                           "No os/arch setting in nodetype table for $node.\n");
        return 1;
    }

    return $et;

}

#-------------------------------------------------------------------------------

=head3   logEventsToDatabase
       Logs the given events info to the xCAT's 'eventlog' database 
    Arguments:
        arrayref -- A pointer to an array. Each element is a hash that contains an events.
        The hash should contain the at least one of the following keys:
          eventtime -- The format is "yyyy-mm-dd hh:mm:ss".
                       If omitted, the current date and time will be used.
          monitor  -- The name of the monitor that monitors this event.
          monnode -- The node that monitors this event.
          node -- The node where the event occurred.
          application -- The application that reports the event.
          component -- The component where the event occurred.
          id -- The location or the resource name where the event occurred.
          severity -- The severity of the event. Valid values are: informational, warning, critical.
          message -- The full description of the event.
	  rawdata -- The data that associated with the event.         
  Returns:
       (ret code, error message) 
  Example:
    my  @a=();
    my $event={
        eventtime=>"2009-07-28 23:02:03",
        node => 'node1',
        rawdata => 'kjdlkfajlfjdlksaj',
    };
    push (@a, $event);

    my $event1={
        node => 'cu03cp',
        monnode => 'cu03sv',
        application => 'RMC',
        component => 'IBM.Sensor',
        id => 'AIXErrorLogSensor',
        severity => 'warning',
    };
    push(@a, $event1);
    xCAT::TableUtils->logEventsToDatabase(\@a);

=cut

#-------------------------------------------------------------------------------
sub logEventsToDatabase
{
    my $pEvents = shift;
    if (($pEvents) && ($pEvents =~ /xCAT::TableUtils/))
    {
        $pEvents = shift;
    }

    if (($pEvents) && (@$pEvents > 0))
    {
        my $currtime;
        my $tab = xCAT::Table->new("eventlog", -create => 1, -autocommit => 0);
        if (!$tab)
        {
            return (1, "The evnetlog table cannot be opened.");
        }

        foreach my $event (@$pEvents)
        {

            #create event time if it does not exist
            if (!exists($event->{eventtime}))
            {
                if (!$currtime)
                {
                    my (
                        $sec,  $min,  $hour, $mday, $mon,
                        $year, $wday, $yday, $isdst
                      )
                      = localtime(time);
                    $currtime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                                        $year + 1900, $mon + 1, $mday, 
                                        $hour, $min, $sec);
                }
                $event->{eventtime} = $currtime;
            }
            my @ret = $tab->setAttribs(undef, $event);
            if (@ret > 1) { return (1, $ret[1]); }
        }
        $tab->commit;
    }

    return (0, "");
}


#-------------------------------------------------------------------------------

=head3   logEventsToTealDatabase
       Logs the given events info to the TEAL's 'x_tealeventlog' database 
    Arguments:
        arrayref -- A pointer to an array. Each element is a hash that contains an events.
  Returns:
       (ret code, error message) 

=cut

#-------------------------------------------------------------------------------
sub logEventsToTealDatabase
{
    my $pEvents = shift;
    if (($pEvents) && ($pEvents =~ /xCAT::TableUtils/))
    {
        $pEvents = shift;
    }

    if (($pEvents) && (@$pEvents > 0))
    {
        my $currtime;
        my $tab = xCAT::Table->new("x_tealeventlog", -create => 1, -autocommit => 0);
        if (!$tab)
        {
            return (1, "The x_tealeventlog table cannot be opened.");
        }

        foreach my $event (@$pEvents)
        {
            my @ret = $tab->setAttribs(undef, $event);
            if (@ret > 1) { return (1, $ret[1]); }
        }
        $tab->commit;
    }

    return (0, "");
}

#-------------------------------------------------------------------------------

=head3  setAppStatus
    Description:
        Set an AppStatus value for a specific application in the nodelist
        appstatus attribute for a list of nodes
    Arguments:
        @nodes
        $application
        $status
    Returns:
        Return result of call to setNodesAttribs
    Globals:
        none
    Error:
        none
    Example:
        xCAT::TableUtils->setAppStatus(\@nodes,$application,$status);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub setAppStatus
{

    my ($class, $nodes_ref, $application, $status) = @_;
    my @nodes = @$nodes_ref;

    #get current local time to set in appstatustime attribute
    my (
        $sec,  $min,  $hour, $mday, $mon,
        $year, $wday, $yday, $isdst
        )
        = localtime(time);
    my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                           $mon + 1, $mday, $year + 1900,
                           $hour, $min, $sec);

    my $nltab = xCAT::Table->new('nodelist');
    my $nodeappstat = $nltab->getNodesAttribs(\@nodes,['appstatus']);

    my %new_nodeappstat;
    foreach my $node (keys %$nodeappstat) {
        if ( $node =~ /^\s*$/ ) { next; }  # Skip blank node names 
        my $new_appstat = "";
        my $changed = 0;

        # Search current appstatus and change if app entry exists
        my $cur_appstat = $nodeappstat->{$node}->[0]->{appstatus};
        if ($cur_appstat) {
            my @appstatus_entries = split(/,/,$cur_appstat);
            foreach my $appstat (@appstatus_entries) {
                my ($app, $stat) = split(/=/,$appstat);
                if ($app eq $application) {
                   $new_appstat .= ",$app=$status";
                   $changed = 1;
                } else {
                   $new_appstat .= ",$appstat";
                }
            }
        }
        # If no app entry exists, add it
        if (!$changed){
           $new_appstat .= ",$application=$status";
        }
        $new_appstat =~ s/^,//;
        $new_nodeappstat{$node}->{appstatus} = $new_appstat;
        $new_nodeappstat{$node}->{appstatustime} = $currtime;
    }

    return $nltab->setNodesAttribs(\%new_nodeappstat);

}

#-------------------------------------------------------------------------------

=head3  setUpdateStatus
    Description:
        Set the updatestatus  attribute for a list of nodes during "updatenode"
    Arguments:
        @nodes
        $status
    Returns:
        none
        
    Globals:
        none
    Error:
        none
    Example:
        xCAT::TableUtils->setUpdateStatus(\@nodes,$status);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub setUpdateStatus
{


    my ($class, $nodes_ref, $status) = @_;
    my @nodes = @$nodes_ref;



    #get current local time to set in Updatestatustime attribute
    my (
        $sec,  $min,  $hour, $mday, $mon,
        $year, $wday, $yday, $isdst
        )
        = localtime(time);
    my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                           $mon + 1, $mday, $year + 1900,
                           $hour, $min, $sec);

    my $nltab = xCAT::Table->new('nodelist');
    if($nltab){
		if(@nodes>0){
		   my %updates;

                   foreach my $node (@nodes)
                   {
                        $updates{$node}{'updatestatus'} = $status;
                        $updates{$node}{'updatestatustime'} = $currtime;
                   }

                   $nltab->setNodesAttribs(\%updates);
 		}
              $nltab->close;	
	}
   return;
}

#-------------------------------------------------------------------------------

=head3  getAppStatus
    Description:
        Get an AppStatus value for a specific application from the
        nodelist appstatus attribute for a list of nodes
    Arguments:
        @nodes
        $application
    Returns:
        a hashref of nodes set to application status value
    Globals:
        none
    Error:
        none
    Example:
        my $appstatus = $xCAT::TableUtils->getAppStatus(\@nodes,$application);
       my $node1_status = $appstatus->{node1};
    Comments:

=cut

#-----------------------------------------------------------------------------

sub getAppStatus
{

    my ($class, $nodes_ref, $application) = @_;
    my @nodes = @$nodes_ref;

    my $nltab = xCAT::Table->new('nodelist');
    my $nodeappstat = $nltab->getNodesAttribs(\@nodes,['appstatus']);

    my $ret_nodeappstat;
    foreach my $node (keys %$nodeappstat) {
        my $cur_appstat = $nodeappstat->{$node}->[0]->{appstatus};
        my $found = 0;
        if ($cur_appstat) {
            my @appstatus_entries = split(/,/,$cur_appstat);
            foreach my $appstat (@appstatus_entries) {
                my ($app, $stat) = split(/=/,$appstat);
                if ($app eq $application) {
                   $ret_nodeappstat->{$node} = $stat;
                   $found = 1;
                }
            }
        }
        # If no app entry exists, return empty
        if (!$found){
           $ret_nodeappstat->{$node} = "";
        }
    }

    return $ret_nodeappstat;

}

#-----------------------------------------------------------------------

=head3
  get_site_attribute

	Arguments:

	Returns:
	    The value of the attribute requested from the site table
	Globals:
		none
	Error:
		undef
	Example:
	   @attr=xCAT::TableUtils->get_site_attribute($attribute);
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub get_site_attribute
{
    my ($class, $attr) = @_;
    
    my $values;
    if (defined($::XCATSITEVALS{$attr})) {
        $values = ($::XCATSITEVALS{$attr});
    } else {
        my $sitetab = xCAT::Table->new('site');
        if ($sitetab)
        {
            (my $ref) = $sitetab->getAttribs({key => $attr}, 'value');
            if ($ref)
            {
                $values = $ref->{value};
            }
        }
        else
        {
            xCAT::MsgUtils->message("E", " Could not read the site table\n");

        }
        $sitetab->close;
    }
    return $values;
}


#--------------------------------------------------------------------------------

=head3    getInstallDir

        Get location of the directory, used to hold the node deployment packages.

        Arguments:
                none
        Returns:
                path to install directory defined at site.installdir.
        Globals:
                none
        Error:
                none
        Example:
                $installdir = xCAT::TableUtils->getInstallDir();
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub getInstallDir
{
    # Default installdir location. Used by default in most Linux distros.
    my $installdir = "/install";

    # Try to lookup real installdir place.
    my @installdir1 = xCAT::TableUtils->get_site_attribute("installdir");

    # Use fetched value, incase successful database lookup.
    if ($installdir1[0])
    {
        $installdir = $installdir1[0];
    }

    return $installdir;
}


#--------------------------------------------------------------------------------

=head3    getTftpDir

        Get location of the directory, used to hold network boot files.

        Arguments:
                none
        Returns:
                path to TFTP directory defined at site.tftpdir.
        Globals:
                none
        Error:
                none
        Example:
                $tftpdir = xCAT::TableUtils->getTftpDir();
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub getTftpDir
{
    # Default tftpdir location. Used by default in most Linux distros.
    my $tftpdir = "/tftpboot";

    # Try to lookup real tftpdir place.
    my @tftpdir1 = xCAT::TableUtils->get_site_attribute("tftpdir");

    # Use fetched value, incase successful database lookup.
    if ($tftpdir1[0])
    {
        $tftpdir = $tftpdir1[0];
    }

    return $tftpdir;
}

#-------------------------------------------------------------------------------

=head3   GetMasterNodeName
        Reads the database for the Master node name for the input node
    Arguments:
		 Node
    Returns:
        MasterHostName
    Globals:
        none
    Error:
        none
    Example:
         $master=(xCAT::TableUtils->GetMasterNodeName($node))
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub GetMasterNodeName
{
    my ($class, $node) = @_;
    my $master;
    my $noderestab = xCAT::Table->new('noderes');
    unless ($noderestab)
    {
        xCAT::MsgUtils->message('S',
                                "Unable to open noderes  table.\n");
        return 1;
    }
    my @masters = xCAT::TableUtils->get_site_attribute("master"); 
    $master = $masters[0];
    
    my $et = $noderestab->getNodeAttribs($node, ['xcatmaster']);
    if ($et and $et->{'xcatmaster'})
    {
        $master = $et->{'xcatmaster'};
    }
    unless ($master)
    {
        xCAT::MsgUtils->message('S', "Unable to identify master for $node.\n");
        $noderestab->close;
        return 1;
    }

    $noderestab->close;
    return $master;
}


#-----------------------------------------------------------------------------

=head3 create_postscripts_tar

     This routine will tar and compress the /install/postscripts directory
	 and place in /install/autoinst/xcat_postscripts.Z

     input: none
	 output:
	 example: $rc=xCAT::TableUtils->create_postscripts_tar();

=cut

#-----------------------------------------------------------------------------
sub create_postscripts_tar
{
    my ($class) = @_;
    my $installdir = xCAT::TableUtils->getInstallDir();
    my $cmd;
    if (!(-e "$installdir/autoinst"))
    {
        mkdir("$installdir/autoinst");
    }

    $cmd =
      "cd $installdir/postscripts; tar -cf $installdir/autoinst/xcatpost.tar * .ssh/* _xcat/*; gzip -f $installdir/autoinst/xcatpost.tar";
    my @result = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd\n");
        return $::RUNCMD_RC;
    }

    # for AIX add an entry to the /etc/tftpaccess.ctrl file so
    #	we can tftp the tar file from the node
    if (xCAT::Utils->isAIX())
    {
        my $tftpctlfile = "/etc/tftpaccess.ctl";
        my $entry       = "allow:$installdir/autoinst/xcatpost.tar.gz";

        # see if there is already an entry
        my $cmd = "cat $tftpctlfile | grep xcatpost";
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {

            # not found so add it
            unless (open(TFTPFILE, ">>$tftpctlfile"))
            {
                xCAT::MsgUtils->message("S", "Could not open $tftpctlfile.\n");
                return $::RUNCMD_RC;
            }

            print TFTPFILE $entry;

            close(TFTPFILE);
        }
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3 get_site_Master

     Reads the site table for the Master attribute and returns it.
     input: none
     output : value of site.Master attribute , blank is an error
	 example: $Master =xCAT::TableUtils->get_site_Master();

=cut

#-----------------------------------------------------------------------------

sub get_site_Master
{
    if ($::XCATSITEVALS{master}) {
        return $::XCATSITEVALS{master};
    }
    my $Master;
    my $sitetab = xCAT::Table->new('site');
    (my $et) = $sitetab->getAttribs({key => "master"}, 'value');
    if ($et and $et->{value})
    {
        $Master = $et->{value};
    }
    else
    {
# this msg can be missleading
#        xCAT::MsgUtils->message('E',
#                           "Unable to read site table for Master attribute.\n");
    }
    return $Master;
}


#-------------------------------------------------------------------------------

=head3 checkCredFiles 
        Checks the various credential files on the Management Node to
		make sure the permission are correct for using and transferring
		to the nodes and service nodes.
		Also removes /install/postscripts/etc/xcat/cfgloc if found
    Arguments:
      $callback 
    Returns:
        0 - ok
    Globals:
        none 
    Error:
         warnings of possible missing files  and directories
    Example:
         my $rc=xCAT::TableUtils->checkCreds
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub checkCredFiles
{
    my $lib = shift;
    my $cb  = shift;
    my $installdir = xCAT::TableUtils->getInstallDir();
    my $dir = "$installdir/postscripts/_xcat";
    if (-d $dir)
    {
        my $file = "$dir/ca.pem";
        if (-e $file)
        {

            my $cmd = "/bin/chmod 0644 $file";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {    # ca.pem missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }


    $dir = "$installdir/postscripts/ca";
    if (-d $dir)
    {
        my $file = "$dir/ca-cert.pem";
        if (-e $file)
        {

            my $cmd = "/bin/chmod 0644 $file";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {    # ca_cert.pem missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }


    # ssh hostkeys
    $dir = "$installdir/postscripts/hostkeys";
    if (-d $dir)
    {
        my $file = "$dir/ssh_host_key.pub";
        if (-e $file)
        {
            my $file2  = "$dir/*.pub";                     # all public keys
            my $cmd    = "/bin/chmod 0644 $file2";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {                                                  # hostkey missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }
    # ssh hostkeys
    $dir = "/etc/xcat/hostkeys";
    if (-d $dir)
    {
        my $file = "$dir/ssh_host_key.pub";
        if (-e $file)
        {
            my $file2  = "$dir/*.pub";                     # all public keys
            my $cmd    = "/bin/chmod 0644 $file2";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {                                                  # hostkey missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }

    # ssh directory
    $dir = "$installdir/postscripts/_ssh";

    if (-d $dir)
    {
        my $file = "$dir/authorized_keys";
        if (-e $file)
        {
            my $file2  = "$dir/authorized_keys*";
            my $cmd    = "/bin/chmod 0644 $file2";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }

            # make install script executable
            $file2 = "$dir/copy.sh";
            if (-e $file2)
            {
                my $cmd = "/bin/chmod 0744 $file2";
                my $outref = xCAT::Utils->runcmd("$cmd", 0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Error on command: $cmd";
                    xCAT::MsgUtils->message("I", $rsp, $cb);

                }
            }
        }
        else
        {    # authorized keys missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }

    # remove any old cfgloc files
    my $file = "$installdir/postscripts/etc/xcat/cfgloc";
    if (-e $file)
    {

        my $cmd = "/bin/rm  $file";
        my $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Error on command: $cmd";
            xCAT::MsgUtils->message("I", $rsp, $cb);

        }
    }

}

#-------------------------------------------------------------------------------

=head3  enableSSH 
    Description:
        Reads the site.sshbetweennodes attribute and determines
        if the input node should be enabled to ssh between nodes 
    Arguments:
        $node 
    Returns:
       1 = enable ssh
       0 = do not enable ssh 
    Globals:
        none
    Error:
        none
    Example:
        my $eable = xCAT::TableUtils->enablessh($node);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub enablessh 
{

    my ($class, $node) = @_;
    my $enablessh=1;
    
    if( xCAT::Utils->isSN($node) ) {
            $enablessh=1;   # service nodes always enabled
       
    } else { 
        # if not a service node we need to check, before enabling
        my $values;
        my @vals = xCAT::TableUtils->get_site_attribute("sshbetweennodes");
        $values = $vals[0];
        if ($values) {
            my @groups = split(/,/, $values);
            if (grep(/^ALLGROUPS$/, @groups))
            {
              $enablessh=1;
            }
            else
            {
                if (grep(/^NOGROUPS$/, @groups))
                {
                      $enablessh=0;
                }
                else
                {    # check to see if the node is a member of a group
                    my $ismember = 0;
                    foreach my $group (@groups)
                    {
                        $ismember = xCAT::Utils->isMemberofGroup($node, $group);
                        if ($ismember == 1)
                        {
                            last;
                        }
                    }
                    if ($ismember == 1)
                    {
                        $enablessh=1;
                    }
                    else
                    {
                        $enablessh=0;
                    }
                }
            }
         }
         else
         {    # does not exist, set default
            $enablessh=1;

         }
    }
    return $enablessh;

}

#-------------------------------------------------------------------------------

=head3  enableSSH 
    Description:
        The function is same as enablessh() above. Before using this function,
        the $sn_hash for noderange, and $groups_hash for site.sshbetweennodes should be
        got.  This is performance improvement.
    Arguments:
        $node  --  node name
        $sn_hash -- if the node is one sn, key is the node name, and value is 1. 
                    if the node is not a sn, the key isn't in this hash
        $groups_hash -- there are two keys:
                     1.  Each group in the value of site.sshbetweennodes could be the key
                     2.  Each node in the groups from the value of site.sshbetweennodes , if the 
                         value isn't ALLGROUPS or NOGROUPS.
          
    Returns:
       1 = enable ssh
       0 = do not enable ssh 
    Globals:
        none
    Error:
        none
    Example:
        my $enable = xCAT::TableUtils->enableSSH($node);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub enableSSH
{

    my ($class, $node, $sn_hash, $groups_hash) = @_;
    my $enablessh=1;
    
    if( defined($sn_hash) && defined($sn_hash->{node}) && $sn_hash->{$node} == 1 ) {
            $enablessh=1;   # service nodes always enabled
       
    } else { 
        # if not a service node we need to check, before enabling
        if (defined($groups_hash)) {
            if ($groups_hash->{ALLGROUPS} == 1)
            {
              $enablessh=1;
            }
            else
            {
                if ($groups_hash->{NOGROUPS} == 1)
                {
                      $enablessh=0;
                }
                else
                {    # check to see if the node is a member of a group
                    my $ismember = 0;
                    $ismember = $groups_hash->{$node};

                    if ($ismember == 1)
                    {
                        $enablessh=1;
                    }
                    else
                    {
                        $enablessh=0;
                    }
                }
            }
         }
         else
         {    # does not exist, set default
            $enablessh=1;

         }
    }
    return $enablessh;

}





#-----------------------------------------------------------------------------


=head3 getrootimage
    Get the directory of root image for a node; 
    Note: This subroutine only works for diskless node

    Arguments:
      $node
    Returns:
      string - directory of the root image
      undef - this is not a diskless node or the root image does not existed
    Globals:
        none
    Error:
    Example:
         my $node_syncfile=xCAT::TableUtils->getrootimage($node);

=cut

#-----------------------------------------------------------------------------

sub getrootimage()
{
  my $node = shift;
  my $installdir = xCAT::TableUtils->getInstallDir();
  if (($node) && ($node =~ /xCAT::TableUtils/))	
  {
    $node = shift;
  }
      # get the os,arch,profile attributes for the nodes
  my $nodetype_t = xCAT::Table->new('nodetype');
  unless ($nodetype_t) {
    return ;
  }
  my $nodetype_v = $nodetype_t->getNodeAttribs($node, ['profile','os','arch']);
  my $profile = $nodetype_v->{'profile'};
  my $os = $nodetype_v->{'os'};
  my $arch = $nodetype_v->{'arch'};

  if ($^O eq "linux") {
    my $rootdir = "$installdir/netboot/$os/$arch/$profile/rootimg/";
    if (-d $rootdir) {
      return $rootdir;
    } else {
      return undef;
    }
  } else {
    # For AIX
  }
}
#-----------------------------------------------------------------------------


=head3 getimagenames
    Get an array of osimagenames that correspond to the input node array; 

    Arguments:
     Array of nodes 
    Returns:
      array of all the osimage names that are the provmethod for the nodes 
      undef - no osimage names 
    Globals:
        none
    Error:
    Example:
         my @imagenames=xCAT::TableUtils->getimagenames(\@nodes);

=cut

#-----------------------------------------------------------------------------

sub getimagenames()
{
  my ($class, $nodes)=@_;
  my @nodelist = @$nodes;
   my $nodetab = xCAT::Table->new('nodetype');
    my $images  =
      $nodetab->getNodesAttribs(\@nodelist, ['node', 'provmethod', 'profile']);
    my @imagenames;
    foreach my $node (@nodelist)
    {
        my $imgname;
        if ($images->{$node}->[0]->{provmethod})
        {
            $imgname = $images->{$node}->[0]->{provmethod};
        }
        elsif ($images->{$node}->[0]->{profile})
        {
            $imgname = $images->{$node}->[0]->{profile};
        }
        # if the node has an image
        if ($imgname) {
          if (!grep(/^$imgname$/, @imagenames)) # not already on the list
          {
             push @imagenames, $imgname;   # add to the array
          }
        }
    }
    $nodetab->close;
    return @imagenames;
}
#-----------------------------------------------------------------------------


=head3 updatenodegroups
    Update groups attribute for the specified node

    Arguments:
      node
      tabhd: the handler of 'nodelist' table, 
      groups: the groups attribute need to be merged.
              Can be an array or string. 
    Globals:
        none
    Error:
    Example:
         xCAT::TableUtils->updatenodegroups($node, $tab, $groups);

=cut

#-----------------------------------------------------------------------------

sub updatenodegroups {
    my ($class, $node, $tabhd, $groups) = @_;
    if (!$groups) {
        $groups = $tabhd;
        $tabhd = xCAT::Table->new('nodelist');
        unless ($tabhd)  { 
           xCAT::MsgUtils->message("E", " Could not read the nodelist table\n");
           return; 
        }
    }
    my ($ent) = $tabhd->getNodeAttribs($node, ['groups']);
    my @list = qw(all);
    if (defined($ent) and $ent->{groups}) {
        push @list, split(/,/,$ent->{groups});
    }   
    if (ref($groups) eq 'ARRAY') {
        push @list, @$groups;
    } else {
        push @list, split(/,/,$groups);
    }
    my %saw;
    @saw{@list} = ();
    @list = keys %saw;
    $tabhd->setNodeAttribs($node, {groups=>join(",",@list)});
}

1;
