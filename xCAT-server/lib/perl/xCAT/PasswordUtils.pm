package xCAT::PasswordUtils;
my $ipmiuser = "USERID"; # default username to apply if nothing specified
my $ipmipass = "PASSW0RD"; # default password to apply if nothing specified
my $bladeuser = "USERID"; # default username to apply if nothing specified
my $bladepass = "PASSW0RD"; # default password to apply if nothing specified
sub getIPMIAuth {
	my %args = @_;
	my $noderange = $args{noderange};
	my $ipmihash = $args{ipmihash};
	my $mphash = $args{mphash};
        my $tmp;
	my %authmap;
        unless ($ipmihash) { #in the event that calling code does not pass us a prefetched set of values, pull it ourselves
		my $ipmitab = xCAT::Table->new('ipmi',-create=>0);
		if ($ipmitab) { $ipmihash = $ipmitab->getNodesAttribs($noderange,['username','password']); }
	}
        unless ($mphash) { 
		my $mptab = xCAT::Table->new('mp',-create=>0);
		if ($mptab) { $mphash = $mptab->getNodesAttribs($noderange,['mpa','id']); }
	}
	my $passtab = xCAT::Table->new('passwd');
	if ($passtab) {
		($tmp)=$passtab->getAttribs({'key'=>'ipmi'},'username','password');
		if (defined($tmp)) { 
			$ipmiuser = $tmp->{username};
			$ipmipass = $tmp->{password};
		}
		($tmp)=$passtab->getAttribs({'key'=>'blade'},'username','password');
		if (defined($tmp)) { 
			$bladeuser = $tmp->{username};
			$bladepass = $tmp->{password};
		}
	}
	my $mpatab;
        if ($mphash) { $mpatab = xCAT::Table->new('mp',-create=>0); }
	my %mpaauth;
	foreach $node (@$noderange) {
		$authmap{$node}->{username}=$ipmiuser;
		$authmap{$node}->{password}=$ipmipass;
		if ($mphash and ref $mphash->{$node} and $mphash->{$node}->[0]->{mpa}) { #this appears to be a Flex or similar config, tend to use blade credentials
			if ($bladeuser) { $authmap{$node}->{username}=$bladeuser; }
			if ($bladepass) { $authmap{$node}->{password}=$bladepass; }
			my $mpa = $mphash->{$node}->[0]->{mpa};
			if (not $mpaauth{$mpa} and $mpatab) { 
				my $mpaent = $mpatab->getNodeAttribs($mpa,[qw/username password/],prefetchcache=>1);
				if (ref $mpaent and $mpaent->[0]->{username}) { $mpaauth{$mpa}->{username} = $mpaent->[0]->{username} }
				if (ref $mpaent and $mpaent->[0]->{password}) { $mpaauth{$mpa}->{password} = $mpaent->[0]->{password} }
				 $mpaauth{$mpa}->{checked} = 1;  #remember we already looked this up, to save lookup time even if search was fruitless
			}
			if ($mpaauth{$mpa}->{username}) {  $authmap{$node}->{username} = $mpa->{username} }
			if ($mpaauth{$mpa}->{password}) {  $authmap{$node}->{password} = $mpa->{password} }
		} 
		unless (ref $ipmihash and ref $ipmihash->{$node}) { 
			next;
		}
		if ($ipmihash->{$node}->[0]->{username}) {   $authmap{$node}->{username}=$ipmihash->{$node}->[0]->{username} }
		if ($ipmihash->{$node}->[0]->{password}) {   $authmap{$node}->{username}=$ipmihash->{$node}->[0]->{password} }
	}
}
	
