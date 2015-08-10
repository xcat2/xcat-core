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
    push @{ $rsp->{data} },
      "\nUsage: bmcdiscover - discover bmc using scan method,now scan_method can be nmap .\n";
    push @{ $rsp->{data} },
      "\n                   - check if BMC username or password is correct or not .\n";
    push @{ $rsp->{data} },
      "\n                   - get BMC IP Address source, DHCP Address or static Address  .\n";
    push @{ $rsp->{data} }, "\tbmcdiscover [-h|--help|-?]\n";
    push @{ $rsp->{data} }, "\tbmcdiscover [-v|--version]\n ";
    push @{ $rsp->{data} }, "\tbmcdiscover [-s] scan_method [--range] ip_range [-z] [-w] \n ";
    push @{ $rsp->{data} }, "\tbmcdiscover [-i|--bmcip] bmc_ip [-u|--bmcuser] bmcusername [-p|--bmcpwd] bmcpassword [-c|--check]\n ";
    push @{ $rsp->{data} }, "\tbmcdiscover [-i|--bmcip] bmc_ip [-u|--bmcuser] bmcusername [-p|--bmcpwd] bmcpassword [--ipsource]\n ";
    push @{ $rsp->{data} }, "\tFor example: \n ";
    push @{ $rsp->{data} }, "\t1, bmcdiscover -s nmap --range \"10.4.23.100-254 50.3.15.1-2\" \n ";
    push @{ $rsp->{data} }, "\t   Note : ip_range should be a string, can pass hostnames, IP addresses, networks, etc. \n ";
    push @{ $rsp->{data} }, "\t   If there is bmc,bmcdiscover returns bmc ip or hostname, or else, it returns null. \n ";
    push @{ $rsp->{data} }, "\t   Ex: scanme.nmap.org, microsoft.com/24, 192.168.0.1; 10.0.0-255.1-254 \n ";
    push @{ $rsp->{data} }, "\t2, bmcdiscover -s nmap --range \"10.4.23.100-254 50.3.15.1-2\" -z \n ";
    push @{ $rsp->{data} }, "\t3, bmcdiscover -s nmap --range \"10.4.23.100-254 50.3.15.1-2\" -w \n ";
    push @{ $rsp->{data} }, "\t4, bmcdiscover -i <bmc_ip> -u <bmcusername> -p <bmcpassword> -c\n ";
    push @{ $rsp->{data} }, "\t   Note : check if bmc username and password are correct or not. \n";
    push @{ $rsp->{data} }, "\t5, bmcdiscover -i <bmc_ip> -u <bmcusername> -p <bmcpassword> --ipsource\n ";

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
                              'range=s' => \$::opt_R,
                              'bmcip|i=s' => \$::opt_I,
                              'z' => \$::opt_Z,
                              'w' => \$::opt_W,
                              'check|c' => \$::opt_C,
                              'bmcuser|u=s' => \$::opt_U,
                              'bmcpwd|p=s' => \$::opt_P,
                              'ipsource' => \$::opt_S,
                              'version|v' => \$::opt_v,
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

    #########################################
    # Option -i -u -p -c should be used together
    ######################################

    if ( defined($::opt_C) )
    {
        if ( defined($::opt_P) && defined($::opt_I) )
        {
             if ( defined($::opt_U) )
             {
                 my $res=check_auth_process($::opt_I,$::opt_U,$::opt_P);
                 return $res;
             }
             else
             {
                 my $res=check_auth_process($::opt_I,"none",$::opt_P);
                 return $res;

             }
        }
        else
        {
             my $msg = "bmc_ip or bmcuser or bmcpw is empty.";
             my $rsp = {};
             push @{ $rsp->{data} }, "$msg";
             xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
             return 2;
        }
    }
        #########################################
        # Option -i -u -p -s should be used together
        ######################################
    if ( defined($::opt_S) )
    {
        if ( defined($::opt_P) && defined($::opt_I) )
        {
             if ( defined($::opt_U))
             {
                my $res=get_bmc_ip_source($::opt_I,$::opt_U,$::opt_P);
                return $res;
             }
             else
             {
                my $res=get_bmc_ip_source($::opt_I,"none",$::opt_P);
                return $res;
             }
        }
        else
        {
             my $msg = "Can not get BMC IP Address source.";
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
    my $bmcerror = "Can not find IP Address Source.";
    my $ipsource_t = "IP Address Source";
    my $pcmd;

    if ( $bmcuser eq "none" )
    {
       $pcmd = "/opt/xcat/bin/ipmitool-xcat -I lanplus -P $bmcpw -H $bmcip lan print ";
    }
    else
    {
       $pcmd = "/opt/xcat/bin/ipmitool-xcat -I lanplus -U $bmcuser -P $bmcpw -H $bmcip lan print ";

    }
    my $output = xCAT::Utils->runcmd("$pcmd", -1);
    if ( $output !~ $ipsource_t )
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "$bmcerror";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
    else
    {
        my $rsp = {};
        my $ipsource=`echo "$output"|grep "IP Address Source"|awk -F":" '{print \$2}'`;
        chomp($ipsource); 
        push @{ $rsp->{data} }, "$ipsource";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    
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
    my $bmstr1 = "RAKP 2 message indicates an error : unauthorized name";
    my $bmstr2 = "RAKP 2 HMAC is invalid";
    my $bmstr3 = "Set Session Privilege Level to ADMINISTRATOR";
    my $bmstr31 = "Correct ADMINISTRATOR";
    my $bmstr21 = "Wrong bmc password";
    my $bmstr11 = "Wrong bmc user";
    my $bmcerror = "Not bmc";
    my $othererror = "Check bmc first";
    my $bmstr4 = "BMC Session ID";
     
    my $callback = $::CALLBACK;
    my $icmd;
    if ( $bmcuser eq "none" )
    {
       $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -P $bmcpw -H $bmcip chassis status ";
    }
    else
    { 
       $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -U $bmcuser -P $bmcpw -H $bmcip chassis status ";
    }
    my $output = xCAT::Utils->runcmd("$icmd", -1);
    if ( $output =~ $bmstr1 )
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "$bmstr11";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
    elsif ( $output =~ $bmstr2 )
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "$bmstr21";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
    elsif ( $output =~ $bmstr3 )
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "$bmstr31";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;

    }
    elsif ( $output !~ $bmstr4 )
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "$bmcerror";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }
    else
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "$othererror";
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
        my $bcmd = join(" ",$nmap_path," -sn -n $range | grep for |cut -d ' ' -f5 |tr -s '\n' ' ' ");
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
   
    if (defined($live_ip)){
  
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
    my $bmcip = shift;
    my $host = "node$bmcip";
       $host =~ s/\.//g;
    my $result;
    if (defined($bmcip)){     
        $result .= "$host:\n\tobjtype=node\n";
        $result .= "\tgroups=all\n";
        $result .= "\tbmc=$bmcip\n";
        $result .= "\tcons=ipmi\n";
        $result .= "\tmgt=ipmi\n";
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
    my $bmcip = shift;
    my $request_command = shift;
    my $ret;
    my $host = "node$bmcip";
       $host =~ s/\.//g;

       $ret = xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','node','-o',$host,"bmc=$bmcip","cons=ipmi","mgt=ipmi","groups=all"] }, $request_command, 0, 1);
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
    my $bmcstr = "BMC Session ID";
    my $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -U USERID -P PASSW0RD -H $ip chassis status ";
    my $output = xCAT::Utils->runcmd("$icmd", -1);
    if ( $output =~ $bmcstr ){
       if ( defined($opz) || defined($opw) )
       {
          format_stanza($ip);
          if (defined($opw))
          {
              write_to_xcatdb($ip,$request_command);
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
