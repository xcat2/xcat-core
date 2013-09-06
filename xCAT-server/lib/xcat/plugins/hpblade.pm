#!/usr/bin/env perl
# 
# © Copyright 2009 Hewlett-Packard Development Company, L.P.
# EPL license http://www.eclipse.org/legal/epl-v10.html
#
# Revision history:
#   July, 2010    vallard@sumavi.com comments added.
#   August, 2009	blade.pm adapted to generate hpblade.pm
#
package xCAT_plugin::hpblade;
BEGIN
{
	$::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::Usage;
use IO::Socket;
use Thread 'yield';
use Storable qw(freeze thaw);
use XML::Simple;
use Net::SSLeay qw(die_now die_if_ssl_error);


use Data::Dumper;
use POSIX "WNOHANG";
use Getopt::Long;
#use xCAT::hpoa;	# require this dynamically below instead

sub handled_commands {
	return {
		findme => 'blade',
		getmacs => 'nodehm:getmac,mgt',
		rscan => 'nodehm:mgt',
		rpower => 'nodehm:power,mgt',
		gethpbladecons => 'hpblade',
		getrvidparms => 'nodehm:mgt',
		rvitals => 'nodehm:mgt',
		rinv => 'nodehm:mgt',
		rbeacon => 'nodehm:mgt',
		rspreset => 'nodehm:mgt',
		rspconfig => 'nodehm:mgt',
		rbootseq => 'nodehm:mgt',
		reventlog => 'nodehm:mgt',
		switchblade => 'nodehm:mgt',
	};
}

my $hpoa;
my $activeOABay;
my $slot;
my ($username, $password);
my %mm_comm_pids;
my %macmap; #Store responses from rinv for discovery
my $macmaptimestamp; #reflect freshness of cache
my %oahash;
my $curn;
my $oa;
my $getBladeStatusResponse;  # Make this a global here so we can re-use the result
my $status_noop="XXXno-opXXX";
my $eventHash;
my $globalDebug = 0;
my $ctx;
my @cfgtext;

my %bootdevices = (
	0 => 'IPL_NO_OP',
	1 => 'CD',
	2 => 'FLOPPY',
	3 => 'USB',
	4 => 'HDD',
	5 => 'PXE_NIC1',
	6 => 'PXE_NIC2' ,
	7 => 'PXE_NIC3',
	8 => 'PXE_NIC4'
);

my %bootnumbers = (
	'none' => 0,
	'c' => 1,
	'cd' => 1,
	'dvd' => 1,
	'cdrom' => 1,
	'dvdrom' => 1,
	'f' => 2,
	'floppy' => 2,
	'usb' => 3,
	'usbflash' => 3,
	'flash' => 3,
	'h' => 4,
	'hd' => 4,
	'hdd' => 4,
	'hd0' => 4,
	'harddisk' => 4,
	'eth0' => 5,
	'nic1' => 5,
	'net1' => 5,
	'net' => 5,
	'n' => 5,
	'pxe_nic1' => 5,
	'eth1' => 6,
	'nic2' => 6,
	'net2' => 6,
	'pxe_nic2' => 6,
	'eth2' => 7,
	'nic3' => 7,
	'net3' => 7,
	'pxe_nic3' => 7,
	'eth3' => 8,
	'nic4' => 8,
	'net4' => 8,
	'pxe_nic4' => 8
);

my @rscan_attribs = qw(nodetype name id mtm serial mpa groups mgt);
my @rscan_header = (
["type",          "%-8s" ],
["name",          "" ],
["id",            "%-8s" ],
["type-model",    "%-12s" ],
["serial-number", "%-15s" ],
["address",       "%s\n" ]);

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


# Login to the OA using credentials found in the database.
sub oaLogin {
	my $oaName = shift;
	my $result = "";
	my $hopa = "";
	my $errHash;
	
	# we need to get the info on the OA. If the specfied OA is NOT the
	# ACTIVE OA then we return failure because we can't get the desired
	# info from a STANDBY OA.
	
	my ($username, $passwd, $encinfo);

	my $mpatab = xCAT::Table->new('mpa');
	my $ent;
	if(defined($mpatab)) {
		($ent) = $mpatab->getAttribs({'mpa'=>$oaName}, 'username', 'password');
		if (defined($ent->{password})) {$password = $ent->{password}; }
		if (defined($ent->{username})) {$username = $ent->{username}; }
	}
	
	
	$hpoa = xCAT::hpoa->new('oaAddress' => $oaName);
	my $loginResponse = $hpoa->userLogIn('username' => $username, 'password' => $password);
	if($loginResponse->fault) {
		$errHash = $loginResponse->fault;
		print Dumper($errHash);
		$result = $loginResponse->oaErrorText;
		if($loginResponse->fault) {
			return(1, "Error on login attempt");
		}
	}
	
	my $response = $hpoa->getEnclosureInfo();
	if($response->fault) {
		return(1, "Error on get Enclosure Info call");
	}
	my $numOABays = $response->result->{oaBays};
		
	# OK We now know how many oaBays we have in this enclosure. Ask the OAs in each bay
	# if they are active. If they are not, then leave since we can't get what we want 
	# from a standby OA
	$activeOABay = 0;
		
	for (my $oaBay = 1; $oaBay <= $numOABays; $oaBay++) {
		$response = $hpoa->getOaInfo(bayNumber=>$oaBay);
		if(!defined $response->result() || $response->result()->{oaRole} eq "OA_ABSENT" || 
			$response->result->{youAreHere} eq "false") {
			# either there is no OA here or this is not the one I am currently
			# communicating with
			next;
		} elsif ($response->result->{youAreHere} eq "true") {
			$activeOABay = $oaBay;
			last;
		}
	}
		
	if(! $activeOABay ) {
		return(1, "Cannot determine active OnBoard Administrator");
	}
		
	# Last thing. Need to determine if this is the active OA. If not, then we 
	# just tell the caller, and they can make the decision as to what they want
	# to do.
			
	$response = $hpoa->getOaStatus(bayNumber=>$activeOABay);
	if($response->result->{oaRole} ne "ACTIVE") {
		return (-1);
	}
		
	return ($hpoa);
}
	
sub oaLogout
{
	my $hpoa = shift;
	
	my $response = $hpoa->userLogOut();
}

sub convertSlot {
	my $origSlot = shift;
	
	if($origSlot =~ /\D/) {
		my $slotNum = $origSlot;
		my $slotAlpha = $slotNum;
		
		$slotNum =~ s/\D//;
		$slotAlpha =~ s/\d//;
		
		my $side;
		if ($slotAlpha eq "a" or $slotAlpha eq "A") {
			$side = 1;
		} elsif ($slotAlpha eq "b" or $slotAlpha eq "B") {
			$side = 2;
		} else {
			return(-1);
		}
		
		my $returnSlot = $side * 16 + $slotNum;
		return($returnSlot);
	}
	return($origSlot);
}
	
sub gethpbladecons {
	my $noderange = shift;
	my $callback=shift;
	my $mpatab = xCAT::Table->new('mpa');
	my $passtab = xCAT::Table->new('passwd');
	my $tmp;
	my $user="USERID";

	if ($passtab) {
		($tmp)=$passtab->getAttribs({'key'=>'blade'},'username');
		if (defined($tmp)) {
			$user = $tmp->{username};
		}
	}
	my $mptab=xCAT::Table->new('mp');
	my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id']);
	foreach my $node (@$noderange) {
		my $rsp = {node=>[{name=>[$node]}]};
		my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
		if (defined($ent->{mpa})) { 
			$oa = $ent->{mpa};
			$slot = convertSlot($ent->{id});
			if($slot == 0) { # want to open a console on the OA
				$rsp->{node}->[0]->{mm} = $oa;
			} else {
				$hpoa = oaLogin($oa);
				my $mpInfoResp = $hpoa->getBladeMpInfo("bayNumber"=>$slot);
				if($mpInfoResp->fault) {
					$rsp->{node}->[0]->{error}= ["Error getting MP info"];
					$rsp->{node}->[0]->{errorcode} = [1];
					$callback->($rsp);
					next;
				}
				my $ipaddress = $mpInfoResp->result->{ipAddress};
				$rsp->{node}->[0]->{mm} = $ipaddress;
			}
			($tmp) = $mpatab->getAttribs({'mpa'=>$oa}, 'username');
			$user = [$tmp->{username}];
			$rsp->{node}->[0]->{username} = $user;
		} else { 
			$rsp->{node}->[0]->{error}=["no mpa defined"];
			$rsp->{node}->[0]->{errorcode}=[1];
			$callback->($rsp);
			next;
		}
		if (defined($ent->{id})) { 
			$rsp->{node}->[0]->{slot}=$ent->{id};
		} else { 
			$rsp->{node}->[0]->{slot}="";
		}
		
		$callback->($rsp);
	}
}

	
sub preprocess_request { 
	my $request = shift;
	#if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
        if (   (defined($request->{_xcatpreprocessed}))
        && ($request->{_xcatpreprocessed}->[0] == 1))
        {
           return [$request];
        }

	my $callback=shift;
	my @requests;
		
	#display usage statement if -h is present or no noderage is specified
	my $noderange = $request->{node}; #Should be arrayref
	my $command = $request->{command}->[0];
	my $extrargs = $request->{arg};
	my @exargs=($request->{arg});
	if (ref($extrargs)) {
		@exargs=@$extrargs;
	}
		
	my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
	if ($usage_string) {
		$callback->({data=>$usage_string});
		$request = {};
		return;
	}
		
	if (!$noderange) {
		$usage_string=xCAT::Usage->getUsage($command);
		$callback->({data=>$usage_string});
		$request = {};
		return;
	}   

	# require SOAP::Lite for hpoa.pm so we can do it dynamically
	my $soapsupport = eval { require SOAP::Lite; };
	unless ($soapsupport) { #Still no SOAP::Lite module
      $callback->({error=>"SOAP::Lite perl module missing.  Install perl-SOAP-Lite before running HP blade commands.",errorcode=>[42]});
      return [];
	}
	require xCAT::hpoa;
		
	#get the MMs for the nodes for the nodes in order to figure out which service nodes to send the requests to
	my $mptab = xCAT::Table->new("mp");
	unless ($mptab) { 
		$callback->({data=>["Cannot open mp table"]});
		$request = {};
		return;
	}
	my %mpa_hash=();
	my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id']);
	if ($request->{command}->[0] eq "gethpbladecons") { #Can handle it here and now
		gethpbladecons($noderange,$callback);
		return ();
	}
		
		
	foreach my $node (@$noderange) {
		my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
		if (defined($ent->{mpa})) { push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;}
		else { 
			$callback->({data=>["no mpa defined for node $node"]});
			$request = {};
			return;
		}
		my $tempid;
		if (defined($ent->{id})) {
			#if the ide is defined, we need to see if there is a letter embedded in it. If there is,
			#then we need to convert the id to the correct slot
			$tempid = convertSlot($ent->{id});
			push @{$mpa_hash{$ent->{mpa}}{ids}}, $tempid;
		} else { 
			push @{$mpa_hash{$ent->{mpa}}{ids}}, ""; 
		}
	}
		
	# find service nodes for the MMs
	# build an individual request for each service node
	my $service  = "xcat";
	my @mms=keys(%mpa_hash);
	my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@mms, $service, "MN");
		
	# build each request for each service node
	foreach my $snkey (keys %$sn)
	{
		#print "snkey=$snkey\n";
		my $reqcopy = {%$request};
		$reqcopy->{'_xcatdest'} = $snkey;
		my $mms1=$sn->{$snkey};
		my @moreinfo=();
		my @nodes=();
		foreach (@$mms1) { 
			push @nodes, @{$mpa_hash{$_}{nodes}};
			push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
		}
		$reqcopy->{node} = \@nodes;
		#print "nodes=@nodes\n";
		$reqcopy->{moreinfo}=\@moreinfo;
		push @requests, $reqcopy;
	}
	return \@requests;
}
	
sub build_more_info{
	my $noderange=shift;
	my $callback=shift;
	my $mptab = xCAT::Table->new("mp");
	my @moreinfo=();
	unless ($mptab) { 
	$callback->({data=>["Cannot open mp table"]});
			return @moreinfo;
	}
	my %mpa_hash=();
	my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id']);
	foreach my $node (@$noderange) {
		my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
		if (defined($ent->{mpa})) { push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;}
		else { 
			$callback->({data=>["no mpa defined for node $node"]});
			return @moreinfo;;
		}
		if (defined($ent->{id})) { push @{$mpa_hash{$ent->{mpa}}{ids}}, $ent->{id};}
		else { push @{$mpa_hash{$ent->{mpa}}{ids}}, "";} 
	}
	
	foreach (keys %mpa_hash) {
		push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
			
	}
		
	return \@moreinfo;
}

sub handle_depend {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	my $dp = shift;
	my %node = ();
	my $dep = @$dp[0];
	my $dep_hash = @$dp[1];
	
	# send all dependencies (along w/ those dependent on nothing)
	# build moreinfo for dependencies 
	my %mpa_hash = ();
	my @moreinfo=();
	my $reqcopy = {%$request};
	my @nodes=();
	
	foreach my $node (keys %$dep) {
		my $mpa = @{$dep_hash->{$node}}[0];
		push @{$mpa_hash{$mpa}{nodes}},$node;
		push @{$mpa_hash{$mpa}{ids}},  @{$dep_hash->{$node}}[1];
	}
	foreach (keys %mpa_hash) {
		push @nodes, @{$mpa_hash{$_}{nodes}};
		push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
	}
	$reqcopy->{node} = \@nodes;
	$reqcopy->{moreinfo}=\@moreinfo;
	process_request($reqcopy,$callback,$doreq,1); 
	
	my $start = Time::HiRes::gettimeofday();
    
	# build list of dependent nodes w/delays
	while(my ($name,$h) = each(%$dep) ) {
		foreach ( keys %$h ) { 
			if ( $h->{$_} =~ /(^\d+$)/ ) {
				$node{$_} = $1/1000.0;
			}
		}
	}
	# send each dependent node as its delay expires
	while (%node) {
		my @noderange = ();
		my $delay = 0.1;
		my $elapsed = Time::HiRes::gettimeofday()-$start;
		
		# sort in ascending delay order
		foreach (sort {$node{$a} <=> $node{$b}} keys %node) {
			if ($elapsed < $node{$_}) {
				$delay = $node{$_}-$elapsed;
				last;
			}
			push @noderange,$_;
			delete $node{$_};
		}
		if (@noderange) {
			%mpa_hash=();
			foreach my $node (@noderange) {
				my $mpa = @{$dep_hash->{$node}}[0];
				push @{$mpa_hash{$mpa}{nodes}},$node;
				push @{$mpa_hash{$mpa}{ids}},  @{$dep_hash->{$node}}[1];
			}
			
			@moreinfo=();
			$reqcopy = {%$request};
			@nodes=();
			
			foreach (keys %mpa_hash) {
				push @nodes, @{$mpa_hash{$_}{nodes}};
				push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
			}
			$reqcopy->{node} = \@nodes;
			$reqcopy->{moreinfo}=\@moreinfo;
			
			# clear global hash variable
			%oahash = ();
			process_request($reqcopy,$callback,$doreq,1);
		}
		# millisecond sleep
		Time::HiRes::sleep($delay);
	}
	return 0;
}

sub build_depend {
	my $noderange = shift;
	my $exargs = shift;
	my $depstab  = xCAT::Table->new('deps');
	my $mptab    = xCAT::Table->new('mp');
	my %dp    = ();
	my %no_dp = ();
	my %mpa_hash;
	
	if (!defined($depstab)) {
		return([\%dp]);
	}
	unless ($mptab) {
		return("Cannot open mp table");
	}
	
	my $depset = $depstab->getNodesAttribs($noderange,[qw(nodedep msdelay cmd)]);
	foreach my $node (@$noderange) {
		my $delay = 0;
		my $dep;
		
		my @ent = @{$depset->{$node}}; #$depstab->getNodeAttribs($node,[qw(nodedep msdelay cmd)]);
		foreach my $h ( @ent ) {
			if ( grep(/^@$exargs[0]$/, split /,/, $h->{cmd} )) {
				if (exists($h->{nodedep})) { $dep=$h->{nodedep}; }
				if (exists($h->{msdelay})) { $delay=$h->{msdelay}; }
				last;
			}
		}
		if (!defined($dep)) {
			$no_dp{$node} = 1;
		}
		else {
			foreach my $n (split /,/,$dep ) {
				if ( !grep( /^$n$/, @$noderange )) {
					return( "Missing dependency on command-line: $node -> $n" );
				} elsif ( $n eq $node ) {
					next;  # ignore multiple levels
				}
				$dp{$n}{$node} = $delay;
			}
		}
	}
	# if there are dependencies, add any non-dependent nodes
	if (scalar(%dp)) {
		foreach (keys %no_dp) {
			if (!exists( $dp{$_} )) {
				$dp{$_}{$_} = -1;
			}
		}
		# build hash of all nodes in preprocess_request() format
		my @namelist = keys %dp;
		my $mphash = $mptab->getNodesAttribs(\@namelist,['mpa','id']);
		while(my ($name,$h) = each(%dp) ) {
			my $ent=$mphash->{$name}->[0]; #$mptab->getNodeAttribs($name,['mpa', 'id']);
			if (!defined($ent->{mpa})) {
				return("no mpa defined for node $name");
			}
			my $id = (defined($ent->{id})) ? $ent->{id} : "";
			push @{$mpa_hash{$name}},$ent->{mpa};
			push @{$mpa_hash{$name}},$id;
			
			@namelist = keys %$h;
			my $mpsubhash = $mptab->getNodesAttribs(\@namelist,['mpa','id']);
			foreach ( keys %$h ) {
				if ( $h->{$_} =~ /(^\d+$)/ ) {
					my $ent=$mpsubhash->{$_}->[0]; #$mptab->getNodeAttribs($_,['mpa', 'id']);
					if (!defined($ent->{mpa})) {
						return("no mpa defined for node $_");
					}
					my $id = (defined($ent->{id})) ? $ent->{id} : "";
					push @{$mpa_hash{$_}},$ent->{mpa};
					push @{$mpa_hash{$_}},$id;
				}
			}
		}
	}
	return( [\%dp,\%mpa_hash] );
}


sub process_request { 
	$SIG{INT} = $SIG{TERM} = sub { 
		foreach (keys %mm_comm_pids) {
			kill 2, $_;
		}
		exit 0;
	};
		
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;
	my $level = shift;
	my $noderange = $request->{node};
	my $command = $request->{command}->[0];
	my @exargs;
	unless ($command) {
		return; #Empty request
	}

	# require SOAP::Lite for hpoa.pm so we can do it dynamically
	my $soapsupport = eval { require SOAP::Lite; };
	unless ($soapsupport) { #Still no SOAP::Lite module
      $callback->({error=>"SOAP::Lite perl module missing.  Install perl-SOAP-Lite before running HP blade commands.",errorcode=>[42]});
      return [];
	}
	require xCAT::hpoa;

	if (ref($request->{arg})) {
		@exargs = @{$request->{arg}};
	} else {
		@exargs = ($request->{arg});
	}
		
	my $moreinfo;
	if ($request->{moreinfo}) { $moreinfo=$request->{moreinfo}; }
	else {  $moreinfo=build_more_info($noderange,$callback);} 
		
	if ($command eq "rpower" and grep(/^on|off|boot|reset|cycle$/, @exargs)) {
			
		if ( my ($index) = grep($exargs[$_]=~ /^--nodeps$/, 0..$#exargs )) {
			splice(@exargs, $index, 1);
		} else {
			# handles 1 level of dependencies only
			if (!defined($level)) {
				my $dep = build_depend($noderange,\@exargs);
				if ( ref($dep) ne 'ARRAY' ) {
					$callback->({data=>[$dep],errorcode=>1});
					return;
				}
				if (scalar(%{@$dep[0]})) {
					handle_depend( $request, $callback, $doreq, $dep );
					return 0;
				} 
			}
		}
	}
	# only 1 node when changing textid to something other than '*'
	if ($command eq "rspconfig" and grep(/^textid=[^*]/,@exargs)) {
		if ( @$noderange > 1 ) {
			$callback->({data=>["Single node required when changing textid"],
			errorcode=>1});
			return;
		}
	}
	my $bladeuser = 'USERID';
	my $bladepass = 'PASSW0RD';
	my $blademaxp = 64;
	#my $sitetab = xCAT::Table->new('site');
	my $mpatab = xCAT::Table->new('mpa');
	my $mptab = xCAT::Table->new('mp');
	my $tmp;
	#if ($sitetab) {
		#($tmp)=$sitetab->getAttribs({'key'=>'blademaxp'},'value');
                my @entries =  xCAT::TableUtils->get_site_attribute("blademaxp");
                my $t_entry = $entries[0];
		if (defined($t_entry)) { $blademaxp=$t_entry; }
	#}
	my $passtab = xCAT::Table->new('passwd');
	if ($passtab) {
		($tmp)=$passtab->getAttribs({'key'=>'blade'},'username','password');
		if (defined($tmp)) {
			$bladeuser = $tmp->{username};
			$bladepass = $tmp->{password};
		}
	}
	if ($request->{command}->[0] eq "findme") {
		my $mptab = xCAT::Table->new("mp");
		unless ($mptab) { return 2; }
		my @bladents = $mptab->getAllNodeAttribs([qw(node)]);
		my @blades;
		foreach (@bladents) {
			push @blades,$_->{node};
		}
		my %invreq;
		$invreq{node} = \@blades;
		$invreq{arg} = ['mac'];
		$invreq{command} = ['rinv'];
		my $mac;
		my $ip = $request->{'_xcat_clientip'};
		my $arptable;
                if ( -x "/usr/sbin/arp") {
                    $arptable = `/usr/sbin/arp -n`;
                }
                else{
                    $arptable = `/sbin/arp -n`;
                }
		my @arpents = split /\n/,$arptable;
		foreach  (@arpents) {
			if (m/^($ip)\s+\S+\s+(\S+)\s/) {
				$mac=$2;
				last;
			}
		}
		unless ($mac) { return };
			
		#Only refresh the the cache when the request permits and no useful answer
		if ($macmaptimestamp < (time() - 300)) { #after five minutes, invalidate cache
			%macmap = ();
		}
			
		unless ($request->{cacheonly}->[0] or $macmap{$mac} or $macmaptimestamp > (time() - 20)) { #do not refresh cache if requested not to, if it has an entry, or is recent
			%macmap = ();
			$macmaptimestamp=time();
			foreach (@{preprocess_request(\%invreq,\&fillresps)}) {
				%invreq = %$_;
				process_request(\%invreq,\&fillresps);
			}
		}
		unless ($macmap{$mac}) { 
			return 1; #failure
		}
		my $mactab = xCAT::Table->new('mac',-create=>1);
		$mactab->setNodeAttribs($macmap{$mac},{mac=>$mac});
		$mactab->close();
		#my %request = (
		#  command => ['makedhcp'],
		#  node => [$macmap{$mac}]
		#  );
		#$doreq->(\%request);
		$request->{command}=['discovered'];
		$request->{noderange} = [$macmap{$mac}];
		$doreq->($request);
		%{$request}=(); #Clear request. it is done
		undef $mactab;
		return 0;
	}
		
		
	my $children = 0;
	$SIG{CHLD} = sub { my $cpid; while ($cpid = waitpid(-1, WNOHANG) > 0) { delete $mm_comm_pids{$cpid}; $children--; } };
	my $inputs = new IO::Select;;
	foreach my $info (@$moreinfo) {
		$info=~/^\[(.*)\]\[(.*)\]\[(.*)\]/;
		my $mpa=$1;
		my @nodes=split(',', $2);
		my @ids=split(',', $3);
		#print "mpa=$mpa, nodes=@nodes, ids=@ids\n";
		my $user=$bladeuser;
		my $pass=$bladepass;
		my $ent;
		if (defined($mpatab)) {
			($ent)=$mpatab->getAttribs({'mpa'=>$mpa},'username','password');
			if (defined($ent->{password})) { $pass = $ent->{password}; }
			if (defined($ent->{username})) { $user = $ent->{username}; }
		}
		$oahash{$mpa}->{username} = $user;
		$oahash{$mpa}->{password} = $pass;
		for (my $i=0; $i<@nodes; $i++) {
			my $node=$nodes[$i];;
			my $nodeid=$ids[$i];
			$oahash{$mpa}->{nodes}->{$node}=$nodeid;

		
		}
	}
	my $sub_fds = new IO::Select;
	foreach $oa (sort (keys %oahash)) {
		while ($children > $blademaxp) { forward_data($callback,$sub_fds); }
		$children++;
		my $cfd;
		my $pfd;
		socketpair($pfd, $cfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
		$cfd->autoflush(1);
		$pfd->autoflush(1);
		my $cpid = xCAT::Utils->xfork;
		unless (defined($cpid)) { die "Fork error"; }
		unless ($cpid) {
			close($cfd);
			eval {
				doblade($pfd,$oa,\%oahash,$command,-args=>\@exargs);
				exit(0);
			};
			if ($@) { die "$@"; }
			die "blade plugin encountered a general error while communication with $oa";
		}
		$mm_comm_pids{$cpid} = 1;
		close ($pfd);
		$sub_fds->add($cfd);
	}
	while ($sub_fds->count > 0 or $children > 0) {
		forward_data($callback,$sub_fds);
	}
	while (forward_data($callback,$sub_fds)) {}
}
	
my $IMPORT_SSH_KEY_HEADER = '
<LOCFGVERSION="2.21"/>
<RIBCL VERSION="2.0">
<LOGIN USER_LOGIN="AdMiNnAmE" PASSWORD="PaSsWoRd">
<RIB_INFO MODE="write">
<IMPORT_SSH_KEY>
-----BEGIN SSH KEY-----
';

my $IMPORT_SSH_KEY_FOOTER = '
-----END SSH KEY-----
</IMPORT_SSH_KEY>
</RIB_INFO>
</LOGIN>
</RIBCL>';

my $MOD_NETWORK_SETTINGS_HEADER = '
<LOCFGVERSION="2.21"/>
<RIBCL VERSION="2.0">
<LOGIN USER_LOGIN="AdMiNnAmE" PASSWORD="PaSsWoRd">
<RIB_INFO MODE="write">
<MOD_NETWORK_SETTINGS>
';

my $MOD_NETWORK_SETTINGS_FOOTER = '
</MOD_NETWORK_SETTINGS>
</RIB_INFO>
<LOGIN>
</RIBCL>';

my $GET_NETWORK_SETTINGS = '
<LOCFGVERSION="2.21"/>
<RIBCL VERSION="2.0">
<LOGIN USER_LOGIN="AdMiNnAmE" PASSWORD="PaSsWoRd">
<RIB_INFO MODE="read">
<GET_NETWORK_SETTINGS/>
</RIB_INFO>
</LOGIN>
</RIBCL>';


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
	Net::SSLeay::connect($ssl) and die_if_ssl_error("ERROR: ssl connect");
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
	my $reply2return = "";
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
				$reply2return = "ERROR: STATUS: $1, MESSAGE: $2";
			}
		}
	}
	print "READ: $lastreply\n" if $globalDebug;
	if($lastreply =~ m/STATUS="(0x[0-9A-F]+)"[\s]+MESSAGE='(.*)'[\s]+\/>[\s]*(([\s]|.)*?)<\/RIBCL>/) {
		if($1 eq "0x0000") {
			#Sprint STDERR "$3\n" if $3;
		} else {
			$reply2return = "ERROR: STATUS: $1, MESSAGE: $2";
		}
	}
	
	closeSSLconnection($ssl);
	return $reply2return;
}

sub extractValue {
	my $inputString = shift;
	my $testString = shift;
	
	$testString = "<"."$testString"." VALUE=";
	
	my $start = index ($inputString, $testString) + length $testString;
	my $end = index $inputString, "\"", ($start + 1);
	return(substr($inputString, ($start + 1), ($end - $start - 1)));
}



sub iloconfig {
	
	my $oa=shift;
	my $user=shift;
	my $pass=shift;
	my $node=shift;
	my $nodeid=shift;
	my $parameter;
	my $value;
	my $assignment;
	my $returncode=0;
	my $textid=0;
	@cfgtext=();
	
	# Before we get going, lets get the info on the MP (iLO)
	$slot = convertSlot($nodeid);
	my $mpInfoResp = $hpoa->getBladeMpInfo("bayNumber"=>$slot);
	if($mpInfoResp->fault) {
		my $errorText ="Error getting MP info";
		next;
	}
	my $ipaddress = $mpInfoResp->result->{ipAddress};
	
	foreach $parameter (@_) {
		$assignment = 0;
		$value = undef;
		if ($parameter =~ /=/) {
			$assignment = 1;
			($parameter,$value) = split /=/,$parameter,2;
		}
		if ($parameter =~ /^sshcfg$/) {
			my $fname = "/root/.ssh/id_dsa.pub";
			if ( ! -s $fname ) {
				# Key file specified does not exist. Error!
				push @cfgtext,"rspconfig:key file does not exist";
				next;
			}
			open (KEY, "$fname");
			my $key = readline(KEY);
			close(KEY);
			my $script = "$IMPORT_SSH_KEY_HEADER"."$key"."$IMPORT_SSH_KEY_FOOTER";
			$script =~ s/AdMiNnAmE/$user/;
			$script =~ s/PaSsWoRd/$pass/;
			my $reply = sendScript($ipaddress, $script);
			push @cfgtext,$reply;
			next;
		}
		if ($parameter =~ /^network$/) {
			if($value) {
				# If value is set, then the user wans us to set these values
				my ($newip,$newhostname,$newgateway,$newmask) = split /,/,$value;
				my $script = "$MOD_NETWORK_SETTINGS_HEADER";
				$script = $script."<IP_ADDRESS VALUE=\"$newip\"\/>" if ($newip);
				$script = $script."<GATEWAY_IP_ADDRESS VALUE=\"$newgateway\"\/>" if($newgateway);
				$script = $script."<SUBNET_MASK VALUE=\"$newmask\"\/>" if($newmask);
				$script = $script."$MOD_NETWORK_SETTINGS_FOOTER";
				$script =~ s/AdMiNnAmE/$user/;
				$script =~ s/PaSsWoRd/$pass/;
				my $reply = sendScript($ipaddress, $script);
				if ($newip)     { push @cfgtext,"iLO IP: $newip"; }
				if ($newgateway){ push @cfgtext,"Gateway: $newgateway"; }
				if ($newmask)   { push @cfgtext,"Subnet Mask: $newmask"; }
				push @cfgtext, $reply;
				
			} else {
				my $script = "$GET_NETWORK_SETTINGS";
				$script =~ s/AdMiNnAmE/$user/;
				$script =~ s/PaSsWoRd/$pass/;
				my $reply = sendScript($ipaddress, $script);
				my $readipaddress = extractValue($reply, "IP_ADDRESS");
				my $gateway = extractValue($reply, "GATEWAY_IP_ADDRESS");
				my $netmask = extractValue($reply, "SUBNET_MASK");
				push @cfgtext,"iLO IP: $readipaddress";
				push @cfgtext, "Gateway: $gateway";
				push @cfgtext, "Subnet mask: $netmask";
				push @cfgtext, $reply;
			}
		}
	}
	return 0, @cfgtext;
}
			
sub getmacs
{
	(my $code,my @macs)=inv('mac');
	my $mkey;
	my $nic2Find;
	my $nrtab = xCAT::Table->new('noderes');
	if ($nrtab) {
		my $nent = $nrtab->getNodeAttribs($curn,['primarynic','installnic']);
		if ($nent) {
			if (defined $nent->{installnic}) { #Prefer the install nic
				$mkey="installnic";
			} elsif (defined $nent->{primarynic}) { #see if primary nic was set
				$mkey="primarynic";
			}
			$nic2Find = $nent->{$mkey};
		}
	}
	# We now have the nic2Find, so we need to convert this to the NIC format
	# Strip away the "eth"
	my $interface = $nic2Find;
	$nic2Find =~ s/eth//;
	my $numberPxeNic = $nic2Find + 1;
	my $pxeNic = "NIC ".$numberPxeNic;
	
	if ($code==0) {
		my $mac;
		my @allmacs;
		foreach my $macEntry (@macs) {
			if ($macEntry =~ /MAC ADDRESS $pxeNic/) {
				$mac = $macEntry;
				$mac =~ s/MAC ADDRESS $pxeNic: //;
				$mac = lc $mac;
				last;
			}
		}
		if (! $mac) {
			return 1,"Unable to retrieve MAC address for interface $pxeNic from OnBoard Administrator";
		} 
				
		my $mactab = xCAT::Table->new('mac',-create=>1);
		$mactab->setNodeAttribs($curn,{mac=>$mac},{interface=>$interface});
		$mactab->close;
		return 0,":mac.mac set to $mac";
	} else {
		return $code,$macs[0];
	}
}
	
sub inv {
	my @invitems;
	my @output;
	foreach (@_) {
		push @invitems, split( /,/,$_);
	}
	my $item;
	unless(scalar(@invitems)) {
		@invitems = ("all");
	}
	
	# Before going off to handle the items, issue a getBladeInfo, getBladeMpInfo, and getOaInfo 
	my $getBladeInfoResult = $hpoa->getBladeInfo("bayNumber" => $slot);
	if($getBladeInfoResult->fault) {
		return(1, "getBladeInfo on node $curn failed");
	}
	my $getBladeMpInfoResult = $hpoa->getBladeMpInfo("bayNumber" => $slot);
	if($getBladeMpInfoResult->fault) {
		return(1, "getBladeMpInfo on node $curn fault");
	}
	my $getOaInfoResult = $hpoa->getOaInfo("bayNumber" => $activeOABay);
	if($getOaInfoResult->fault) {
		my $errHash = $getOaInfoResult->fault;
		return(1, "getOaInfo failed");
	}
		
	while (my $item = shift @invitems) {
		if($item =~ /^all/) {
			push @invitems,(qw(mtm serial mac firm));
			next;
		}
			
		if($item =~ /^firm/) {
			push @invitems,(qw(bladerom mprom oarom));
		}	
		if($item =~ /^bladerom/)  {
			push @output,"BladeFW: ". $getBladeInfoResult->result->{romVersion};
		}
		if($item =~ /^mprom/) {
			push @output, "iLOFW: ". $getBladeMpInfoResult->result->{fwVersion};
		}
		if($item =~ /~oarom/) {
			push @output, "OA FW: ". $getOaInfoResult->result->{fwVersion};
		}
					
		if($item =~ /^model/ or $item =~ /^mtm/ ) {
			push @output,"Machine Type/Model: ". $getBladeInfoResult->result->{partNumber};
		}
		if($item =~ /^serial/) {
			push @output, "Serial Number: ". $getBladeInfoResult->result->{serialNumber};
		}
		if($item =~ /^mac/) {
			my $numberOfNics = $getBladeInfoResult->result->{numberOfNics};
			for (my $i = 0; $i < $numberOfNics; $i++) {
				my $mac = $getBladeInfoResult->result->{nics}->{bladeNicInfo}[$i]->{macAddress};
				my $port = $getBladeInfoResult->result->{nics}->{bladeNicInfo}[$i]->{port};
				push @output, "MAC ADDRESS ".$port.": ".$mac;
				#push@output, "MAC Address ".($_+1).": ".$getBladeInfoResult->result->{nics}->{bladeNicInfo}[$i]->{macAddress};
			}
		}
	}
	return(0, @output);
}


sub CtoF {
	my $Ctemp = shift;
	return((($Ctemp * 9) / 5) + 32);
}

my %chassiswidevitals;
sub vitals {
	my @output;
	my $tmp;
	my @vitems;
	
	if ( $#_ == 0 && $_[0] eq '' ) { pop @_; push @_,"all" }	#-- default is all if no argument given
	
	if ( defined $slot and $slot > 0 ) { 	#-- blade query
		foreach (@_) {
			if ($_ eq 'all') {
				# push @vitems,qw(temp voltage wattage summary fan);
				push @vitems,qw(cpu_temp memory_temp system_temp ambient_temp summary fanspeed);
				push @vitems,qw(led power);;
			} elsif ($_ =~ '^led') {
				push @vitems,qw(led);
			} else {
				push @vitems,split( /,/,$_);
			}
		}
	} else {		#-- chassis query
		foreach (@_) {
			if ($_ eq 'all') {
				# push @vitems,qw(voltage wattage power summary);
				push @vitems,qw(cpu_temp memory_temp system_temp ambient_temp summary fanspeed);
				# push @vitems,qw(errorled beaconled infoled templed);
				push @vitems,qw(led power);
			} elsif ($_ =~ '^led') {
				push @vitems,qw(led);
			} elsif ($_ =~ '^cool') {
				push @vitems,qw(fanspeed);
			} elsif ($_ =~ '^temp') {
				push @vitems,qw(ambient_temp);
			} else {
				push @vitems,split( /,/,$_);
			}
		}
	}

	my @vitals;
	if ( defined $slot and $slot > 0) {	#-- querying some blade
		if (grep /temp/, @vitems) {
			my $tempResponse = $hpoa->getBladeThermalInfoArray("bayNumber" => $slot);

			if($tempResponse->fault) {
				push @output, "Request to get Temperature info on slot $slot failed";
			}
			elsif (! $tempResponse->result) {
				# If is the case then the temperature data is not yet available.
				push @output, "Temperature data not available.";
			} else {
				# We have data so go process it....
				my @tempdata =  $tempResponse->result->{bladeThermalInfo};
				my $lastElement = $tempResponse->result->{bladeThermalInfo}[-1]->{sensorNumber};
				if(grep /cpu_temp/, @vitems) {
					my $index = -1;
					do {
						$index++;
						if(grep /CPU/, $tempResponse->result->{bladeThermalInfo}[$index]->{description}) {
							my $Ctemp = $tempResponse->result->{bladeThermalInfo}[$index]->{temperatureC};
							my $desc = $tempResponse->result->{bladeThermalInfo}[$index]->{description};
							my $Ftemp = CtoF($Ctemp);
							push @output , "$desc Temperature: $Ctemp C \( $Ftemp F \)";
						}
					} until $tempResponse->result->{bladeThermalInfo}[$index]->{sensorNumber} eq $lastElement;
				}
				if(grep /memory_temp/, @vitems) {
					my $index = -1;
					do {
						$index++;
						if(grep /Memory/, $tempResponse->result->{bladeThermalInfo}[$index]->{description}) {
							my $Ctemp = $tempResponse->result->{bladeThermalInfo}[$index]->{temperatureC};
							my $desc = $tempResponse->result->{bladeThermalInfo}[$index]->{description};
							my $Ftemp = CtoF($Ctemp);
							push @output , "$desc Temperature: $Ctemp C \( $Ftemp F \)";
						}
					} until $tempResponse->result->{bladeThermalInfo}[$index]->{sensorNumber} eq $lastElement;
				}
				if(grep /system_temp/, @vitems) {
					my $index = -1;
					do {
						$index++;
						if(grep /System/, $tempResponse->result->{bladeThermalInfo}[$index]->{description}) {
							my $Ctemp = $tempResponse->result->{bladeThermalInfo}[$index]->{temperatureC};
							my $desc = $tempResponse->result->{bladeThermalInfo}[$index]->{description};
							my $Ftemp = CtoF($Ctemp);
							push @output , "$desc Temperature: $Ctemp C \( $Ftemp F \)";
						}
					} until $tempResponse->result->{bladeThermalInfo}[$index]->{sensorNumber} eq $lastElement;
				}
				if(grep /ambient_temp/, @vitems) {
					my $index = -1;
					do {
						$index++;
						if(grep /Ambient/, $tempResponse->result->{bladeThermalInfo}[$index]->{description}) {
							my $Ctemp = $tempResponse->result->{bladeThermalInfo}[$index]->{temperatureC};
							my $desc = $tempResponse->result->{bladeThermalInfo}[$index]->{description};
							my $Ftemp = CtoF($Ctemp);
							push @output , "$desc Temperature: $Ctemp C \( $Ftemp F \)";
						}
					} until $tempResponse->result->{bladeThermalInfo}[$index]->{sensorNumber} eq $lastElement;	
				}
			}
		}
		
		if(grep /fanspeed/, @vitems) {
			my $fanInfoResponse = $hpoa->getFanInfo("bayNumber" => $slot);
			if($fanInfoResponse->fault) {
				push @output, "Request to get Fan Info from slot $slot failed ";
			} elsif (! $fanInfoResponse->result ) {
				push @output, "No Fan Information";
			} else {
				my $fanStatus = $fanInfoResponse->result->{operationalStatus};
				my $fanMax = $fanInfoResponse->result->{maxFanSpeed};
				my $fanCur = $fanInfoResponse->result->{fanSpeed};
				my $fanPercent = ($fanCur / $fanMax) * 100;
				push @output, "Fan status: $fanStatus  Percent of max: $fanPercent\%";
			}
		}
		
		if(grep /led/, @vitems) {
			my $currstat = $getBladeStatusResponse->result->{uid};

			if ($currstat eq "UID_ON") {
				push @output, "Current UID Status On";
			} elsif ($currstat eq "UID_OFF") {
				push @output, "Current UID Status Off";
			} elsif ($currstat eq "UID_BLINK") {
				push @output, "Current UID Status Blinking";
			}
		}
		
		if(grep /power/, @vitems) {
			my $currPowerStat = $getBladeStatusResponse->result->{powered};
			if($currPowerStat eq "POWER_ON") {
				push @output , "Current Power Status On";
			} elsif ($currPowerStat eq "POWER_OFF") {
				push @output,"Current Power Status Off";
			}
		}
	}
	return(0, @output);
}

sub buildEventHash {
	my $logText = shift;
	my $eventLogFound = 0;
	my $eventFound = 0;
	my $eventNumber = 0;

	my @lines = split /^/, $logText;
	foreach my $line (@lines){
		if(! $eventLogFound ) {
			if(! $line =~ m/EVENT_LOG/) {
				next;
			} elsif ($line =~ m/EVENT_LOG/) {
				$eventLogFound = 1;
				next;
			}
		}
		
		if(! $eventFound && $line =~ m/\<EVENT/) {
			$eventFound = 1;
			next;
		} elsif ($eventFound && $line =~ m/\/\>/) {
			$eventNumber++;
			$eventFound = 0;
			next;
		}
		
		# We have a good line. Need to split it up and build the hash.
		my ($desc, $value) = split /=/, $line;
		for ($desc) {
			s/^\s+//;
			s/\s+$//;
			s/\"//g;
			s/\\n//;
		}
		for ($value) {
			s/^\s+//;
			s/\"//g;
			s/\s+$//;
			s/\\n//;
		}
		$eventHash->{event}->{$eventNumber}->{$desc} = $value;
		next;
	}
	return $eventNumber;
}

sub eventlog {
	my $subcommand= shift;
	
	my @output;
 
	$subcommand = "all" if $subcommand eq "";
 
	if ($subcommand eq "all" or $subcommand =~ /\d+/) {
		my $mpEventLogResponse = $hpoa->getBladeMpEventLog("bayNumber"=>$slot, "maxsize"=>640000);
		if($mpEventLogResponse->fault) {
			return(1, "Attempt to retrieve Event Log faulted");
		}
		my $logText = $mpEventLogResponse->result->{logContents};
		my $numEvents = buildEventHash($logText);

		my $recCount = 0;
		$eventHash->{'event'} = {
			map {
				$recCount++ => $_->[1]
			} sort {
				$a->[0] <=> $b->[0]
			} map {
				(defined $_->{LAST_UPDATE} && $_->{LAST_UPDATE} ne '[NOT SET]')
				? [ &extractDate($_->{LAST_UPDATE}), $_]
				: [ $_->{SELID}, $_ ]
			} map {
				$eventHash->{'event'}{$_}{SELID} = $_;
				$eventHash->{'event'}{$_};
			} grep {
				defined $eventHash->{'event'}{$_}
			} keys %{$eventHash->{'event'}}
		};
		
		my $limitEvents = ($subcommand eq "all" ? $recCount : $subcommand);

		for (my $index = 0; $index < $limitEvents; $index++) {
			--$recCount;

			my $class = $eventHash->{event}->{$recCount}->{CLASS};
			my $severity = $eventHash->{event}->{$recCount}->{SEVERITY};
			my $dateTime = $eventHash->{event}->{$recCount}->{LAST_UPDATE};
			my $desc = $eventHash->{event}->{$recCount}->{DESCRIPTION};
			unshift @output,"$class $severity:$dateTime $desc";
		}
		return(0, @output);
	} elsif ($subcommand eq "clear") {
		return(1, "Command not supported");
	} else {
		return(1, "Command '$subcommand' not supported");
	}
}
			

sub rscan {
	my $args = shift;
	my @values;
	my $result;
	my %opt;
	
	@ARGV = @$args;
	$Getopt::Long::ignorecase = 0;
	Getopt::Long::Configure("bundling");
	
	local *usage = sub {
		my $usage_string=xCAT::Usage->getUsage("rscan");
		return( join('',($_[0],$usage_string)));
	};
	
	if ( !GetOptions(\%opt,qw(V|Verbose w x z))){
		return(1,usage());
	}
	if ( defined($ARGV[0]) ) {
		return(1,usage("Invalid argument: @ARGV\n"));
	}
	if (exists($opt{x}) and exists($opt{z})) {
		return(1,usage("-x and -z are mutually exclusive\n"));
	} 

	my $encInfo = $hpoa->getEnclosureInfo();
	if( $encInfo->fault) {
		return(1, "Attempt tp get enclosure information has failed");
	}
			
	my $numBays = $encInfo->result->{bladeBays};
	my $calcBladeBays = $numBays * 3;  # Need to worry aboyt casmir blades
			
	my $encName = $encInfo->result->{enclosureName};
	my $enctype = $encInfo->result->{name};
	my $encmodel = $encInfo->result->{partNumber};
	my $encserial = $encInfo->result->{serialNumber};
	
	push @values,join(",","hpoa",$encName,0,"$enctype-$encmodel",$encserial,$oa);
	my $max = length($encName);
	
	for( my $i = 1; $i <= $calcBladeBays; $i++) {
		my $bayInfo = $hpoa->getBladeInfo("bayNumber"=>$i);
		if($bayInfo->fault) {
			return(1, "Attempt to get blade info from bay $i has failed");
		}
		if($bayInfo->result->{presence} eq "ABSENT"  ) {
			# no blade in the bya
			next;
		}
		
		my $name = $bayInfo->result->{serverName};
		my $bayNum = $i;
		my $type = $bayInfo->result->{bladeType};
		my $model = $bayInfo->result->{name};
		my $serial = $bayInfo->result->{serialNumber};
			
		push @values, join (",", "hpblade", $name, $bayNum, "$type-$model", $serial, "");
	}
	
	my $format = sprintf "%%-%ds",($max+2);
	$rscan_header[1][1] = $format;
		
	if (exists($opt{x})) {
		$result = rscan_xml($oa,\@values); 
	} 
	elsif ( exists( $opt{z} )) {
		$result = rscan_stanza($oa,\@values); 
	} 
	else {
		foreach ( @rscan_header ) {
			$result .= sprintf @$_[1],@$_[0];
		}
		foreach (@values ){
			my @data = split /,/;
			my $i = 0;
				
			foreach (@rscan_header) {
				$result .= sprintf @$_[1],$data[$i++];
			}
		}
	}
	if (!exists( $opt{w})) {
		return(0,$result);
	}
	my @tabs = qw(mp nodehm nodelist);
	my %db   = ();
		
	foreach (@tabs) {
		$db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
		if ( !$db{$_} ) {
			return(1,"Error opening '$_'" );
		}
	}
	foreach (@values) {
		my @data = split /,/;
		my $name = $data[1];
			
		my ($k1,$u1);
		$k1->{node} = $name;
		$u1->{mpa}  = $oa;
		$u1->{id}   = $data[2];
		$db{mp}->setAttribs($k1,$u1);
		$db{mp}{commit} = 1;
			
		my ($k2,$u2);
		$k2->{node} = $name;
		$u2->{mgt}  = "hpblade";
		$db{nodehm}->setAttribs($k2,$u2);
		$db{nodehm}{commit} = 1;
			
		my ($k3,$u3);
		$k3->{node}   = $name;
		$u3->{groups} = "blade,all";
		$db{nodelist}->setAttribs($k3,$u3);
		$db{nodelist}{commit} = 1;
	}
	foreach ( @tabs ) {
		if ( exists( $db{$_}{commit} )) {
			$db{$_}->commit;
		}
	}
	return (0,$result);
}
	
sub rscan_xml {
		
	my $mpa = shift;
	my $values = shift;
	my $xml;
		
	foreach (@$values) {
		my @data = split /,/;
		my $i = 0;
			
		my $href = {
			Node => { }
		};
		foreach ( @rscan_attribs ) {
			my $d = $data[$i++];
			my $type = $data[0];
				
			if ( /^name$/ ) {
				next;
			} elsif ( /^nodetype$/ ) {
				$d = $type;
			} elsif ( /^groups$/ ) {
				$d = "$type,all";
			} elsif ( /^mgt$/ ) {
				$d = "blade";
			} elsif ( /^mpa$/ ) {
				$d = $mpa;
			}
			$href->{Node}->{$_} = $d;
		}
		$xml.= XMLout($href,NoAttr=>1,KeyAttr=>[],RootName=>undef);
	}
	return( $xml );
}
	
sub rscan_stanza {
		
	my $mpa = shift;
	my $values = shift;
	my $result;
		
	foreach (@$values) {
		my @data = split /,/;
		my $i = 0; 
		my $type = $data[0];
		$result .= "$data[1]:\n\tobjtype=node\n";
			
		foreach ( @rscan_attribs ) {
			my $d = $data[$i++];
				
			if ( /^name$/ ) {
				next; 
			} elsif ( /^nodetype$/ ) {
				$d = $type;
			} elsif ( /^groups$/ ) {
				$d = "$type,all";
			} elsif ( /^mgt$/ ) {
				$d = "blade"; 
			} elsif ( /^mpa$/ ) {
				$d = $mpa;
			}
			$result .= "\t$_=$d\n";
		}
	}
	return( $result );
}
	
	
	
					
sub beacon {
	my $subcommand = shift;
	
	if($subcommand eq "stat" ) {
		my $currstat = $getBladeStatusResponse->result->{uid};
		if ($currstat eq "UID_ON") {
			return(0, "on");
		} elsif ($currstat eq "UID_OFF") {
			return(0, "off");
		} elsif ($currstat eq "UID_BLINK") {
			return(0, "blink");
		}
	}
	my $response;
	if($subcommand eq "on") {
		$response =$hpoa->setBladeUid('bayNumber' => $slot, 'uid' => "UID_CMD_ON");
		if($response->fault) {
			my $errHash = $response->fault;
			my $result = $response->oaErrorText;
			print "result is $result \n";
			return("1", "Uid On failed");
		} else {
			return("0", "");
		}
	} elsif ($subcommand eq "off") {
		$response = $hpoa->setBladeUid('bayNumber' => $slot ,'uid' => "UID_CMD_OFF");
		if($response->fault) {
			my $errHash = $response->fault;
			my $result = $response->oaErrorText;
			print "result is $result \n";
			return("1", "Uid Off failed");
		} else {
			return("0", "");
		}
	} elsif ($subcommand eq "blink") {
		$response = $hpoa->setBladeUid('bayNumber' => $slot, 'uid' => "UID_CMD_BLINK");
		if($response->fault) {
			my $errHash = $response->fault;
			my $result = $response->oaErrorText;
			print "result is $result \n";
			return("1", "Uid Blink failed");
		} else {
			return("0", "");
		}
	} else {
		return(1, "subcommand unsupported");
	}

	return(1, "subcommand unsupported");
}

sub bootseq {
	my @args=@_;
	my $data;
	my @order=();
	
	if ($args[0] eq "list" or $args[0] eq "stat") {
		# Before going off to handle the items, issue a getBladeInfo and getOaInfo 
		my $getBladeBootInfoResult = $hpoa->getBladeBootInfo("bayNumber"=> $slot);
		if($getBladeBootInfoResult->fault) {
			return(1, "getBladeBootInfo on node $curn failed");
		}
		# Go through the the IPL Array from the last call to GetBladeStatus
		my $numberOfIpls = $getBladeBootInfoResult->result->{numberOfIpls};
		foreach (my $i = 0; $i < $numberOfIpls; $i++) { 
			foreach (my $j = 0; $j <= 7; $j++) {
				if($getBladeBootInfoResult->result->{ipls}->{ipl}[$j]->{bootPriority} eq ($i + 1)) {
					push(@order, $getBladeBootInfoResult->result->{ipls}->{ipl}[$j]->{iplDevice});
					last;
				}
			}	
		}
					
		return (0, lc join(',',@order));
	} else {
		foreach (@args) {
			my @neworder=(split /,/,$_);
			push @order,@neworder;
		}
		my $number=@order;
		if ($number > 5) {
			return (1,"Only five boot sequence entries allowed");
		}
		my $nonespecified=0;
		my $foundnic = 0;
		foreach (@order) {
			if(($bootnumbers{$_} > 4)) {
				if($foundnic == 1) {
					# only one nic allowed. error out
					return(1, "Only one Eth/Nic device permitted.");
				} else {
					$foundnic = 1;
				}
			}
			unless (defined($bootnumbers{$_})) { return (1,"Unsupported device $_"); }
			unless ($bootnumbers{$_}) { $nonespecified = 1; }
			if ($nonespecified and $bootnumbers{$_}) { return (1,"Error: cannot specify 'none' before a device"); }
		}
		unless ($bootnumbers{$order[0]}) {
			return (1,"Error: cannot specify 'none' as first device");
		}
		
		# Build array to be sent to the blade here
		my @ipl;
		my $i = 1;
		foreach my $dev (@order) {
			push @ipl, {"bootPriority"=>"$i", "iplDevice" => "$bootdevices{$bootnumbers{$order[$i - 1]}}"};
			$i++;
		}

		my $setiplResponse = $hpoa->setBladeIplBootPriority("bladeIplArray" => ['ipl', \@ipl, "" ], "bayNumber" => $slot);
		if($setiplResponse->fault) {
			my $errHash = $setiplResponse->fault;
			my $result = $setiplResponse->oaErrorText;
			print "result is $result \n";
			return(1, "Error on slot $slot setting ipl");
		}
		
		return bootseq('list');
	}
}

	
sub power {
	my $subcommand = shift;
	my $command2Send;
	my $currPowerStat;
	my $returnState;
	
	$returnState = "";
	$currPowerStat = $getBladeStatusResponse->result->{powered};
	
	if($subcommand eq "stat" || $subcommand eq "state") {
		if($currPowerStat eq "POWER_ON") {
			return(0, "on");
		} elsif ($currPowerStat eq "POWER_OFF") {
			return(0, "off");
		}
	}
	
	if ($subcommand eq "on") {
		if($currPowerStat eq "POWER_OFF") {
			$command2Send = "MOMENTARY_PRESS";
			$returnState = "on";
		} else {
			return(0, "on");
		}
	} elsif ($subcommand eq "off") {
		if($currPowerStat eq "POWER_ON") {
			$command2Send = "PRESS_AND_HOLD";
			$returnState = "off";
		} else {
			return(0, "off");
		}
	} elsif ($subcommand eq "reset") {
		$command2Send = "RESET";
	} elsif ($subcommand eq "cycle") {
		if($currPowerStat eq "POWER_ON") {
			power("off");
		}
		$command2Send = "MOMENTARY_PRESS";
	} elsif ($subcommand eq "boot") {
		if($currPowerStat eq "POWER_OFF") {
			$command2Send = "MOMENTARY_PRESS";
			$returnState = "off on";
		} else {
			$command2Send = "COLD_BOOT";
			$returnState = "on reset";
		}
	} elsif ($subcommand eq "softoff") {
		if($currPowerStat eq "POWER_ON") {
			$command2Send = "MOMENTARY_PRESS";
		}
	}
		
	#If we got here with a command to send, do it, otherwise just return
	if($command2Send) {
		my $pwrResult = $hpoa->setBladePower('bayNumber' => $slot, 'power' => $command2Send);
		if($pwrResult->fault) {
			return(1, "Node $curn - Power command failed");
		}
		return(0, $returnState);
	}
}
	
		

sub bladecmd {
	my $oa = shift;
	my $node = shift;
	$slot = shift;
	my $user = shift;
	my $pass = shift;
	my $command = shift;
	my @args = @_;
	my $error;
	if ($slot > 0) {
		$getBladeStatusResponse = $hpoa->getBladeStatus('bayNumber' => $slot);
		if($getBladeStatusResponse->fault) {
			my $errHash = $getBladeStatusResponse->fault;
			my $result = $getBladeStatusResponse->oaErrorText;
		}
		if ($getBladeStatusResponse->result->{presence} ne "PRESENT") {
			return (1, "Target bay empty");
		}
	}
		
	if ($command eq "rbeacon") {
		return beacon(@args);
	} elsif ($command eq "rpower") {
		return power(@args);
	} elsif ($command eq "rvitals") {
		return vitals(@args);
	} elsif ($command =~ /r[ms]preset/) {
		return resetmp(@args);
	} elsif ($command eq "rspconfig") {
		return iloconfig($oa,$user,$pass,$node,$slot,@args);
	} elsif ($command eq "rbootseq") {
		return bootseq(@args);
	} elsif ($command eq "switchblade") {
		return switchblade(@args);
	} elsif ($command eq "getmacs") {
		return getmacs(@args);
	} elsif ($command eq "rinv") {
		return inv(@args);
	} elsif ($command eq "reventlog") {
		return eventlog(@args);
	} elsif ($command eq "rscan") {
		return rscan(\@args);
	}
		
	return (1,"$command not a supported command by blade method");
}


sub forward_data {
	my $callback = shift;
	my $fds = shift;
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
				$callback->($_);
			}
		} else {
			$fds->remove($rfh);
			close($rfh);
		}
	}
	yield; #Try to avoid useless iterations as much as possible
	return $rc;
}

	
	
sub doblade {
	my $out = shift;
	$oa = shift;
	my $oahash = shift;
	my $command = shift;
	my %namedargs = @_;
	my @exargs = @{$namedargs{-args}};
	my $node;
	my $args = \@exargs;
	
	$hpoa = oaLogin($oa);
		
	# We are now logged into the OA and have a pointer to the OA session. Process
	# the command.
	
	#get new node status
	my %nodestat=();
	my $check=0;
	my $nsh={};
		
	foreach $node (sort (keys %{$oahash->{$oa}->{nodes}})) {
		$curn = $node;
		my ($rc, @output) = bladecmd($oa, $node, $oahash->{$oa}->{nodes}->{$node}, $oahash->{$oa}->{username}, $oahash->{$oa}->{password}, $command, @$args);
		
		foreach(@output) {
			my %output;
				
			if ( $command eq "rscan" ) { 
				$output{errorcode}=$rc;
				$output{data} = [$_];
			}
			else {
				(my $desc,my $text) = split (/:/,$_,2);
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
				$output{node}->[0]->{errorcode} = $rc;
				$output{node}->[0]->{name}->[0]=$node;
				$output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
			}
			print $out freeze([\%output]);
			print $out "\nENDOFFREEZE6sK4ci\n";
			yield;
			waitforack($out);
		}
		yield;
	}
		
	#update the node status to the nodelist.status table
	if ($check) {
		my %node_status=();
			
		#foreach (keys %nodestat) { print "node=$_,status=" . $nodestat{$_} ."\n"; } #Ling:remove
			
		foreach my $node (keys %nodestat) {
			my $stat=$nodestat{$node};
			if ($stat eq "no-op") { next; }
			if (exists($node_status{$stat})) {
				my $pa=$node_status{$stat};
				push(@$pa, $node);
			}
			else {
				$node_status{$stat}=[$node];
			}
		}
		xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1);
			
	}
	#my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
	#print $out $msgtoparent; #$node.": $_\n";
}

sub extractDate {
	use Time::Local;
	my $date = shift;

	return 0 unless $date =~ m/(\d{1,2})\/(\d{1,2})\/(\d{4}) (\d{1,2}):(\d{1,2})/;

	return timegm(0,$5,$4,$2,$1,$3);
}

1;
