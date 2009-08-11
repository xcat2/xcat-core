# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::networks;
use xCAT::Table;
use Data::Dumper;
use Sys::Syslog;
use Socket;
use xCAT::Utils;
use Getopt::Long;

sub handled_commands
{
    return {makenetworks => "networks",};
}

sub preprocess_request
{
    my $req = shift;
    my $callback  = shift;
	if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    # exit if preprocessed
    my @requests = ({%$req}); #first element is local instance
	$::args     = $req->{arg};

	if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } 

	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'help|h|?'    => \$::HELP,
					'display|d'	=> \$::DISPLAY,
					'mnonly|m'	=> \$::MNONLY,
					'verbose|V' => \$::VERBOSE,
                    'version|v' => \$::VERSION,
        )
      )
    {
    #    return 1;
    }

	# Option -h for Help
    if ($::HELP )
    {
        &makenetworks_usage($callback);
        return undef;
    }

	# Option -v for version - do we need this???
    if ($::VERSION)
    {
        my $rsp;
        my $version=xCAT::Utils->Version();
        $rsp->{data}->[0] = "makenetworks - $version";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return undef;
    }

    my @sn = xCAT::Utils->getSNList();
    foreach my $s (@sn)
    {
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $s;
        push @requests, $reqcopy;
    }
    return \@requests;
}

sub process_request
{
	my $request  = shift;
    my $callback = shift;

	my $host = `hostname`;
	chomp $host;

	$::args     = $request->{arg};

    if (defined(@{$::args})) {
        @ARGV = @{$::args};
    }

    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'help|h|?'    => \$::HELP,
                    'display|d' => \$::DISPLAY,
                    'mnonly|m'  => \$::MNONLY,
                    'verbose|V' => \$::VERBOSE,
                    'version|v' => \$::VERSION,
        )
      )
    {
    #    return 1;
    }

	my $nettab = xCAT::Table->new('networks', -create => 1, -autocommit => 0);

	if (xCAT::Utils->isAIX()) {

		# get list of interfaces "ifconfig -l"
		my $ifgcmd = "ifconfig -l";
		my @interfaces = split(/\s+/, xCAT::Utils->runcmd($ifgcmd, 0));
		if ($::RUNCMD_RC != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not run \'$ifgcmd\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		# do each ethernet interface
		foreach my $i (@interfaces) {

			if ($i =~ /^en/) {
				# "mktcpip -S en0" to get nm & gw
				my $mkcmd = "mktcpip -S $i";
				my @netinfo = xCAT::Utils->runcmd($mkcmd, 0);
				if ($::RUNCMD_RC != 0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not run \'$mkcmd\'.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}

				my $netmask;
				my $ipaddr;
				my @fields;
				my $gateway;
				foreach my $line (@netinfo) {
					next if ($line =~ /^\s*#/);

					@fields = split(/:/, $line);
				}
				$ipaddr = $fields[1];
				$netmask = $fields[2];
				$gateway = $fields[6];

				# split interface IP
                my ($ip1, $ip2, $ip3, $ip4) = split('\.', $ipaddr);

				# split mask
                my ($m1, $m2, $m3, $m4) = split('\.', $netmask);

				# AND nm and ip to get net attribute
				my $n1 = ((int $ip1) & (int $m1));
                my $n2 = ((int $ip2) & (int $m2));
                my $n3 = ((int $ip3) & (int $m3));
                my $n4 = ((int $ip4) & (int $m4));

				my $net = "$n1.$n2.$n3.$n4";

				# use convention for netname attr
				my $netn;
				my $maskn;
				($netn = $net) =~ s/\./\_/g;
				($maskn = $netmask) =~ s/\./\_/g;
				#  ( 1_2_3_4-255_255_255_192 - ugh!)
				my $netname = $netn . "-" . $maskn;

				if ($::DISPLAY) {
					my $rsp;
					push @{$rsp->{data}}, "\n#From $host.";
            		push @{$rsp->{data}}, "$netname:";
					push @{$rsp->{data}}, "    objtype=network";
					push @{$rsp->{data}}, "    net=$net";
					push @{$rsp->{data}}, "    mask=$netmask";
					push @{$rsp->{data}}, "    gateway=$gateway\n";
            		xCAT::MsgUtils->message("I", $rsp, $callback);
				} else {
					# add new network def 
					$nettab->setAttribs({'net' => $net}, {'mask' => $mask}, {'netname' => $netname}, {'gateway' => $gateway});
				}

			}
		}

	} else {

		# For Linux systems
    	my @rtable = split /\n/, `/bin/netstat -rn`;
    	open($rconf, "/etc/resolv.conf");
    	my @nameservers;
    	if ($rconf)
    	{
        	my @rcont;
        	while (<$rconf>)
        	{
            	push @rcont, $_;
        	}
        	close($rconf);
        	foreach (grep /nameserver/, @rcont)
        	{
            	my $line = $_;
            	my @pair;
            	$line =~ s/#.*//;
            	@pair = split(/\s+/, $line);
            	push @nameservers, $pair[1];
        	}
    	}
    	splice @rtable, 0, 2;
    	foreach (@rtable)
    	{ #should be the lines to think about, do something with U, and something else with UG

			my $rsp;
        	my $net;
        	my $mask;
        	my $mgtifname;
        	my $gw;
        	my @ent = split /\s+/, $_;
        	my $firstoctet = $ent[0];
        	$firstoctet =~ s/^(\d+)\..*/$1/;

        	if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239) or $ent[0] eq "127.0.0.0")
        	{
            	next;
        	}
        	if ($ent[3] eq 'U')
        	{
            	$net       = $ent[0];
            	$mask      = $ent[2];
				$mgtifname = $ent[7];

				# use convention for netname attr
                my $netn;
                my $maskn;
                ($netn = $net) =~ s/\./\_/g;
                ($maskn = $mask) =~ s/\./\_/g;
                #  ( 1_2_3_4-255_255_255_192 - ugh!)
                my $netname = $netn . "-" . $maskn;

				if ($::DISPLAY) {
					push @{$rsp->{data}}, "\n#From $host.";
					push @{$rsp->{data}}, "$netname:";
					push @{$rsp->{data}}, "    objtype=network";
                    push @{$rsp->{data}}, "    net=$net";
                    push @{$rsp->{data}}, "    mask=$mask";
                    push @{$rsp->{data}}, "    mgtifname=$mgtifname";
				} else {
            		$nettab->setAttribs({'net' => $net}, {'mask' => $mask, 'mgtifname' => $mgtifname}, {'netname' => $netname});
				}

            	my $tent = $nettab->getAttribs({'net' => $net}, 'nameservers');
            	unless ($tent and $tent->{nameservers})
            	{
                	my $text = join ',', @nameservers;
					if ($::DISPLAY) {
                    	push @{$rsp->{data}}, "    nameservers=$text";
					} else {
                		$nettab->setAttribs({'net' => $net}, {nameservers => $text});
					}
            	}
            	unless ($tent and $tent->{tftpserver})
            	{
                	my $netdev = $ent[7];
                	my @netlines = split /\n/, `/sbin/ip addr show dev $netdev`;
                	foreach (grep /\s*inet\b/, @netlines)
                	{
                    	my @row = split(/\s+/, $_);
                    	my $ipaddr = $row[2];
                    	$ipaddr =~ s/\/.*//;
                    	my @maska = split(/\./, $mask);
                    	my @ipa   = split(/\./, $ipaddr);
                    	my @neta  = split(/\./, $net);
                    	my $isme  = 1;
                    	foreach (0 .. 3)
                    	{
                        	my $oct = (0 + $maska[$_]) & ($ipa[$_] + 0);
                        	unless ($oct == $neta[$_])
                        	{
                            	$isme = 0;
                            	last;
                        	}
                    	}
                    	if ($isme)
                    	{
							if ($::DISPLAY) {
                        		push @{$rsp->{data}}, "    tftpserver=$ipaddr";
                    		} else {
                        		$nettab->setAttribs({'net' => $net}, {tftpserver => $ipaddr});
							}
                        	last;
                    	}
                	}
            	}

            	#Nothing much sane to do for the other fields at the moment?
        	}
        	elsif ($ent[3] eq 'UG')
        	{

            	#TODO: networks through gateway. and how we might care..
        	}
        	else
        	{

            	#TODO: anything to do with such entries?
        	}
			
			if ($::DISPLAY) {
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
    	}
	}

	$nettab->commit;
}

#----------------------------------------------------------------------------

=head3  makenetworks_usage

=cut

#-----------------------------------------------------------------------------

sub makenetworks_usage
{
	my $callback = shift;

    my $rsp;
	push @{$rsp->{data}}, "\nUsage: makenetworks - Gather cluster network information and add it to the xCAT database.\n";
	push @{$rsp->{data}}, "  makenetworks [-h|--help ]\n";
	push @{$rsp->{data}}, "  makenetworks [-v|--version]\n";
	push @{$rsp->{data}}, "  makenetworks [-V|--verbose] [-d|--display]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

1;
