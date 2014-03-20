# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle makeknownhosts 

   Supported command:
         makenownhosts-> makeknownhosts 

=cut

#-------------------------------------------------------
package xCAT_plugin::makeknownhosts;
use strict;
require xCAT::Table;

require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::MsgUtils;
use Getopt::Long;
use Socket;
require xCAT::DSHCLI;
require xCAT::NetworkUtils;
1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {makeknownhosts => "makeknownhosts"};
}

#-------------------------------------------------------

=head3  process_request

  Process the command
  Get list of nodes and for each node, find all possible 
  names and ipaddresses and add an entry into the users
  /.ssh knownhost file.

=cut

#-------------------------------------------------------
sub process_request
{

    Getopt::Long::Configure("bundling");
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("no_pass_through");
    my $request  = shift;
    my $callback = shift;
    my $nodes    = $request->{node};
    my $rc       = 0;

    # parse the input
    if ($request && $request->{arg}) { @ARGV = @{$request->{arg}}; }
    else { @ARGV = (); }

    my $usage = "Usage: makeknownhosts <noderange> [-r] [-V]\n       makeknownhosts -h";

    # print "argv=@ARGV\n";
    if (!GetOptions(
                     'h|help'    => \$::opt_h,
                     'V|verbose' => \$::opt_V,
                     'r|remove'  => \$::opt_r
                   )) 
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }

    # display the usage if -h
    if ($::opt_h)
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("I", $rsp, $callback, 1);
        return 0;
    }
    if ($nodes eq "")
    {    # no noderange
        my $rsp = {};
        $rsp->{data}->[0] = "The Noderange is missing.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }
    my $hostkey = "/etc/xcat/hostkeys/ssh_host_rsa_key.pub";
    if (!(-e $hostkey))
    {    # the key is missing, cannot create known_hosts
        my $rsp = {};
        $rsp->{data}->[0] =
          "The keyfile:$hostkey is missing. Cannot create the known_hosts file.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }

    # Backup the existing known_hosts file to known_hosts.backup
    $rc = backup_known_hosts_file($callback);
    if ($rc != 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error backing up known_hosts file.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;

    }

    # Remove the nodes from knownhosts file
    $rc = remove_nodes_from_knownhosts($callback, $nodes);
    if ($rc != 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error backing up known_hosts file.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;

    }

    # if -r flag is not specified, adding the nodes back to known_hosts file
    if (!$::opt_r)
    {
        my @nodelist = @$nodes;
        foreach my $node (@nodelist)
        {
            $rc = add_known_host($node, $callback);
            if ($rc != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error building known_hosts file.";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                return 1;
            }
        }
     }
    return 0;
}

#-------------------------------------------------------

=head3  backup_known_hosts file 

  Backs up the old known_hosts file in roots  .ssh directory,
  if it exists. 



=cut

#-------------------------------------------------------
sub backup_known_hosts_file
{

    my ($callback) = @_;

    # Get the home directory
    my $home = xCAT::Utils->getHomeDir("root");
    if (!-d "$home/.ssh")
    {    # ssh has not been setup
        my $rsp = {};
        $rsp->{data}->[0] =
          "ssh has not been setup on this machine. .ssh directory does not existfor root id";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }
    else
    {
        my $cmd;
        my $file = "$home/.ssh/known_hosts";
        if (-e $file)
        {
            my $newfile = $file;
            $newfile .= ".backup";
            $cmd = "cat $file > $newfile";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "$cmd failed";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                return 1;
            }

        }
    }
    return 0;
}

#-------------------------------------------------------

=head3  add_known_host 

  Adds entires to $ROOTHOME/.ssh/known_hosts file 



=cut

#-------------------------------------------------------
sub add_known_host
{
    my ($node, $callback) = @_;
    my $cmd;
    my $line;
    my @ip_address;
    my $home        = xCAT::Utils->getHomeDir("root");
    my $known_hosts = "$home/.ssh/known_hosts";

    my $hostkey = "/etc/xcat/hostkeys/ssh_host_rsa_key.pub";
    my $hostname;
    my $aliases;
    my $addrtype;
    my $length;
    my @addrs;

    # get the key
    $cmd = "cat $hostkey";
    if ($::opt_V)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Running command: $cmd";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    my @output = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "$cmd failed, cannot build known_hosts file";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }
    chomp($output[0]);
    my ($hostname,$ip_address) = xCAT::NetworkUtils->gethostnameandip($node);
    if (!$hostname || !$ip_address)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Can not resolve $node";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }
    chomp($ip_address);

    if (defined $hostname)
    {
        my $hostdomain;
		my @hosts;
		push (@hosts, $hostname);
		my $nd = xCAT::NetworkUtils->getNodeDomains(\@hosts);
		my %nodedomains = %$nd;
		$hostdomain = $nodedomains{$hostname};

        $line = "\"";
        $line .= "$hostname,";
        if ($hostdomain)
        {
            $line .= "$hostname.$hostdomain,";
        }
        $line .= "$ip_address";
        $line .= " ";
        $line .= $output[0];
        $line .= "\"";
        $cmd = "echo  $line >> $known_hosts";
        if ($::opt_V)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Running command: $cmd";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        xCAT::Utils->runcmd($cmd, 0);

        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "$cmd failed, cannot create known_hosts";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return 1;
        }
    }
    return 0;
}

#--------------------------------------------------------------------------------

=head3    remove_nodes_from_knownhosts

        Removes the nodes from SSH known hosts

        Arguments:
                \@node_hostnames

        Returns:
                1 - error
                0 - success
        Globals:
                none
        Example:
                remove_nodes_from_knownhosts(\@nodes);
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub remove_nodes_from_knownhosts
{
    my ($callback, $ref_nodes) = @_;
    my @node_hostnames = @$ref_nodes;
    my $home           = xCAT::Utils->getHomeDir("root");
    
    my @all_names;
    
    my ($hostname, $ipaddr);
    
    # Put all the possible knownhosts entries 
    # for the nodes into @all_names
    foreach my $node (@node_hostnames)
    {
        if (!grep(/^$node$/, @all_names))
        { 
            push @all_names, $node;
        }
        ($hostname, $ipaddr) = xCAT::NetworkUtils->gethostnameandip($node);
        if (!$hostname || !$ipaddr)
        {
            return 0;
        }
        if (!grep(/^$hostname$/, @all_names))
        {
            push @all_names, $hostname;
        }
        if (!grep(/^$ipaddr$/, @all_names))
        {
            push @all_names, $ipaddr;
        }
        
    }

    #create the sed command
    my $sed = "/bin/sed -e ";
    $sed .= "\"";
    foreach my $n (@all_names)
    {
        $sed .= "/^$n\[,| ]/d; ";
    }
    chop $sed;    #get rid of last space
    $sed .= "\"";
    my $file = "/tmp/$$";
    while (-e $file)
    {
        $file = xCAT::Utils->CreateRandomName($file);
    }
    if (-e "$home/.ssh/known_hosts")
    {
        $sed .= " $home/.ssh/known_hosts";
        $sed .= " > $file";
        my $printsed = $sed;
        $printsed =~ s/"//g;    #"
        if ($::opt_V)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Running command: $printsed";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        xCAT::Utils->runcmd($sed, -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Command \"$printsed\" failed.";
            xCAT::MsgUtils->message("I", $rsp, $callback, 1);
            return 1;
        }

        my $cp = "cat $file > $home/.ssh/known_hosts";
        if ($::opt_V)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Running command: $cp";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        xCAT::Utils->runcmd($cp, -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Command \"$cp\" failed.";
            xCAT::MsgUtils->message("I", $rsp, $callback, 1);
            return 1;
        }
    }
    xCAT::Utils->runcmd("rm -f $file", -1);
    return 0;
}
