# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::switch;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";


use IO::Socket;
use Data::Dumper;
use xCAT::MacMap;
use xCAT::NodeRange;
use Sys::Syslog;
use xCAT::Usage;
use Storable;
use xCAT::MellanoxIB;
require xCAT::TableUtils;
require xCAT::ServiceNodeUtils;

my $macmap;

sub handled_commands {
    return {
        findme      => 'switch',
        findmac     => 'switch',
        switchprobe => 'switch',
        rspconfig   => 'nodehm:mgt',
    };
}

sub preprocess_request {
    my $request = shift;
    if (defined $request->{_xcatpreprocessed}->[0] and $request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }

    my $callback = shift;
    my @requests;

    my $noderange = $request->{node};
    my $command   = $request->{command}->[0];

    if ($command eq "rspconfig") {
        my $extrargs = $request->{arg};
        my @exargs   = ($request->{arg});
        if (ref($extrargs)) {
            @exargs = @$extrargs;
        }
        my $usage_string = xCAT::Usage->parseCommand($command, @exargs);
        if ($usage_string) {
            $callback->({ data => $usage_string });
            $request = {};
            return;
        }
        if (!$noderange) {
            $usage_string = xCAT::Usage->getUsage($command);
            $callback->({ data => $usage_string });
            $request = {};
            return;
        }

        #make sure all the nodes are switches
        my $switchestab = xCAT::Table->new('switches', -create => 0);
        my @all_switches;
        my @tmp = $switchestab->getAllAttribs(('switch'));
        if (@tmp && (@tmp > 0)) {
            foreach (@tmp) {
                my @switches_tmp = noderange($_->{switch});
                if (@switches_tmp == 0) { push @switches_tmp, $_->{switch}; }
                foreach my $switch (@switches_tmp) {
                    push @all_switches, $switch;
                }
            }
        }

        #print "all switches=@all_switches\n";
        my @wrong_nodes;
        foreach my $node (@$noderange) {
            if (!grep /^$node$/, @all_switches) {
                push @wrong_nodes, $node;
            }
        }
        if (@wrong_nodes > 0) {
            my $rsp = {};
            $rsp->{error}->[0] = "The following nodes are not defined in the switches table:\n  @wrong_nodes.";
            $callback->($rsp);
            return;
        }

        # find service nodes for requested switch
        # build an individual request for each service node
        my $service = "xcat";
        my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, $service, "MN");

        # build each request for each service node
        foreach my $snkey (keys %$sn)
        {
            #print "snkey=$snkey\n";
            my $reqcopy = {%$request};
            $reqcopy->{node}                   = $sn->{$snkey};
            $reqcopy->{'_xcatdest'}            = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;
        }
        return \@requests;
    }
    elsif ($command eq 'switchprobe') {
        @ARGV = ();
        if (ref($request->{arg})) {
            @ARGV = @{ $request->{arg} };
        }
        use Getopt::Long;
        $Getopt::Long::ignorecase = 0;
        Getopt::Long::Configure("bundling");
        my $verbose = undef;
        my $check   = undef;
        my $help    = undef;
        unless (GetOptions('h|help' => \$help, 'V|verbose' => \$verbose, 'c|check' => \$check)) {
            $callback->({ error => ["Parse args failed"], errorcode => 1 });
            return;
        }
        if (@ARGV) {
            $callback->({ error => [ "Option @ARGV not supported.\n" . xCAT::Usage->getUsage($command) ], errorcode => 1 });
            return;
        }
        if (defined($help)) {
            $callback->({ data => xCAT::Usage->getUsage($command) });
            return;
        }
        if (defined($verbose)) {
            $request->{opt}->{verbose} = $verbose;
        }
        if (defined($check)) {
            $request->{opt}->{check} = $check;
        }
        my $switchestab = xCAT::Table->new('switches', -create => 0);
        my $swhash = undef;
        if ($switchestab) {
            $swhash = $switchestab->getAllNodeAttribs(['switch'], 1);
            if (!defined($swhash)) {
                $callback->({ error => ["Get attributes from table 'switches' failed"], errorcode => 1 });
                return;
            }
        }
        else {
            $callback->({ error => ["Open table 'switches' failed"], errorcode => 1 });
            return;
        }
        if (defined($noderange)) {
            my $nthash = undef;
            my $nodetypetab = xCAT::Table->new('nodetype', -create => 0);
            if ($nodetypetab) {
                $nthash = $nodetypetab->getNodesAttribs($noderange, ['nodetype']);
                if (!defined($nthash)) {
                    $callback->({ error => ["Get attributes from table 'nodetype' failed"], errorcode => 1 });
                    return;
                }
            }
            else {
                $callback->({ error => ["Open table 'nodetype' failed"], errorcode => 1 });
                return;
            }
            my @switchnode = ();
            my @errswnode  = ();
            my @errornode  = ();
            foreach my $node (@$noderange) {
                if (!defined($nthash->{$node}) or $nthash->{$node}->[0]->{nodetype} ne 'switch') {
                    push @errornode, $node;
                }
                elsif (!defined($swhash->{$node}) or !defined($swhash->{$node}->[0])) {
                    push @errswnode, $node;
                }
                else {
                    push @switchnode, $node;
                }
            }
            if (@errornode) {
                $callback->({ error => [ "The nodetype is not 'switch' for nodes: " . join(",", @errornode) ], errorcode => 1 });
            }
            if (@errswnode) {
                $callback->({ error => [ "No switch configuration info find for " . join(",", @errswnode) ], errorcode => 1 });
            }
            if (@switchnode) {
                @{ $request->{node} } = @switchnode;
                return [$request];
            }
            return;
        }
        else {
            if (!scalar(keys %$swhash)) {
                $callback->({ error => ["No switch configuration info get from 'switches' table"], errorcode => 1 });
                return;
            }
        }
    }
    return [$request];
}

sub process_request {
    my $req   = shift;
    my $cb    = shift;
    my $doreq = shift;
    unless ($macmap) {
        $macmap = xCAT::MacMap->new();
    }
    my $node;
    my $mac = '';
    if ($req->{command}->[0] eq 'findmac') {
        $mac = $req->{arg}->[0];
        $node = $macmap->find_mac($mac, 0);
        $cb->({ node => [ { name => $node, data => $mac } ] });
        return;
    } elsif ($req->{command}->[0] eq 'rspconfig') {
        return process_switch_config($req, $cb, $doreq);
    } elsif ($req->{command}->[0] eq 'switchprobe') {
        my $macinfo = $macmap->dump_mac_info($req, $cb);
        if ($macinfo and ref($macinfo) eq 'HASH') {
            my $switch_name_length = 0;
            my $port_name_length   = 0;
            foreach my $switch (keys %$macinfo) {
                if (length($switch) > $switch_name_length) {
                    $switch_name_length = length($switch);
                }
                if (defined($macinfo->{$switch}->{ErrorStr})) {
                    next;
                }
                foreach my $portname (keys %{ $macinfo->{$switch} }) {
                    if (length($portname) > $port_name_length) {
                        $port_name_length = length($portname) + 10;
                    }
                }
            }
            my $format = "%-" . $switch_name_length . "s  %-" . $port_name_length . "s  %-26s  %s";
            my %failed_switches = ();
            my $header = sprintf($format, "Switch", "Port(MTU)", "MAC address(VLAN)", "Node");
            if (!defined($req->{opt}->{check}) and $port_name_length) {
                $cb->({ data => $header });
                $cb->({ data => "--------------------------------------------------------------------------------------" })
            }
            foreach my $switch (keys %$macinfo) {
                if (defined($macinfo->{$switch}->{ErrorStr})) {
                    if (defined($req->{opt}->{check})) {
                        $cb->({ node => [ { name => $switch, error => [ $macinfo->{$switch}->{ErrorStr} ], errorcode => 1 } ] });
                    }
                    else {
                        $failed_switches{$switch} = "$macinfo->{$switch}->{ErrorStr}";
                    }
                    next;
                }
                elsif (defined($req->{opt}->{check})) {
                    $cb->({ node => [ { name => $switch, data => ["PASS"] } ] });
                    next;
                }
                foreach my $port (map{$_->[0]}sort{$a->[1] cmp $b->[1] || $a->[2] <=> $b->[2]}map{[$_, /^(.*?)(\d+)?$/]} keys %{ $macinfo->{$switch} }) {
                    my $node = '';
                    if (defined($macinfo->{$switch}->{$port}->{Node})) {
                        $node = $macinfo->{$switch}->{$port}->{Node};
                    }

                    my $mtu = '';
                    my $vlanid = '';
                    my @vlans = ();
                    if (defined($macinfo->{$switch}->{$port}->{Vlanid})) {
                        @vlans = @{ $macinfo->{$switch}->{$port}->{Vlanid} };
                    }

                    my @macarrary = ();
                    if (defined($macinfo->{$switch}->{$port}->{MACaddress})) {
                        @macarray = @{ $macinfo->{$switch}->{$port}->{MACaddress} };
                        my $ind = 0;
                        foreach (@macarray) {
                            my $mac = $_;
                            $vlanid = $vlans[$ind];
                            my $mac_vlan;
                            if (!$mac) {
                                $mac_vlan="N/A";
                            } elsif ($vlanid) {
                                $mac_vlan = "$mac($vlanid)"; 
                            } else {
                                $mac_vlan = $mac;
                            }
                            my $port_mtu = $port;
                            if (defined($macinfo->{$switch}->{$port}->{Mtu})) {
                                $mtu = $macinfo->{$switch}->{$port}->{Mtu}->[0];
                                $port_mtu = "$port($mtu)";
                            }
                            my $data = sprintf($format, $switch, $port_mtu, $mac_vlan, $node);
                            $cb->({ data => $data });
                            $ind++;

                            #$cb->({node=>[{name=>$switch,data=>$data}]});
                        }
                    }
                }
            }
            if (!defined($req->{opt}->{check}) and $port_name_length) {
                $cb->({ data => "--------------------------------------------------------------------------------------" })
            }
            foreach (keys %failed_switches) {
                $cb->({ node => [ { name => $_, error => [ $failed_switches{$_} ], errorcode => 1 } ] });
            }
        }
        return;
    } elsif ($req->{command}->[0] eq 'findme') {
        if (defined($req->{discoverymethod}) and defined($req->{discoverymethod}->[0]) and ($req->{discoverymethod}->[0] ne 'undef')) {

            # The findme request had been processed by other module, just return
            return;
        }
        $mac = $req->{_xcat_clientmac}->[0];
        if (defined $req->{nodetype} and $req->{nodetype}->[0] eq 'virtual') {

            #Don't attempt switch discovery of a  VM Guest
            #TODO: in this case, we could/should find the host system
            #and then ask it what node is associated with the mac
            #Either way, it would be kinda weird since xCAT probably made up the mac addy
            #anyway, however, complex network topology function may be aided by
            #discovery working.  Food for thought.
            return;
        }
        my $discoverswitch = 0;
        if (defined $req->{nodetype} and $req->{nodetype}->[0] eq 'switch') {
            $discoverswitch = 1;
        }
        my $firstpass = 1;
        if ($mac) {
            $node = $macmap->find_mac($mac, $req->{cacheonly}->[0], $discoverswitch);
            $firstpass = 0;
        }
        if (not $node) {    # and $req->{checkallmacs}->[0]) {
            foreach (@{ $req->{mac} }) {
                /.*\|.*\|([\dABCDEFabcdef:]+)(\||$)/;
                $node = $macmap->find_mac($1, $firstpass, $discoverswitch);
                $firstpass = 0;
                if ($node) { last; }
            }
        }
        my $bmc_node = undef;
        if ($req->{'mtm'}->[0] and $req->{'serial'}->[0]) {
            my $mtms      = $req->{'mtm'}->[0] . "*" . $req->{'serial'}->[0];
            my $tmp_nodes = $::XCATVPDHASH{$mtms};
            foreach (@$tmp_nodes) {
                if ($::XCATMPHASH{$_}) {
                    $bmc_node = $_;
                }
            }
        }

        unless ($bmc_node) {
            if ($req->{'bmcmac'}->[0]) {
                my $bmcmac = lc($req->{'bmcmac'}->[0]);
                $bmcmac =~ s/\://g;
                my $tmp_node = "node-$bmcmac";
                $bmc_node = $tmp_node if ($::XCATMPHASH{$tmp_node});
            }
        }

        if ($node) {
            xCAT::MsgUtils->message("S", "xcat.discovery.switch: ($req->{_xcat_clientmac}->[0]) Found node: $node");

            # No need to write mac table here, 'discovered' command will write
            # my $mactab = xCAT::Table->new('mac',-create=>1);
            # $mactab->setNodeAttribs($node,{mac=>$mac});
            # $mactab->close();
            #my %request = (
            #  command => ['makedhcp'],
            #  node => [$node]
            #);
            #$doreq->(\%request);
            $req->{discoverymethod}->[0] = 'switch';
            my $request = {%$req};
            $request->{command}   = ['discovered'];
            $request->{noderange} = [$node];
            $request->{bmc_node}  = [$bmc_node];
            $doreq->($request);
            %{$request} = ();    #Clear req structure, it's done..
            undef $mactab;
        } else {
            xCAT::MsgUtils->message("S", "xcat.discovery.switch: ($req->{_xcat_clientmac}->[0]) Warning: Could not find any nodes using switch-based discovery");
        }
    }
}

sub process_switch_config {
    my $request   = shift;
    my $callback  = shift;
    my $subreq    = shift;
    my $noderange = $request->{node};
    my $command   = $request->{command}->[0];
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    my $subcommand = join(' ', @exargs);
    my $argument;
    ($subcommand, $argument) = split(/=/, $subcommand);
    if (!$subcommand) {
        my $rsp = {};
        $rsp->{error}->[0] = "No subcommand specified.";
        $callback->($rsp);
        return;
    }


    #decide what kind of swith it is
    my $sw_types = getSwitchType($noderange);    #hash {type=>[node1,node1...]}
    foreach my $t (keys(%$sw_types)) {
        my $nodes = $sw_types->{$t};
        if (@$nodes > 0) {
            if ($t =~ /Mellanox/i) {
                if (!$argument) {
                    xCAT::MellanoxIB::getConfig($nodes, $callback, $subreq, $subcommand);
                } else {
                    xCAT::MellanoxIB::setConfig($nodes, $callback, $subreq, $subcommand, $argument);
                }
            } else {
                my $rsp = {};
                $rsp->{error}->[0] = "The following '$t' switches are unsuppored:\n@$nodes";
                $callback->($rsp);
            }
        }
    }
}

#--------------------------------------------------------------------------------

=head3    getSwitchType
      It determins the swtich vendor and model for the given swith.      
    Arguments:
        noderange-- an array ref to switches.
    Returns:
        a hash ref. the key is the switch type string and the value is an array ref to the swithces t
=cut

#--------------------------------------------------------------------------------
sub getSwitchType {
    my $noderange = shift;
    if ($noderange =~ /xCAT_plugin::switch/) {
        $noderange = shift;
    }

    my $ret = {};
    my $switchestab = xCAT::Table->new('switches', -create => 1);
    my $switches_hash = $switchestab->getNodesAttribs($noderange, ['switchtype']);
    foreach my $node (@$noderange) {
        my $type = "EtherNet";
        if ($switches_hash) {
            if ($switches_hash->{$node} - [0]) {
                $type = $switches_hash->{$node}->[0]->{switchtype};
            }
        }
        if (exists($ret->{$type})) {
            $pa = $ret->{$type};
            push @$pa, $node;
        } else {
            $ret->{$type} = [$node];
        }
    }

    return $ret;
}

1;
