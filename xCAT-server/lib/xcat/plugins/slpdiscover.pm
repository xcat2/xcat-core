package xCAT_plugin::slpdiscover;
use strict;
use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SLP;
use xCAT::MacMap;

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
		push @toconfig,$data;
	}
	foreach my $data (@toconfig) {
		sendmsg(":Found ".$data->{nodename}." which seems to be ".$data->{SrvType}." at address ".$data->{peername}." with scope index of ".$data->{scopeid},$callback);
	}
}

1;
