package xCAT::VMCommon;
use Socket;
use strict;

#Functions common to virtualization management (KVM, Xen, VMware)
sub grab_table_data {    #grab table data relevent to VM guest nodes
    my $noderange = shift;
    my $cfghash   = shift;
    my $callback  = shift;
    my $vmtab     = xCAT::Table->new("vm");
    my $vpdtab    = xCAT::Table->new("vpd");
    my $hmtab     = xCAT::Table->new("nodehm");
    my $nttab     = xCAT::Table->new("nodetype");

    #my $sitetab = xCAT::Table->new("site");
    $cfghash->{site}->{genmacprefix} = $::XCATSITEVALS{genmacprefix}; #xCAT::Utils->get_site_attribute('genmacprefix');
    if ($hmtab) {
        $cfghash->{nodehm} = $hmtab->getNodesAttribs($noderange, ['serialspeed']);
    }
    if ($nttab) {
        $cfghash->{nodetype} = $nttab->getNodesAttribs($noderange, [ 'os', 'arch', 'profile' ]); #allow us to guess RTC config
                #also needed for vmware guestid and also data for vmmaster
    }
    unless ($vmtab) {
        $callback->({ data => ["Cannot open vm table"] });
        return;
    }
    if ($vpdtab) {
        $cfghash->{vpd} = $vpdtab->getNodesAttribs($noderange, ['uuid']);
    }
    $cfghash->{vm} = $vmtab->getNodesAttribs($noderange, [ 'node', 'host', 'migrationdest', 'cfgstore', 'storage', 'storagecache', 'storageformat', 'vidmodel', 'vidproto', 'vidpassword', 'storagemodel', 'memory', 'cpus', 'nics', 'nicmodel', 'bootorder', 'virtflags', 'datacenter', 'guestostype', 'othersettings', 'master' ]);
    my $mactab = xCAT::Table->new("mac",     -create => 1);
    my $nrtab  = xCAT::Table->new("noderes", -create => 1);
    $cfghash->{mac} = $mactab->getAllNodeAttribs(['mac'], 1);
    my $macs;
    my $mac;
    foreach (keys %{ $cfghash->{mac} }) {
        $macs = $cfghash->{mac}->{$_}->[0]->{mac};
        foreach $mac (split /\|/, $macs) {
            $mac =~ s/\!.*//;
            if ($cfghash->{usedmacs}->{ lc($mac) }) {
                $cfghash->{usedmacs}->{ lc($mac) } += 1;
            } else {
                $cfghash->{usedmacs}->{ lc($mac) } = 1;
            }
        }
    }
}

sub macsAreUnique { #internal function, do not call, argument format may change without warning
        #Take a list of macs, ensure that in the table view, they are unique.
        #this should be performed after the macs have been committed to
        #db
    my $cfghash = shift;
    my @macs    = @_;
    my $mactab  = xCAT::Table->new("mac", -create => 0);
    unless ($mactab) {
        return 1;
    }
    $cfghash->{mac} = $mactab->getAllNodeAttribs(['mac'], 1);
    $cfghash->{usedmacs} = {};
    my $macs;
    my $mac;
    foreach (keys %{ $cfghash->{mac} }) {
        $macs = $cfghash->{mac}->{$_}->[0]->{mac};
        foreach $mac (split /\|/, $macs) {
            $mac =~ s/\!.*//;
            if ($cfghash->{usedmacs}->{ lc($mac) }) {
                $cfghash->{usedmacs}->{ lc($mac) } += 1;
            } else {
                $cfghash->{usedmacs}->{ lc($mac) } = 1;
            }
        }
    }
    foreach $mac (@macs) {
        if ($cfghash->{usedmacs}->{ lc($mac) } > 1) {
            return 0;
        }
    }
    return 1;
}

sub requestMacAddresses {

    #This function combs through the list of nodes to assure every vm.nic declared nic has a mac address
    my $tablecfg   = shift;
    my $neededmacs = shift;
    my $mactab     = xCAT::Table->new("mac", -create => 1);
    my $node;
    my @allmacs;
    my $complete = 0;
    my $updatesneeded;
    my $vpdupdates;
    srand(); #Re-seed the rng.  This will make the mac address generation less deterministic

    while (not $complete and scalar @$neededmacs) {
        foreach $node (@$neededmacs) {
            my $nicdata = $tablecfg->{vm}->{$node}->[0]->{nics};
            unless ($nicdata) { $nicdata = "" }
            my @nicsneeded = split /,/, $nicdata;
            my $count = scalar(@nicsneeded);

            my $macdata = $tablecfg->{mac}->{$node}->[0]->{mac};
            unless ($macdata) { $macdata = "" }
            my @macs;
            my $macaddr;
            foreach $macaddr (split /\|/, $macdata) {
                $macaddr =~ s/\!.*//;
                push @macs, lc($macaddr);
            }
            $count -= scalar(@macs);
            if ($count > 0) {
                $updatesneeded->{$node}->{mac} = 1;
            }

            while ($count > 0) {    #still need more, autogen
                $macaddr = "";
                while (not $macaddr) {
                    $macaddr = lc(genMac($node, $tablecfg->{site}->{genmacprefix}));
                    push @allmacs, $macaddr;
                    if ($tablecfg->{usedmacs}->{$macaddr}) {
                        $macaddr = "";
                    }
                }
                $count--;
                $tablecfg->{usedmacs}->{$macaddr} = 1;
                if (not $macdata) {
                    $macdata = $macaddr;
                } else {
                    $macdata .= "|" . $macaddr . "!*NOIP*";
                }
                push @macs, $macaddr;
            }
            if (defined $updatesneeded->{$node}) {
                $updatesneeded->{$node}->{mac} = $macdata;
                $tablecfg->{dhcpneeded}->{$node} = 1; #at our leisure, this dhcp binding should be updated
            }

            #now that macs are done, do simple uuid... (done after to benefit from having at least one mac address)
            unless ($tablecfg->{vpd}->{$node}->[0]->{uuid}) {
                my $umac = $macs[0];
                my $uuid;
                if ($umac) {
                    $uuid = xCAT::Utils::genUUID(mac => $umac);
                } else {    #shouldn't be possible, but just in case
                    $uuid = xCAT::Utils::genUUID();
                }
                $vpdupdates->{$node}->{uuid} = $uuid;
                $tablecfg->{vpd}->{$node} = [ { uuid => $uuid } ];
                $tablecfg->{dhcpneeded}->{$node} = 1; #at our leisure, this dhcp binding should be updated
            }

            #TODO: LOCK if a distributed lock management structure goes in place, that may be a faster solution than this
            #this code should be safe though as it is, if a tiny bit slower
            #can also be sped up by doing it for a noderange in a sweep instead of once per node
            #but the current architecture has this called at a place that is unaware of the larger context
            #TODO2.4 would be either the lock management or changing this to make large scale mkvm faster
        }
        if (defined $vpdupdates) {
            my $vpdtab = xCAT::Table->new('vpd', -create => 1);
            $vpdtab->setNodesAttribs($vpdupdates);
        }
        if (defined $updatesneeded) {
            my $mactab = xCAT::Table->new('mac', -create => 1);
            $mactab->setNodesAttribs($updatesneeded);
            if (macsAreUnique($tablecfg, @allmacs)) {
                $complete = 1;
            } else {    #Throw away ALL macs and try again
                        #this currently includes manually specified ones
                foreach $node (keys %$updatesneeded) {
                    $tablecfg->{mac}->{$node}->[0]->{mac} = "";
                }
                $tablecfg->{usedmacs} = {};
            }
        }
    }

    #    $cfghash->{usedmacs}-{lc{$mac}};
}

sub getMacAddresses {
    my $tablecfg = shift;
    my $node     = shift;
    my $count    = shift;
    my $mactab   = xCAT::Table->new("mac", -create => 1);
    my $macdata  = $tablecfg->{mac}->{$node}->[0]->{mac};
    unless ($macdata) { $macdata = "" }
    my @macs;
    my $macaddr;

    foreach $macaddr (split /\|/, $macdata) {
        $macaddr =~ s/\!.*//;
        push @macs, lc($macaddr);
    }
    $count -= scalar(@macs);
    my $updatesneeded = 0;
    if ($count > 0) {
        $updatesneeded = 1;
    }

    srand(); #Re-seed the rng.  This will make the mac address generation less deterministic
    while ($count > 0) {
        while ($count > 0) {    #still need more, autogen
            $macaddr = "";
            while (not $macaddr) {
                $macaddr = lc(genMac($node, $tablecfg->{site}->{genmacprefix}));
                if ($tablecfg->{usedmacs}->{$macaddr}) {
                    $macaddr = "";
                }
            }
            $count--;
            $tablecfg->{usedmacs}->{$macaddr} = 1;
            if (not $macdata) {
                $macdata = $macaddr;
            } else {
                $macdata .= "|" . $macaddr . "!*NOIP*";
            }
            push @macs, $macaddr;
        }
        if ($updatesneeded) {
            my $mactab = xCAT::Table->new('mac', -create => 1);
            $mactab->setNodeAttribs($node, { mac => $macdata });
            $tablecfg->{dhcpneeded}->{$node} = 1; #at our leisure, this dhcp binding should be updated
        }

        #TODO: LOCK if a distributed lock management structure goes in place, that may be a faster solution than this
        #this code should be safe though as it is, if a tiny bit slower
        #can also be sped up by doing it for a noderange in a sweep instead of once per node
        #but the current architecture has this called at a place that is unaware of the larger context
        #TODO2.4 would be either the lock management or changing this to make large scale mkvm faster
        unless (macsAreUnique($tablecfg, @macs)) { #Throw away ALL macs and try again
                #this currently includes manually specified ones
            $count += scalar(@macs);
            @macs    = ();
            $macdata = "";
        }
    }

    return @macs;

    #    $cfghash->{usedmacs}-{lc{$mac}};

}

sub genMac { #Generates a mac address for a node, does NOT assure uniqueness, calling code needs to do that
    my $node   = shift;
    my $prefix = shift;
    if ($prefix) {    #Specific prefix requested, honor it
        my $tail = int(rand(0xffffff)); #With only 24 bits of space, use random bits;
        if ($prefix eq '00:50:56') { #vmware reserves certain addresses in their scheme if this prefix used
            $tail = $tail & 0x3fffff;    #mask out the two bits in question
        }
        $tail = sprintf("%06x", $tail);
        $tail =~ s/(..)(..)(..)/:$1:$2:$3/;
        return $prefix . $tail;
    }

    #my $allbutmult = 0xfeff; # to & with a number to ensure multicast bit is *not* set
    #my $locallyadministered = 0x200; # to | with the 16 MSBs to indicate a local mac
    #my $leading = int(rand(0xffff));
    #$leading = $leading & $allbutmult;
    #$leading = $leading | $locallyadministered;
    #for the header, we used to use all 14 possible bits, however, if a guest mac starts with 0xfe then libvirt will construct a bridge that looks identical
    #First thought was to go to 13 bits, but by fixing our generated mac addresses to always start with the same byte and still be unique
    #this induces libvirt to do unique TAP mac addresses
    my $leading = int(rand(0xff));
    $leading = $leading | 0x4200;

    #If this nodename is a resolvable name, we'll use that for the other 32 bits
    my $low32;
    my $n;
    if ($n = inet_aton($node)) {
        $low32 = unpack("N", $n);
    }
    unless ($low32) {    #If that failed, just do 32 psuedo-random bits
        $low32 = int(rand(0xffffffff));
    }
    my $mac;
    $mac = sprintf("%04x%08x", $leading, $low32);
    $mac =~ s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
    return $mac;

}

#-------------------------------------------------------

=head3 esx_guest_uuid

    Descriptions:
        Converts between config.uuid of a VMware VM and the UUID that its guest reports.
        vpd.uuid holds the UUID that the guest reports.

        VMware writes uuid.bios into the SMBIOS type 1 structure unencoded. Only the version
        of the SMBIOS entry point changes, and the guest decodes the bytes according to it. A
        guest behind a 2.7 entry point reads the first three fields little-endian and reports
        them swapped. A guest behind a 2.4 entry point reports the same bytes unswapped.

        Measured on ESXi 7.0.3, 8.0.3 and 9.1.0: EFI firmware gives SMBIOS 2.7 at every
        hardware version, and BIOS firmware gives 2.4 up to hardware version 11 and 2.7 from
        hardware version 12. The host default firmware and hardware version are both newer
        than that, so an unknown value reads 2.7. The swap is its own inverse, so one sub
        converts both ways.

        VMware documents acpi.smbiosVersion2.7 = FALSE, which puts a 2.7 guest back on 2.4.
        That override is not measured and this sub does not read it.
    Arguments:
        $uuid - config.uuid, or the UUID that the guest reports, or undef
        $firmware - config.firmware, bios or efi, or undef for the host default
        $hwversion - config.version, such as vmx-13, or undef for the host default
    Returns:
        the UUID on the other side

=cut

#-------------------------------------------------------
sub esx_guest_uuid {
    my ($uuid, $firmware, $hwversion) = @_;
    return $uuid unless defined($uuid);
    my ($number) = (defined($hwversion) ? $hwversion : '') =~ /(\d+)/;
    return $uuid if defined($firmware) and lc($firmware) eq 'bios' and defined($number) and $number < 12;
    $uuid =~ s/^(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
    return $uuid;
}

#-------------------------------------------------------

=head3 esx_vmx_settings

    Descriptions:
        Splits vm.othersettings of a VMware guest into the fields of a
        VirtualMachineConfigSpec and the extraConfig options.

        firmware and virtualHW.version are vmx keys that the VirtualMachineConfigSpec carries
        as the firmware and version fields. extraConfig does not apply them, so mkvm passes
        them as fields, and esx_guest_uuid needs both to convert the UUID of a guest that
        mkvm creates.
    Arguments:
        $othersettings - vm.othersettings, a list of key=value separated by ;, or undef
    Returns:
        a hash reference with the firmware and version keys that are present, and an array
        reference of [key, value] pairs for extraConfig

=cut

#-------------------------------------------------------
sub esx_vmx_settings {
    my ($othersettings) = @_;
    my %spec;
    my @extraconfig;
    foreach my $setting (split /;/, (defined($othersettings) ? $othersettings : '')) {
        my ($key, $value) = split /=/, $setting, 2;
        next unless defined($key) and length($key);
        my $name = lc($key);
        if ($name eq 'firmware' and defined($value) and length($value)) {
            $spec{firmware} = lc($value);
        } elsif ($name eq 'virtualhw.version' and defined($value) and $value =~ /(\d+)/) {
            $spec{version} = "vmx-$1";
        } else {
            push @extraconfig, [ $key, $value ];
        }
    }
    return (\%spec, \@extraconfig);
}

1;
