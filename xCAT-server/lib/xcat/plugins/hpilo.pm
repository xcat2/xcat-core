# 
# Copyright 2009 Hewlett-Packard Development Company, L.P.
# EPL license http://www.eclipse.org/legal/epl-v10.html
# 
# CHANGES:
#	VERSION 1.3 - Adaptive Computing Enterprises Inc <lmsilva@adaptivecomputing.com>
#		(tested with a BladeSystem c3000 running iLO2 (firmware version: 1.50 Mar 14 2008))
#
#		- fixed ssl connection bug by introducing a 15 second sleep between boot commands (stat / on|off) in issuePowerCmd() 
#
#	VERSION 1.2 - Adaptive Computing Enterprises Inc <lmsilva@adaptivecomputing.com>
#		(tested with a BladeSystem c3000 running iLO2 (firmware version: 1.50 Mar 13 2008))
#
#		- fixed boot process (to account for different power states)
#		- found a bug in the Net::SSLeay library
#			- it seems we cannot trust the following instructions inside openSSLconnection
#			Net::SSLeay::connect($ssl) and die_if_ssl_error("ERROR: ssl connect") 
#			- it seems this problem only happens during several requests at the same time, i believe the iLO service becomes unresponsive
#			- here is how to reproduce it: rpower node01 off ; rpower node01 on ; rpower node01 boot
#			- added a timeout to try and minimize the issue (it can be controlled by changing the $SSL_CONNECT_TIMEOUT variable
#
#	VERSION 1.1 - Adaptive Computing Enterprises Inc <lmsilva@adaptivecomputing.com>
#		(tested with a BladeSystem c3000 running iLO2 (firmware version: 1.50 Mar 12 2008))
#
#		- fixed bug where we tried to use an existing xCAT library (xCAT::Utils->getNodesetStates())
#		- fixed protocol handling logic (sendScript was returning an incorrect value)
#		- fixed processReply sub as it wasn't prepared to handle on/off requests (just STAT or BEACON requests) 
#		- added TOGGLE parameter to HOLD_PWR_BTN command. Otherwise requests would not work as expected
#		- changed issuePowerCmd() so that "off" subcommands would use SET_HOST_POWER_NO requests instead of HOLD_PWR_BTN
#		- added CHANGES to module
#
#	VERSION 1.0? - Hewlett-Packard Development Company, L.P.
#		- first version of hpilo.pm module?
#

package xCAT_plugin::hpilo;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";
use xCAT::GlobalDef;

use POSIX qw(ceil floor);
use Storable qw(store_fd retrieve_fd thaw freeze);
use xCAT::Utils;
use xCAT::Usage;
use Thread qw(yield);
use Socket;
use Net::SSLeay qw(die_now die_if_ssl_error);
use POSIX "WNOHANG";
my $tfactor = 0;
my $vpdhash;
my %bmc_comm_pids;
my $globalDebug = 0;
my $outfd;
my $currnode;
my $status_noop="XXXno-opXXX";
my $SSL_CONNECT_TIMEOUT = 30;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
		hpiloinit
        hpilocmd
);
our $VERSION = 1.1;

sub handled_commands {
  return {
    rpower => 'nodehm:power,mgt',
    rvitals => 'nodehm:mgt',
    rbeacon => 'nodehm:mgt',
    reventlog => 'nodehm:mgt'
  }
}

	
# These commands do not map directly to iLO commands
#	boot:
#		if power is off
#			power the server on
#		else
#			issue a HARD BOOT to the server
#
#	cycle:
#		Issue power off to server
#		Issue power on to server
#
	
	

my $INITIAL_HEADER = '
<LOCFG VERSION="2.21"/>
<RIBCL VERSION="2.0">
<LOGIN USER_LOGIN="AdMiNnAmE" PASSWORD="PaSsWoRd">';


# Command Definitions
my $GET_HOST_POWER_STATUS = '
<SERVER_INFO MODE="write">
<GET_HOST_POWER_STATUS/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

# This command enables or disables the Virtual Power Button
my $SET_HOST_POWER_YES = '
<SERVER_INFO MODE="write">
<SET_HOST_POWER HOST_POWER="Yes"/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $SET_HOST_POWER_NO = '
<SERVER_INFO MODE="write">
<SET_HOST_POWER HOST_POWER="No"/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $RESET_SERVER = '
<SERVER_INFO MODE="write">
<RESET_SERVER/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $PRESS_POWER_BUTTON = '
<SERVER_INFO MODE="write">
<PRESS_PWR_BTN/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $HOLD_POWER_BUTTON = '
<SERVER_INFO MODE="write">
<HOLD_PWR_BTN TOGGLE="Yes"/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $COLD_BOOT_SERVER = '
<SERVER_INFO MODE="write">
<COLD_BOOT_SERVER/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $WARM_BOOT_SERVER = '
<SERVER_INFO MODE="write">
<WARM_BOOT_SERVER/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $GET_UID_STATUS = '
<SERVER_INFO MODE="write">
<GET_UID_STATUS />
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $UID_CONTROL_ON = '
<SERVER_INFO MODE="write">
<UID_CONTROL UID="YES"/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $UID_CONTROL_OFF = '
<SERVER_INFO MODE="write">
<UID_CONTROL UID="NO"/>
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $GET_EMBEDDED_HEALTH = '
<SERVER_INFO MODE="read">
<GET_EMBEDDED_HEALTH />
</SERVER_INFO>
</LOGIN>
</RIBCL>';

my $GET_EVENT_LOG = '
<RIB_INFO MODE = "read" >
<GET_EVENT_LOG />
</RIB_INFO>
</LOGIN>
</RIBCL>';

my $CLEAR_EVENT_LOG = '
<RIB_INFO MODE = "write" >
<CLEAR_EVENT_LOG />
</RIB_INFO>
</LOGIN>
</RIBCL>';

my $IMPORT_SSH_KEY = '
<RIB_INFO MODE = "write" >
<IMPORT_SSH_KEY>
-----BEGIN SSH KEY -----';

my $IMPORT_SSH_KEY_ENDING = '
</IMPORT_SSH_KEY>
</RIB_INFO>
</LOGIN>
</RIBLC> ';


use Socket;
use Net::SSLeay qw(die_now die_if_ssl_error) ;

my $ctx;   # Make this a global

Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();
Net::SSLeay::randomize();
#
# opens an ssl connection to port 443 of the passed host
#
sub openSSLconnection($)
{
	my $host = shift;
	my ($ssl, $sin, $ip, $nip);
	if (not $ip = inet_aton($host))
	{
		print "$host is a DNS Name, performing lookup\n" if $globalDebug;
		$ip = gethostbyname($host) or die "ERROR: Host $host notfound. \n";
	}
	$nip = inet_ntoa($ip);
	#print STDERR "Connecting to $nip:443\n";
	$sin = sockaddr_in(443, $ip);
	socket (S, &AF_INET, &SOCK_STREAM, 0) or die "ERROR: socket: $!";
	connect (S, $sin) or die "connect: $!";
	$ctx = Net::SSLeay::CTX_new() or die_now("ERROR: Failed to create SSL_CTX $! ");

	Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);
	die_if_ssl_error("ERROR: ssl ctx set options");
	$ssl = Net::SSLeay::new($ctx) or die_now("ERROR: Failed to create SSL $!");

	Net::SSLeay::set_fd($ssl, fileno(S));
	eval {
		local $SIG{ALRM} = sub { die "TIMEOUT" };
		alarm $SSL_CONNECT_TIMEOUT;
		Net::SSLeay::connect($ssl) and die_if_ssl_error("ERROR: ssl connect");
		alarm 0;
	};
	if ($@) {
		die "TIMEOUT!" if $@ eq "TIMEOUT";
		die "Caught ssl error!";
	}
	#print STDERR 'SSL Connected ';
	print 'Using Cipher: ' . Net::SSLeay::get_cipher($ssl) if $globalDebug;
	#print STDERR "\n\n";
	return $ssl;
}

sub closeSSLconnection($)
{
	my $ssl = shift;
	
	Net::SSLeay::free ($ssl);		# Tear down connection
	Net::SSLeay::CTX_free ($ctx);	
	close S;
}

sub waitforack {
    my $sock = shift;
    my $select = new IO::Select;
    $select->add($sock);
    my $str;
    if ($select->can_read(10)) { # Continue after 10 seconds, even if not acked...
        if ($str = <$sock>) {
        } else {
           $select->remove($sock); #Block until parent acks data
        }
    }
}



# usage: sendscript(host, script)
# sends the xmlscript script to host, returns reply
sub sendScript($$)
{
	my $host = shift;
	my $script = shift;
	my ($ssl, $reply, $lastreply, $res, $n);
	$ssl = openSSLconnection($host);
	# write header
	$n = Net::SSLeay::ssl_write_all($ssl, '<?xml version="1.0"?>'."\r\n");
	print "Wrote $n\n" if $globalDebug;
	$n = Net::SSLeay::ssl_write_all($ssl, '<LOCFG version="2.21"/>'."\r\n");
	print "Wrote $n\n" if $globalDebug;

	# write script
	$n = Net::SSLeay::ssl_write_all($ssl, $script);
	print "Wrote $n\n$script\n" if $globalDebug;
	$reply = "";
	$lastreply = "";
	my $reply2return;
	READLOOP:
	while(1) {
		$n++;
		$lastreply = Net::SSLeay::read($ssl);
		die_if_ssl_error("ERROR: ssl read");
		if($lastreply eq "") {
			sleep(2); # wait 2 sec for more text.
			$lastreply = Net::SSLeay::read($ssl);
			die_if_ssl_error("ERROR: ssl read");
			last READLOOP if($lastreply eq "");
		}
		$reply .= $lastreply;
		print "lastreply  $lastreply \b" if $globalDebug;
		
		# Check response to see if a error was returned.
		if($lastreply =~ m/STATUS="(0x[0-9A-F]+)"[\s]+MESSAGE='(.*)'[\s]+\/>[\s]*(([\s]|.)*?)<\/RIBCL>/) {
			if($1 eq "0x0000") {
				#print STDERR "$3\n" if $3;
			} else {
				$reply2return = "ERROR: STATUS: $1, MESSAGE: $2\n";
			}
		}
	}
	print "READ: $lastreply\n" if $globalDebug;
	if($lastreply =~ m/STATUS="(0x[0-9A-F]+)"[\s]+MESSAGE='(.*)'[\s]+\/>[\s]*(([\s]|.)*?)<\/RIBCL>\n/) {
		if($1 eq "0x0000") {
			#Sprint STDERR "$3\n" if $3;
		} else {
			$reply2return =  "ERROR: STATUS: $1, MESSAGE: $2\n";
		}
	}
	else
	{
		$reply2return = $reply;
	}
	closeSSLconnection($ssl);
	return $reply2return;
}

sub process_request {
	my $request = shift;
	my $callback = shift;
	my $noderange = $request->{node}; #Should be arrayref
	my $command = $request->{command}->[0];
	my $extrargs = $request->{arg};
	my @exargs=($request->{arg});
	my $ipmimaxp = 64;
	if (ref($extrargs)) {
		@exargs=@$extrargs;
	}
	my $ipmitab = xCAT::Table->new('ipmi');

	my $ilouser = "USERID";
	my $ilopass = "PASSW0RD";
	# Go to the passwd table to see if usernames and passwords are defined
	my $passtab = xCAT::Table->new('passwd');
	if ($passtab) {
		my ($tmp)=$passtab->getAttribs({'key'=>'ipmi'},'username','password');
		if (defined($tmp)) {
			$ilouser = $tmp->{username};
			$ilopass = $tmp->{password};
		}
	}
	
	my @donargs = ();
	my $ipmihash = $ipmitab->getNodesAttribs($noderange,['bmc','username','password']);
	foreach(@$noderange) { 
		my $node=$_;
		my $nodeuser=$ilouser;
		my $nodepass=$ilopass;
		my $nodeip = $node;
		my $ent;
		if (defined($ipmitab)) {
			$ent=$ipmihash->{$node}->[0];
			if (ref($ent) and defined $ent->{bmc}) { $nodeip = $ent->{bmc}; }
			if (ref($ent) and defined $ent->{username}) { $nodeuser = $ent->{username}; }
			if (ref($ent) and defined $ent->{password}) { $nodepass = $ent->{password}; }
		}
		push @donargs,[$node,$nodeip,$nodeuser,$nodepass];
	}

	#get new node status
	my %nodestat=();
	my $check=0;
	my $newstat;
	if ($command eq 'rpower') {
		if (($extrargs->[0] ne 'stat') && ($extrargs->[0] ne 'status') && ($extrargs->[0] ne 'state')) {
			$check=1;
			my @allnodes;
			foreach (@donargs) { push(@allnodes, $_->[0]); }

			if ($extrargs->[0] eq 'off') { $newstat=$::STATUS_POWERING_OFF; }
			else { $newstat=$::STATUS_BOOTING;}

			foreach (@allnodes) { $nodestat{$_}=$newstat; }

			if ($extrargs->[0] ne 'off') {
				#get the current nodeset stat
				if (@allnodes>0) {
					my $nsh={};
					my ($ret, $msg)=xCAT::SvrUtils->getNodesetStates(\@allnodes, $nsh);
					if (!$ret) {
						foreach (keys %$nsh) {
							my $currstate=$nsh->{$_};
							$nodestat{$_}=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($currstate, "rpower");
						}
					}
				}
			}
		}
	}
	
	# fork off separate processes to handle the requested command on each node.
	my $children = 0;
	$SIG{CHLD} = sub {my $kpid; do { $kpid = waitpid(-1, &WNOHANG); if ($kpid > 0) { delete $bmc_comm_pids{$kpid}; $children--; } } while $kpid > 0; };
	my $sub_fds = new IO::Select;
	foreach (@donargs) {
		while ($children > $ipmimaxp) {
			my $errornodes={};
			forward_data($callback,$sub_fds,$errornodes);
			#update the node status to the nodelist.status table
			if ($check) {
				updateNodeStatus(\%nodestat, $errornodes);
			}
		}
		$children++;
		my $cfd;
		my $pfd;
		socketpair($pfd, $cfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
		$cfd->autoflush(1);
		$pfd->autoflush(1);
		my $child = xCAT::Utils->xfork();
		unless (defined $child) { die "Fork failed" };
		if ($child == 0) {
			close($cfd);
			my $rrc=execute_cmd($pfd,$_->[0],$_->[1],$_->[2],$_->[3],$command,-args=>\@exargs);
			close($pfd);
			exit(0);
		}
		$bmc_comm_pids{$child}=1;
		close ($pfd);
		$sub_fds->add($cfd)
	}
	while ($sub_fds->count > 0 and $children > 0) {
		my $errornodes={};
		forward_data($callback,$sub_fds,$errornodes);
		#update the node status to the nodelist.status table
		if ($check) {
			updateNodeStatus(\%nodestat, $errornodes);
		}
	}

	#Make sure they get drained, this probably is overkill but shouldn't hurt
	#my $rc=1;
	#while ( $rc > 0 ) {
		#my $errornodes={};
		#$rc=forward_data($callback,$sub_fds,$errornodes);
		#update the node status to the nodelist.status table
		#if ($check ) {
			#updateNodeStatus(\%nodestat, $errornodes);
		#}
	#}
}

sub updateNodeStatus {
	my $nodestat=shift;
	my $errornodes=shift;
	my %node_status=();
	foreach my $node (keys(%$errornodes)) {
		if ($errornodes->{$node} == -1) { next;} #has error, not updating status
		my $stat=$nodestat->{$node};
		if (exists($node_status{$stat})) {
			my $pa=$node_status{$stat};
			push(@$pa, $node);
		}else {
			$node_status{$stat}=[$node];
		}
	}
	xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1);
}

sub processReply 
{
	my $command = shift;
	my $subcommand = shift;
	my $reply = shift;   # This is the returned xml string from the iLO that we will now parse
	my $replyToReturn = "";
	my $rc = 0;

	if ($command eq "power" ) {
		if($subcommand =~ m/stat/) {
			# Process power status command
			$replyToReturn = "on" if $reply =~ m/HOST_POWER="ON"/;
			$replyToReturn = "off" if $reply =~ m/HOST_POWER="OFF"/;
			$replyToReturn = "timeout!" if $reply =~ m/ERROR: timed out/;
		}
		elsif (($subcommand =~/on/) || ($subcommand =~/off/) || ($subcommand =~ /reset/))
		{
			# Power commands do not actually return anything we can use
			# so we have to check for error RESPONSE STATUS!
			my $error_check = 0;
			while ($reply =~ m/STATUS="(0x[0-9A-F]+)"[\s]+MESSAGE='(.*)'[\s]+\/>[\s]*(([\s]|.)*?)<\/RIBCL>/g) {
				if ($1 ne "0x0000") {
					$error_check = 1;
					last;
				}
			}
			if (!$error_check) {
				return lc($subcommand);
			}
			else {
				return "could not process command!\n";
			}
		}
	} elsif ($command eq "beacon") {
		if($subcommand =~ m/stat/) {
			$replyToReturn = "on" if $reply =~ /GET_UID_STATUS UID="ON"/;
			$replyToReturn = "off" if $reply =~ /GET_UID_STATUS UID="OFF"/;
		}
	}
	
	if (! $replyToReturn) {
		$rc = -1;
	}
	
	return ($rc, $replyToReturn);
}

sub makeGEHXML
{
	my $inputreply = shift;
	# process response
	my $geh_output = "";

	my @lines = split/^/, $inputreply;
	my $capture = 0;

	foreach my $line (@lines) {
		if ($capture == 0 && $line =~ m/GET_EMBEDDED_HEALTH_DATA/) {
                $capture = 1;
        } elsif ($capture == 1 && $line =~ m/GET_EMBEDDED_HEALTH_DATA/) {
                $geh_output .= $line;
                last;
        }
        $geh_output .= $line if $capture;
	}
	return ($geh_output);
}
	

sub processGEHReply
{
	my $subcommand = shift;
	my $reply = shift ;
	
	use XML::Simple;
	
	# Process the reply from the ilo. Parse out all the untereting
	# stuff so we then have some XML which represents only the output of the GEH command.
	
	my $gehXML = makeGEHXML($reply);
	my $gehOutput = "";
	
	# Now use XML::Simple to build a perl hash representation of the output
	my $gehHash =XMLin($gehXML);
	
	# We now have the reply in a format which is easy to parse. Now we 
	# figure out what the user wants and return it.
	
	my $numoftemps = $#{$gehHash->{TEMPERATURE}->{TEMP}};
	
	if($subcommand eq "temp" || $subcommand eq "all") {
		
		for my $index (0 .. $numoftemps) {
			my $location = $gehHash->{TEMPERATURE}->{TEMP}[$index]->{LOCATION}->{VALUE};
			my $temperature = $gehHash->{TEMPERATURE}->{TEMP}[$index]->{CURRENTREADING}->{VALUE};
			my $unit = $gehHash->{TEMPERATURE}->{TEMP}[$index]->{CURRENTREADING}->{UNIT};
			$gehOutput .= "$location "."Temperature: "."$temperature $unit \n";
		}
	}

	if($subcommand eq "cputemp" || $subcommand eq "ambtemp") {
		my $temp2look4 = "CPU" if ($subcommand eq "cputemp");
		$temp2look4 = "Ambient" if ($subcommand eq "ambtemp");
		for my $index (0 .. $numoftemps) {
			if($gehHash->{TEMPERATURE}->{TEMP}[$index]->{LOCATION} =~ m/$temp2look4/) {
				my $location = $gehHash->{TEMPERATURE}->{TEMP}[$index]->{LOCATION}->{VALUE};
				my $temperature = $gehHash->{TEMPERATURE}->{TEMP}[$index]->{CURRENTREADING}->{VALUE};
				my $unit = $gehHash->{TEMPERATURE}->{TEMP}[$index]->{CURRENTREADING}->{UNIT};
				$gehOutput .= " $location "."Temperature: "."$temperature $unit \n";
			}
		}
	}
	
	
	if($subcommand eq "fanspeed" || $subcommand eq "all") {
		foreach my $fan (keys %{$gehHash->{FANS}}) {
			my $fanLabel = $gehHash->{FANS}->{$fan}->{LABEL}->{VALUE};
			my $fanStatus = $gehHash->{FANS}->{$fan}->{STATUS}->{VALUE};
			my $fanZone = $gehHash->{FANS}->{$fan}->{ZONE}->{VALUE};
			my $fanUnit = $gehHash->{FANS}->{$fan}->{SPEED}->{UNIT};
			my $fanSpeedValue = $gehHash->{FANS}->{$fan}->{SPEED}->{VALUE};
		
			if($fanUnit eq "Percentage") {
				$fanUnit = "%";
			}
		
			$gehOutput .= "Fan Status $fanStatus Fan Speed: $fanSpeedValue $fanUnit Label - $fanLabel Zone - $fanZone";
	
		}
	}

	return(0, $gehOutput);
	
}
	

sub execute_cmd {
	$outfd = shift;
	my $node = shift;
	$currnode= $node;
	my $iloip = shift;
	my $user = shift;
	my $pass = shift;
	my $command = shift;
	my %namedargs = @_;
	my $extra=$namedargs{-args};
	my @exargs=@$extra;

	
	my $subcommand = $exargs[0];
	
	my ($rc, @reply);
	
	if($command eq "rpower" ) {   # THe almighty power command
	
		($rc, @reply) = issuePowerCmd($iloip, $user, $pass, $subcommand);
	
	} elsif ($command eq "rvitals" ) {
	
		($rc, @reply) = issueEmbHealthCmd($iloip, $user, $pass, $subcommand);
		
	} elsif ($command eq "rbeacon") {
		
		($rc, @reply) = issueUIDCmd($iloip, $user, $pass, $subcommand);
		
	} elsif ($command eq "reventlog") {
	
		($rc, @reply) = issueEventLogCmd($iloip, $user, $pass, $subcommand);
	
	}
	
	sendoutput($rc, @reply);
	
	return $rc;

}

sub issueUIDCmd 
{
	my $ipaddr = shift;
	my $username = shift;
	my $password = shift;
	my $subcommand = shift;
	
	my $cmdString;
	
	if($subcommand eq "on") {
		$cmdString = $UID_CONTROL_ON;
	} elsif ($subcommand eq "off") {
		$cmdString = $UID_CONTROL_OFF;
	} elsif ($subcommand eq "stat") {
		$cmdString = $GET_UID_STATUS;
	} else { # anything else is not supported by the ilo
		return(-1, "not supported");
	}
	
	# All figured out.... send the command
	my ($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $cmdString);
	
	my $condensedReply = processReply("beacon", $subcommand, $reply);
	
	return ($rc, $condensedReply);
}

sub issuePowerCmd {
	my $ipaddr = shift;
	my $username = shift;
	my $password = shift;
	my $subcommand = shift;
	
	my $cmdString = "";
	my ($rc, $reply);
	
	if ($subcommand eq "on") {
		$cmdString = $SET_HOST_POWER_YES;
	} elsif($subcommand eq "off") {
		$cmdString = $SET_HOST_POWER_NO;
		#$cmdString = $HOLD_POWER_BUTTON;
	} elsif ($subcommand eq "stat" || $subcommand eq "state") {
		$cmdString = $GET_HOST_POWER_STATUS;
	} elsif ($subcommand eq "reset") {
		$cmdString = $RESET_SERVER;
	} elsif ($subcommand eq "softoff") {
		$cmdString = $HOLD_POWER_BUTTON;
	# Handle two special cases here. For these commands we will need to issue a series of
	# commands to the ilo to emulate the desired operation
	} elsif ($subcommand eq "cycle") {
		($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $SET_HOST_POWER_NO);
		sleep 15;
		if ($rc != 0) {
			print STDERR "issuePowerCmd:cycle Command to power down server failed. \n";
			return ($rc, $reply);
		}
		$cmdString = $SET_HOST_POWER_YES;
		
	} elsif ($subcommand eq "boot") {
		# Determine the current power status of the server
		($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $GET_HOST_POWER_STATUS);
		if ($rc == 0) {
			my $powerstatus = processReply("power", "status", $reply);
			
			if ($powerstatus eq "on") {
				$subcommand = "on reset";
				$cmdString = $RESET_SERVER;
			} else {
				$subcommand = "on";
				$cmdString = $SET_HOST_POWER_YES;
			}
			# iLO doesn't seem to handle several connections in a small amount of time
			# so let's just wait a few seconds...
			sleep(15);
		} else {
			print STDERR "issuePowerCmd:boot Power status of server failed. \n";
			return ($rc, $reply);
		}
		
	}

	($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $cmdString);
	
	my $condensedReply = processReply("power", $subcommand, $reply);

	return ($rc, $condensedReply);
}


sub issueEmbHealthCmd {
	my $ipaddr = shift;
	my $username = shift;
	my $password = shift;
	my $subcommand = shift;
	
	my ($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $GET_EMBEDDED_HEALTH);
	
	my $condensedReply = processGEHReply($subcommand, $reply);
	
	return ($rc, $condensedReply);
}

sub issueEventLogCmd {
	my $ipaddr = shift;
	my $username = shift;
	my $password = shift;
	my $subcommand = shift;
	
	my $numberOfEntries = "";
	my $errorLogOutput;
	my ($rc, $reply);
	
	if($subcommand eq "clear") {
		($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $CLEAR_EVENT_LOG);
		return($rc, $reply);
	}
	
	if(! $subcommand =~ /\D/) {
		$numberOfEntries = $subcommand;
	}
	
	if($subcommand eq "all" || $numberOfEntries) {
		($rc, $reply) = iloCmd($ipaddr, $username, $password, 0, $GET_EVENT_LOG);
		
		if ($rc != 0) {
			print STDERR "issueEventLogCmd: Failed get error log \n";
		}
		$errorLogOutput = processErrorLogReply($reply);
	}
	
	return ($rc, $errorLogOutput);
}
		
	

sub iloCmd {
	my $ipaddr = shift;
	my $username = shift;
	my $password = shift;
	my $localdebug = shift;
	my $command = shift;
	
	# Before we open the connection to the iLO, build the command we are going
	# to send
	
	my $cmdToSend = $INITIAL_HEADER;
	$cmdToSend =~ s/AdMiNnAmE/$username/;
	$cmdToSend =~ s/PaSsWoRd/$password/;
	$cmdToSend = "$cmdToSend"."$command";
	
	if($localdebug) {
		print STDERR "Command built. Command is $cmdToSend \n";
	}
	
	my $reply = sendScript($ipaddr, $cmdToSend);
	
	return(0, $reply);
}

sub forward_data { #unserialize data from pipe, chunk at a time, use magic to determine end of data structure
	my $callback = shift;
	my $fds = shift;
	my $errornodes=shift;

	my @ready_fds = $fds->can_read(1);
	my $rfh;
 	my $rc = @ready_fds;
 	foreach $rfh (@ready_fds) {
		my $data;
		if ($data = <$rfh>) {
			while ($data !~ /ENDOFFREEZE6sK4ci/) {
				$data .= <$rfh>;
			}
			print $rfh "ACK\n";
			my $responses=thaw($data);
			foreach (@$responses) {
				#save the nodes that has errors and the ones that has no-op for use by the node status monitoring
				my $no_op=0;
				if (exists($_->{node}->[0]->{errorcode})) { $no_op=1; }
				else {
					my $text=$_->{node}->[0]->{data}->[0]->{contents}->[0];
					#print "data:$text\n";
					if (($text) && ($text =~ /$status_noop/)) {
						$no_op=1;
						#remove the symbols that meant for use by node status
						$_->{node}->[0]->{data}->[0]->{contents}->[0] =~ s/ $status_noop//;
					}
				}
				#print "data:". $_->{node}->[0]->{data}->[0]->{contents}->[0] . "\n";
				if ($no_op) {
					if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=-1; }
				} else {
					if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=1; }
				}
				$callback->($_);
			}
		} else {
			$fds->remove($rfh);
			close($rfh);
		}
	}
yield; #Avoid useless loop iterations by giving children a chance to fill pipes  return $rc;
}

	

sub sendoutput {
	my $rc=shift;
	foreach (@_) {
		my %output;
		(my $desc,my $text) = split(/:/,$_,2);
		unless ($text) {
			$text=$desc;
		} else {
			$desc =~ s/^\s+//;
			$desc =~ s/\s+$//;
			if ($desc) {
				$output{node}->[0]->{data}->[0]->{desc}->[0]=$desc;
			}
		}
		$text =~ s/^\s+//;
		$text =~ s/\s+$//;
		$output{node}->[0]->{name}->[0]=$currnode;
		$output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
		if ($rc) {
			$output{node}->[0]->{errorcode}=[$rc];
		}
		#push @outhashes,\%output; #Save everything for the end, don't know how to be slicker with Storable and a pipe
		print $outfd freeze([\%output]);
		print $outfd "\nENDOFFREEZE6sK4ci\n";
		yield;
		waitforack($outfd);
	}
}

1;

	
		
