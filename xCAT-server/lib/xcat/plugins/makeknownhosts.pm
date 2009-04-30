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

require xCAT::MsgUtils;
use Getopt::Long;
use Socket;
require xCAT::DSHCLI;
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
    my $HELP;

    # parse the input
    if ($request && $request->{arg}) { @ARGV = @{$request->{arg}}; }
    else { @ARGV = (); }

    my $usage = "Usage: makeknownhosts <noderange>\n       makeknownhosts -h";

    # print "argv=@ARGV\n";
    if (!GetOptions('h|help' => \$HELP))
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }

    # display the usage if -h
    if ($HELP)
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
    $rc = create_known_hosts_file($callback);
    if ($rc != 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error building known_hosts file.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;

    }
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
    return 0;
}

#-------------------------------------------------------

=head3  create_known_hosts file 

  Creates a new known_hosts file in roots  .ssh directory, backs up the 
  old one, if it exists



=cut

#-------------------------------------------------------
sub create_known_hosts_file
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
            $cmd = "mv $file $newfile";
            xCAT::Utils->runcmd($cmd, -1);

        }
        $cmd = " touch $file";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Could not create $file";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return 1;
        }
        $cmd = " chmod 0644 $file";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "$cmd failed";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return 1;
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
    my $ip_address;
    my $home        = xCAT::Utils->getHomeDir("root");
    my $known_hosts = "$home/.ssh/known_hosts";

    my $hostkey = "/etc/xcat/hostkeys/ssh_host_rsa_key.pub";
    my $hostname;
    my $aliases;
    my $addrtype;
    my $length;
    my @addrs;
    if (($hostname, $aliases, $addrtype, $length, @addrs) =
        gethostbyname($node))
    {
        $ip_address = inet_ntoa($addrs[0]);
    }
    $cmd = "cat $hostkey";
    my @output = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Could $cmd, cannot create known_hosts";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }
    if (defined $hostname) {
      chop($output[0]);
      $line = "\"";
      $line .= "$hostname,$ip_address ";
      $line .= $output[0];
      $line .= "\"";
      $cmd = "echo  $line >> $known_hosts";
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
