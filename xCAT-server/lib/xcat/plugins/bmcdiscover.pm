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
use LWP;
use HTTP::Cookies;
use HTTP::Response;
use JSON;

my $log_label = "bmcdiscover:";
my $nmap_path;
my %ipmac = ();

my $debianflag = 0;
my $tempstring = xCAT::Utils->osver();
if ($tempstring =~ /debian/ || $tempstring =~ /ubuntu/) {
    $debianflag = 1;
}
my $parent_fd;
my $bmc_user;
my $bmc_pass;
my $openbmc_user;
my $openbmc_pass;
my $done_num = 0;
$::P9_AC922_MFG_ID     = "42817"; #Witherspoon
$::P9_AC922_PRODUCT_ID = "16975";
$::P9_IC922_MFG_ID     = "42817"; #Mihawk
$::P9_IC922_PRODUCT_ID = "1";
$::CHANGE_PW_REQUIRED="The password provided for this account must be changed before access is granted";
$::NO_SESSION="Unable to establish IPMI v2 / RMCP";
$::CHANGE_PW_INSTRUCTIONS_1="Rerun 'bmcdiscover' command with '-p default_bmc_password -n new_bmc_password' flag";
$::PW_PAM_VALIDATION="password value failed PAM validation checks";
$::NO_MFG_OR_PRODUCT_ID="Zeros returned for Manufacturer id and Product id";
%::VPDHASH = ();
my %node_in_list = ();

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
#
sub preprocess_request {
    my $request = shift;
    if (defined $request->{_xcatpreprocessed}->[0] and $request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }

    my $callback = shift;
    my $extargs = $request->{arg};
    my @exargs = ($request->{arg});
    if (ref($extargs)) {
        @exargs = @$extargs;
    }
    @ARGV = @exargs;
    $Getopt::Long::ignorecase=0;
    Getopt::Long::Configure("bundling");
    my $sns = undef;
    if ((grep /--sn/, @ARGV) and (Getopt::Long::GetOptions('sn=s' => \$sns))) {
        unless ($sns) {
            $callback->({ error => ["The value for --sn is invalid"], errorcode => [1] });
            $request = ();
            return;
        }
        my $nettab = xCAT::Table->new("networks");
        my @entries   = $nettab->getAllAttribs('dhcpserver', 'dynamicrange');
        my @dhcpservers = ();
        foreach (@entries) {
            if (!defined($_->{dynamicrange})) {next;}
            push @dhcpservers, $_->{dhcpserver};
        }
        my @requests = ();
        foreach (split (/,/, $sns)) {
            my $reqcopy = {%$request};
            $reqcopy->{'_xcatdest'} = $_;
            $reqcopy->{'sn'} = $_;
            $reqcopy->{'dhcpservers'} = \@dhcpservers;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;
        }
        return \@requests;
    } elsif (grep /--check/, @ARGV) {
        $callback->({ error => ["The option '--check' is not supported"], errorcode=>[1]});
        $request = ();
        return;
    } elsif (grep /--ipsource/, @ARGV) {
        $callback->({ error => ["The option '--ipsource' is not supported"], errorcode=>[1]});
        $request = ();
        return;
    } else {
        return [$request];
    }
}

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request         = shift;
    my $callback        = shift;
    my $request_command = shift;
    $::CALLBACK = $callback;

    if ($request->{sn}) {
        my $dhcpservers = $request->{dhcpservers};
        if (!defined($dhcpservers) or ref($dhcpservers) ne 'ARRAY') {
            $callback->({ error => ["the ". $request->{command}->[0]. " doesn't work when no dynamic range set."], errorcode => [1] });
            return 1;
        }
        else {
            my $have_dynamicrange_set = 0;
            foreach (@$dhcpservers) {
                unless (xCAT::NetworkUtils->thishostisnot($_)) {
                    $have_dynamicrange_set = 1;
                    last;
                }
            }
            unless ($have_dynamicrange_set) {
                $callback->({ error => ["the ". $request->{command}->[0]. " won't work since no dynamic range set on $request->{sn}->[0]"], errorcode => [1] });
                return 1;
            }
        }
    }
    unless (defined($request->{arg})) {
        bmcdiscovery_usage();
        return 2;
    }
    @ARGV = @{ $request->{arg} };
    if ($#ARGV == -1) {
        return 2;
    }


    my $command = $request->{command}->[0];
    my $rc;

    if ($command eq "bmcdiscover") {
        $rc = bmcdiscovery($request, $callback, $request_command);
    } else {
        $callback->({ error => ["Error: $command not found in this module."], errorcode => [1] });
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
    push @{ $rsp->{data} }, "\tbmcdiscover --range ip_range <ip_range> [--sn <SN_nodename>] [-s <scan_method>] [-u <bmc_user>] [-p <bmc_passwd>] [-n <new_bmc_passwd>] [-z] [-w]\n";

    xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
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
    my $request         = shift;
    my $callback        = shift;
    my $request_command = shift;

    my $rc = 0;


    # parse the options
    # options can be bundled up like -v, flag unsupported options
    Getopt::Long::Configure("bundling", "no_ignore_case", "no_pass_through");
    my $getopt_success = Getopt::Long::GetOptions(
        'help|h|?'      => \$::opt_h,
        's=s'           => \$::opt_M,
        'm=s'           => \$::opt_M,
        'range=s'       => \$::opt_R,
        'bmcip|i=s'     => \$::opt_I,
        'z'             => \$::opt_Z,
        'w'             => \$::opt_W,
        'check'         => \$::opt_C,
        'bmcuser|u=s'   => \$::opt_U,
        'bmcpasswd|p=s' => \$::opt_P,
        'newbmcpw|n=s'  => \$::opt_N,
        'ipsource'      => \$::opt_S,
        'version|v'     => \$::opt_v,
        't'             => \$::opt_T,
        'sn=s'          => \$::opt_SN,
    );

    if (!$getopt_success) {
        return 3;
    }


    #########################################
    # This command is for linux
    #########################################
    if ($^O ne 'linux') {
        my $rsp = {};
        push @{ $rsp->{data} }, "The bmcdiscovery command is only supported on Linux.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    ##########################################
    # Option -h for Help
    ##########################################
    if (defined($::opt_h)) {
        bmcdiscovery_usage;
        return 0;
    }

    #########################################
    # Option -v for version
    #########################################
    if (defined($::opt_v)) {
        create_version_response('bmcdiscover');

        # no usage - just exit
        return 1;
    }

    ############################################
    # Option -U and -P for bmc user and password
    #
    # Get the default bmc account from passwd table,
    # this is only done for the discovery process
    ############################################
    ($bmc_user, $bmc_pass, $openbmc_user, $openbmc_pass) = bmcaccount_from_passwd();
    # overwrite the default user and password if one is provided
    if ($::opt_U) {
        $bmc_user = $::opt_U;
        $openbmc_user = $::opt_U;
    } elsif ($::opt_P) {
        # If password is provided, but no user, set the user to blank
        # Support older FSP and Tuletta machines
        $bmc_user = '';
    }
    if ($::opt_P) {
        $bmc_pass = $::opt_P;
        $openbmc_pass = $::opt_P;
    }
    if ($request->{sn}) {
        $::opt_SN = $request->{sn}->[0];
    } else {
        $::opt_SN = '';
    }

    #########################################
    # Option -s -r should be together
    ######################################
    if (defined($::opt_R))
    {
        # Option -c should not be used with -r
        if (defined($::opt_C)) {
            my $msg = "The 'check' and 'range' option cannot be used together.";
            my $rsp = {};
            push @{ $rsp->{data} }, "$msg";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 2;
        }
        ######################################
        # check if there is nmap or not
        ######################################
        if (-x '/usr/bin/nmap') {
            $nmap_path = "/usr/bin/nmap";
        }
        elsif (-x '/usr/local/bin/nmap') {
            $nmap_path = "/usr/local/bin/nmap";
        }
        else {
            my $rsp;
            push @{ $rsp->{data} }, "\tThere is no nmap in /usr/bin/ or /usr/local/bin/. \n ";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 1;
        }

        ######################################
        # check if there is ipmitool-xcat or not
        ######################################
        unless (-x '/opt/xcat/bin/ipmitool-xcat') {
            my $rsp;
            push @{ $rsp->{data} }, "\tThere is no ipmitool-xcat in /opt/xcat/bin/, make sure that package ipmitool-xcat is installed successfully.\n ";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 1;
        }

        if ($::opt_T) {
            my $msg = "The -t option is deprecated and will be ignored";
            my $rsp = {};
            push @{ $rsp->{data} }, "$msg";
            xCAT::MsgUtils->message("W", $rsp, $::CALLBACK);
        }

        scan_process($::opt_M, $::opt_R, $::opt_Z, $::opt_W, $request_command);
        return 0;
    }

    if (defined($::opt_C) && defined($::opt_S)) {
        my $msg = "The 'check' and 'ipsource' option cannot be used together.";
        my $rsp = {};
        push @{ $rsp->{data} }, "$msg";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }

    #########################################################
    # --check option, requires -i, -u, and -p to be specified
    #########################################################
    if (defined($::opt_C)) {
        if (defined($::opt_P) && defined($::opt_U) && defined($::opt_I)) {
            my $res = check_auth_process($::opt_I, $::opt_U, $::opt_P);
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
    if (defined($::opt_S)) {
        if (defined($bmc_pass) && defined($::opt_I)) {
            my $res = get_bmc_ip_source($::opt_I, $bmc_user, $bmc_pass);
            return $res;
        }
        else {
            my $msg = "";
            if (!defined($::opt_I)) {
                $msg = "The ipsource option requires a BMC IP.  Specify the IP using the -i|--bmcip option.";
            } elsif (!defined($::opt_P)) {
                $msg = "The ipsource option requires a password.  Specify the password with the -p|--bmcpasswd option.";
            } else {
                $msg = "Failed to process ipsource command for bmc ip=$::opt_I user=$bmc_user password=$bmc_pass";
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

my $bmc_str1  = "RAKP 2 message indicates an error : unauthorized name";
my $bmc_resp1 = "Wrong BMC username";

my $bmc_str2  = "RAKP 2 HMAC is invalid";
my $bmc_resp2 = "Wrong BMC password";

#----------------------------------------------------------------------------

=head3   get_bmc_ip_source

        get bmc ip address source
        Returns:
                0 - OK
                2 - Error
=cut

#-----------------------------------------------------------------------------

sub get_bmc_ip_source {
    my $bmcip    = shift;
    my $bmcuser  = shift;
    my $bmcpw    = shift;
    my $callback = $::CALLBACK;
    my $pcmd;

    if ($bmcuser eq "none") {
        $pcmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -P $bmcpw -H $bmcip lan print ";
    }
    else {
        $pcmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -U $bmcuser -P $bmcpw -H $bmcip lan print ";
    }

    my $output = xCAT::Utils->runcmd("$pcmd", -1);

    if ($output =~ "IP Address Source") {
        # success case
        my $rsp      = {};
        my $ipsource = `echo "$output"|grep "IP Address Source"`;
        chomp($ipsource);
        push @{ $rsp->{data} }, "$ipsource";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }
    else {
        my $rsp = {};
        if ($output =~ $bmc_str1) {
            # Error: RAKP 2 message indicates an error : unauthorized name <== incorrect username
            push @{ $rsp->{data} }, "$bmc_resp1";
        } elsif ($output =~ $bmc_str2) {
            # Error: RAKP 2 HMAC is invalid <== incorrect password
            push @{ $rsp->{data} }, "$bmc_resp2";
        } else {
            my $error_msg = `echo "$output"|grep "Error" `;
            if ($error_msg eq ""){
                $error_msg = "Can not find IP address Source";
            }
            # all other errors
            push @{ $rsp->{data} }, "$error_msg";
        }
        xCAT::MsgUtils->message("W", $rsp, $::CALLBACK);
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

sub check_auth_process {
    my $bmcip    = shift;
    my $bmcuser  = shift;
    my $bmcpw    = shift;
    my $bmc_str4 = "BMC Session ID";

    my $callback = $::CALLBACK;
    my $icmd;
    if ($bmcuser eq "none") {
        $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -P $bmcpw -H $bmcip chassis status ";
    }
    else {
        $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus -U $bmcuser -P $bmcpw -H $bmcip chassis status ";
    }
    my $output = xCAT::Utils->runcmd("$icmd", -1);

    if ($output =~ "Set Session Privilege Level to ADMINISTRATOR") {

        # Success case
        my $rsp = {};
        push @{ $rsp->{data} }, "Correct ADMINISTRATOR";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    } else {

        # handle the various error scenarios
        my $rsp = {};

        if ($output =~ $bmc_str1) {

            # Error: RAKP 2 message indicates an error : unauthorized name <== incorrect username
            push @{ $rsp->{data} }, "$bmc_resp1";
        }
        elsif ($output =~ $bmc_str2) {

            # Error: RAKP 2 HMAC is invalid <== incorrect password
            push @{ $rsp->{data} }, "$bmc_resp2";
        }
        elsif ($output !~ $bmc_str4) {

            # Did not find "BMC Session ID" in the response
            push @{ $rsp->{data} }, "Not a BMC, please verify the correct IP address";
        }
        else {
            push @{ $rsp->{data} }, "Unknown Error: $output";
        }
        xCAT::MsgUtils->message("W", $rsp, $::CALLBACK);
        return 2;
    }
}

sub buildup_mtms_hash {
    xCAT::MsgUtils->trace(0, "I", "Establish hash for vpd table with key=mtm*serial, value=node");
    my %nodehash = ();
    if (my $vpdtab = xCAT::Table->new("vpd")) {
        my @entries = $vpdtab->getAllAttribs(qw/node serial mtm/);
        foreach (@entries) {
            unless ($_->{mtm} and $_->{serial}) { next; }
            my $mtms = lc($_->{mtm}) . "*" . lc($_->{serial});
            $nodehash{$_->{node}} = $mtms; 
        }
    }
    my @nodes = keys %nodehash;
    foreach my $tab (qw/ipmi openbmc/) {
        my $tabfd = xCAT::Table->new($tab);
        my $entries = $tabfd->getNodesAttribs(\@nodes,qw/bmc/);
        foreach my $node (@nodes) {
            my $bmc = $entries->{$node}->[0]->{bmc};
            unless($bmc) { next; }
            if (exists($nodehash{$node})) {
                my $mtmsip = $nodehash{$node}."-".$bmc;
                $nodehash{$node} = $mtmsip;
            }
        }
    }
    my @tmp_bmc_nodes = ();
    foreach my $node (keys %nodehash) {
        my $mtmsip = $nodehash{$node};
        if (exists($::VPDHASH{$mtmsip})) {
            my $tmp_node = $::VPDHASH{$mtmsip};
            if ($tmp_node =~ /node-.+/) {
                push @tmp_bmc_nodes, $tmp_node;
            } elsif ($node =~ /node-.+/) {
                $::VPDHASH{$mtmsip} = $node;
                push @tmp_bmc_nodes, $node;
            } else {
                xCAT::MsgUtils->message("W", { data => ["Node $node and $tmp_node have the same mtms-ip keys: $mtmsip"] }, $::CALLBACK);
            }
            next;
        }
        $::VPDHASH{$mtmsip} = $node;
    }
    if ($#tmp_bmc_nodes > 0) {
        my $useless_nodes = join(',', @tmp_bmc_nodes);
        xCAT::MsgUtils->message("W", { data => ["The nodes: $useless_nodes have normal nodes defined, please remove them"] }, $::CALLBACK);
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

sub scan_process {

    my $method          = shift;
    my $range           = shift;
    my $opz             = shift;
    my $opw             = shift;
    my $request_command = shift;
    my $callback        = $::CALLBACK;
    my $children;       # The number of child process
    my %sp_children;    # Record the pid of child process
    my $bcmd;


    if (!defined($method))
    {
        $method = "nmap";
    }

    # Handle commas in $range for nmap
    $range =~ tr/,/ /;

    ############################################################
    # get live ip list
    ###########################################################
    if ($method ne "nmap") {
        my $rsp = {};
        push @{ $rsp->{data} }, "The bmcdiscover method should be nmap.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }

    #check nmap version first
    my $nmap_version = xCAT::Utils->get_nmapversion();
    my $ip_info_list;

    #  the output of nmap is different for version under 5.10
    if (xCAT::Utils->version_cmp($nmap_version, "5.10") < 0) {
        $bcmd = join(" ", $nmap_path, " -sP -n $range");
    } else {
        $bcmd = join(" ", $nmap_path, " -sn -n $range");
    }

    xCAT::MsgUtils->trace(0, "I", "$log_label Try to scan live IPs with command $bcmd ...");
    $ip_info_list = xCAT::Utils->runcmd("$bcmd", -1);
    if ($::RUNCMD_RC != 0) {
        my $rsp = {};
        push @{ $rsp->{data} }, "Nmap scan has failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;
    }

    my $ip_list;
    my $mac_list;
    if (xCAT::Utils->version_cmp($nmap_version, "5.10") < 0) {
        $ip_list  = `echo -e "$ip_info_list" | grep \"appears to be up\" |cut -d ' ' -f2 |tr -s '\n' ' '`;
        $mac_list = `echo -e "$ip_info_list" | grep -A1 up | grep "MAC Address" | cut -d ' ' -f3 | tr -s '\n' ' '`;
    } else {
        $ip_list  = `echo -e "$ip_info_list" | grep -B1 up | grep "Nmap scan report" |cut -d ' ' -f5 | tr -s '\n' ' '`;
        $mac_list = `echo -e "$ip_info_list" | grep -A1 up | grep "MAC Address" | cut -d ' ' -f3 | tr -s '\n' ' '`;
    }

    my $live_ip  = split_comma_delim_str($ip_list);
    my $live_mac = split_comma_delim_str($mac_list);
    my %pipe_map;
    if (scalar(@{$live_ip}) > 0) {
        
        xCAT::MsgUtils->trace(0, "I", "$log_label Scanned " . scalar(@{$live_ip}) . " live IPs with " . scalar(@{$live_mac}) . " MACs");
        foreach (@{$live_ip}) {
            my $new_mac = lc(shift @{$live_mac});
            $new_mac =~ s/\://g;
            $ipmac{$_} = $new_mac;
        }

        my $nodelisttab;
        if ($nodelisttab = xCAT::Table->new("nodelist")) {
            my @nodes_in_list = $nodelisttab->getAllAttribs("node");
            foreach my $node (@nodes_in_list) {
                $node_in_list{$node->{node}} = 1;
            }
        } else {
            xCAT::MsgUtils->message("E", " Could not read the nodelist table\n");
            return 1;
        }

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
            alarm(1);    # wait 1s for grace exit
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
                    forward_data($callback, $pipe_map{$cpid});
                    close($pipe_map{$cpid});
                    delete $pipe_map{$cpid};
                }
            }
        };
        buildup_mtms_hash();
        for (my $i = 0 ; $i < scalar(@{$live_ip}) ; $i++) {

            # fork a sub process to handle the communication with service processor
            $children++;
            my $cfd;

            # the $parent_fd will be used by &send_rep() to send response from child process to parent process
            socketpair($parent_fd, $cfd, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die "socketpair: $!";
            $cfd->autoflush(1);
            $parent_fd->autoflush(1);
            my $child = xCAT::Utils->xfork;
            if ($child == 0) {
                close($cfd);
                $callback = \&send_rep;

                # Set child process default, if not the function runcmd may return error
                $SIG{CHLD} = 'DEFAULT';

TRY_TO_DISCOVER:
                my $bmcusername;
                my $bmcpassword;
                $bmcusername = "-U $bmc_user" if ($bmc_user);
                $bmcpassword = "-P $bmc_pass" if ($bmc_pass);

                my @mc_cmds = ("/opt/xcat/bin/ipmitool-xcat -I lanplus -H ${$live_ip}[$i] -P $openbmc_pass mc info -N 1 -R 1",
                               "/opt/xcat/bin/ipmitool-xcat -I lanplus -H ${$live_ip}[$i] -U $openbmc_user -P $openbmc_pass mc info -N 1 -R 1",
                               "/opt/xcat/bin/ipmitool-xcat -I lanplus -H ${$live_ip}[$i] $bmcusername $bmcpassword mc info -N 1 -R 1");
                my $mc_info;
                my $is_openbmc = 0;
                my $is_ipmi = 0;
                foreach my $mc_cmd (@mc_cmds) {
                    $mc_info = xCAT::Utils->runcmd($mc_cmd, -1);
                    if ($::RUNCMD_RC != 0) {
                        next;
                    }
                    if ($mc_info =~ /Manufacturer ID\s*:\s*(\d+)\s*Manufacturer Name.+\s*Product ID\s*:\s*(\d+)/) {
                        xCAT::MsgUtils->trace(0, "D", "$log_label Found ${$live_ip}[$i] Manufacturer ID: $1 Product ID: $2");
                        if (($1 eq $::P9_AC922_MFG_ID and $2 eq $::P9_AC922_PRODUCT_ID) or 
                            ($1 eq $::P9_IC922_MFG_ID and $2 eq $::P9_IC922_PRODUCT_ID)) {
                            bmcdiscovery_openbmc(${$live_ip}[$i], $opz, $opw, $request_command,$parent_fd,$2);
                            $is_openbmc = 1;
                            $is_ipmi = 0;
                            last;
                        }
                        elsif ($1 eq "0" and $2 eq "0") {
                            # Got zeros for MFG and PRODUCT ID, not sure if openbmc or ipmi. Print message and move on.
                            xCAT::MsgUtils->message("W", { data => ["${$live_ip}[$i]: $::NO_MFG_OR_PRODUCT_ID"] }, $::CALLBACK);
                            last;
                        }
                        else {
                            # System replied to mc info but not with either 
                            # $::P9_AC922_MFG_ID and $::P9_AC922_PRODUCT_ID, or
                            # $::P9_IC922_MFG_ID and $::P9_IC922_PRODUCT_ID,
                            # assume IPMI
                            $is_openbmc = 0;
                            $is_ipmi = 1;
                            last;
                        }
                    }
                }

                if ($is_ipmi) {
                    bmcdiscovery_ipmi(${$live_ip}[$i], $opz, $opw, $request_command,$parent_fd);
                }
                if (!$is_openbmc and !$is_ipmi) {
                    if ($mc_info =~ /$::NO_SESSION/) {
                        # Did not get usefull data from ipmi mc info, could be one of two possibilities:
                        # 1. Incorrect pw was used
                        # 2. New system installed after January 1, 2020 where default password needs to be changed
                        #
                        # Verify this is case 2, by attempting to establish a RedFish session
                        my $redfish_session_cmd = "curl -sD - --data '{\"UserName\":\"$openbmc_user\",\"Password\":\"$openbmc_pass\"}' -k -X POST https://${$live_ip}[$i]/redfish/v1/SessionService/Sessions";
                        my $redfish_session_info = xCAT::Utils->runcmd($redfish_session_cmd, -1);
                        if ($redfish_session_info =~ /$::CHANGE_PW_REQUIRED/) {
                            # RedFish session replied that password change is needed.
                            xCAT::MsgUtils->message("I", { data => ["${$live_ip}[$i]: $::CHANGE_PW_REQUIRED"] }, $::CALLBACK);
                            if ($::opt_N) {
                                # New password was passed in, use it to change the default (AC922 or IC922)
                                my $password_change_cmd = "curl -s -u $openbmc_user:$openbmc_pass --data '{\"Password\":\"$::opt_N\"}' -k -X PATCH https://${$live_ip}[$i]/redfish/v1/AccountService/Accounts/$openbmc_user";
                                my $password_changed = xCAT::Utils->runcmd($password_change_cmd, -1);
                                if (! $password_changed) {
                                    # No output from change password command, assume success
                                    xCAT::MsgUtils->message("I", { data => ["${$live_ip}[$i]: Password changed."] }, $::CALLBACK);
                                    $openbmc_pass = $::opt_N; # Set new password
                                    $bmc_pass = $::opt_N;     # Set new password
                                    goto TRY_TO_DISCOVER;     # Attempt discover with changed password
                                }
                                elsif ($password_changed =~ /$::PW_PAM_VALIDATION/) {
                                    # Output from change password command indicates pw validation error
                                    xCAT::MsgUtils->message("I", { data => ["Can not change password - $::PW_PAM_VALIDATION"] }, $::CALLBACK);
                                }
                                else {
                                    # Some unexpected output changing the password - report error and show output
                                    xCAT::MsgUtils->message("I", { data => ["Unable to change password - $password_changed"] }, $::CALLBACK);
                                }
                            }
                            else {
                                # New password was not passed in, print instruction message and exit
                                xCAT::MsgUtils->message("I", { data => ["$::CHANGE_PW_INSTRUCTIONS_1"] }, $::CALLBACK);
                            }
                        }
                    }
                }
                close($parent_fd);
                exit 0;
            } else {

                # in the main process, record the created child process and add parent fd for the child process to an IO:Select object
                # the main process will check all the parent fd and receive response
                $sp_children{$child} = 1;
                close($parent_fd);
                $pipe_map{$child} = $cfd;
            }

            while ($children >= 32) {
                sleep(1);
            }
        }
        while($children > 0) {
            sleep(1);
        }
        unless ($done_num) {
            my %rsp;
            $rsp{data} = ["No bmc found.\n"];
            xCAT::MsgUtils->message("W", \%rsp, $::CALLBACK);
        }

    }
    else
    {
        my $rsp = {};
        push @{ $rsp->{data} }, "No bmc found.\n";
        xCAT::MsgUtils->message("W", $rsp, $::CALLBACK);
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
    my $mgt_type = shift;
    my ($bmcip, $bmcmtm, $bmcserial, $bmcuser, $bmcpass, $nodetype, $hwtype, $mac, $sn, $conserver) = split(/,/, $data);
    my $result;
    if (defined($bmcip)) {
        $result .= "$node:\n\tobjtype=node\n";
        $result .= "\tgroups=all\n";
        $result .= "\tbmc=$bmcip\n";
        $result .= "\tcons=$mgt_type\n";
        $result .= "\tmgt=$mgt_type\n";
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
        if ($sn) {
            $result .="\tservicenode=$sn\n";
        }
        if ($conserver) {
            $result .= "\tconserver=$conserver\n";
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
    my $mgt_type = shift;
    my ($bmcip, $bmcmtm, $bmcserial, $bmcuser, $bmcpass, $nodetype, $hwtype, $mac, $sn, $conserver) = split(/,/, $data);
    my $request_command = shift;
    my $ret;

    $ret = xCAT::Utils->runxcmd({ command => ['chdef'],
                                  arg => [ '-t', 'node', '-o', $node, "bmc=$bmcip", "cons=$mgt_type",
                                           "mgt=$mgt_type", "mtm=$bmcmtm", "serial=$bmcserial",
                                           "bmcusername=$bmcuser", "bmcpassword=$bmcpass", "nodetype=$nodetype",
                                           "servicenode=$sn", "conserver=$conserver",
                                           "hwtype=$hwtype", "groups=all" ] },
                                  $request_command, -1, 1);
    if ($::RUNCMD_RC != 0) {
        my $rsp = {};
        push @{ $rsp->{data} }, "Failed to run chdef command for node=$node\n";
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
    my $resp = shift;
    unless ($resp) { return; }
    store_fd($resp, $parent_fd);
}

#----------------------------------------------------------------------------

=head3 forward_data

    DESCRIPTION:
        Receive data from forked child process and call the original $callback to forward data to xcat client

=cut

#----------------------------------------------------------------------------
sub forward_data {
    my $callback  = shift;
    my $cfd       = shift;
    my $responses;

    if (!($@ and $@ =~ /^Magic number checking on storable file/)) { #this most likely means we ran over the end of available input
        $callback->($responses);
    }
    eval {
        $responses = fd_retrieve($cfd);
        if ($responses->{data}) {
            $done_num += $responses->{data};
        }
    };
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
    xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
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
    xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
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

    my $request         = shift;
    my $callback        = shift;
    my $request_command = shift;

    my $rc = 0;

    ##############################################################
    # process the command line
    # 0=success, 1=version, 2=error for check_auth_, other=error
    ##############################################################
    $rc = bmcdiscovery_processargs($request, $callback, $request_command);
    if ($rc != 0) {
        if ($rc != 1)
        {
            if ($rc != 2)
            {
                bmcdiscovery_usage(@_);
            }
        }
        return ($rc - 1);
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
    my $openbmcusername = "root";
    my $openbmcpassword = "0penBmc";
    my $passwdtab   = xCAT::Table->new("passwd", -create => 0);
    if ($passwdtab) {
        my $bmcentry = $passwdtab->getAttribs({ 'key' => 'ipmi' }, 'username', 'password');
        if (defined($bmcentry)) {
            $bmcusername = $bmcentry->{'username'};
            $bmcpassword = $bmcentry->{'password'};

            # if username or password is undef or empty in passwd table, bmcusername or bmcpassword is empty
            unless ($bmcusername) {
                $bmcusername = '';
            }
            unless ($bmcpassword) {
                $bmcpassword = '';
            }
        }

        my $openbmcentry = $passwdtab->getAttribs({ 'key' => 'openbmc' }, 'username', 'password');
        if (defined($openbmcentry)) {
            $openbmcusername = $openbmcentry->{'username'};
            $openbmcpassword = $openbmcentry->{'password'};
            # if username or password is undef or empty in passwd table, openbmcusername or openbmcpassword is empty
            unless ($openbmcusername) {
                $openbmcusername = '';
            }
            unless ($openbmcpassword) {
                $openbmcpassword = '';
            }
        }
    }
    return ($bmcusername, $bmcpassword, $openbmcusername, $openbmcpassword);
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
    my $ip              = shift;
    my $opz             = shift;
    my $opw             = shift;
    my $request_command = shift;
    my $fd              = shift;
    my $bmcstr          = "BMC Session ID";
    my $bmcusername     = '';
    my $bmcpassword     = '';
    if ($bmc_user) {
        $bmcusername = "-U $bmc_user";
    }
    if ($bmc_pass) {
        $bmcpassword = "-P $bmc_pass";
    }

    my $log_info = "$ip: Detected ipmi, attempting to obtain system information...";
    xCAT::MsgUtils->trace(0, "D", "$log_label $log_info");

    my $mtms_node = "";
    my $mac_node = "";

    my $node_data = $ip;
    my $icmd = "/opt/xcat/bin/ipmitool-xcat -vv -I lanplus $bmcusername $bmcpassword -H $ip chassis status -R 1";
    my $output = xCAT::Utils->runcmd("$icmd", -1);
    if ($output =~ $bmcstr) {
        store_fd({data=>1}, $fd);

        if ($output =~ /RAKP \d+ message indicates an error : (.+)\nError: (.+)/) {
            xCAT::MsgUtils->message("W", { data => ["$2: $1 for $ip"] }, $::CALLBACK);
            return;
        }

        # The output contains System Power indicated the username/password is correct, then try to get MTMS
        if ($output =~ /System Power\s*:\s*\S*/) {
            my $mtm    = '';
            my $serial = '';

            # For system X and Tuleta, the fru 0 will contain the MTMS; For firestone, fru 3; For habanero, fru 2
            my @fru_num = (0, 2, 3);
            foreach my $fru_cmd_num (@fru_num) {
                my $fru_cmd = "$::XCATROOT/bin/ipmitool-xcat -I lanplus $bmcusername $bmcpassword " .
                  "\-H $ip fru print $fru_cmd_num";
                my @fru_output_array = xCAT::Utils->runcmd($fru_cmd, -1);
                if (($::RUNCMD_RC eq 0) && @fru_output_array) {
                    my $fru_output = join(" ", @fru_output_array);

                    if (($fru_output =~ /Chassis Part Number\s*:\s*(\S*).*Chassis Serial\s*:\s*(\S*)/)) {
                        $mtm    = $1;
                        $serial = $2;
                        last;
                    }

                    if (($fru_output =~ /Product Part Number   :\s*(\S*).*Product Serial        :\s*(\S*)/)) {
                        $mtm    = $1;
                        $serial = $2;
                        last;
                    }

                    if (($fru_output =~ /Product Manufacturer\s+:\s+(.*?)\s+P.*?roduct Name\s+:\s+(.*?)\s+P.*?roduct Serial\s+:\s+(\S+)/)) {
                        $mtm    = $1.":".$2;
                        $serial = $3;
                        last;
                    }

                }
            }

            $mtm = '' if ($mtm =~ /^0+$/);
            $serial = '' if ($serial =~ /^0+$/);

            # To constract a node name need either mac or both mtm and serial
            # Exit if mac AND one of mtm or serial is missing
            if (!($mtm and $serial) and !$ipmac{$ip}) {
                xCAT::MsgUtils->message("W", { data => ["BMC Type/Model and Serial or MAC Address is unavailable for $ip"] }, $::CALLBACK);
                return;
            }

            $node_data .= ",$mtm";
            $node_data .= ",$serial";
            if ($::opt_P) {
                if ($::opt_U) {
                    $node_data .= ",$::opt_U,$::opt_P";
                } else {
                    $node_data .= ",,$::opt_P";
                }
            } else {
                $node_data .= ",,";
            }
            $node_data .= ",mp,bmc";
            if ($mtm and $serial) {
                my $mtmsip = lc($mtm)."*".lc($serial)."-".$ip;
                if (exists($::VPDHASH{$mtmsip})) {
                    my $pre_node = $::VPDHASH{$mtmsip};
                    xCAT::MsgUtils->message("I", { data => ["Found matching node $pre_node with bmc ip address: $ip, rsetboot/rpower $pre_node to continue hardware discovery."] }, $::CALLBACK);
                    if ($opz) {
                        $node_data .= ",";
                        display_output($opz,undef,$pre_node,$mac_node,$node_data,"ipmi",$request_command);
                    }
                    return;
                }
                $mtms_node = "node-$mtm-$serial";
                $mtms_node =~ s/(.*)/\L$1/g;
                $mtms_node =~ s/[\s:\._]/-/g;
                $node_data .= ",";
            } elsif ($ipmac{$ip}) {
                $mac_node = "node-$ipmac{$ip}";
                $node_data .= ",$ipmac{$ip}";
            }
            $node_data .= ",$::opt_SN,$::opt_SN";
        } elsif ($output =~ /error : unauthorized name/) {
            xCAT::MsgUtils->message("W", { data => ["BMC username is incorrect for $ip"] }, $::CALLBACK);
            return;
        } elsif ($output =~ /RAKP \S* \S* is invalid/) {
            xCAT::MsgUtils->message("W", { data => ["BMC password is incorrect for $ip"] }, $::CALLBACK);
            return;
        } else {
            xCAT::MsgUtils->message("W", { data => ["Unknown error from $ip"] }, $::CALLBACK);
            return;
        }

        display_output($opz,$opw,$mtms_node,$mac_node,$node_data,"ipmi",$request_command);
    }
}

#-----------------------------------------------------------------------------

=head3  bmcdiscovery_openbmc

        Support for discovering bmc using openbmc
        Returns:
              if it is openbmc, it returns bmc ip or host;
              if it is not openbmc, it returns nothing;

=cut

#-----------------------------------------------------------------------------
sub bmcdiscovery_openbmc{
    my $ip              = shift;
    my $opz             = shift;
    my $opw             = shift;
    my $request_command = shift;
    my $fd              = shift;
    my $model_id        = shift;
    my $mtms_node       = "";
    my $mac_node        = "";

    store_fd({data=>1}, $fd);
    my $log_info = "$ip: Detected openbmc, attempting to obtain system information...";
    print "$log_info\n";
    xCAT::MsgUtils->trace(0, "D", "$log_label $log_info");

    my $http_protocol="https";
    my $openbmc_project_url = "xyz/openbmc_project";
    my $login_endpoint = "login";
    my $system_endpoint = "inventory/system";
    my $motherboard_boxelder_endpoint = "$system_endpoint/chassis/motherboard/boxelder/bmc";
    my $motherboard_bmc_endpoint = "$system_endpoint/chassis/motherboard/bmc";

    my $node_data = $ip;
    my $brower = LWP::UserAgent->new( ssl_opts => { SSL_verify_mode => 0x00, verify_hostname => 0  }, );
    my $cookie_jar = HTTP::Cookies->new();
    my $header = HTTP::Headers->new('Content-Type' => 'application/json');
    my $data = '{"data": [ "' . $openbmc_user .'", "' . $openbmc_pass . '" ] }';
    $brower->cookie_jar($cookie_jar);

    my $url = "$http_protocol://$ip/$login_endpoint";
    my $login_request = HTTP::Request->new( 'POST', $url, $header, $data );
    my $login_response = $brower->request($login_request);

    if ($login_response->is_success) {
        # attempt to find the system serial/model
        $url = "$http_protocol://$ip/$openbmc_project_url/$system_endpoint";
        my $req = HTTP::Request->new('GET', $url, $header);
        my $req_output = $brower->request($req);
        if ($req_output->is_error) {
            # If the host system has not yet been powered on, system_endpoint call will return error
            # Instead, check the boxelder (for AC922) or bmc (for IC922) info for model/serial
            if ($model_id eq $::P9_MIHAWK_PRODUCT_ID) {
                $url = "$http_protocol://$ip/$openbmc_project_url/$motherboard_bmc_endpoint";
            }
            else {
                $url = "$http_protocol://$ip/$openbmc_project_url/$motherboard_boxelder_endpoint";
            }
            $req = HTTP::Request->new('GET', $url, $header);
            $req_output = $brower->request($req);
            if ($req_output->is_error) {
                xCAT::MsgUtils->message("W", { data => ["$ip: Could not obtain system information from BMC."] }, $::CALLBACK);
                return;
            }
        }
        my $response = decode_json $req_output->content;
        my $mtm;
        my $serial;

        if (defined($response->{data})) {
            if (defined($response->{data}->{Model}) and defined($response->{data}->{SerialNumber})) {
                $mtm = $response->{data}->{Model};
                $serial = $response->{data}->{SerialNumber};
            }

        } else {
            xCAT::MsgUtils->message("E", { data => ["Unable to connect to REST server at $ip"] }, $::CALLBACK);
            return;
        }

        # delete space before and after
        $mtm =~ s/^\s+|\s+$|\.+//g;
        $serial =~ s/^\s+|\s+$|\.+//g;

        $mtm = '' if ($mtm =~ /^0+$/);
        $serial = '' if ($serial =~ /^0+$/);

        # To constract a node name need either mac or both mtm and serial
        # Exit if mac AND one of mtm or serial is missing
        if (!($mtm and $serial) and !$ipmac{$ip}) {
            xCAT::MsgUtils->message("W", { data => ["BMC Type/Model and Serial or MAC Address is unavailable for $ip"] }, $::CALLBACK);
            return;
        }

        # format info string for format_stanza function
        $node_data .= ",$mtm";
        $node_data .= ",$serial";
        if ($::opt_P) {
            if ($::opt_U) {
                if ($::opt_N) {
                    $node_data .= ",$::opt_U,$::opt_N"; # Display the new changed password
                } else {
                    $node_data .= ",$::opt_U,$::opt_P";
                }
            } else {
                $node_data .= ",,$::opt_P";
            }
        } else {
            $node_data .= ",,";
        }
        $node_data .= ",mp,bmc";
        if ($mtm and $serial) {
            my $mtmsip = lc($mtm)."*".lc($serial)."-".$ip;
            if (exists($::VPDHASH{$mtmsip})) {
                my $pre_node = $::VPDHASH{$mtmsip};
                xCAT::MsgUtils->message("I", { data => ["Found matching node $pre_node with bmc ip address: $ip, rsetboot/rpower $pre_node to continue hardware discovery."] }, $::CALLBACK);
                if ($opz) {
                    $node_data .= ",";
                    display_output($opz,undef,$pre_node,$mac_node,$node_data,"openbmc",$request_command);
                }
                return;
            }
            $mtms_node = "node-$mtm-$serial";
            $mtms_node =~ s/(.*)/\L$1/g;
            $mtms_node =~ s/[\s:\._]/-/g;
            $node_data .= ",";
        } elsif ($ipmac{$ip}) {
            $mac_node = "node-$ipmac{$ip}";
            $node_data .= ",$ipmac{$ip}";
        }
        $node_data .= ",$::opt_SN,$::opt_SN";
    } else {
        my $login_status;
        eval { $login_status = $login_response->status_line };
        if ($@) {
            xCAT::MsgUtils->message("W", { data => ["Login failed for $ip and no status received from response"] }, $::CALLBACK);
            return;
        }
        if ($login_status =~ /401 Unauthorized/) {
            xCAT::MsgUtils->message("W", { data => ["Invalid username or password for $ip"] }, $::CALLBACK);
        } else {
            xCAT::MsgUtils->message("W", { data => ["Received response " . $login_response->status_line . " for $ip"] }, $::CALLBACK);
        }
        return;
    }
    display_output($opz,$opw,$mtms_node,$mac_node,$node_data,"openbmc",$request_command);
}


#-----------------------------------------------------------------------------

=head3  display_output

        Common code to print output of bmcdiscover

=cut

#-----------------------------------------------------------------------------
sub display_output {
    my $opz             = shift;
    my $opw             = shift;
    my $mtms_node       = shift;
    my $mac_node        = shift;
    my $node_data       = shift;
    my $mgttype         = shift;
    my $request_command = shift;

    my $node;
    if (($node_in_list{$mac_node} and !$node_in_list{$mtms_node}) or (!$node_in_list{$mac_node} and !$mtms_node)) {
        $node = $mac_node;
    } else {
        $node = $mtms_node;
    }

    if (defined($opw)) {
        my $rsp = {};
        push @{ $rsp->{data} }, "Writing $node ($node_data) to database...";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        if (defined($opz)) {
            format_stanza($node, $node_data, $mgttype);
        }
        write_to_xcatdb($node, $node_data, $mgttype, $request_command);
    }
    elsif (defined($opz)) {
        format_stanza($node, $node_data, $mgttype);
    } else {
        my $rsp = {};
        push @{ $rsp->{data} }, "$node_data";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
    }
}

1;
