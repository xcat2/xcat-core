#!/usr/bin/env perl
## IBM(c) 20013 EPL license http://www.eclipse.org/legal/epl-v10.html
#
# This plugin is used to handle the sequencial discovery. During the discovery,
# the nodes should be powered on one by one, sequencial discovery plugin will 
# discover the nodes one by one and  define them to xCAT DB. 

# For the new discovered node but NOT handled by xCAT plugin, 
# it will be recorded to discoverydata table.
#

package xCAT_plugin::seqdiscovery;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use strict;
use Getopt::Long;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';

use lib "$::XCATROOT/lib/perl";
use xCAT::NodeRange;
use xCAT::Table;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::DiscoveryUtils;
use xCAT::NodeRange qw/noderange/;
require xCAT::data::ibmhwtypes;

use Time::HiRes qw(gettimeofday sleep);

sub handled_commands {
    return {
        findme => 'seqdiscovery',
        nodediscoverstart => 'seqdiscovery',
        nodediscoverstop => 'seqdiscovery',
        nodediscoverls => 'seqdiscovery',
        nodediscoverstatus => 'seqdiscovery',
        nodediscoverdef => 'seqdiscovery',
    }
}

=head3 findme 
    Handle the request form node to map and define the request to a node
=cut
sub findme {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my @SEQdiscover = xCAT::TableUtils->get_site_attribute("__SEQDiscover");
    my @PCMdiscover = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    unless ($SEQdiscover[0]) {
        if ($PCMdiscover[0]) {
            #profile disocvery is running, then just return to make profile discovery to handle it
            return;
        }
        # update the discoverydata table to have an undefined node
        $request->{discoverymethod}->[0] = 'undef';
        xCAT::DiscoveryUtils->update_discovery_data($request);
        return;
    }

    # do the sequential discovery
    xCAT::MsgUtils->message("S", "Sequential Discovery: Processing");

    # Get the parameters for the sequential discovery
    my %param;
    my @params = split (',', $SEQdiscover[0]);
    foreach (@params) {
        my ($name, $value) = split ('=', $_);
        $param{$name} = $value;
    }
    
    my $mac;
    my $ip = $request->{'_xcat_clientip'};
    if (defined $request->{nodetype} and $request->{nodetype}->[0] eq 'virtual') {
        xCAT::MsgUtils->message("S", "Sequential discovery does not support virtual machines, exiting...");
        return;
    }
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
    
    unless ($mac) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not find the mac of the $ip.");
        return;
    }

    # check whether the mac could map to a node
    my $mactab = xCAT::Table->new('mac');
    unless ($mactab) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: mac.");
    }

    my $node;
    my @macs = $mactab->getAllAttribs('node', 'mac');
    # for each entry: 34:40:b5:be:db:b0!*NOIP*|34:40:b5:be:db:b0!*NOIP*
    foreach my $macnode (@macs) {
        my @macents = split ('\|', $macnode->{'mac'});
        foreach my $macent (@macents) {
            my ($usedmac) = split ('!', $macent);
            if ($usedmac =~ /$mac/i) {
                 $node = $macnode->{'node'};
                 last;
            }
        }
    }

    my @allnodes;
    unless ($node) {
        # get a free node
        @allnodes = getfreenodes($param{'noderange'}, "all");
        if (@allnodes) {
            $node = $allnodes[0];
        }
    }
    my $pbmc_node = undef;
    if ($request->{'mtm'}->[0] and $request->{'serial'}->[0]) {
        my $mtms = $request->{'mtm'}->[0]."*".$request->{'serial'}->[0];
        my $tmp_nodes = $::XCATVPDHASH{$mtms};
        foreach (@$tmp_nodes) {
            if ($::XCATPPCHASH{$_}) {
                $pbmc_node = $_;
            }
        } 
    }


    if ($node) {
        my $skiphostip;
        my $skipbmcip;
        my $bmcname;
        # check the host ip and bmc 
        my $hosttab = xCAT::Table->new('hosts');
        unless ($hosttab) {
            xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: hosts.");
        }
        my $hostip = getpredefips([$node], "host");
        foreach (keys %$hostip) {
            if ($hostip->{$_} eq "$node") {
                $skiphostip = 1;
            }
        }

        my $ipmitab = xCAT::Table->new('ipmi');
        unless ($ipmitab) {
            xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: ipmi.");
        }

        # check the bmc definition in the ipmi table
        my $ipmient = $ipmitab->getNodeAttribs($node, ['bmc']);
        if (defined($ipmient->{'bmc'})) {
            $bmcname = $ipmient->{'bmc'};
            if ($bmcname =~ /\d+\.\d+\.\d+\.\d+/) {
                $skipbmcip = 1;
            } else {
                my $bmcip = getpredefips([$node], "bmc");
                foreach (keys %$bmcip) {
                    if ($bmcip->{$_} eq $bmcname) {
                        $skipbmcip = 1;
                    }
                }  
            }
        }

        # set the host ip if the node does not have
        unless ($skiphostip) {
            my $hostip = getfreeips($param{'hostiprange'}, \@allnodes, "host");
            unless ($hostip) {
                nodediscoverstop($callback, undef, "host ips");
                return;
            }
            $hosttab->setNodeAttribs($node, {ip => $hostip});
            $hosttab->commit();
        }

        # set the bmc ip if the node does not have
        unless ($skipbmcip) {
            unless ($bmcname) {
                # set the default bmc name
                $bmcname= $node."-bmc";
            }
            my $bmcip = getfreeips($param{'bmciprange'}, \@allnodes, "bmc");
            unless ($bmcip) {
                nodediscoverstop($callback, undef, "bmc ips");
                return;
            }
            # for auto created bmc, just add it to hosts.otherinterfaces instead of adding a new bmc node
            my $otherif = $hosttab->getNodeAttribs($node, ['otherinterfaces']);
            my $updateotherif;
            if ($otherif && defined ($otherif->{'otherinterfaces'})) {
                $updateotherif .= ",$bmcname:$bmcip";
            } else {
                $updateotherif = "$bmcname:$bmcip";
            }
            $hosttab->setNodeAttribs($node, {otherinterfaces => $updateotherif});
            $hosttab->commit();

            # set the bmc to the ipmi table
            $ipmitab->setNodeAttribs($node, {bmc => $bmcname});
            $ipmitab->commit();
        }

        # update the host ip pair to /etc/hosts, it's necessary for discovered and makedhcp commands
        my @newhosts = ($node, $bmcname);
        if (@newhosts) {
            my $req;
            $req->{command}=['makehosts'];
            $req->{node} = \@newhosts;
            $subreq->($req); 

            # run makedns only when -n flag was specified with nodediscoverstart,
            # dns=yes in site.__SEQDiscover
            if (defined($param{'dns'}) && ($param{'dns'} eq 'yes'))
            {
                my $req;
                $req->{command}=['makedns'];
                $req->{node} = \@newhosts;
                $subreq->($req);
            }
        }

        # set the specific attributes from parameters
        my $updateparams;
        my %setpos;
        if (defined ($param{'rack'})) {
            $setpos{'rack'} = $param{'rack'};
        } 
        if (defined ($param{'chassis'})) {
            $setpos{'chassis'} = $param{'chassis'};
        }
        if (defined ($param{'height'})) {
            $setpos{'height'} = $param{'height'};
        }
        if (defined ($param{'unit'})) {
            $setpos{'u'} = $param{'unit'};

            if (defined ($param{'height'})) {
                $param{'unit'} += $param{'height'};
            } else {
                $param{'unit'} += 1;
            }

            $updateparams = 1;
        }
        if (keys %setpos) {
            my $postab = xCAT::Table->new('nodepos');
            unless ($postab) {
                xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: nodepos.");
            }
            $postab->setNodeAttribs($node, \%setpos);
            $postab->close();
        }
        

        if ($updateparams) {
            my $textparam;
            foreach my $name (keys %param) {
                $textparam .= "$name=$param{$name},";
            }
            $textparam =~ s/,\z//;

            # Update the discovery parameters to the site.__SEQDiscover which will be used by nodediscoverls/status/stop and findme, 
            my $sitetab = xCAT::Table->new("site");
            $sitetab->setAttribs({"key" => "__SEQDiscover"}, {"value" => "$textparam"});
            $sitetab->close();
        }

        #set the groups for the node
        my $nltab = xCAT::Table->new('nodelist');
        unless ($nltab) {
            xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: nodelist.");
        }
        if (defined ($param{'groups'})) {
            $nltab->setNodeAttribs($node, {groups=>$param{'groups'}});
        } else {
            # just set the groups attribute when there was no groups value was set
            my $nlent = $nltab->getNodeAttribs($node,['groups']);
            if (!$nlent || !$nlent->{'groups'}) {
                $nltab->setNodeAttribs($node, {groups=>"all"});
            }
        }
        # update node groups with pre-defined groups
        if (defined($param{'mtm'})){
            my @list = ();
            my $tmp_group = xCAT::data::ibmhwtypes::parse_group($param{'mtm'});
            if (defined($tmp_group)) {
                xCAT::TableUtils->updatenodegroups($node, $nltab, $tmp_group);
            }
        }
        # set the mgt for the node
        my $hmtab = xCAT::Table->new('nodehm');
        unless ($hmtab) {
            xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: nodehm.");
        }
        my $hment = $hmtab->getNodeAttribs($node,['mgt']);
        if (!$hment || !$hment->{'mgt'}) {
            $hmtab->setNodeAttribs($node, {mgt=>"ipmi"});
        }

        my $chaintab = xCAT::Table->new('chain');
        # Could not open chain table, but do not fail the discovery process
        if (!$chaintab) {
            xCAT::MsgUtils->message("S", "Error: could not open chain table");
        } else {
            my $chainent = $chaintab->getNodeAttribs($node, ['chain']);
            my $nodechain = '';
            my $origchain = '';
            if (defined($chainent->{'chain'})) {
                $nodechain = $chainent->{'chain'};
                $origchain = $nodechain;
            }

            # If the bmciprange=xxx is specified with nodediscoverstart command,
            # add the runcmd=bmcsetup at the beginning of the chain attribute
            # the skipbmcsetup could be used to skip the bmcsetup for the node
            if ($param{'bmciprange'} && !$param{'skipbmcsetup'}) {
                if (!$nodechain) {
                    $nodechain = "runcmd=bmcsetup";
                } else {
                    # do not add duplicate runcmd=bmcsetup in the chain attribute
                    if ($nodechain !~ /runcmd=bmcsetup/) {
                        $nodechain = "runcmd=bmcsetup," . $nodechain;
                    }
                }
            } # end if $param{'bmciprange'}

            # Remove the runcmd=bmcsetup from chain if skipbmcsetup is specified
            # this is useful for predefined configuration, or attributes inherit from groups
            if ($param{'skipbmcsetup'}) {
                if ($nodechain =~ /runcmd=bmcsetup/) {
                    $nodechain =~ s/runcmd=bmcsetup,//;
                    $nodechain =~ s/runcmd=bmcsetup//;
                }
            }

            # If the osimage=xxx is specified with nodediscoverstart command,
            # append the osimage=xxx at the end of the chain attribute
            if ($param{'osimage'}) {
                if (!$nodechain) {
                    $nodechain = "osimage=$param{'osimage'}";
                } else {
                    # do not add multiple osimage=xxx in the chain attribute
                    # replace the old one with the new one
                    if ($nodechain !~ /osimage=/) {
                        $nodechain = $nodechain . ",osimage=$param{'osimage'}"; 
                    } else {
                        $nodechain =~ s/osimage=\w+/osimage=$param{'osimage'}/;
                    }
                }
            } # end if $param{'osimage'}

            # Update the table only when the chain attribute is changed
            if ($nodechain ne $origchain) {
                $chaintab->setNodeAttribs($node, {chain => $nodechain});
            }
            $chaintab->close();
        }

        # call the discovered command to update the discovery request to a node
         
        $request->{command}=['discovered'];
        $request->{noderange} = [$node];
        if ($pbmc_node) {
            $request->{pbmc_node} = [$pbmc_node];
        }

        $request->{discoverymethod} = ['sequential'];
        $request->{updateswitch} = ['yes'];
        $subreq->($request); 
        %{$request}=();#Clear req structure, it's done..
        undef $mactab;
    } else {
        nodediscoverstop($callback, undef, "node names");
        return;
    }

    xCAT::MsgUtils->message("S", "Sequential Discovery: Done");
}

=head3 displayver 
    Display the version information
=cut

sub displayver {
    my $callback = shift;
    
    my $version = xCAT::Utils->Version();
    
    my $rsp;
    push @{$rsp->{data}}, $version;
    xCAT::MsgUtils->message("I", $rsp, $callback);
}

=head3 nodediscoverstart 
 Initiate the sequencial discovery process
=cut
sub nodediscoverstart {
    my $callback = shift;
    my $args = shift;

    my $usage = sub {
        my $cb = shift;
        my $msg = shift;

        my $rsp;
        if ($msg) {
            push @{$rsp->{data}}, $msg;
            xCAT::MsgUtils->message("E", $rsp, $cb, 1);
        }

        my $usageinfo = "nodediscoverstart: Start a discovery process: Sequential or Profile.
Usage: 
    Common:
        nodediscoverstart [-h|--help|-v|--version|-V|--verbose] 
    Sequential Discovery:
        nodediscoverstart noderange=<noderange> [hostiprange=<hostiprange>] [bmciprange=<bmciprange>] [groups=<groups>] [rack=<rack>] [chassis=<chassis>] [height=<height>] [unit=<unit>] [osimage=<osimagename>] [-n|--dns] [-s|--skipbmcsetup] [-V|--verbose]
    Profile Discovery:
        nodediscoverstart networkprofile=<networkprofile> imageprofile=<imageprofile> hostnameformat=<hostnameformat> [hardwareprofile=<hardwareprofile>] [groups=<groups>] [rack=<rack>] [chassis=<chassis>] [height=<height>] [unit=<unit>] [rank=rank-num]";
        $rsp = ();
        push @{$rsp->{data}}, $usageinfo;
        xCAT::MsgUtils->message("I", $rsp, $cb);
    };

    # valid attributes for deqdiscovery
    my %validargs = (
        'noderange' => 1, 
        'hostiprange' => 1,
        'bmciprange' => 1,
        'groups' => 1,
        'rack' => 1,
        'chassis' => 1,
        'height' => 1,
        'unit' => 1,
        'osimage' => 1,
    );

    if ($args) {    
        @ARGV = @$args;
    }
    my ($help, $ver); 
    if (!GetOptions(
        'h|help' => \$help,
        'V|verbose' => \$::VERBOSE,
        '-n|dns' => \$::DNS,
        '-s|skipbmcsetup' => \$::SKIPBMCSETUP,
        'v|version' => \$ver)) {
        $usage->($callback);
        return;
    }

    if ($help) {
        $usage->($callback);
        return;
    }

    if ($ver) {
        &displayver($callback);
        return;
    }

    my %orgargs;
    foreach (@ARGV) {
        my ($name, $value) = split ('=', $_);
        $orgargs{$name} = $value;
    }

    # Check the noderage=has been specified which is the flag that this is for sequential discovery
    # Otherwise try to check the whether the networkprofile || hardwareprofile || imageprofile 
    # has been passed, if yes, return to profile discovery
    unless (defined ($orgargs{noderange}) ) {
        if (defined ($orgargs{networkprofile}) || defined($orgargs{hostnameformat}) || defined($orgargs{imageprofile})) {
            # just return that make profile-based discovery to handle it
            return;
        } else {
            $usage->($callback, "For sequential discovery, the \'noderange\' option must be specified.");
            return;
        }
    }

    my %param;    # The valid parameters
    my $textparam; # The valid parameters in 'name=value,name=value...' format

    # Check the validate of parameters
    foreach my $name (keys %orgargs) {
        unless (defined ($validargs{$name})) {
            $usage->($callback, "Invalid arguement \"$name\".");
            return;
        }
        unless (defined ($orgargs{$name})) {
            $usage->($callback, "The parameter \"$name\" need a value.");
            return;
        }

        # keep the valid parameters
        $param{$name} = $orgargs{$name};
        $textparam .= $name.'='.$param{$name}.',';
    }

    # If the -n flag is specified,
    # add setupdns=yes into site.__SEQDiscover
    if ($::DNS)
    {
        $textparam .= "dns=yes,";
    }

    # If the -s flag is specified,
    # add skipbmcsetup=yes into site.__SEQDiscover
    if ($::SKIPBMCSETUP)
    {
        $textparam .= "skipbmcsetup=yes,";
    }

    $textparam =~ s/,\z//;

    # Check the running of profile-based discovery
    my @PCMdiscover = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if ($PCMdiscover[0]) {
        my $rsp;
        push @{$rsp->{data}}, "Sequentail Discovery cannot be run together with Profile-based discovery";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return;
    }

    # Check the running of sequential discovery
    my @SEQdiscover = xCAT::TableUtils->get_site_attribute("__SEQDiscover");
    if ($SEQdiscover[0]) {
        my $rsp;
        push @{$rsp->{data}}, "Sequentail Discovery is running. If you want to rerun the discovery, stop the running discovery first.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return;
    }

    # Check that the dynamic range in the dhcpd.conf has been set correctly
    # search all the network in the networks table that make sure the dynamic range for the deployment network has been set 

    # Set the discovery parameters to the site.__SEQDiscover which will be used by nodediscoverls/status/stop and findme, 
    my $sitetab = xCAT::Table->new("site");
    $sitetab->setAttribs({"key" => "__SEQDiscover"}, {"value" => "$textparam"});
    $sitetab->close();

    # Clean the entries which discovery method is 'sequential' from the discoverdata table
    my $distab = xCAT::Table->new("discoverydata");
    $distab->delEntries({method => 'sequential'});
    $distab->commit();

    # Calculate the available node name and IPs
    my @freenodes = getfreenodes($param{'noderange'}, "all");
    my @freehostips = getfreeips($param{'hostiprange'}, \@freenodes, "host", "all");
    my @freebmcips = getfreeips($param{'bmciprange'}, \@freenodes, "bmc", "all");

    #xCAT::MsgUtils->message("S", "Sequential Discovery: Start");
    my $rsp;
    push @{$rsp->{data}}, "Sequential Discovery: Started:";
    push @{$rsp->{data}}, "    Number of free node names: ".($#freenodes+1);
    if ($param{'hostiprange'}) {
        if (@freehostips) {
            push @{$rsp->{data}}, "    Number of free host ips: ".($#freehostips+1);
        } else {
            push @{$rsp->{data}}, "    No free host ips.";
        }
    }
    if ($param{'bmciprange'}) {
        if (@freebmcips) {
            push @{$rsp->{data}}, "    Number of free bmc ips: ".($#freebmcips+1);
        } else {
            push @{$rsp->{data}}, "    No free bmc ips.";
        }
    }
    xCAT::MsgUtils->message("I", $rsp, $callback);
    if ($::VERBOSE) {
        # dispaly the free nodes
        
        # get predefined host ip
        my %prehostips;
        my $prehosts = getpredefips(\@freenodes, "host");   #pre{ip} = nodename
        foreach (keys %$prehosts) {
            $prehostips{$prehosts->{$_}} = $_;   #pre{nodename} = ip
        }

        # get predefined bmc ip
        my %prebmcips;
        my $prebmcs = getpredefips(\@freenodes, "bmc"); #pre{ip} = bmcname
        foreach (keys %$prebmcs) {
            $prebmcips{$prebmcs->{$_}} = $_;   #pre{bmcname} = ip
        }

        # get the bmc of nodes
        my $ipmitab = xCAT::Table->new('ipmi');
        my $ipmient;
        if ($ipmitab) {
            $ipmient = $ipmitab->getNodesAttribs(\@freenodes, ['bmc']);
        }
                
        my $vrsp;
        push @{$vrsp->{data}}, "\n====================Free Nodes===================";
        push @{$vrsp->{data}}, sprintf("%-20s%-20s%-20s", "NODE", "HOST IP", "BMC IP");

        my $index = 0;
        foreach (@freenodes) {
            my $hostip;
            my $bmcip;
            # if predefined, use it; otherwise pop out one from the free ip list
            if (defined ($prehostips{$_})) {
                $hostip = $prehostips{$_};
            } else {
                while (($hostip = shift @freehostips)) {
                    if (!defined($prehosts->{$hostip})) { last;}
                }
                unless ($hostip) {
                    $hostip = "--no free--";
                }
            }

            # if predefined, use it; otherwise pop out one from the free ip list
            my $bmcname;
            if (defined ($ipmient->{$_}->[0]->{'bmc'})) {
                $bmcname = $ipmient->{$_}->[0]->{'bmc'};
                if ($bmcname =~ /\d+\.\d+\.\d+\.\d+/) {
                    $bmcip = $bmcname;
                } elsif (defined ($prebmcips{$bmcname})) {
                    $bmcip = $prebmcips{$bmcname};
                }
            }
            unless ($bmcip) {
                while (($bmcip = shift @freebmcips)) {
                    if (!defined($prebmcs->{$bmcip})) { last;}
                }
                unless ($bmcip) {
                    $bmcip = "--no free--";
                }
            }
            
            push @{$vrsp->{data}}, sprintf("%-20s%-20s%-20s", $_, $hostip, $bmcip);
            $index++;
        }
        xCAT::MsgUtils->message("I", $vrsp, $callback);
        
    }
}


=head3 nodediscoverstop 
 Stop the sequencial discovery process
=cut
sub nodediscoverstop {
    my $callback = shift;
    my $args = shift;
    my $auto = shift;

    my $usage = sub {
        my $cb = shift;
        my $msg = shift;

        my $rsp;
        if ($msg) {
            push @{$rsp->{data}}, $msg;
            xCAT::MsgUtils->message("E", $rsp, $cb, 1);
        }

        my $usageinfo = "nodediscoverstop: Stop the running discovery: Sequential and Profile.
Usage: 
  nodediscoverstop [-h|--help|-v|--version]    ";
        $rsp = ();
        push @{$rsp->{data}}, $usageinfo;
        xCAT::MsgUtils->message("I", $rsp, $cb);
    };
    
    if ($args) {    
        @ARGV = @$args;
    }
    my ($help, $ver); 
    if (!GetOptions(
        'h|help' => \$help,
        'V|verbose' => \$::VERBOSE,
        'v|version' => \$ver)) {
        $usage->($callback);
        return;
    }

    if ($help) {
        $usage->($callback);
        return;
    }
    if ($ver) {
        &displayver($callback);
        return;
    }

    # Check the running of sequential discovery
    my @SEQDiscover = xCAT::TableUtils->get_site_attribute("__SEQDiscover");
    my @PCMDiscover = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if ($PCMDiscover[0]) {
        # return directly that profile discover will cover it
        return;
    } elsif (!$SEQDiscover[0]) {
        # Neither of profile nor sequential was running
        my $rsp;
        push @{$rsp->{data}}, "Sequential Discovery is stopped.";
        push @{$rsp->{data}}, "Profile Discovery is stopped.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return;
    }
    
    my $DBname = xCAT::Utils->get_DBName;   # support for DB2
    # Go thought discoverydata table and display the sequential disocvery entries
    my $distab = xCAT::Table->new('discoverydata');
    unless ($distab) {
        my $rsp;
        push @{$rsp->{data}}, "Discovery Error: Could not open table: discoverydata.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }
    my @disdata;
    if ($DBname =~ /^DB2/) {
     @disdata = $distab->getAllAttribsWhere("\"method\" = 'sequential'", 'node', 'mtm', 'serial');
    } else {
     @disdata = $distab->getAllAttribsWhere("method='sequential'", 'node', 'mtm', 'serial');
    }
    my @discoverednodes;

    foreach (@disdata) {
        push @discoverednodes, sprintf("    %-20s%-10s%-10s", $_->{'node'}, $_->{'mtm'}, substr($_->{'serial'},0,8), );
    }

    my $rsp;
    push @{$rsp->{data}}, "Discovered ".($#discoverednodes+1)." nodes.";
    if (@discoverednodes) {
        push @{$rsp->{data}}, sprintf("    %-20s%-10s%-10s", 'NODE', 'MTM', 'SERIAL');
        foreach (@discoverednodes) {
             push @{$rsp->{data}}, "$_"; 
        }
    }
    xCAT::MsgUtils->message("I", $rsp, $callback);

    if ($auto) {
        xCAT::MsgUtils->message("S", "Sequential Discovery: Auto Stopped because all $auto in the specified range have been assigned to discovered nodes. Run \'nodediscoverls -t seq\' to display the discovery result.");
    } else {
        xCAT::MsgUtils->message("S", "Sequential Discovery: Stoped.");
    }

    # Remove the site.__SEQDiscover
    my $sitetab = xCAT::Table->new("site");
    $sitetab->delEntries({key => '__SEQDiscover'});
    $sitetab->commit();
}

=head3 nodediscoverls 
 Display the discovered nodes
=cut
sub nodediscoverls {
    my $callback = shift;
    my $args = shift;

    my $usage = sub {
        my $cb = shift;
        my $msg = shift;

        my $rsp;
        if ($msg) {
            push @{$rsp->{data}}, $msg;
            xCAT::MsgUtils->message("E", $rsp, $cb, 1);
        }

        my $usageinfo = "nodediscoverls: list the discovered nodes.
Usage: 
    nodediscoverls
    nodediscoverls [-h|--help|-v|--version] 
    nodediscoverls [-t seq|profile|switch|blade|manual|undef|all] [-l] 
    nodediscoverls [-u uuid] [-l]
    ";
        $rsp = ();
        push @{$rsp->{data}}, $usageinfo;
        xCAT::MsgUtils->message("I", $rsp, $cb);
    };

    if ($args) {    
        @ARGV = @$args;
    }
    my ($type, $uuid, $long, $help, $ver); 
    if (!GetOptions(
        't=s' => \$type,
        'u=s' => \$uuid,
        'l' => \$long,
        'h|help' => \$help,
        'V|verbose' => \$::VERBOSE,
        'v|version' => \$ver)) {
        $usage->($callback);
        return;
    }

    if ($help) {
        $usage->($callback);
        return;
    }
    if ($ver) {
        &displayver($callback);
        return;
    }

    # If the type is specified, display the corresponding type of nodes
    my @SEQDiscover;
    if ($type) {
        if ($type !~ /^(seq|profile|switch|blade|manual|undef|all)$/) {
            $usage->($callback, "The discovery type \'$type\' is not supported.");
            return;
        }
    } elsif ($uuid) {
    } else {
        # Check the running of sequential discovery
        @SEQDiscover = xCAT::TableUtils->get_site_attribute("__SEQDiscover");
        if  ($SEQDiscover[0]) {
            $type = "seq";
        } else {
            my @PCMDiscover = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
            if ($PCMDiscover[0]) {
                #return directly if my type of discover is not running.
                 return;
            } else {
                 # no type, no seq and no profile, then just diaplay all
                 $type = "all";
            }
        }
    }

    my $DBname = xCAT::Utils->get_DBName;   # support for DB2
    # Go thought discoverydata table and display the disocvery entries
    my $distab = xCAT::Table->new('discoverydata');
    unless ($distab) {
        my $rsp;
        push @{$rsp->{data}}, "Discovery Error: Could not open table: discoverydata.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }
    my @disdata;
    my @disattrs;
    if ($long) {
        @disattrs = ('uuid', 'node', 'method', 'discoverytime', 'arch', 'cpucount', 'cputype', 'memory', 'mtm', 'serial', 'nicdriver', 'nicipv4', 'nichwaddr', 'nicpci', 'nicloc', 'niconboard', 'nicfirm', 'switchname', 'switchaddr', 'switchdesc', 'switchport');
    } else {
        @disattrs = ('uuid', 'node', 'method', 'mtm', 'serial');        
    }
    if ($type) {
        if ($type eq "all") {
            @disdata = $distab->getAllAttribs(@disattrs);
        } else {
            $type = "sequential" if ($type =~ /^seq/);
            if ($DBname =~ /^DB2/) {
              @disdata = $distab->getAllAttribsWhere("\"method\" = '$type'", @disattrs);
            } else {
              @disdata = $distab->getAllAttribsWhere("method='$type'", @disattrs);
            }
        }
    } elsif ($uuid) {
        if ($DBname =~ /^DB2/) {
          @disdata = $distab->getAllAttribsWhere("\"uuid\" = '$uuid'", @disattrs);
        } else {
          @disdata = $distab->getAllAttribsWhere("uuid='$uuid'", @disattrs);
        }
    }
    my $discoverednum = $#disdata + 1;
    
    my @discoverednodes;
    foreach my $ent (@disdata) {
        if ($long) {
            foreach my $attr (@disattrs) {
                if ($attr eq "uuid") {
                    push @discoverednodes, "Object uuid: $ent->{$attr}";
                } elsif (defined ($ent->{$attr})) {
                    push @discoverednodes, "    $attr=$ent->{$attr}";
                }
            }
        } else {
            $ent->{'node'} = 'undef' unless ($ent->{'node'});
            $ent->{'method'} = 'undef' unless ($ent->{'method'});
            push @discoverednodes, sprintf("  %-40s%-20s%-15s%-10s%-10s", $ent->{'uuid'}, $ent->{'node'}, $ent->{'method'}, $ent->{'mtm'}, substr($ent->{'serial'},0,8));
        }
    }

    my $rsp;
    if ($SEQDiscover[0] && $type eq "sequential") {
        push @{$rsp->{data}}, "Discovered $discoverednum node.";
    }
    if (@discoverednodes) {
        unless ($long) {
            push @{$rsp->{data}}, sprintf("  %-40s%-20s%-15s%-10s%-10s", 'UUID', 'NODE', ,'METHOD', 'MTM', 'SERIAL');
        }
        foreach (@discoverednodes) {
             push @{$rsp->{data}}, "$_"; 
        }
    }

    xCAT::MsgUtils->message("I", $rsp, $callback);
}


=head3 nodediscoverstatus 
 Display the discovery status
=cut
sub nodediscoverstatus {
    my $callback = shift;
    my $args = shift;

    my $usage = sub {
        my $cb = shift;
        my $msg = shift;

        my $rsp;
        if ($msg) {
            push @{$rsp->{data}}, $msg;
            xCAT::MsgUtils->message("E", $rsp, $cb, 1);
        }

        my $usageinfo = "nodediscoverstatus: Display the discovery process status.
Usage: 
    nodediscoverstatus [-h|--help|-v|--version]     ";
        $rsp = ();
        push @{$rsp->{data}}, $usageinfo;
        xCAT::MsgUtils->message("I", $rsp, $cb);
    };
    
    if ($args) {    
        @ARGV = @$args;
    }
    my ($type, $uuid, $long, $help, $ver); 
    if (!GetOptions(
        'h|help' => \$help,
        'V|verbose' => \$::VERBOSE,
        'v|version' => \$ver)) {
        $usage->($callback);
        return;
    }

    if ($help) {
        $usage->($callback);
        return;
    }
    if ($ver) {
        &displayver($callback);
        return;
    }

    # Check the running of sequential discovery
    my @SEQDiscover = xCAT::TableUtils->get_site_attribute("__SEQDiscover");
    my @PCMDiscover = xCAT::TableUtils->get_site_attribute("__PCMDiscover");
    if  ($SEQDiscover[0]) {
        my $rsp;
        push @{$rsp->{data}}, "Sequential discovery is running.";
        push @{$rsp->{data}}, "    The parameters used for discovery: ".$SEQDiscover[0];
        xCAT::MsgUtils->message("I", $rsp, $callback);
    } elsif ($PCMDiscover[0]) {
        my $rsp;
        push @{$rsp->{data}}, "Node discovery for all nodes using profiles is running";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    } else {
        my $rsp;
        push @{$rsp->{data}}, "Sequential Discovery is stopped.";
        push @{$rsp->{data}}, "Profile Discovery is stopped.";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

}

=head3 nodediscoverdef
  Define the undefined entry from the discoverydata table to a specific node
  Or clean the discoverydata table
=cut
sub nodediscoverdef {
    my $callback = shift;
    my $subreq = shift;
    my $args = shift;

    # The subroutine used to display the usage message
    my $usage = sub {
        my $cb = shift;
        my $msg = shift;

        my $rsp;
        if ($msg) {
            push @{$rsp->{data}}, $msg;
            xCAT::MsgUtils->message("E", $rsp, $cb, 1);
        }

        my $usageinfo = "nodediscoverdef: Define the undefined discovery request, or clean the discovery entries in the discoverydata table (Which can be displayed by nodediscoverls command).
Usage: 
    nodediscoverdef -u uuid -n node
    nodediscoverdef -r -u uuid
    nodediscoverdef -r -t {seq|profile|switch|blade|manual|undef|all}
    nodediscoverdef [-h|--help|-v|--version]";
        $rsp = ();
        push @{$rsp->{data}}, $usageinfo;
        xCAT::MsgUtils->message("I", $rsp, $cb);
    };

    # Parse arguments
    if ($args) {    
        @ARGV = @$args;
    }
    my ($type, $uuid, $node, $remove, $help, $ver); 
    if (!GetOptions(
        'u=s' => \$uuid,
        'n=s' => \$node,
        't=s' => \$type,
        'r' => \$remove,
        'h|help' => \$help,
        'V|verbose' => \$::VERBOSE,
        'v|version' => \$ver)) {
        $usage->($callback);
        return;
    }

    if ($help) {
        $usage->($callback);
        return;
    }
    if ($ver) {
        &displayver($callback);
        return;
    }

    my $DBname = xCAT::Utils->get_DBName;   # support for DB2
    # open the discoverydata table for the subsequent using
    my $distab = xCAT::Table->new("discoverydata");
    unless ($distab) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: discoverydata.");
        return;
    }
    
    if ($remove) {
        # handle the -r to remove the entries from discoverydata table
        if (!($uuid || $type) || $node) {
            $usage->($callback);
            return;
        }
        if ($uuid && $type) {
            $usage->($callback);
            return;
        }
        
        if ($uuid) {
            # handle the -r -u <uuid>
            my @disdata;
            if ($DBname =~ /^DB2/) {
             @disdata = $distab->getAllAttribsWhere("\"uuid\" = '$uuid'", 'method');
            } else {
             @disdata = $distab->getAllAttribsWhere("uuid='$uuid'", 'method');
            }
            unless (@disdata) {
                xCAT::MsgUtils->message("E", {data=>["Cannot find discovery entry with uuid equals [$uuid]."]}, $callback);
                return;
            }
            
            $distab->delEntries({uuid => $uuid});
            $distab->commit();
        } elsif ($type) {
            # handle the -r -t <...>
            if ($type !~ /^(seq|profile|switch|blade|manual|undef|all)$/) {
                $usage->($callback, "The discovery type \'$type\' is not supported.");
                return;
            }
            
            if ($type eq "all") {
                # remove all the entries from discoverydata table
                # there's no subroutine to remove all the entries from a table, so just make code to work around

                # get all the entries first
                my @disdata = $distab->getAllAttribs('uuid', 'method');
                my %methodlist;
                foreach my $ent (@disdata) {
                    if ($ent->{'method'}) {
                        # if the entry has 'method' att set, classify them and remove at once
                        $methodlist{$ent->{'method'}} = 1;
                    } else {
                        # if 'method' is not set, remove the entry directly
                        $distab->delEntries({uuid => $ent->{'uuid'}});
                    }
                }

                # remove entries which have method att been set
                foreach (keys %methodlist) {
                    $distab->delEntries({method => $_});
                }
                $distab->commit();
            } else {
                # remove the specific type of discovery entries
                if ($type =~ /^seq/) {
                    $type = "sequential";
                }
                $distab->delEntries({method => $type});
                $distab->commit();
            }
        }
        xCAT::MsgUtils->message("I", {data=>["Removing discovery entries finished."]}, $callback);
    } elsif ($uuid) {
        # define the undefined entry to a node
        if (!$node) {
            $usage->($callback);
            return;
        }

        # make sure the node is valid. 
        my @validnode = noderange($node);
        if ($#validnode != 0) {
            xCAT::MsgUtils->message("E", {data=>["The node [$node] should be a valid xCAT node."]}, $callback);
            return;
        }
        $node = $validnode[0];

        # to define the a request to a node, reuse the 'discovered' command to update the node
        # so the procedure will be that regenerate the request base on the attributes which stored in the discoverydata table

        # get all the attributes for the entry from the discoverydata table
        my @disattrs = ('uuid', 'node', 'method', 'discoverytime', 'arch', 'cpucount', 'cputype', 'memory', 'mtm', 'serial', 'nicdriver', 'nicipv4', 'nichwaddr', 'nicpci', 'nicloc', 'niconboard', 'nicfirm', 'switchname', 'switchaddr', 'switchdesc', 'switchport', 'otherdata');
        my @disdata ;
        if ($DBname =~ /^DB2/) {
         @disdata = $distab->getAllAttribsWhere("\"uuid\" = '$uuid'", @disattrs);
        } else {
         @disdata = $distab->getAllAttribsWhere("uuid='$uuid'", @disattrs);
        }
        unless (@disdata) {
            xCAT::MsgUtils->message("E", {data=>["Cannot find discovery entry with uuid equals $uuid"]}, $callback);
            return;
        }

        # generate the request which is used to define the node
        my $request;
        my $ent = @disdata[0];
        my $interfaces;
        my $otherdata;
        foreach my $key (keys %$ent) {
            if ($key =~ /(nicdriver|nicfirm|nicipv4|nichwaddr|nicpci|nicloc|niconboard|switchaddr|switchname|switchport)/) {
                # these entries are formatted as: eth0!xxx,eth1!xxx. split it and generate the request as eth0 {...}, eth1 {...}
                my @ifs = split (/,/, $ent->{$key});
                foreach (@ifs) {
                    my ($if, $value) = split('!', $_);
                    my $origname = $key;
                    if ($key eq "nicdriver") {
                        $origname = "driver";
                    } elsif ($key eq "nicfirm") {
                        $origname = "firmdesc";
                    } elsif ($key eq "nicipv4") {
                        $origname = "ip4address";
                    } elsif ($key eq "nichwaddr") {
                        $origname = "hwaddr";
                    } elsif ($key eq "nicpci") {
                        $origname = "pcidev";
                    } elsif ($key eq "nicloc") {
                        $origname = "location";
                    } elsif ($key eq "niconboard") {
                        $origname = "onboardeth";
                    } 
                    push @{$interfaces->{$if}->{$origname}}, $value;
                }
            } elsif ($key eq "otherdata") {
                # this entry is just keep as is, so translate to hash is enough
                $otherdata = eval { XMLin($ent->{$key}, SuppressEmpty=>undef,ForceArray=>1) };
            } elsif ($key eq "switchdesc") {
                # just ingore the switchdesc, since it include ','
            }else {
                # for general attrs which just have one first level
                $request->{$key} = [$ent->{$key}];
            }
        }

        # add the interface part to the request hash
        if ($interfaces) {
            foreach (keys %$interfaces) {
                $interfaces->{$_}->{'devname'} = [$_];
                push @{$request->{nic}}, $interfaces->{$_};
            }
        }

        # add the untouched part to the request hash
        if ($otherdata) {
            foreach (keys %$otherdata) {
                $request->{$_} = $otherdata->{$_};
            }
        }

        # call the 'discovered' command to update the request to a node
        $request->{command}=['discovered'];
        $request->{node} = [$node];
        $request->{discoverymethod} = ['manual'];
        $request->{updateswitch} = ['yes'];
        my $rsp = $subreq->($request);
        if (defined ($rsp->{errorcode}->[0])) {
            xCAT::MsgUtils->message("E", $rsp, $callback);
        } else {
            xCAT::MsgUtils->message("I", {data=>["Defined [$uuid] to node $node."]}, $callback);
        }
    } else {
        $usage->($callback);
        return;
    }
}

sub process_request {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $command = $request->{command}->[0];
    my $args = $request->{arg};

    if ($command eq "findme"){
        findme($request, $callback, $subreq);
    } elsif ($command eq "nodediscoverstart") {
        nodediscoverstart($callback, $args);
    } elsif ($command eq "nodediscoverstop") {
        nodediscoverstop($callback, $args);
    } elsif ($command eq "nodediscoverls") {
        nodediscoverls($callback, $args);
    } elsif ($command eq "nodediscoverstatus") {
        nodediscoverstatus($callback, $args);
    } elsif ($command eq "nodediscoverdef") {
        nodediscoverdef($callback, $subreq, $args);
    }
}

=head3 getfreenodes 
 Get the free nodes base on the user specified noderange and defined nodes
 arg1 - the noderange
 arg2 - "all': return all the free nodes; otherwise just return one.
=cut
sub getfreenodes () {
    my $noderange = shift;
    my $all = shift;
    
    my @freenodes;

    # get all the nodes from noderange
    my @nodes = noderange($noderange, 0);
    
    # get all nodes from nodelist and mac table
    my $nltb = xCAT::Table->new('nodelist');
    unless ($nltb) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: nodelist.");
        return;
    }

    my $mactb = xCAT::Table->new('mac');
    unless ($mactb) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: mac.");
        return;
    }

    # if mac address has been set, the node is not free
    my $nlent = $nltb->getNodesAttribs(\@nodes,['groups']);
    my $macent = $mactb->getNodesAttribs(\@nodes,['mac']);
    foreach my $node (@nodes) {
        if ($nlent->{$node}->[0]) {
            unless ($macent->{$node}->[0] && $macent->{$node}->[0]->{'mac'}) {
                push @freenodes, $node;
                unless ($all) { last;}
            }
        } else {
            push @freenodes, $node;
            unless ($all) { last;}
        }
    }

    unless (@freenodes) {
        return;
    }

    if ($all ) {
        return @freenodes;
    } else {
        return $freenodes[0];
    }
}

=head3 getpredefips
 Get the ips which have been predefined to host or bmc
 arg1 - a refenrece to the array of nodes 
 arg2 - type: host, bmc

 return: hash {ip} = node
=cut
sub getpredefips {
    my $freenode = shift;
    my $type = shift;   # type: host, bmc

    my $hoststb = xCAT::Table->new('hosts');
    unless ($hoststb) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: hosts.");
    }
    
    my %predefips;   # to have the ip which prefined to the nodes
    if ($type eq "bmc") {
        # Find the bmc name from the ipmi table.
        # if ipmi.bmc is an IP address, that means this is the IP of bmc
        my @freebmc;
        my %node2bmc; # $node2bmc{$node} = $bmc;
        my $ipmitab = xCAT::Table->new('ipmi');
        if ($ipmitab) {
            my $ipmient = $ipmitab->getNodesAttribs($freenode, ['bmc']);
            foreach (@$freenode) {
                if (defined($ipmient->{$_}->[0]->{'bmc'})) {
                    if ($ipmient->{$_}->[0]->{'bmc'} =~ /\d+\.\d+\.\d+\.\d+/) {
                        $predefips{$ipmient->{$_}->[0]->{'bmc'}} = $_."-bmc";
                    } else {
                        push @freebmc, $ipmient->{$_}->[0]->{'bmc'};
                        $node2bmc{$_} = $ipmient->{$_}->[0]->{'bmc'};
                    }
                }
            }
        }

        # check the system resolution first, then host.ip, then host.otherinterfaces
        my $freenodeent = $hoststb->getNodesAttribs(\@freebmc, ['ip']);
        foreach (@freebmc) {
            my $nodeip = xCAT::NetworkUtils->getipaddr($_);
            if ($nodeip) {
                # handle the bmc which could be resolved to an IP by system
                $predefips{$nodeip} = $_;
            } else {
                # handle the bmc which IP was defined in the hosts.ip
                if (defined($freenodeent->{$_}->[0]) && $freenodeent->{$_}->[0]->{'ip'}){
                    $predefips{$freenodeent->{$_}->[0]->{'ip'}} = $_;
                }
            }
        }

        # handle the bmcs which bmc has been set in the hosts.otherinterfaces
        $freenodeent = $hoststb->getNodesAttribs($freenode, ['otherinterfaces']);
        foreach (@$freenode) {
            if (defined ($node2bmc{$_})) {
                # for bmc node, search the hosts.otherinterface to see whether there's perdefined ip for bmc
                my $bmcip = getbmcip_otherinterfaces($_, $node2bmc{$_}, $freenodeent->{$_}->[0]->{'otherinterfaces'});
                if ($bmcip) {
                    $predefips{$bmcip} = $node2bmc{$_};
                }
            }
        }
    } elsif ($type eq "host") {
        # get the predefined node which ip has been set in the hosts.ip
        my $freenodeent = $hoststb->getNodesAttribs($freenode, ['ip']);
        
        foreach (@$freenode) {
            my $nodeip = xCAT::NetworkUtils->getipaddr($_);
            if ($nodeip) {
                $predefips{$nodeip} = $_;
            } else {
                if (defined($freenodeent->{$_}->[0]) && $freenodeent->{$_}->[0]->{'ip'}){
                    $predefips{$freenodeent->{$_}->[0]->{'ip'}} = $_;
                }
            }
        }
    }

    return \%predefips;
}

=head3 getfreeips 
 Get the free ips base on the user specified ip range
 arg1 - the ip range. Two format are suported: 192.168.1.1-192.168.2.50; 192.168.[1-2].[10-100]
 arg2 - all the free nodes
 arg3 - type: host, bmc
 arg4 - "all': return free ips for all the free nodes; otherwise just return the first one.

 return: array of all free ips or one ip base on the arg4
=cut
sub getfreeips {
    my $iprange = shift;
    my $freenode = shift;
    my $type = shift;   # type: host, bmc
    my $all = shift;

    my @freeips;
    my %predefips;   # to have the ip which prefined to the nodes

    my $hoststb = xCAT::Table->new('hosts');
    unless ($hoststb) {
        xCAT::MsgUtils->message("S", "Discovery Error: Could not open table: hosts.");
    }

    my @freebmc;
    my %usedips = ();
    if ($type eq "bmc") {
        # get the host ip for all predefind nodes from $freenode
        %predefips = %{getpredefips($freenode, "bmc")};

        # get all the used ips, the predefined ip should be ignored
        my @hostsent = $hoststb->getAllNodeAttribs(['node', 'ip', 'otherinterfaces']);

        # Find the bmc name from the ipmi table.
        # if ipmi.bmc is an IP address, that means this is the IP of bmc
        my %node2bmc; # $node2bmc{$node} = $bmc;
        my $ipmitab = xCAT::Table->new('ipmi');
        if ($ipmitab) {
            my @ipmients = $ipmitab->getAllNodeAttribs(['node', 'bmc']);
            foreach my $ipmient (@ipmients) {
                if (defined($ipmient->{'bmc'})) {
                    if ($ipmient->{'bmc'} =~ /\d+\.\d+\.\d+\.\d+/) {
                        unless ($predefips{$ipmient->{'bmc'}}) {
                            $usedips{$ipmient->{'bmc'}} = 1;
                        }
                    } else {
                        $node2bmc{$ipmient->{'node'}} = $ipmient->{'bmc'};
                    }
                }
            }
        }
        
        foreach my $host (@hostsent) {
            # handle the case that bmc has an entry in the hosts table
            my $nodeip = xCAT::NetworkUtils->getipaddr($host->{'node'});
            if ($nodeip) {
                unless ($predefips{$nodeip}) {
                    $usedips{$nodeip} = 1;
                }
            } else {
                if (defined ($host->{'ip'}) && !$predefips{$host->{'ip'}}) {
                    $usedips{$host->{'ip'}} = 1;
                }
            }
            # handle the case that the bmc<->ip mapping is specified in hosts.otherinterfaces
            if (defined ($node2bmc{$host->{'node'}})) {
                my $bmcip = xCAT::NetworkUtils->getipaddr($node2bmc{$host->{'node'}});
                if ($bmcip) {
                    unless ($predefips{$bmcip}) {
                        $usedips{$bmcip} = 1;
                    }
                } else {
                    if (defined($host->{'otherinterfaces'})) {
                        my $bmcip = getbmcip_otherinterfaces($host->{'node'}, $node2bmc{$host->{'node'}}, $host->{'otherinterfaces'});
                        unless ($predefips{$bmcip}) {
                            $usedips{$bmcip} = 1;
                        }
                    }
                }
            }
        }
    } elsif ($type eq "host") {
        # get the bmc ip for all predefind nodes from $freenode
        %predefips = %{getpredefips($freenode, "host")};

        # get all the used ips, the predefined ip should be ignored
        my @hostsent = $hoststb->getAllNodeAttribs(['node', 'ip']);
        foreach my $host (@hostsent) {
            my $nodeip = xCAT::NetworkUtils->getipaddr($host->{'node'});
            if ($nodeip) {
                unless ($predefips{$nodeip}) {
                    $usedips{$nodeip} = 1;
                }
            } else {
                if (defined ($host->{'ip'}) && !$predefips{$host->{'ip'}}) {
                    $usedips{$host->{'ip'}} = 1;
                }
            }
        }
    }

    # to calculate the free IP. free ip = 'ip in the range' - 'used ip'
    if ($iprange =~ /(\d+\.\d+\.\d+\.\d+)-(\d+\.\d+\.\d+\.\d+)/) {
        # if ip range format is 192.168.1.0-192.168.1.200
        my ($startip, $endip) = ($1, $2);
        my $startnum = xCAT::NetworkUtils->ip_to_int($startip);
        my $endnum = xCAT::NetworkUtils->ip_to_int($endip);
    
        while ($startnum <= $endnum) {
            my $ip = xCAT::NetworkUtils->int_to_ip($startnum);
            unless ($usedips{$ip}) {
                push @freeips, $ip;
                unless ($all) {last;}
            }
            $startnum++;
        }
    } elsif ($iprange) {
        # use the noderange to expand the range
        my @ips = noderange($iprange, 0);
        foreach my $ip (@ips) {
            unless ($usedips{$ip}) {
                push @freeips, $ip;
                unless ($all) {last;}
            }
        }
    } else {
        # only find the ip which mapping to the node
    }

    unless (@freeips) {
        return;
    }

    if ($all) {
        return @freeips;
    } else {
        return $freeips[0];
    }
}

=head3 getbmcip_otherinterfaces 
 Parse the value in the hosts.otherinterfaces
 arg1 - node
 arg2 - bmc name
 arg3 - value in the hosts.otherinterfaces

 return: the ip of the node <node>-bmc
=cut
sub getbmcip_otherinterfaces
{
    my $node = shift;
    my $bmc  = shift;
    my $otherinterfaces = shift;

    my @itf_pairs = split(/,/, $otherinterfaces);
    foreach (@itf_pairs)
    {
        my ($itf, $ip); 
        if ($_  =~ /!/) {
        	($itf, $ip) = split(/!/, $_);
        } else {
        	($itf, $ip) = split(/:/, $_);
        }

        if ($itf =~ /^-/)
        {
            $itf = $node . $itf;
        }

        if ($itf eq $bmc) {
            return xCAT::NetworkUtils->getipaddr($ip);
        }
    }

    return;
}

1;
