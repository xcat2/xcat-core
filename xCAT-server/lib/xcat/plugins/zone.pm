# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle mkzone,chzone,Input rmzone commands 

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
    my $keydir="/etc/xcat/sshkeys/";
    
    # check if Management Node, if not error
    unless (xCAT::Utils->isMN()) 
    {
            my $rsp = {};
            $rsp->{error}->[0] = "The $command may only be run on the Management Node.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return 1; 

    }
    # you may not run on AIX
    if (xCAT::Utils->isAIX()) {
            my $rsp = {};
            $rsp->{error}->[0] = "The $command may only be run on a Linux Cluster.";
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
    # Get the zonename if it is in the input 
    my @SaveARGV = @ARGV;
    my $zonename = @SaveARGV[0];  # here is the zonename, if there is one
    if ($zonename) {   #  take zonename off the argument list so it will parse correctly
       my $tmp = shift(@SaveARGV);
       @ARGV = @SaveARGV;       
    }
    Getopt::Long::Configure("posix_default");
    Getopt::Long::Configure("no_gnu_compat");
    Getopt::Long::Configure("bundling");
    my %options = ();

    if (
        !GetOptions(
                    'a|noderange=s'   => \$options{'addnoderange'},
                    'r|noderange=s'   => \$options{'rmnoderange'},
                    'defaultzone|defaultzone'   => \$options{'defaultzone'}, 
                    'g|assigngrp'     => \$options{'assigngroup'},
                    'f|force'        => \$options{'force'},
                    'h|help'        => \$options{'help'},
                    'k|sshkeypath=s'   => \$options{'sshkeypath'},
                    'K|genkeys'     => \$options{'gensshkeys'},
                    's|sshbetweennodes=s'     => \$options{'sshbetweennodes'},
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
    if (!$zonename) {
        my $rsp = {};
        $rsp->{error}->[0] =
          "zonename not specified, it is required for this command.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    } else {
       $request->{zonename} = $zonename;
    }
    # if -s entered must be yes/1 or no/0
    if ($options{'sshbetweennodes'}) {
      if ($options{'sshbetweennodes'}=~ /^yes$/i || $options{'sshbetweennodes'} eq "1") {
           $options{'sshbetweennodes'}= "yes";
      } else {
        if ($options{'sshbetweennodes'}=~ /^no$/i || $options{'sshbetweennodes'} eq "0") {
           $options{'sshbetweennodes'}= "no";
        } else {
             my $rsp = {};
             $rsp->{error}->[0] =
              "The input on the -s flag $options{'sshbetweennodes'} is not valid.";
             xCAT::MsgUtils->message("E", $rsp, $callback);
             exit 1;
        }
      }
    }

    # check for site.sshbetweennodes attribute, put out a warning it will not be used as long
    # as zones are defined in the zone table.
    my @entries =  xCAT::TableUtils->get_site_attribute("sshbetweennodes");    
    if ($entries[0]) {
         my $rsp = {};
         $rsp->{info}->[0] =
              "The site table sshbetweennodes attribute is set to $entries[0].  It is not used when zones are defined.  To get rid of this warning, remove the site table sshbetweennodes attribute.";
             xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    #  -a and -r flags cannot be used together
    if (($options{'addnoderange'})  && ($options{'rmnoderange'})) {
        my $rsp = {};
        $rsp->{error}->[0] =
              "You may not use the -a flag to add nodes and the -r flag to remove nodes on one command.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
           
    }
    # save input noderange  to add nodes
    if ($options{'addnoderange'}) {
       
       # check to see if Management Node is in the noderange, if so error
       $request->{noderange}->[0] = $options{'addnoderange'};
       my @nodes = xCAT::NodeRange::noderange($request->{noderange}->[0]);
       my @mname = xCAT::Utils->noderangecontainsMn(@nodes); 
       if (@mname)
        {    # MN in the nodelist
            my $nodes=join(',', @mname);
            my $rsp = {};
            $rsp->{error}->[0] =
              "You must not run $command and include the  management node: $nodes.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1; 
        }
 
 
    }
    # save input noderange  to remove nodes
    if ($options{'rmnoderange'}) {
       
       # check to see if Management Node is in the noderange, if so error
       $request->{noderange}->[0] = $options{'rmnoderange'};
       my @nodes = xCAT::NodeRange::noderange($request->{noderange}->[0]);
       my @mname = xCAT::Utils->noderangecontainsMn(@nodes); 
       if (@mname)
        {    # MN in the nodelist
            my $nodes=join(',', @mname);
            my $rsp = {};
            $rsp->{error}->[0] =
              "You must not run $command and include the  management node: $nodes.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1; 
        }
 
 
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
         $rc=rmzone($request, $callback,\%options);
    }
    my $rsp = {};
    if ($rc ==0) {
      $rsp->{info}->[0] = "The $command ran successfully.";
      xCAT::MsgUtils->message("I", $rsp, $callback);
    } else {
      $rsp->{error}->[0] = "The $command had errors.";
      xCAT::MsgUtils->message("E", $rsp, $callback);
    }
    return $rc; 

}

#-------------------------------------------------------

=head3   

   Parses and runs  mkzone 
   Input 
     request
     callback
     Input  arguments from the GetOpts
     zone ssh key dir

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
          "zonename not specified The zonename is required.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    # test for -g, if no noderange this is an error 
    if (( ! defined($$options{'addnoderange'})) && ($$options{'assigngroup'})) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " The -g flag requires a noderange ( -a).";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }  
    # test for -r,  not valid 
    if ($$options{'rmnoderange'}) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " The -r flag Is not valid for mkzone. Use chzone.";
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
    # keydir comes in set to /etc/xcat/sshkeys
    $keydir .= $request->{zonename}; 
    $keydir .= "/.ssh"; 
    

    # add new zones to the zone table 
    $rc=addtozonetable($request, $callback,$options,$keydir);
    if ($rc == 0) {  # zone table setup is ok
      # test for a noderange, if(-a) not supplied nothing to do
      if (defined($$options{'addnoderange'})) {
        $rc=addnodestozone($request, $callback,$options,$keydir);
      }  
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
   Input 
     request
     callback
     Input  arguments from the GetOpts


=cut

#-------------------------------------------------------
sub chzone 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    # Create default  path to generated ssh keys
    # keydir comes in set to /etc/xcat/sshkeys
    $keydir .= $request->{zonename}; 
    $keydir .= "/.ssh"; 
    my $zonename=$request->{zonename};
    # already checked but lets do it again,  need a zonename
    if (!($request->{zonename})) {

        my $rsp = {};
        $rsp->{error}->[0] =
          "zonename not specified The zonename is required.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    # see if they asked to do anything
    if ((!($$options{'sshkeypath'})) && (!($$options{'gensshkeys'})) && 
       (!( $$options{'addnoderange'})) && (!( $$options{'rmnoderange'})) &&
       (!( $$options{'defaultzone'})) &&
        (!($$options{'assigngroup'} )) && (!($$options{'sshbetweennodes'}))) {
        my $rsp = {};
        $rsp->{info}->[0] =
          "chzone was run but nothing to do.";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }
    # get the zone ssh key directory. We don't have a good zone without it.
    my $sshrootkeydir = xCAT::Zone->getzonekeydir($zonename);
    if ($sshrootkeydir == 1) { # error return
       #if we have been requested to regenerated the ssh keys continue
       if (($$options{'sshkeypath'}) || ($$options{'gensshkeys'})) { 
           my $rsp = {};
           $rsp->{info}->[0] =
           " sshkeydir attribute not defined for $zonename. The zone sshkeydir will be regenerated.";
           xCAT::MsgUtils->message("I", $rsp, $callback);
       } else {  # sshkeydir is missing  and they did not request to regenerate,   that is an error
           my $rsp = {};
           $rsp->{error}->[0] =
           " sshkeydir attribute not defined for $zonename. The zone sshkeydir must be regenerated. Rerun this command with -k or -K options";
           xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
       }
    } else {  # we got a sshkeydir from the database, use it
        $keydir=$sshrootkeydir;
    }
    # do we regenerate keys (-k or -K)
    if (($$options{'sshkeypath'}) || ($$options{'gensshkeys'})) {
       $rc=gensshkeys($request, $callback,$options,$keydir);
       if ($rc != 0) {
         return 1;
       }
    }
    
    # update the zone table 
    $rc=updatezonetable($request, $callback,$options,$keydir);
    if ($rc == 0) {  # zone table setup is ok
      # update the nodelist table
      if (defined($$options{'addnoderange'})) {
        $rc=addnodestozone($request, $callback,$options,$keydir);
      } else {  # note -a and -r are not allowed on one chzone
          if (defined($$options{'rmnoderange'})) {
            $rc=rmnodesfromzone($request, $callback,$options,$keydir);
          }
      }
    }


    return $rc;
}
#-------------------------------------------------------

=head3   

   Parses and runs rmzone 
   Input 
     request
     callback
     Input  arguments from the GetOpts
      

=cut

#-------------------------------------------------------
sub rmzone 
{
    my ($request, $callback,$options) = @_;
    
    # already checked but lets do it again,  need a zonename, it is the only required parm
    if (!($request->{zonename})) {

        my $rsp = {};
        $rsp->{error}->[0] =
          "zonename not specified The zonename is required.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    # check to see if the input zone already exists
    # cannot remove it if it is not defined
    my $zonename=$request->{zonename};
    if (!(xCAT::Zone->iszonedefined($zonename))) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " zonename: $zonename is not defined. You cannot remove it.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }
    # is this zone is the default zone you must force the delete
    my $defaultzone =xCAT::Zone->getdefaultzone($callback);
    if (($defaultzone eq $zonename) && (!($$options{'force'}))) {
       my $rsp = {};     
       $rsp->{error}->[0] =
        " You are removing the default zone: $zonename.  You must define another default zone before deleting or use the -f flag to force the removal.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }

    # get the zone ssh key directory
    my $sshrootkeydir = xCAT::Zone->getzonekeydir($zonename);
    if ($sshrootkeydir == 1) { # error return
       my $rsp = {};
       $rsp->{info}->[0] =
        " sshkeydir attribute not defined for $zonename. Cannot remove it.";
       xCAT::MsgUtils->message("I", $rsp, $callback);
    } else {  # remove the keys  unless it is /root/.ssh
       my $roothome = xCAT::Utils->getHomeDir("root");
       $roothome .="\/.ssh";
       if ($sshrootkeydir eq $roothome) {  # will not delete /root/.ssh
           my $rsp = {};
           $rsp->{info}->[0] =
             "  $zonename sshkeydir is $roothome. This will not be deleted.";
             xCAT::MsgUtils->message("I", $rsp, $callback);
       } else {  # not roothome/.ssh
         # check to see if id_rsa.pub is there. I don't want to remove the
         # wrong directory
         # if id_rsa.pub exists remove the files
         # then remove the directory
         if ( -e "$sshrootkeydir/id_rsa.pub") {
           my $cmd= "rm -rf $sshrootkeydir";    
           xCAT::Utils->runcmd($cmd,0);
           if ($::RUNCMD_RC != 0)
           {
              my $rsp = {};
              $rsp->{error}->[0] = "Command: $cmd failed";
              xCAT::MsgUtils->message("E", $rsp, $callback);
           }
           my ($zonedir,$ssh)= split(/\.ssh/, $sshrootkeydir);
           $cmd= "rmdir $zonedir";    
           xCAT::Utils->runcmd($cmd,0);
           if ($::RUNCMD_RC != 0)
           {
              my $rsp = {};
              $rsp->{error}->[0] = "Command: $cmd failed";
              xCAT::MsgUtils->message("E", $rsp, $callback);
           }
          } else {  #  no id_rsa.pub key will not remove the files
              my $rsp = {};
              $rsp->{info}->[0] = "$sshrootkeydir did not contain an id_rsa.pub key, will not remove files";
              xCAT::MsgUtils->message("I", $rsp, $callback);
          }
       }
    
    }

    # open zone table and remove this entry
    my $tab = xCAT::Table->new("zone");
    if (!defined($tab)) {  
       my $rsp = {};
       $rsp->{error}->[0] =
        " Failure opening the zone table.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }
    # remove the table entry
    $tab->delEntries({zonename=>$zonename});

    # remove zonename and possibly group name (-g flag) from  any nodes defined in this zone
    my $rc=rmnodesfromzone($request, $callback,$options,"ALL");

    return $rc;



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
       $usagemsg2  = " mkzone <zonename> [-V] [--defaultzone] [-k <full path to the ssh RSA private key] \n        [-a <noderange>] [-g] [-f] [-s <yes/no>]";
    } else {
       if ($command eq "chzone") {
           $usagemsg1  = " chzone -h \n chzone -v \n";
           $usagemsg2  = " chzone <zonename> [-V] [--defaultzone] [-k <full path to the ssh RSA private key] \n      [-K] [-a <noderange>] [-r <noderange>] [-g] [-s <yes/no>]";
       } else {
            if ($command eq "rmzone") {
               $usagemsg1  = " rmzone -h \n rmzone -v \n";
               $usagemsg2  = " rmzone <zonename> [-g]";
            }
       }
    }
    my $usagemsg .= $usagemsg1 .=  $usagemsg2 ;
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

   generate the ssh keys and store them in /etc/xcat/sshkeys/<zonename>/.ssh 


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
    addtozonetable
    Add the new zone to the zone table, check if already there and 
    error - use either chzone or -f to override default 



=cut

#-------------------------------------------------------
sub addtozonetable 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    my $zoneentry;
    my $tab = xCAT::Table->new("zone");
    if ($tab)
    {
     # read a record from the zone table, if it is empty then add
     #  the xcatdefault entry
     my @zones = $tab->getAllAttribs('zonename');
     if (!(@zones)) {  # table empty
       my %xcatdefaultzone;
       $xcatdefaultzone{defaultzone} ="yes";
       $xcatdefaultzone{sshbetweennodes} ="yes";
       my $roothome = xCAT::Utils->getHomeDir("root");
       $roothome .="\/.ssh";
       $xcatdefaultzone{sshkeydir} =$roothome;
       $tab->setAttribs({zonename => "xcatdefault"}, \%xcatdefaultzone);
     }

     # now add the users zone
     my %tb_cols;
     $tb_cols{sshkeydir} = $keydir;  # key directory
     # set sshbetweennodes attribute from -s flag or default to yes
     if ( $$options{'sshbetweennodes'}) {
        $tb_cols{sshbetweennodes} = $$options{'sshbetweennodes'};         
     } else {
        $tb_cols{sshbetweennodes} = "yes";         
     }
     my $zonename=$request->{zonename};
     if ( $$options{'defaultzone'}) {  # set the default
       # check to see if a default already defined
       my $curdefaultzone = xCAT::Zone->getdefaultzone($callback);
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
    updatezonetable
    change either the sshbetweennodes or defaultzone  attribute
    or generate new keys ( -k -K)


=cut

#-------------------------------------------------------
sub updatezonetable 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $zoneentry; 
    my $zonename=$request->{zonename};
    # check for changes
    if (($$options{'sshbetweennodes'}) || ( $$options{'defaultzone'}) ||
       ($$options{'sshkeypath'}) || ($$options{'gensshkeys'})) { 

      my $tab = xCAT::Table->new("zone");
      if($tab) {

       # now add the users changes 
       my %tb_cols;
       # generated keys ( -k or -K)
       if (($$options{'sshkeypath'}) || ($$options{'gensshkeys'})) {
         $tb_cols{sshkeydir} = $keydir;  # key directory
       }
       # set sshbetweennodes attribute from -s flag 
       if ( $$options{'sshbetweennodes'}) {
        $tb_cols{sshbetweennodes} = $$options{'sshbetweennodes'};         
       }
       # if --defaultzone
       if ( $$options{'defaultzone'}) {  # set the default
         # check to see if a default already defined
         my $curdefaultzone = xCAT::Zone->getdefaultzone($callback);
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
       } else { # not a default zone change, just commit the other changes
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
  }

     
  return  0;

}
#-------------------------------------------------------

=head3   
    addnodestozone 
    Add the new zonename attribute to any nodes in the noderange ( if a noderange specified) 
    Add zonename group to nodes in the noderange if -g flag. 



=cut

#-------------------------------------------------------
sub addnodestozone 
{
    my ($request, $callback,$options,$keydir) = @_;
    my $rc=0;
    my $zonename=$request->{zonename};
    # if -g add zonename group also
    my @nodes = xCAT::NodeRange::noderange($request->{noderange}->[0]);
    # check to see if noderange expanded
    if (!(scalar @nodes)) {
       my $rsp = {};
       $rsp->{error}->[0] =
        " The noderange $request->{noderange}->[0] is not valid. The nodes are not defined.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    } 
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
#-------------------------------------------------------

=head3   
    rmnodesfromzone 
    removes the zonename from all nodes with their zonename the input zone or
    the noderange supplied on the -r flag
    if -g, removes zonename group from all nodes defined with their zonename the input zone. 
    Note if $ALL is input it removes all nodes from the zone, 
     otherwise  $request->{noderange} points to the noderange


=cut

#-------------------------------------------------------
sub rmnodesfromzone 
{
    my ($request, $callback,$options,$ALL) = @_;
    my $zonename=$request->{zonename};
    my $tab = xCAT::Table->new("nodelist");
    if ($tab)
    {
      # read all the nodes with zonename
      my @nodes;
      if ($ALL) {  # do all nodes
        @nodes = xCAT::Zone->getnodesinzone($callback,$zonename);
      } else {  # the nodes in the noderange ( -r )
        @nodes = xCAT::NodeRange::noderange($request->{noderange}->[0]);
        # check to see if noderange expanded
        if (!(scalar @nodes)) {
           my $rsp = {};
           $rsp->{error}->[0] =
           " The noderange $request->{noderange}->[0] is not valid. The nodes are not defined.";
           xCAT::MsgUtils->message("E", $rsp, $callback);
           return 1;
        } 
      }
      # if -g then remove the zonename  group attribute on each node
      if ($$options{'assigngroup'}){
         foreach my $node (@nodes) {
             xCAT::TableUtils->rmnodegroups($node,$tab,$zonename);
         }
      }
      # set the nodelist zonename to nothing
      my $nozonename=""; 
      $tab-> setNodesAttribs(\@nodes, { zonename => $nozonename  });
      $tab->commit();
      $tab->close();
    } else {
       my $rsp = {};
       $rsp->{error}->[0] =
        " Failure opening the nodelist table.";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }
    return  0;

}


1;
