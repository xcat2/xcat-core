package xCAT_plugin::slpdiscover;
use strict;
use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SLP;
use xCAT::MacMap;
my $defaultbladeuser;
my $defaultbladepass;
my $mpahash;

sub handled_commands {
	return {
		slpdiscover => "slpdiscover",
	};
};

my $callback;
my $docmd;
my %ip4neigh;
my %ip6neigh;
my %searchmacs;
my %researchmacs;
my $macmap;
sub get_mac_for_addr {
	my $neigh;
	my $addr = shift;
	if ($addr =~ /:/) {
		get_ipv6_neighbors();
		return $ip6neigh{$addr};
	} else {
		get_ipv4_neighbors();
		return $ip4neigh{$addr};
	}
}
sub get_ipv4_neighbors {
	#TODO: something less 'hacky'
	my @ipdata = `ip -4 neigh`;
	%ip6neigh=();
	foreach (@ipdata) {
		if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
			$ip4neigh{$1}=$2;
		}
	}
}
sub get_ipv6_neighbors {
	#TODO: something less 'hacky'
	my @ipdata = `ip -6 neigh`;
	%ip6neigh=();
	foreach (@ipdata) {
		if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
			$ip6neigh{$1}=$2;
		}
	}
}
sub handle_new_slp_entity {
	my $data = shift;
	delete $data->{sockaddr}; #won't need it
	my $mac = get_mac_for_addr($data->{peername});
	unless ($mac) { return; }
	$searchmacs{$mac} = $data;
}

sub process_request {
	my $request = shift;
	$callback = shift;
	$docmd = shift;
	%searchmacs=();
	my $srvtypes = [ qw/service:management-hardware.IBM:chassis-management-module service:management-hardware.IBM:management-module/ ];
	xCAT::SLP::dodiscover(SrvTypes=>$srvtypes,Callback=>\&handle_new_slp_entity);
	$macmap = xCAT::MacMap->new();
	$macmap->refresh_table();
	my @toconfig;
	foreach my $mac (keys(%searchmacs)) {
		my $node = $macmap->find_mac($mac,1);
		unless ($node) {
			next;
		}
		my $data = $searchmacs{$mac};
		$data->{nodename}=$node;
		$data->{macaddress}=$mac;
		push @toconfig,$data;
	}
	my $mpatab=xCAT::Table->new("mpa",-create=>0);
	my @mpaentries;
	$mpahash={};
	if ($mpatab) {
		@mpaentries = $mpatab->getAllNodeAttribs([qw/mpa username password/]);
		foreach (@mpaentries) {
			$mpahash->{$_->{mpa}}=$_;
		}
	}
	my $passwdtab=xCAT::Table->new("passwd",-create=>0);
	$defaultbladeuser="USERID";
	$defaultbladepass="";
	if ($passwdtab) {
		my @ents = $passwdtab->getAttribs({key=>'blade'},'username','password');
		foreach (@ents) {
			if ($_->{username} eq "HMC") { next; }
			if ($_->{username}) { $defaultbladeuser=$_->{username}; }
			if ($_->{password}) { $defaultbladepass=$_->{password}; }
		}
	}
	my $mactab = xCAT::Table->new("mac");
	my @maclist = $mactab->getAllNodeAttribs([qw/node mac/]);
	my %machash;
	foreach (@maclist) {
		$machash{$_->{node}}=$_->{mac};
	}
		

	
	my $macupdatehash;
	foreach my $data (@toconfig) {
		my $mac = $data->{macaddress};
		my $nodename = $data->{nodename};
		my $addr = $data->{peername}; #todo, use sockaddr and remove the 427 port from it instead?
		if ($addr =~ /^fe80/) { #Link local address requires scope index
			$addr .= "%".$data->{scopeid};
		}
		if ($machash{$nodename} =~ /$mac/) { #ignore prospects already known to mac table
			next;
		}
		sendmsg(":Found ".$nodename." which seems to be ".$data->{SrvType}." at address $addr",$callback);
		if ($data->{SrvType} eq "service:management-hardware.IBM:chassis-management-module") {
			unless (do_blade_setup($data,curraddr=>$addr)) {
				next;
			}
		}
	}
}

sub do_blade_setup {
	my $data = shift;
	my %args = @_;
	my $addr = $args{curraddr};
	my $nodename = $data->{nodename};
	my $localuser=$defaultbladeuser;
	my $localpass=$defaultbladepass;
	if ($mpahash->{$nodename}) {
		if ($mpahash->{$nodename}->{username}) {
			$localuser = $mpahash->{$nodename}->[0]->{username};
		}
		if ($mpahash->{$nodename}->{password}) {
			$localuser = $mpahash->{$nodename}->[0]->{password};
		}
	}
	if (not $localpass or $localpass eq "PASSW0RD") {
		sendmsg([1,":Password for blade must be specified in either mpa or passwd tables, and it must not be PASSW0RD"],$callback,$nodename);
		return 0;
	}
	require xCAT_plugin::blade;
	my @cmds = qw/snmpcfg=enable sshcfg=enable initnetwork=*/;
	my $result = xCAT_plugin::blade::clicmds(
						 $nodename,
						 $localuser,
						 $localpass,
						 $nodename,
						 0,
						 curraddr=>$addr,
						 defaultcfg=>1,
						 cmds=>\@cmds );
	if ($result) {
		if ($result->[0]) {
			sendmsg([$result->[0],$result->[2]],$callback,$nodename);
		}
	}
}
1;
