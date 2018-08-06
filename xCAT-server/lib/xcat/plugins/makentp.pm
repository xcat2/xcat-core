#!/usr/bin/env perl
# IBM(c) 2015 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::makentp;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use Getopt::Long;
use xCAT::Usage;
use xCAT::NetworkUtils;
use xCAT::TableUtils;
use xCAT::Utils;
use XML::Simple;
no strict;
use Data::Dumper;
use Socket;

my %globalopt;

#-------------------------------------------------------------------------------

=head1  xCAT_plugin:makentp
=head2    Package Description
    Handles ntp server setup on a xCAT management node.
=cut

#-------------------------------------------------------------------------------


#--------------------------------------------------------------------------------

=head3   send_msg
      Invokes the callback with the specified message
    Arguments:
        request: request structure for plguin calls
        ecode: error code. 0 for succeful.
        msg: messages to be displayed.
    Returns:
        none
=cut

#--------------------------------------------------------------------------------
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my $msg     = shift;
    my %output;

    # Called from child process - send to parent
    if (exists($request->{pipe})) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data}      = \@_;
        print $out freeze([ \%output ]);
        print $out "\nENDOFFREEZE6sK4ci\n";
    }

    # Called from parent - invoke callback directly
    elsif (exists($request->{callback})) {
        my $callback = $request->{callback};
        $output{errorcode} = $ecode;
        $output{data}->[0] = $msg;
        $callback->(\%output);
    }
}


#--------------------------------------------------------------------------------

=head3   handled_commands
      It returns a list of commands handled by this plugin.
    Arguments:
       none
    Returns:
       a list of commands.
=cut

#--------------------------------------------------------------------------------
sub handled_commands {
    return ({ makentp => "makentp" });
}


#--------------------------------------------------------------------------------

=head3   parse_args
      Parse the command line options and operands.
    Arguments:
        request: the request structure for plugin
    Returns:
        Usage string or error message.
        0 if no user promp needed.

=cut

#--------------------------------------------------------------------------------
sub parse_args {

    my $request = shift;
    my $args    = $request->{arg};
    my $cmd     = $request->{command};
    my %opt;

    # Responds with usage statement
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        send_msg($request, 0, " $usage_string");
        return ([ $_[0], $usage_string ]);
    };

    # No command-line arguments - use defaults
    if (!defined($args)) {
        return (0);
    }

    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    @ARGV                     = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");

    # Process command-line flags
    if (!GetOptions(\%opt,
            qw(h|help V|Verbose v|version a|all))) {
        return (usage());
    }

    # Option -V for verbose output
    if (exists($opt{V})) {
        $globalopt{verbose} = 1;
    }

    if (exists($opt{a})) {
        $globalopt{a} = 1;
    }

    return;
}


#--------------------------------------------------------------------------------

=head3   preprocess_request
      Parse the arguments and display the usage or the version string. 

=cut

#--------------------------------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback = shift;

    my $command  = $req->{command}->[0];
    my $extrargs = $req->{arg};
    my @exargs   = ($req->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    # Build hash to pass around
    my %request;
    $request{arg}      = $extrargs;
    $request{callback} = $callback;
    $request{command}  = $command;

    my $usage_string = xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({ data => [$usage_string] });
        $req = {};
        return;
    }

    my $result = parse_args(\%request);
    if (ref($result) eq 'ARRAY') {
        send_msg(\%request, 1, @$result);
        return (1);
    }

    # add current request
    my @result  = ();
    my $reqcopy = {%$req};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    if (xCAT::Utils->isMN() && exists($globalopt{a})) {
        $reqcopy->{_all}->[0] = 1;
    }
    if (exists($globalopt{verbose})) {
        $reqcopy->{_verbose}->[0] = 1;
    }
    push @result, $reqcopy;

    return \@result;
}

#--------------------------------------------------------------------------------

=head3   process_request
    Pasrse the arguments and call the correspondent functions
    to do switch discovery. 

=cut

#--------------------------------------------------------------------------------
sub process_request {
    my $req      = shift;
    my $callback = shift;
    my $sub_req  = shift;

    # Build hash to pass around
    my %request;
    $request{arg}      = $req->{arg};
    $request{callback} = $callback;
    $request{command}  = $req->{command}->[0];

    my $verbose;
    if ($req->{_verbose}->[0] == 1) {
        $verbose = 1;
    }

    my @nodeinfo = xCAT::NetworkUtils->determinehostname();
    my $nodename = pop @nodeinfo;

    if (xCAT::Utils->isMN()) {
        send_msg(\%request, 0, "configuring management node: $nodename.");
    } else {
        send_msg(\%request, 0, "configuring service node: $nodename.");
    }

    # get site.extntpservers for mn, for sn use mn as the server
    my $ntp_servers;
    my $ntp_master;
    my $ntp_attrib;
    if (xCAT::Utils->isMN()) {
        $ntp_attrib = "extntpservers";
    } else {
        $ntp_attrib = "ntpservers";
    }
    my @entries     = xCAT::TableUtils->get_site_attribute($ntp_attrib);
    my $ntp_servers = $entries[0];

    if (!xCAT::Utils->isMN() && ((!$ntp_servers) ||
        (($ntp_servers) && ($ntp_servers =~ /<xcatmaster>/)))) {
        my $retdata = xCAT::ServiceNodeUtils->readSNInfo($nodename);
        $ntp_servers = $retdata->{'master'};
    }

    # Handle chronyd here,
    if (-f "/usr/sbin/chronyd") {
        send_msg(\%request, 0, "Will configure chronyd instead.");

        my $cmd = "/install/postscripts/setupntp " .
            join(' ', split(',', $ntp_servers));
        send_msg(\%request, 0, "Calling ... " . $cmd);

        my $result = xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0) {
            send_msg(\%request, 1, "Error from command: $cmd\n    $result");
            return 1;
        }

        send_msg(\%request, 0, "Daemon chronyd configured.");

	# Cannot find a better way other than use goto statement :-/
        goto HANDLE_MAKENTP_A;
    }

    #check if ntp is installed or not
    if ($verbose) {
        send_msg(\%request, 0, " ...checking if nptd is installed.");
    }
    if (!-f "/usr/sbin/ntpd") {
        send_msg(\%request, 1, "Please make sure ntpd is installed on $nodename.");
        return 1;
    }

    #configure the ntp configuration file
    if ($verbose) {
        send_msg(\%request, 0, " ...backing up the ntp configuration file /etc/ntp.conf.");
    }
    my $ntpcfg           = "/etc/ntp.conf";
    my $ntpcfgbackup     = "/etc/ntp.conf.orig";
    my $ntpxcatcfgbackup = "/etc/ntp.conf.xcatbackup";
    if (-e $ntpcfg) {
        if (!-e $ntpcfgbackup) {

            # if original backup does not already exist
            my $cmd = "mv $ntpcfg $ntpcfgbackup";
            my $result = xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0) {
                send_msg(\%request, 1, "Error from command:$cmd\n    $result");
                return 1;
            }
        }
        else {
            # backup xcat cfg
            my $cmd = "rm $ntpxcatcfgbackup;mv $ntpcfg $ntpxcatcfgbackup";
            my $result = xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0) {
                send_msg(\%request, 1, "Error from command:$cmd\n    $result.");
                return 1;
            }
        }
    }

    if ($verbose) {
        send_msg(\%request, 0, " ...changing the ntp configuration file /etc/ntp.conf.\n    ntp servers are: $ntp_servers");
    }

    # create ntp server config file
    open(CFGFILE, ">$ntpcfg")
      or xCAT::MsgUtils->message('SE',
        "Cannot open $ntpcfg for NTP update. \n");

    if (defined($ntp_servers) && $ntp_servers) {
        my @npt_server_array = split(',', $ntp_servers);

        # add ntp servers one by one
        foreach my $ntps (@npt_server_array) {
            if (!$ntp_master) { $ntp_master = $ntps; }
            print CFGFILE "server ";
            print CFGFILE "$ntps\n";
        }
    }

    my $os          = xCAT::Utils->osver("all");

    #for sles, /var/lib/ntp/drift is a dir
    if (xCAT::Utils->isAIX()) {
        print CFGFILE "driftfile /etc/ntp.drift\n";
        print CFGFILE "tracefile /etc/ntp.trace\n";
        print CFGFILE "disable auth\n";
        print CFGFILE "broadcastclient\n";
    } elsif ($os =~ /sles/) {
        print CFGFILE "driftfile /var/lib/ntp/drift/ntp.drift\n";
        print CFGFILE "disable auth\n";
    } else {
        print CFGFILE "driftfile /var/lib/ntp/drift\n";
        print CFGFILE "disable auth\n";
    }

    #add xCAT mn/sn itself as a server
    print CFGFILE "server 127.127.1.0\n";
    print CFGFILE "fudge 127.127.1.0 stratum 10\n";

    close CFGFILE;

    my $ntp_service = "ntpserver";

    #stop ntpd
    if ($verbose) {
        send_msg(\%request, 0, " ...stopping $ntp_service");
    }
    my $rc = xCAT::Utils->stopservice($ntp_service);
    if ($rc != 0) {
        send_msg(\%request, 1, "Failed to stop nptd on $nodename.");
        return 1;
    }

    #update the time now
    if ($ntp_master) {
        my $cmd;
        if ($os =~ /sles/) {
            if (-f "/usr/sbin/rcntpd") {
                $cmd = "/usr/sbin/rcntpd ntptimeset";
            } elsif (-f "/usr/sbin/rcntp") {
                $cmd = "/usr/sbin/rcntp ntptimeset";
            } else {
                $cmd = "sntp -P no -r $ntp_master";
            }
        } else {
            $cmd = "ntpdate -t5 $ntp_master";
        }
        if ($verbose) {
            send_msg(\%request, 0, " ...updating the time now. $cmd");
        }
        my $result = xCAT::Utils->runcmd($cmd, 0);
        if ($verbose) {
            send_msg(\%request, 0, "    $result");
        }
        if ($::RUNCMD_RC != 0) {
            send_msg(\%request, 1, "Error from command $cmd\n    $result.");
            send_msg(\%request, 1, "Please check $ntp_master, make sure time is synced (can be validated by 'ntpq -p'), then rerun makentp command again ");
            return 1;
        }
    }

    #setup the hardware clock
    my $hwcmd = "/sbin/hwclock --systohc --utc";
    if ($verbose) {
        send_msg(\%request, 0, " ...updating the hwclock now. $hwcmd");
    }
    my $hwresult = xCAT::Utils->runcmd($hwcmd, 0);
    if ($verbose) {
        send_msg(\%request, 0, "    $hwresult");
    }
    if ($::RUNCMD_RC != 0) {
        send_msg(\%request, 1, "Error from command $hwcmd\n    $hwresult.");
        return 1;
    }

    my $grep_cmd;
    my $rc;

    #setup the RTC is UTC format, which will be used by os
    if ($os =~ /sles/) {
        $grep_cmd = "grep -i HWCLOCK /etc/sysconfig/clock";
        $rc = xCAT::Utils->runcmd($grep_cmd, 0);
        if ($::RUNCMD_RC == 0) {
            `sed -i 's/.*HWCLOCK.*/HWCLOCK=\"-u\"/' /etc/sysconfig/clock`;
        } else {
            `echo HWCLOCK=\"-u\" >> /etc/sysconfig/clock`;
        }
    } elsif (-f "/etc/debian_version") {
        `sed -i 's/.*UTC.*/UTC=\"yes\"/' /etc/default/rcS`;
    } else {
        if (-f "/etc/sysconfig/clock") {
            $grep_cmd = "grep -i utc /etc/sysconfig/clock";
            $rc = xCAT::Utils->runcmd($grep_cmd, 0);
            if ($::RUNCMD_RC == 0) {
                `sed -i 's/.*UTC.*/UTC=\"yes\"/' /etc/sysconfig/clock`;
            } else {
                `echo UTC=\"yes\" >> /etc/sysconfig/clock`;
            }
        } else {
            `type -P timedatectl >/dev/null 2>&1`;
            `timedatectl set-local-rtc 0`;
        }
    }

    #update the hardware clock automaticly
    if (-f "/etc/sysconfig/ntpd") {
        $grep_cmd = "grep -i SYNC_HWCLOCK /etc/sysconfig/ntpd";
        $rc = xCAT::Utils->runcmd($grep_cmd, 0);
        if ($::RUNCMD_RC == 0) {
            `sed -i 's/.*SYNC_HWCLOCK.*/SYNC_HWCLOCK=\"yes\"/' /etc/sysconfig/ntpd`;
        } else {
            `echo SYNC_HWCLOCK=\"yes\" >> /etc/sysconfig/ntpd`;
        }
    } elsif (-f "/etc/sysconfig/ntp") {
        `sed -i 's/.*SYNC_HWCLOCK.*/NTPD_FORCE_SYNC_HWCLOCK_ON_STARTUP=\"yes\"/' /etc/sysconfig/ntp`;
        `sed -i 's/^NTPD_FORCE_SYNC_ON.*/NTPD_FORCE_SYNC_ON_STARTUP=\"yes\"/' /etc/sysconfig/ntp`;
        `sed -i 's/.*RUN_CHROOTED.*/NTPD_RUN_CHROOTED=\"yes\"/' /etc/sysconfig/ntp`;
    } else {
        my $cron_file = "/etc/cron.daily/xcatsethwclock";
        if (!-f "$cron_file") {
            `echo "#!/bin/sh" > $cron_file`;
            `echo "/sbin/hwclock --systohc --utc" >> $cron_file`;
            `chmod a+x $cron_file`;

            #service cron restart
            xCAT::Utils->startservice("cron");
        }
    }

    #start ntpd
    if ($verbose) {
        send_msg(\%request, 0, " ...starting $ntp_service");
    }
    my $rc = xCAT::Utils->startservice($ntp_service);
    if ($rc != 0) {
        send_msg(\%request, 1, "Failed to start nptd on $nodename.");
        return 1;
    }

    #enable ntpd for node reboot
    if ($verbose) {
        send_msg(\%request, 0, " ...enabling $ntp_service");
    }
    xCAT::Utils->enableservice($ntp_service);

HANDLE_MAKENTP_A:

    #now handle sn that has ntpserver=1 set in servicenode table.
    # this part is called by makentp -a.
    if ($req->{_all}->[0] == 1) {
        my @servicenodes = xCAT::ServiceNodeUtils->getSNList('ntpserver');
        if (@servicenodes > 0) {
            send_msg(\%request, 0, "configuring service nodes: @servicenodes");
            my $ret =
              xCAT::Utils->runxcmd(
                {
                    command => ['updatenode'],
                    node    => \@servicenodes,
                    arg     => [ "-P", "setupntp" ],
                },
                $sub_req, -1, 1
              );
            my $retcode=$::RUNCMD_RC;
            my $msg;
            foreach my $line (@$ret) {
                $msg .= "$line\n";
            }
            send_msg(\%request, $retcode, "$msg");
        }
    }

    return;
}

1;
