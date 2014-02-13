# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle mkzone,chzone,rmzone commands 

   Supported command:
         mkzone,chzone,rmzone - manage xcat cluster zones 

=cut

#-------------------------------------------------------
package xCAT_plugin::zone;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}

use strict;
require xCAT::Utils;
require xCAT::Zone;
require xCAT::MsgUtils;
require xCAT::Table;
use xCAT::NodeRange;
use xCAT::NodeRange qw/noderange abbreviate_noderange/;

use Getopt::Long;


#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {mkzone => "zone",
            chzone => "zone",
            rmzone => "zone",
            };
}



#-------------------------------------------------------

=head3  process_request

  Process the command, this only runs on the management node

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $sub_req = shift;
    $::CALLBACK = $callback;
    my $command = $request->{command}->[0];
    my $rc=0;
    # the directory which will contain the zone keys
    my $keydir="/etc/xcat/sshkeydir/";
    
    # check if Management Node, if not error
    unless (xCAT::Utils->isMN()) 
    {
            my $rsp = {};
            $rsp->{error}->[0] = "The $command may only be run on the Management Node.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return 1; 

    }
    # test to see if any parms 
    if (scalar($request->{arg} == 0)) {
        my $rsp = {};
        $rsp->{error}->[0] =
          "No parameters input to the $command command,  see man page for syntax.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    my $args = $request->{arg};
    @ARGV = @{$args};    # get arguments
    my %options = ();
    $Getopt::Long::ignorecase = 0;   
    Getopt::Long::Configure("bundling");

    if (
        !GetOptions(
                    'a|noderange=s'   => \$options{'noderange'},
                    'defaultzone|defaultzone'   => \$options{'defaultzone'}, 
                    'g|assigngrp'     => \$options{'assigngroup'},
                    'f|force'        => \$options{'force'},
                    'h|help'        => \$options{'help'},
                    'k|sshkeypath=s'   => \$options{'sshkeypath'},
                    'K|genkeys'     => \$options{'gensshkeys'},
                    'v|version'     => \$options{'version'},
                    'V|Verbose'     => \$options{'verbose'},
        )
      )
    {

        &usage($callback,$command);
        exit 1;
    }
    if ($options{'help'})
    {
        &usage($callback,$command);
        exit 0;
    }
    if ($options{'version'})
    {
        my $version = xCAT::Utils->Version();
        my $rsp = {};
        $rsp->{data}->[0] = $version;
        xCAT::MsgUtils->message("I", $rsp, $callback);
        exit 0;
    }
    # test to see if the zonename was input
    if (scalar(@ARGV) == 0) {
        my $rsp = {};
        $rsp->{error}->[0] =
          "zonename not specified, see man page for syntax.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    } else {
       $request->{zonename} = $ARGV[0];
    }
    # save input noderange
    if ($options{'noderange'}) {
       $request->{noderange}->[0] = $options{'noderange'};
    }
    if ($options{'verbose'})
    {
        $::VERBOSE = "yes";
    }

    if ($command eq "mkzone")
    {
      $rc=mkzone($request, $callback,\%options,$keydir);
    }
    if ($command eq "chzone")
    {
        $rc=chzone($request, $callback,\%options,$keydir);
    }
    if ($command eq "rmzone")
    {
         $rc=rmzone($request, $callback,\%options,$keydir);
    }
    my $rsp = {};
    if ($rc ==0) {
      $rsp->{info}->[0] = "The $command ran successfully.";
      xCAT::MsgUtils->message("I", $rsp, $callback);
    } else {
      $rsp->{info}->[0] = "The $command had errors.";
      xCAT::MsgUtils->message("E", $rsp, $callback);
    }
    return $rc; 

}

#-------------------------------------------------------

=head3   

   Parses and runs  mkzone 


=cut

#-------------------------------------------------------
sub mkzone 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    # already checked but lets do it again,  need a zonename, it is the only required parm
    if (!($request->{zonename})) {

        my $rsp = {};
        $rsp->{error}->[0] =
          "zonename not specified, see man page for syntax.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    # test for -g, if no noderange this is an error 
    if (( ! defined($$options{'noderange'})) && ($$options{'assigngroup'})) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " The -g flag requires a noderange ( -a).";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }  
    # check to see if the input zone already exists
    if (xCAT::Zone->iszonedefined($request->{zonename})) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " zonename: $request->{zonename} already defined, use chzone or rmzone to change or remove it.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }
    
    # Create path to generated ssh keys
    $keydir .= $request->{zonename}; 

    # update the zone table 
    $rc=updatezonetable($request, $callback,$options,$keydir);
    if ($rc == 0) {  # zone table setup is ok
      $rc=updatenodelisttable($request, $callback,$options,$keydir);
      if ($rc == 0) {  # zone table setup is ok
        # generate root ssh keys
        $rc=gensshkeys($request, $callback,$options,$keydir);
        if ($rc != 0) {
          return 1;
        }
      }
    }


    return $rc;

}
#-------------------------------------------------------

=head3   

   Parses and runs chzone 


=cut

#-------------------------------------------------------
sub chzone 
{
    my ($request, $callback,$options,$keydir) = @_;


   # my $rsp = {};

    #xCAT::MsgUtils->message("I", $rsp, $callback);

    return 0;

}
#-------------------------------------------------------

=head3   

   Parses and runs rmzone 


=cut

#-------------------------------------------------------
sub rmzone 
{
    my ($request, $callback,$options,$keydir) = @_;


   # my $rsp = {};

    #xCAT::MsgUtils->message("I", $rsp, $callback);

    return 0;


}
#-------------------------------------------------------------------------------

=head3
      usage

        puts out zone command usage message

        Arguments:
          None

        Returns:

        Globals:


        Error:
                None


=cut

#-------------------------------------------------------------------------------

sub usage
{
    my ($callback, $command) = @_;
    my $usagemsg1="";
    my $usagemsg2="";
    if ($command eq "mkzone") {
       $usagemsg1  = " mkzone -h \n mkzone -v \n";
       $usagemsg2  = " mkzone <zonename> [-V] [--defaultzone] [-k <full path to the ssh RSA private key] \n        [-a <noderange>] [-g] [-f]";
    } else {
       if ($command eq "chzone") {
           $usagemsg1  = " chzone -h \n chzone -v \n";
           $usagemsg2  = " chzone <zonename> [-V] [--defaultzone] [-k <full path to the ssh RSA private key] \n      [-K] [-a <noderange>] [-r <noderange>] [-g] ";
       } else {
            if ($command eq "rmzone") {
               $usagemsg1  = " rmzone -h \n rmzone -v \n";
               $usagemsg2  = " rmzone <zonename> [-g]";
            }
       }
    }
    my $usagemsg .= $usagemsg1 .=  $usagemsg2 .= "\n";
    if ($callback)
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usagemsg;
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    else
    {
        xCAT::MsgUtils->message("I", $usagemsg);
    }
    return;
}
#-------------------------------------------------------

=head3   

   generate the ssh keys and store them in /etc/xcat/sshkeys/<zonename> 


=cut

#-------------------------------------------------------
sub gensshkeys 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    # generate root ssh keys
    # Did they input a path to existing RSA keys
    my $rsakey;
    my $zonename=$request->{zonename};
    if ($$options{'sshkeypath'}) {
        # check to see if RSA keys exists
        $rsakey= $$options{'sshkeypath'} .= "/id_rsa";
        if (!(-e $rsakey)){   # if it does not exist error out
           my $rsp = {};
           $rsp->{error}->[0] =
             "Input $rsakey does not exist.  Cannot generate the ssh root keys for the zone.";
           xCAT::MsgUtils->message("E", $rsp, $callback);
           return 1;
        }
    } 
    
    $rc =xCAT::Zone->genSSHRootKeys($callback,$keydir, $zonename,$rsakey);
    if ($rc !=0) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " Failure generating the ssh root keys for the zone.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }

    return  $rc;

}
#-------------------------------------------------------

=head3   
    updatezonetable
    Add the new zone to the zone table, check if already there and 
    error - use either chzone or -f to override default 



=cut

#-------------------------------------------------------
sub updatezonetable 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    my $zoneentry;
    my $tab = xCAT::Table->new("zone");
    if ($tab)
    {
     my %tb_cols;
     $tb_cols{sshkeydir} = $keydir;             
     my $zonename=$request->{zonename};
     if ( $$options{'defaultzone'}) {  # set the default
       # check to see if a default already defined
       my $curdefaultzone = xCAT::Zone->getdefaultzone;
       if (!(defined ($curdefaultzone))) {  # no default defined
           $tb_cols{defaultzone} ="yes";
       } else { # already a default
          if ($$options{'force'}) {  # force the default
            $tb_cols{defaultzone} ="yes";
            $tab->setAttribs({zonename => $zonename}, \%tb_cols);
            # now change the old default zone to not be the default
            my %tb1_cols;
            $tb1_cols{defaultzone} ="no";
            $tab->setAttribs({zonename => $curdefaultzone}, \%tb1_cols);
            $tab->commit();
            $tab->close();
          } else {  # no force this is an error
             my $rsp = {};
             $rsp->{error}->[0] =
             " Failure setting default zone. The defaultzone $curdefaultzone already exists. Use the -f flag if you want to override the current default zone.";
             xCAT::MsgUtils->message("E", $rsp, $callback);
             return 1;
          }
       }
     } else { # not a default zone
       $tb_cols{defaultzone} ="no";
       $tab->setAttribs({zonename => $zonename}, \%tb_cols);
       $tab->commit();
       $tab->close();
     }
    } else {
       my $rsp = {};
       $rsp->{error}->[0] =
        " Failure opening the zone table.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }

     
    return  $rc;

}
#-------------------------------------------------------

=head3   
    updatenodelisttable 
    Add the new zonename attribute to any nodes in the noderange ( if a noderange specified) 
    Add zonename group to nodes in the noderange if -g flag. 



=cut

#-------------------------------------------------------
sub updatenodelisttable 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    # test for a noderange, if not supplied nothing to do
    if ( ! defined($$options{'noderange'})) {
       return 0;
    }  
    my $zonename=$request->{zonename};
    # there is a node range. update the nodelist table
    # if -g add zonename group also
    my $group=$$options{'noderange'};
    my @nodes = xCAT::NodeRange::noderange($request->{noderange}->[0]);
    my $tab = xCAT::Table->new("nodelist");
    if ($tab)
    {
      # if -g then add the zonename to the group attribute on each node
      if ($$options{'assigngroup'}){
         foreach my $node (@nodes) {
             xCAT::TableUtils->updatenodegroups($node,$tab,$zonename);
         }
      }
      # set the nodelist zonename attribute to the zonename for all nodes in the range
      $tab-> setNodesAttribs(\@nodes, { zonename => $zonename });
      $tab->commit();
      $tab->close();
    } else {
       my $rsp = {};
       $rsp->{error}->[0] =
        " Failure opening the nodelist table.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }
    return  $rc;

}

1;
