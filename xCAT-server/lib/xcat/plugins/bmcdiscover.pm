# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle BMC discovery
=cut

#-------------------------------------------------------
package xCAT_plugin::bmcdiscover;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use IO::Socket;
use Thread qw(yield);
use POSIX "WNOHANG";
use Storable qw(store_fd fd_retrieve);
use strict;
use warnings "all";
use Getopt::Long;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use File::Path;
use Cwd;

my $nmap_path;

my $debianflag = 0;
my $tempstring = xCAT::Utils->osver();
if ( $tempstring =~ /debian/ || $tempstring =~ /ubuntu/ ){
    $debianflag = 1;
}
my $parent_fd;
my $bmc_user;
my $bmc_pass;
#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            bmcdiscover => "bmcdiscover",
	   };
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $request_command = shift;
    $::CALLBACK = $callback;
    #$::args     = $request->{arg};

    unless(defined($request->{arg})){
        bmcdiscovery_usage();
        return 2; 
    }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            return 2;
    }


    my $command  = $request->{command}->[0];
    my $rc;

    if ($command eq "bmcdiscover"){
        $rc = bmcdiscovery($request, $callback, $request_command);
    } else{
        $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
        return 1;
    }

}


#----------------------------------------------------------------------------

=head3  bmcdiscover_usage

        Display the bmcdiscover usage
=cut

#-----------------------------------------------------------------------------

sub bmcdiscovery_usage {
    my $rsp;
    push @{ $rsp->{data} }, "\nbmcdiscover - Discover BMC (Baseboard Management Controller) using the specified scan method\n";
    push @{ $rsp->{data} }, "Usage:";
    push @{ $rsp->{data} }, "\tbmcdiscover [-?|-h|--help]";
    push @{ $rsp->{data} }, "\tbmcdiscover [-v|--version]";
    push @{ $rsp->{data} }, "\tbmcdiscover [-s scan_method] [-u bmc_user] [-p bmc_passwd] [-z] [-w] [-t] --range ip_range\n";

    push @{ $rsp->{data} }, "\tCheck BMC administrator User/Password:\n";
    push @{ $rsp->{data} }, "\t\tbmcdiscover -u bmc_user -p bmc_password -i bmc_ip --check\n";

    push @{ $rsp->{data} }, "\tDisplay the BMC IP configuration:\n";
    push @{ $rsp->{data} }, "\t\tbmcdiscover [-u bmc_user] [-p bmc_passwd] -i bmc_ip --ipsource";

    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}

#----------------------------------------------------------------------------

=head3   bmcdiscovery_processargs

        Process the bmcdiscovery command line
        Returns:
                0 - OK
                1 - just print version
                2 - just print help
                3 - error
=cut

#-----------------------------------------------------------------------------
sub bmcdiscovery_processargs {

    #if ( defined ($::args) && @{$::args} ){
    #    @ARGV = @{$::args};
    #}
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;

    
    # parse the options
    # options can be bundled up like -v, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    my $getopt_success = Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              's=s' => \$::opt_M,
                              'm=s' => \$::opt_M,
                              'range=s' => \$::opt_R,
                              'bmcip|i=s' => \$::opt_I,
                              'z' => \$::opt_Z,
                              'w' => \$::opt_W,
                              'check' => \$::opt_C,
                              'bmcuser|u=s' => \$::opt_U,
                              'bmcpasswd|p=s' => \$::opt_P,
                              'ipsource' => \$::opt_S,
                              'version|v' => \$::opt_v,
                              't' => \$::opt_T,
    );

    if (!$getopt_success) {
        return 3;
    }


    #########################################
    # This command is for linux
    #########################################
    if ($^O ne 'linux') {
        my $rsp = {};
        push @{ $rsp->{data}}, "The bmcdiscovery command is only supported on Linux.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    ##########################################
    # Option -h for Help
    ##########################################
    if ( defined($::opt_h) ) {
          bmcdiscovery_usage;   
          return 0; 
    }

    #########################################
    # Option -v for version
    #########################################
    if ( defined($::opt_v) ) {
        create_version_response('bmcdiscover');
        # no usage - just exit
        return 1;    
    }

    #
    # Get the default bmc account from passwd table
    #
    ($bmc_user, $bmc_pass) = bmcaccount_from_passwd();
    # overwrite the default user/pass with what is passed in
    if ($::opt_U) {
        $bmc_user = $::opt_U;
    }
    if ($::opt_P) {
        $bmc_pass = $::opt_P;
    }

    #########################################
    # Option -s -r should be together
    ######################################
    if ( defined($::opt_R) ) 
    {
        ######################################
        # check if there is nmap or not
        ######################################
        if ( -x '/usr/bin/nmap' )
        {
            $nmap_path="/usr/bin/nmap";
        }
        elsif ( -x '/usr/local/bin/nmap' )
        {
            $nmap_path="/usr/local/bin/nmap";
        }
        else
        {
            my $rsp;
            push @{ $rsp->{data} }, "\tThere is no nmap in /usr/bin/ or /usr/local/bin/. \n ";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
        scan_process($::opt_M,$::opt_R,$::opt_Z,$::opt_W,$request_command);
        return 0;
    }

    if ( defined($::opt_C) && defined($::opt_S) ) {
        my $msg = "The 'check' and 'ipsource' option cannot be used together.";
        my $rsp = {};
        push @{ $rsp->{data} }, "$msg";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }

    #########################################################
    # --check option, requires -i, -u, and -p to be specified
    #########################################################
    if ( defined($::opt_C) ) {
        if ( defined($::opt_P) && defined($::opt_U) && defined($::opt_I) ) {
            my $res=check_auth_process($::opt_I,$::opt_U,$::opt_P);
            return $res;
        }
        else {
            my $msg = "";
            if (!defined($::opt_I)) {
                $msg = "The check option requires a BMC IP.  Specify the IP using the -i|--bmcip option.";
            } elsif (!defined($::opt_U)) {
                $msg = "The check option requires a user.  Specify the user with the -u|--bmcuser option.";
            } elsif (!defined($::opt_P)) {
                $msg = "The check option requires a password.  Specify the password with the -p|--bmcpasswd option.";
            } 
            my $rsp = {};
            push @{ $rsp->{data} }, "$msg";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 2;
        }
    }

    ####################################################
    # --ipsource option, requires -i, -p to be specified
    ####################################################
    if ( defined($::opt_S) ) {
        if ( defined($bmc_user) && defined($bmc_pass) && defined($::opt_I) ) {
            my $res=get_bmc_ip_source($::opt_I,$bmc_user,$bmc_pass);
            return $res;
        }
        else {
            my $msg = "";
            if (!defined($::opt_I)) {
                $msg = "The ipsource option requires a BMC IP.  Specify the IP using the -i|--bmcip option.";
            } elsif (!defined($::opt_P)) {
                $msg = "The ipsource option requires a password.  Specify the password with the -p|--bmcpasswd option.";
            } 
            my $rsp = {};
            push @{ $rsp->{data} }, "$msg";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 2;
        }
    }

    #########################################
    # Other attributes are not allowed
    #########################################

    return 4;
}

my $bmc_str1 = "RAKP 2 message indicates an error : unauthorized name";
my $bmc_resp1 = "Wrong BMC username";
       
my $bmc_str2 = "RAKP 2 HMAC is invalid";
my $bmc_resp2 = "Wrong BMC password";

#----------------------------------------------------------------------------

=head3   get_bmc_ip_source

        get bmc ip address source
        Returns:
                0 - OK
                2 - Error
=cut

#-----------------------------------------------------------------------------

sub get_bmc_ip_source{
    my $bmcip = shift;
    my $bmcuser = shift;
    my $bmcpw = shift;
    my $callback = $::CALLBACK;
    my $pcmd;

    if ( $bmcuser eq "none" ) {
       $pcmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -P $bmcpw -H $bmcip lan print ";
    }
    else {
       $pcmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -U $bmcuser -P $bmcpw -H $bmcip lan print ";
    }
    my $output = xCAT::Utils->runcmd("$pcmd", -1);

    if ( $output =~ "IP Address Source" ) {
        # success case 
        my $rsp = {};
        my $ipsource=`echo "$output"|grep "IP Address Source"`;
        chomp($ipsource); 
        push @{ $rsp->{data} }, "$ipsource";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }
    else {
        my $rsp = {};
        if ( $output =~ $bmc_str1 ) {
            # Error: RAKP 2 message indicates an error : unauthorized name <== incorrect username 
            push @{ $rsp->{data} }, "$bmc_resp1";
        } elsif ( $output =~ $bmc_str2 ) { 
            # Error: RAKP 2 HMAC is invalid <== incorrect password 
            push @{ $rsp->{data} }, "$bmc_resp2";
        } else { 
            # all other errors 
            push @{ $rsp->{data} }, "Error: Can not find IP Address Source";
        }
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
}


#----------------------------------------------------------------------------

=head3   check_auth_process

        check bmc user and password
        Returns:
                0 - OK
                2 - Error
=cut

#-----------------------------------------------------------------------------

sub check_auth_process{
    my $bmcip = shift;
    my $bmcuser = shift;
    my $bmcpw = shift;
    my $bmc_str4 = "BMC Session ID";
     
    my $callback = $::CALLBACK;
    my $icmd;
    if ( $bmcuser eq "none" ) {
       $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -P $bmcpw -H $bmcip chassis status ";
    }
    else { 
       $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -U $bmcuser -P $bmcpw -H $bmcip chassis status ";
    }
    my $output = xCAT::Utils->runcmd("$icmd", -1);

    if ($output =~ "Set Session Privilege Level to ADMINISTRATOR" ) {
        # Success case
        my $rsp = {};
        push @{ $rsp->{data} }, "Correct ADMINISTRATOR";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    } else { 
        # handle the various error scenarios 
        my $rsp = {};
        
        if ( $output =~ $bmc_str1 ) {
            # Error: RAKP 2 message indicates an error : unauthorized name <== incorrect username 
            push @{ $rsp->{data} }, "$bmc_resp1";
        }
        elsif ( $output =~ $bmc_str2 ) {
            # Error: RAKP 2 HMAC is invalid <== incorrect password 
            push @{ $rsp->{data} }, "$bmc_resp2";
        }
        elsif ( $output !~ $bmc_str4 ) {
            # Did not find "BMC Session ID" in the response 
            push @{ $rsp->{data} }, "Not a BMC, please verify the correct IP address";
        }
        else {
            push @{ $rsp->{data} }, "Unknown Error: $output";
        }
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
}

#----------------------------------------------------------------------------

=head3   scan_process

        Process the bmcdiscovery command line
        Returns:
                0 - OK
                1 - just print version
                2 - just print help
                3 - error
=cut

#-----------------------------------------------------------------------------

sub scan_process{

    my $method = shift;
    my $range = shift;
    my $opz = shift;
    my $opw = shift;
    my $request_command = shift; 
    my $callback = $::CALLBACK;
    my $children;    # The number of child process
    my %sp_children;    # Record the pid of child process
    my $bcmd;
    my $sub_fds = new IO::Select;    # Record the parent fd for each child process
  
    if ( !defined($method) )
    {
       $method="nmap";
    }

    my $ip_list;
    ############################################################
    # get live ip list
    ###########################################################
    if ( $method eq "nmap" ) {
        #check nmap version first
        my $ccmd = "$nmap_path -V | grep version";
        my $version_result = xCAT::Utils->runcmd($ccmd, 0);
        my @version_array = split / /, $version_result;
        my $nmap_version = $version_array[2];
        # the output of nmap is different for version under 4.75
        if (xCAT::Utils->version_cmp($nmap_version,"4.75") <= 0) {
            $bcmd = join(" ",$nmap_path," -sP -n $range | grep Host |cut -d ' ' -f2 |tr -s '\n' ' ' ");
        } else {
            $bcmd = join(" ",$nmap_path," -sn -n $range | grep for |cut -d ' ' -f5 |tr -s '\n' ' ' ");
        }

        $ip_list = xCAT::Utils->runcmd("$bcmd", -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp = {};
            push @{ $rsp->{data} }, "Nmap scan is failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 2;
        }

    }
    else
    {
        my $rsp = {};
        push @{ $rsp->{data}}, "The bmcdiscover method should be nmap.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
    
    my $live_ip=split_comma_delim_str($ip_list);
   
    if ( scalar (@{$live_ip}) > 0 )
    { 
          ###############################
          # Set the signal handler for ^c
          ###############################
          $SIG{TERM} = $SIG{INT} = sub {
          foreach (keys %sp_children) {
              kill 2, $_;
          }
          $SIG{ALRM} = sub {
              while (wait() > 0) {
                yield;
              }
              exit @_;
          };
          alarm(1); # wait 1s for grace exit
          };

          ######################################################
          # Set the singal handler for child process finished it's work
          ######################################################
          $SIG{CHLD} = sub {
              my $cpid;
              while (($cpid = waitpid(-1, WNOHANG)) > 0) {
                   if ($sp_children{$cpid}) {
                        delete $sp_children{$cpid};
                        $children--;
                   }
              }
          };

          for (my $i = 0; $i < scalar (@{$live_ip}); $i ++) {
   
               # fork a sub process to handle the communication with service processor
               $children++;
               my $cfd;

               # the $parent_fd will be used by &send_rep() to send response from child process to parent process
               socketpair($parent_fd, $cfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
               $cfd->autoflush(1);
               $parent_fd->autoflush(1);
               my $child = xCAT::Utils->xfork;
               if ($child == 0) {
                    close($cfd);
                    $callback = \&send_rep;
                    # Set child process default, if not the function runcmd may return error
                    $SIG{CHLD}='DEFAULT';
                    bmcdiscovery_ipmi(${$live_ip}[$i],$opz,$opw,$request_command);
                    exit 0;
               } else {

                    # in the main process, record the created child process and add parent fd for the child process to an IO:Select object
                    # the main process will check all the parent fd and receive response
                    $sp_children{$child}=1;
                    close ($parent_fd);
                    $sub_fds->add($cfd);
               }


               do {
                    sleep(1);
               } until ($children < 32);

          }

          #################################################
          # receive data from child processes
          ################################################
          while ($sub_fds->count > 0 or $children > 0) {
              forward_data($callback,$sub_fds);
          }
          while (forward_data($callback,$sub_fds)) {
          }
    }
    else
    {
        my $rsp = {};
        push @{ $rsp->{data}}, "No bmc found.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
}

#----------------------------------------------------------------------------
=head3  format_stanza
      list the stanza format for node
    Arguments:
      bmc ip 
    Returns:
      lists as stanza format for nodes
=cut
#--------------------------------------------------------------------------------
sub format_stanza {
    my $node = shift;
    my $data = shift;
    my ($bmcip,$bmcmtm,$bmcserial,$bmcuser,$bmcpass,$nodetype,$hwtype) = split(/,/,$data);
    my $result;
    if (defined($bmcip)){     
        $result .= "$node:\n\tobjtype=node\n";
        $result .= "\tgroups=all\n";
        $result .= "\tbmc=$bmcip\n";
        $result .= "\tcons=ipmi\n";
        $result .= "\tmgt=ipmi\n";
        if ($bmcmtm) {
            $result .= "\tmtm=$bmcmtm\n";
        }
        if ($bmcserial) {
            $result .= "\tserial=$bmcserial\n";
        }
        if ($bmcuser) {
            $result .= "\tbmcusername=$bmcuser\n";
        }
        if ($bmcpass) {
            $result .= "\tbmcpassword=$bmcpass\n";
        }
        if ($nodetype && $hwtype) {
            $result .= "\tnodetype=$nodetype\n";
            $result .= "\thwtype=$hwtype\n";
        }
        my $rsp = {};
        push @{ $rsp->{data} }, "$result";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
   }
   return ($result);
}

#----------------------------------------------------------------------------
=head3  write_to_xcatdb
      write node definition into xcatdb
    Arguments:
      $node_stanza:
    Returns:
=cut
#--------------------------------------------------------------------------------
sub write_to_xcatdb {
    my $node = shift;
    my $data = shift;
    my ($bmcip,$bmcmtm,$bmcserial,$bmcuser,$bmcpass,$nodetype,$hwtype) = split(/,/,$data);
    my $request_command = shift;
    my $ret;

       $ret = xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','node','-o',$node,"bmc=$bmcip","cons=ipmi","mgt=ipmi","mtm=$bmcmtm","serial=$bmcserial","bmcusername=$bmcuser","bmcpassword=$bmcpass","nodetype=$nodetype","hwtype=$hwtype","groups=all"] }, $request_command, 0, 1);
       if ($::RUNCMD_RC != 0) {
            my $rsp = {};
            push @{ $rsp->{data} }, "create or modify node is failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 2;
        }

}

#----------------------------------------------------------------------------

=head3 send_rep

    DESCRIPTION:
        Send date from forked child process to parent process.
        This subroutine will be replace the original $callback in the forked child process

    ARGUMENTS:
        $resp - The response which generated in xCAT::Utils->message();

=cut

#----------------------------------------------------------------------------

sub send_rep {
    my $resp=shift;

    unless ($resp) { return; }
    store_fd($resp,$parent_fd);
}

#----------------------------------------------------------------------------

=head3 forward_data

    DESCRIPTION:
        Receive data from forked child process and call the original $callback to forward data to xcat client

=cut
#----------------------------------------------------------------------------

sub forward_data {
  my $callback = shift;
  my $fds = shift;
  my @ready_fds = $fds->can_read(1);
  my $rfh;
  my $rc = @ready_fds;
  foreach $rfh (@ready_fds) {
    my $data;
    my $responses;
    eval {
        $responses = fd_retrieve($rfh);
    };
    if ($@ and $@ =~ /^Magic number checking on storable file/) { #this most likely means we ran over the end of available input
      $fds->remove($rfh);
      close($rfh);
    } else {
      eval { print $rfh "ACK\n"; }; #Ignore ack loss due to child giving up and exiting, we don't actually explicitly care about the acks
      $callback->($responses);
    }
  }
  yield; #Try to avoid useless iterations as much as possible
  return $rc;
}


#----------------------------------------------------------------------------

=head3  split_comma_delim_str

        Split comma-delimited list of strings into an array.

        Arguments: comma-delimited string
        Returns:   Returns list of strings (ref)

=cut

#-----------------------------------------------------------------------------
sub split_comma_delim_str {
    my $input_str = shift;

    my @result = split(/ /, $input_str);
    return \@result;
}

#----------------------------------------------------------------------------

=head3  create_version_response

        Create a response containing the command name and version
=cut

#-----------------------------------------------------------------------------
sub create_version_response {
    my $command = shift;
    my $rsp;
    my $version = xCAT::Utils->Version();
    push @{ $rsp->{data} }, "$command - xCAT $version";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
}


#----------------------------------------------------------------------------

=head3  create_error_response

        Create a response containing a single error message
        Arguments:  error message
=cut

#-----------------------------------------------------------------------------
sub create_error_response {
    my $error_msg = shift;
    my $rsp;
    push @{ $rsp->{data} }, $error_msg;
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
}


#----------------------------------------------------------------------------

=head3  bmcdiscovery

        Support for discovering bmc
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------
sub bmcdiscovery {

    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;

    ##############################################################
    # process the command line
    # 0=success, 1=version, 2=error for check_auth_, other=error
    ##############################################################
    $rc = bmcdiscovery_processargs($request,$callback,$request_command);
    if ( $rc != 0 ) {
       if ( $rc != 1 ) 
       {
           if ( $rc !=2 )
           {
               bmcdiscovery_usage(@_);
           }
       }
       return ( $rc - 1 );
    }
   #scan_process($::opt_M,$::opt_R);

   return $rc;

}


#----------------------------------------------------------------------------
=head3  get bmc account in passwd table
        Returns:
             username/password pair
        Notes:
             The default username/password is ADMIN/admin
=cut
#----------------------------------------------------------------------------

sub bmcaccount_from_passwd {
    my $bmcusername = "ADMIN";
    my $bmcpassword = "admin";
    my $passwdtab = xCAT::Table->new("passwd", -create=>0);
    if ($passwdtab) {
        my $bmcentry = $passwdtab->getAttribs({'key'=>'ipmi'},'username','password');
        if (defined($bmcentry)) {
            $bmcusername = $bmcentry->{'username'};
            $bmcpassword = $bmcentry->{'password'};
            unless ($bmcusername) {
                $bmcusername = '';
            }
            unless ($bmcpassword) {
                $bmcpassword = '';
            }
        }
    }
    return ($bmcusername,$bmcpassword);
}

#----------------------------------------------------------------------------

=head3  bmcdiscovery_ipmi

        Support for discovering bmc using ipmi
        Returns:
              if it is bmc, it returns bmc ip or host;
              if it is not bmc, it returns nothing;

=cut

#-----------------------------------------------------------------------------

sub bmcdiscovery_ipmi {
    my $ip = shift;
    my $opz = shift;
    my $opw = shift;
    my $request_command = shift;
    my $node = sprintf("node-%08x", unpack("N*", inet_aton($ip)));
    my $bmcstr = "BMC Session ID";
    my $bmcusername = '';
    my $bmcpassword = '';
    if ($bmc_user) {
        $bmcusername = "-U $bmc_user";
    }
    if ($bmc_pass) {
        $bmcpassword = "-P $bmc_pass";
    }
    my $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus $bmcusername $bmcpassword -H $ip chassis status ";
    my $output = xCAT::Utils->runcmd("$icmd", -1);
    if ( $output =~ $bmcstr ){
        # The output contains System Power indicated the username/password is correct, then try to get MTMS
        if ($output =~ /System Power\s*:\s*\S*/) {
            my $mtm = '';
            my $serial = '';

            # For system X and Tuleta, the fru 0 will contain the MTMS; For firestone, fru 3; For habanero, fru 2
            my @fru_num = (0, 2, 3);
            foreach my $fru_cmd_num (@fru_num){
                my $fru_cmd = "$::XCATROOT/bin/ipmitool-xcat -I lanplus $bmcusername $bmcpassword ".
                              "\-H $ip fru print $fru_cmd_num";
                my @fru_output_array = xCAT::Utils->runcmd($fru_cmd, -1);
                if (($::RUNCMD_RC eq 0) && @fru_output_array){ 
                    my $fru_output = join(" ", @fru_output_array);
                
                    if ($fru_cmd_num == 0) {
                        if (($fru_output =~ /Product Part Number   :\s*(\S*).*Product Serial        :\s*(\S*)/)) {
                            $mtm = $1;
                            $serial = $2;
                            last;
                        }
                    } 
                    else {
                        if (($fru_output =~ /Chassis Part Number\s*:\s*(\S*).*Chassis Serial\s*:\s*(\S*)/)) {
                            $mtm = $1;
                            $serial = $2;
                            last;
                        }
                    }
                }             
            }

            $ip .= ",$mtm";
            $ip .= ",$serial";
            if ($::opt_P) {
                if ($::opt_U) {
                    $ip .= ",$::opt_U,$::opt_P";
                } else {
                    $ip .= ",,$::opt_P";
                }
            } else {
                $ip .= ",,";
            }
            if ($::opt_T) {
                $ip .= ",mp,bmc";
            }
            if ($mtm and $serial) {
                $node = "node-$mtm-$serial";
                $node =~ s/(.*)/\L$1/g;
            }
        } elsif ($output =~ /error : unauthorized name/){
            xCAT::MsgUtils->message("E", {data=>["BMC username is incorrect for $ip"]}, $::CALLBACK);
            return 1;
        } elsif ($output =~ /RAKP \S* \S* is invalid/) {
            xCAT::MsgUtils->message("E", {data=>["BMC password is incorrect for $ip"]}, $::CALLBACK);
            return 1;
        } 
        if ( defined($opz) || defined($opw) )
        {
            format_stanza($node, $ip);
            if (defined($opw))
            {
                write_to_xcatdb($node, $ip,$request_command);
            }
        }
        else{
            my $rsp = {};
            push @{ $rsp->{data} }, "$ip";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }
}

1;
