#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::nodediscover;
use xCAT::Table;
use IO::Socket;
use strict;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use IO::Select;
use IO::Handle;
use xCAT::Utils;
use Sys::Syslog;
use Text::Balanced qw(extract_bracketed);
use xCAT::data::switchinfo;
use xCAT::DiscoveryUtils;


sub gethosttag {

    #This function tries to return a good hostname for a node based on the
    #network to which it is connected (by $netn or maybe $ifname)
    #heuristic:
    #if the client had a valid IP address from a dhcp server, that is used as key
    #once the matching network is found, and an explicit mapping defined, try that
    #next, try to see if the ip for the case where hostname==nodename is on this net, if so, return that
    #next, try to do nodename-ifname, return that if successful
    #next, repeat process for all networks that have the common mgtifname field
    #return undef for now if none of the above worked
    my $node       = shift;
    my $netn       = shift;
    my $ifname     = shift;
    my $usednames  = shift;
    my %netmap     = %{ xCAT::NetworkUtils::my_if_netmap() };
    my $mgtifname  = $netmap{$netn};
    my $secondpass = 0;
    my $name       = "";
    my $defhost    = inet_aton($node);
    my $nettab     = xCAT::Table->new('networks');
    my $defn       = "";
    my @netents    = @{ $nettab->getAllEntries() };
    my $pass;

    #TODO: mgtifname field will get trounced in hierarchical setup, use a live check to match accurately
    foreach (@netents) {
        if ($_->{net} eq $netn or ($mgtifname and $mgtifname eq $netmap{ $_->{net} })) { #either is the network  or shares physical interface
            if ($_->{nodehostname}) { #Check for a nodehostname rule in the table
                $name = $node;
                if ($_->{nodehostname} =~ /^\/[^\/]*\/[^\/]*\/$/) {
                    my $exp = substr($_->{nodehostname}, 1);
                    chop $exp;
                    my @parts = split('/', $exp, 2);
                    $name =~ s/$parts[0]/$parts[1]/;
                }
                elsif ($_->{nodehostname} =~ /^\|.*\|.*\|$/) {

                    #Perform arithmetic and only arithmetic operations in bracketed issues on the right.
                    #Tricky part:  don't allow potentially dangerous code, only eval if
                    #to-be-evaled expression is only made up of ()\d+-/%$
                    #Futher paranoia?  use Safe module to make sure I'm good
                    my $exp = substr($_->{nodehostname}, 1);
                    chop $exp;
                    my @parts = split('\|', $exp, 2);
                    my $curr;
                    my $next;
                    my $prev;
                    my $retval = $parts[1];
                    ($curr, $next, $prev) =
                      extract_bracketed($retval, '()', qr/[^()]*/);

                    unless ($curr) { #If there were no paramaters to save, treat this one like a plain regex
                        $name =~ s/$parts[0]/$parts[1]/;
                    }
                    while ($curr) {

                        #my $next = $comps[0];
                        if ($curr =~ /^[\{\}()\-\+\/\%\*\$\d]+$/ or $curr =~ /^\(sprintf\(["'%\dcsduoxefg]+,\s*[\{\}()\-\+\/\%\*\$\d]+\)\)$/)
                        {
                            use integer;

                            #We only allow integer operations, they are the ones that make sense for the application
                            my $value = $name;
                            $value =~ s/$parts[0]/$curr/ee;
                            $retval = $prev . $value . $next;
                        }
                        else {
                            print "$curr is bad\n";
                        }
                        ($curr, $next, $prev) =
                          extract_bracketed($retval, '()', qr/[^()]*/);
                    }

                    #At this point, $retval is the expression after being arithmetically contemplated, a generated regex, and therefore
                    #must be applied in total
                    $name =~ s/$parts[0]/$retval/;

                    #print Data::Dumper::Dumper(extract_bracketed($parts[1],'()',qr/[^()]*/));
                    #use text::balanced extract_bracketed to parse earch atom, make sure nothing but arith operators, parans, and numbers are in it to guard against code execution
                }

                print "Name: $name\n";

                #$name =~ s/$left/$right/;
                if ($name and inet_aton($name)) {
                    if ($netn eq $_->{net} and not $usednames->{$name}) { return $name; }

                    #At this point, it could still be valid if block was entered due to mgtifname
                    my $nnetn = inet_ntoa(pack("N", unpack("N", inet_aton($name)) & unpack("N", inet_aton($_->{mask}))));
                    if ($nnetn eq $_->{net} and not $usednames->{$name}) { return $name; }
                }
                $name = "";    #Still here, this branch failed
            }
            $defn = "";
            if ($defhost) {
                $defn = inet_ntoa(pack("N", unpack("N", $defhost) & unpack("N", inet_aton($_->{mask}))));
            }
            if ($defn eq $_->{net} and not $usednames->{$node}) { #the default nodename is on this network
                return $node;
            }
            my $tentativehost = $node . "-" . $ifname;
            my $tnh           = inet_aton($tentativehost);
            if ($tnh) {
                my $nnetn = inet_ntoa(pack("N", unpack("N", $tnh) & unpack("N", inet_aton($_->{mask}))));
                if ($nnetn eq $_->{net} and not $usednames->{$tentativehost}) {
                    return $tentativehost;
                }
            }
        }
    }
}

sub handled_commands {
    return {
        #discovered => 'chain:ondiscover',
        discovered => 'nodediscover',
    };
}

sub process_request {
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $node     = $request->{node}->[0];
    my $clientip = $request->{'_xcat_clientip'};
    openlog("xcat", '', 'local0');


    #First, fill in tables with data fields..
    if (defined($request->{mtm}) or defined($request->{serial})) {
        my $vpdtab = xCAT::Table->new("vpd", -create => 1);
        if ($request->{uuid}->[0]) {
            $vpdtab->setNodeAttribs($node, { uuid => $request->{uuid}->[0] });
        }
        if ($request->{mtm}->[0]) {
            $vpdtab->setNodeAttribs($node, { mtm => $request->{mtm}->[0] });
        }
        if ($request->{serial}) {
            $vpdtab->setNodeAttribs($node, { serial => $request->{serial}->[0] });
        }
    }

    # if there is no bmc ip in ipmi table, save bmc ip into ipmi table
    if (defined($request->{bmc}) && $request->{bmc}->[0]) {
        my $ipmitab = xCAT::Table->new("ipmi", -create => 1);
        if ($ipmitab) {
            my $ipmient = $ipmitab->getNodeAttribs($node, ['bmc']);
            unless ($ipmient->{'bmc'}) {
                $ipmitab->setNodeAttribs($node, { bmc => $request->{bmc}->[0] });
            }
        } else {
            $callback->({ error => ["Open ipmi table failed."], errorcode => ["1"] });
        }
    }


    # save inventory info into the hwinv table
    if (defined($request->{cpucount}) or defined($request->{cputype}) or defined($request->{memory}) or defined($request->{disksize})) {
        my $basicdata;
        my $hwinv_tab = xCAT::Table->new("hwinv", -create => 1);
        if ($request->{memory}->[0]) {
            $basicdata->{memory} = $request->{memory}->[0];
        }
        if ($request->{disksize}->[0]) {
            my @disks = split /\n/, $request->{disksize}->[0];
            my $disk_info = join(",", @disks);
            $basicdata->{disksize} = $disk_info;
        }
        if ($request->{cpucount}->[0]) {
            $basicdata->{cpucount} = $request->{cpucount}->[0];
        }
        if ($request->{cputype}->[0]) {
            $basicdata->{cputype} = $request->{cputype}->[0];
        }
        $hwinv_tab->setNodeAttribs($node, $basicdata);
    }


    my $nrtab;
    my @discoverynics;
    my @forcenics; #list of 'eth' style interface names to require to come up on post-discovery client dhcp restart
    if (defined($request->{arch})) {

        #Set the architecture in nodetype.  If 32-bit only x86 or ppc detected, overwrite.  If x86_64, only set if either not set or not an x86 family
        my $typetab = xCAT::Table->new("nodetype", -create => 1);
        (my $nent) = $typetab->getNodeAttribs($node, [ 'arch', 'supportedarchs' ]);
        if ($request->{arch}->[0] =~ /x86_64/) {
            if ($nent and ($nent->{arch} =~ /x86/)) { #If already an x86 variant, do not change
                unless ($nent and $nent->{supportedarchs} =~ /x86_64/) {
                    $typetab->setNodeAttribs($node, { supportedarchs => "x86,x86_64" });
                }
            } else {
                $typetab->setNodeAttribs($node, { arch => $request->{arch}->[0], supportedarchs => "x86,x86_64" });

                #this check is so that if an admin explicitly declares a node 'x86', the 64 bit capability is ignored
            }
        } else {
            unless ($nent and $nent->{supportedarchs} eq $request->{arch}->[0] and $nent->{arch} eq $request->{arch}->[0]) {
                $typetab->setNodeAttribs($node, { arch => $request->{arch}->[0], supportedarchs => $request->{arch}->[0] });
            }
            if ($request->{arch}->[0] =~ /ppc/ and $request->{platform}->[0] =~ /PowerNV/) {
                $typetab->setNodeAttribs($node, { nodetype => 'mp' });
            }
        }
        my $currboot = '';
        $nrtab = xCAT::Table->new('noderes'); #Attempt to check and set if wrong the netboot method on discovery, if admin omitted
        (my $rent) = $nrtab->getNodeAttribs($node, [ 'netboot', 'discoverynics' ]);
        if ($rent and defined $rent->{discoverynics}) {
            @discoverynics = split /,/, $rent->{discoverynics};
        }
        if ($rent and $rent->{'netboot'}) {
            $currboot = $rent->{'netboot'};
        }

        if ($request->{arch}->[0] =~ /x86/ and $currboot !~ /pxe/ and $currboot !~ /xnba/) {
            $nrtab->setNodeAttribs($node, { netboot => 'xnba' });
        } elsif ($request->{arch}->[0] =~ /ppc/ and $request->{platform}->[0] =~ /PowerNV/) {
            $nrtab->setNodeAttribs($node, { netboot => 'petitboot' });
        } elsif ($request->{arch}->[0] =~ /ppc/ and $currboot !~ /yaboot/) {
            $nrtab->setNodeAttribs($node, { netboot => 'yaboot' });
        } elsif($request->{arch}->[0] =~ /armv7l/ and $currboot !~ /onie/) { 
            #for onie switch, the netboot should be "onie"
            $nrtab->setNodeAttribs($node, { netboot => 'onie' });  
        }
    }

    if(defined $request->{nodetype} and $request->{nodetype}->[0] = 'switch' and $request->{_xcat_clientmac}->[0]){
        #for onie switch, lookup and set the switchtype via mac of mgt interface
        my $switchestab = xCAT::Table->new('switches');
        if ($switchestab) {
            my $switchtype=$xCAT::data::switchinfo::global_mac_identity{substr(lc($request->{_xcat_clientmac}->[0]),0,8)};
            if(defined $switchtype){
                $switchestab->setNodeAttribs($node,{ switchtype => $switchtype });
            }
            $switchestab->close();
        }
    }
  

    my $macstring = "";
    if (defined($request->{mac})) {
        my $mactab = xCAT::Table->new("mac", -create => 1);
        my @ifinfo;
        my %usednames;
        my %usednames_for_net;
        my @hostnames_to_update = ();
        my %bydriverindex;
        my $forcenic = 0; #-1 is force skip, 0 is use default behavior, 1 is force to be declared even if hosttag is skipped to do so
        foreach (@{ $request->{mac} }) {
            @ifinfo = split /\|/;

            if ($ifinfo[1] eq 'usb0') {    #skip usb nic
                next;
            }

            $bydriverindex{ $ifinfo[0] } += 1;
            if (scalar @discoverynics) {
                $forcenic = -1;    #$forcenic defaults to explicitly skip nic
                foreach my $nic (@discoverynics) {
                    if ($nic =~ /:/) { #syntax like 'bnx2:0' to say the first bnx2 managed interface
                        (my $driver, my $index) = split /:/, $nic;
                        if ($driver eq $ifinfo[0] and $index == ($bydriverindex{$driver} - 1)) {
                            $forcenic = 1;    #force nic to be put into database
                            push @forcenics, $ifinfo[1];
                            last;
                        }
                    } else {    #simple 'eth2' sort of argument
                        if ($nic eq $ifinfo[1]) {
                            push @forcenics, $ifinfo[1];
                            $forcenic = 1;
                            last;
                        }
                    }
                }
            }
            if ($forcenic == -1) {    #if force to skip, go to next nic
                next;
            }
            my $currmac = lc($ifinfo[2]);
            if ($ifinfo[3]) {
                (my $ip, my $netbits) = split /\//, $ifinfo[3];
                if ($ip =~ /\d+\.\d+\.\d+\.\d+/) {
                    my $ipn = unpack("N", inet_aton($ip));
                    my $mask = 2**$netbits - 1 << (32 - $netbits);
                    my $netn = inet_ntoa(pack("N", $ipn & $mask));
                    my $hosttag = gethosttag($node, $netn, @ifinfo[1], \%usednames);
                    unless ($hosttag) {
                        my $nettagname = $usednames_for_net{$netn};
                        # For nics not in the install network, don't deal with them if not an avaliable hostname get 
                        # In case another nic in install network get a hosttag other than nodename, need to compare the IP address they can convert to
                        if ($nettagname and (inet_aton($nettagname) eq inet_aton($node))) {
                            $hosttag = "$node-$ifinfo[1]";
                            push @hostnames_to_update, $hosttag;
                        }
                        elsif (!inet_aton($node)) {
                            xCAT::MsgUtils->message("S", "xcat.discovery.nodediscover: Can not resolve IP for the matching node:$node. Make sure \"makehosts\" and \"makedns\" have been run for $node.");
                        }
                    }
                    #print Dumper($hosttag) . "\n";
                    if ($hosttag) {
                        $usednames{$hosttag} = 1;
                        unless ($usednames_for_net{$netn}) {
                            $usednames_for_net{$netn} = $hosttag;
                        }
                        if ($hosttag eq $node) {
                            $macstring .= $currmac . "|";
                        } else {
                            $macstring .= $currmac . "!" . $hosttag . "|";
                        }

                        # following is for manual discovery by nodediscoverdef to define a undef node to predefine node
                        # this this case, the $clientip is null
                        unless ($clientip) {
                            $clientip = $ip;
                        }
                    } else {
                        if ($forcenic == 1) { $macstring .= $currmac . "|"; } else { $macstring .= $currmac . "!*NOIP*|"; }
                    }
                }
            } else {
                if ($forcenic == 1) { $macstring .= $currmac . "|"; }
            }
        }
        $macstring =~ s/\|\z//;
        $mactab->setNodeAttribs($node, { mac => $macstring });
        if (scalar @hostnames_to_update) {
            my $hosttab = xCAT::Table->new('hosts');
            if ($hosttab) {
                my ($ent) = $hosttab->getNodeAttribs($node, ['hostnames']);
                if ($ent and $ent->{hostnames})  {
                    my @hostnames_array = split /,/, $ent->{hostnames};
                    push @hostnames_to_update,@hostnames_array;
                }
                my %allhostnames = map { $_=>1 } @hostnames_to_update;
                my $hostnames = join(",", (keys %allhostnames));
                $hosttab->setNodeAttribs($node, { hostnames => $hostnames });
                $hosttab->commit();
            }
            my %request = (
                command => ['makehosts'],
                node    => [$node]
            );
            $doreq->(\%request);
        }
        my %request = (
            command => ['makedhcp'],
            node    => [$node]
        );
        $doreq->(\%request);
    }

    #TODO: mac table?  on the one hand, 'the' definitive interface was determined earlier...
    #Delete the state it was in to make it traverse destiny once agoin
    my $chaintab = xCAT::Table->new('chain');
    if ($chaintab) {
        $chaintab->setNodeAttribs($node, { currstate => '', currchain => '' });
        $chaintab->close();
    }

    # Update the switch port information if the 'updateswitch' flag is added in the request.
    # 'updateswitch' is default added for sequential discovery
    if ($request->{'updateswitch'} && $macstring) {
        my $firstmac;

        # Get the mac which defined as the management nic
        my @macents = split(/\|/, $macstring);
        foreach my $macent (@macents) {
            my ($mac, $host) = split(/!/, $macent);
            unless ($firstmac) {
                $firstmac = $mac;
            }
            if (!$host || $host eq $node) {
                $firstmac = $mac;
                last;
            }
        }

        # search the management nic and record the switch informaiton
        foreach my $nic (@{ $request->{nic} }) {
            if (defined($nic->{'hwaddr'}) && $nic->{'hwaddr'}->[0] =~ /$firstmac/i) {
                if (defined($nic->{'switchname'}) && defined($nic->{'switchaddr'})) {

                    # update the switch to switches table
                    my $switchestab = xCAT::Table->new('switches');
                    if ($switchestab) {
                        $switchestab->setAttribs({ switch => $nic->{'switchname'}->[0] }, { comments => $nic->{'switchdesc'}->[0] });
                        $switchestab->close();
                    }

                    # update the ip of switch to hosts table
                    my $hosttab = xCAT::Table->new('hosts');
                    if ($hosttab) {
                        $hosttab->setNodeAttribs($nic->{'switchname'}->[0], { ip => $nic->{'switchaddr'}->[0] });
                        $hosttab->commit();
                    }

                    # add the switch as a node to xcat db
                    my $nltab = xCAT::Table->new('nodelist');
                    if ($nltab) {
                        $nltab->setNodeAttribs($nic->{'switchname'}->[0], { groups => "all,switch" });
                        $nltab->commit();
                    }

                    if (defined($nic->{'switchport'})) {

                        # update the switch table
                        my $switchtab = xCAT::Table->new('switch');
                        if ($switchtab) {
                            $switchtab->setNodeAttribs($node, { switch => $nic->{'switchname'}->[0], port => $nic->{'switchport'}->[0] });
                            $switchtab->close();
                        }
                    }
                }
            }
        }
    }

    # make sure the node has the correct ip configured
    unless ($clientip) {
        $callback->({ error => ["The node [$node] should have a correct IP address which belongs to the management network."], errorcode => ["1"] });
        return;
    }
    if (defined($request->{bmcinband})) {
        if (defined($request->{bmc_node}) and defined($request->{bmc_node}->[0])) {
            my $bmc_node = $request->{bmc_node}->[0];
            xCAT::MsgUtils->message("S", "xcat.discovery.nodediscover: Removing discovered node definition: $bmc_node...");
            my $rmcmd = "rmdef $bmc_node";
            xCAT::Utils->runcmd($rmcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("S", "xcat.discovery.nodediscover: Failed to remove $bmc_node from xCAT");
            } else {
                xCAT::MsgUtils->message("S", "xcat.discovery.nodediscover: $bmc_node definition removed from xCAT");
            }
        }
    } else {

        # Only BMC that doesn't support in-band configuration need to run rspconfig out-of-band, such as S822L running in OPAL model
        xCAT::MsgUtils->message("S", "No bmcinband specified, need to configure BMC out-of-band");
        xCAT::Utils->cleanup_for_powerLE_hardware_discovery($request, $doreq);
    }


    my $restartstring = "restart";
    if (scalar @forcenics > 0) {
        $restartstring .= " (" . join("|", @forcenics) . ")";
    }

    #now, notify the node to continue life
    my $sock = new IO::Socket::INET(
        PeerAddr => $clientip,
        PeerPort => '3001',
        Timeout  => '1',
        Proto    => 'tcp'
    );
    unless ($sock) { xCAT::MsgUtils->message("S", "xcat.discovery.nodediscover: Failed to notify $clientip that it's actually $node."); return; }
    print $sock $restartstring;
    close($sock);


    #Update the discoverydata table to indicate the successful discovery
    xCAT::DiscoveryUtils->update_discovery_data($request);

    xCAT::MsgUtils->message("S", "xcat.discovery.nodediscover: $node has been discovered");
}

1;
