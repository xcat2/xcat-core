# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::KVMUtils;

# The libvirt domain decisions of the kvm plugin. This module loads no xCAT module and no
# libvirt binding: each sub takes its inputs as arguments and returns its answer.

use strict;
use warnings;

#-------------------------------------------------------

=head3 default_storagemodel

    Descriptions:
        The storage model of a node whose vmstoragemodel is empty.

        The model names the volume of the node, createstorage builds that name, and libvirt
        reads the bus of the disk out of it. scsi keeps every architecture on sd*, which is
        the only disk controller the riscv64 virt machine has.
    Arguments:
        None.
    Returns:
        the storage model

=cut

#-------------------------------------------------------
sub default_storagemodel {
    return 'scsi';
}

#-------------------------------------------------------

=head3 guest_arch_profile

    Descriptions:
        The libvirt domain type and <os> settings for one guest.

        The architecture of the guest comes from the node, not from the hypervisor. A node
        whose arch is not the arch of the hypervisor runs under emulation, which libvirt
        expresses as domain type "qemu". riscv64 has no BIOS: the virt machine boots UEFI,
        and pae/acpi/apic are x86 features that libvirt rejects there.

        An aarch64 guest takes its accelerator from both architectures. The aarch64
        hypervisor runs it under KVM, which on ARM runs the host CPU and no other model.
        Every other hypervisor emulates it, and TCG needs a named model: libvirt reports
        host-passthrough and host-model as unsupported there, and the emulator default turns
        on SVE, which stops the guest in its firmware.

        video is the fixed video model of the guest. A profile with video_prefer instead
        takes the first of those models that the hypervisor offers. A native aarch64 guest
        wants no VGA-type model: vga, cirrus, bochs and qxl expose their framebuffer through a
        PCI BAR, and under KVM on ARM the guest and the host map that memory with different
        cache attributes, so the display is corrupt.

        POWER keeps reading the hypervisor cpumodel. ppc64le hypervisors report "ppc64le"
        (not "ppc64"); both are pseries guests whose libvirt <os> arch is "ppc64". pseries
        marks that guest, because the CPU model, the CPU topology and the emulator belong to
        it and not to the hypervisor.

        arch and machine stay undef when libvirt is to use its own default for the
        hypervisor. machine is the unversioned alias; libvirt resolves it to the version the
        hypervisor has.

        An x86_64 guest that asks for efi moves to q35, because every x86_64 OVMF descriptor
        targets pc-q35-* only. q35 has no IDE controller, so its disks and its optical drive
        move to scsi.

        efi-secureboot also sets secureboot, which guest_os turns into the requirement
        libvirt reads. efi alone states no requirement, so libvirt takes the descriptor of
        highest priority that fits the guest, and that order belongs to the hypervisor.
    Arguments:
        $guest_arch - nodetype.arch of the node, or undef
        $hyp_cpumodel - the cpumodel of the hypervisor, or undef
        $firmware - the firmware the node asks for in vm.othersettings, or undef
    Returns:
        a hash reference of the profile

=cut

#-------------------------------------------------------
sub guest_arch_profile {
    my ($guest_arch, $hyp_cpumodel, $firmware) = @_;
    my %profile = (
        domtype      => 'kvm',
        arch         => undef,
        machine      => undef,
        firmware     => undef,
        secureboot   => 0,
        cpu_mode     => undef,
        cpu_model    => undef,
        pseries      => 0,
        video_prefer => undef,
        x86_features => 1,
        bios         => 1,
        sound        => 1,
        video        => 'vga',
        usb_input    => 1,
        disk_model   => 'ide',
        cd_prefix    => 'hd',
    );
    if (defined($guest_arch) and $guest_arch eq 'riscv64') {
        $profile{domtype}      = 'qemu';
        $profile{arch}         = 'riscv64';
        $profile{machine}      = 'virt';
        $profile{firmware}     = 'efi';
        $profile{x86_features} = 0;
        $profile{bios}         = 0;
        $profile{sound}        = 0;
        $profile{video}        = 'virtio';
        $profile{usb_input}    = 0;
        $profile{disk_model}   = 'scsi';
        $profile{cd_prefix}    = 'sd';
    } elsif (defined($guest_arch) and $guest_arch eq 'aarch64') {
        my $native = (defined($hyp_cpumodel) and $hyp_cpumodel eq 'aarch64');
        $profile{domtype}      = $native ? 'kvm' : 'qemu';
        $profile{cpu_mode}     = $native ? 'host-passthrough' : 'custom';
        $profile{cpu_model}    = $native ? undef : 'cortex-a57';
        $profile{arch}         = 'aarch64';
        $profile{machine}      = 'virt';
        $profile{firmware}     = 'efi';
        $profile{x86_features} = 0;
        $profile{bios}         = 0;
        $profile{sound}        = 0;
        $profile{video}        = undef;
        $profile{video_prefer} = $native ? [ 'virtio', 'ramfb' ] : [ 'virtio', 'vga', 'ramfb' ];
        $profile{usb_input}    = 0;
        $profile{disk_model}   = 'scsi';
        $profile{cd_prefix}    = 'sd';
    } elsif (defined($hyp_cpumodel) and ($hyp_cpumodel eq "ppc64" or $hyp_cpumodel eq "ppc64le")) {
        $profile{arch}         = 'ppc64';
        $profile{machine}      = 'pseries';
        $profile{pseries}      = 1;
        $profile{x86_features} = 0;
        $profile{bios}         = 0;
        $profile{sound}        = 0;
    }
    if (defined($firmware) and $firmware =~ /^efi(?:-secureboot)?$/) {
        $profile{secureboot} = 1 if $firmware eq 'efi-secureboot';
        unless (defined $profile{firmware}) {
            $profile{firmware} = 'efi';
            if ($profile{x86_features}) {
                $profile{machine}    = 'q35';
                $profile{disk_model} = 'scsi';
                $profile{cd_prefix}  = 'sd';
            }
        }
    }
    return \%profile;
}

#-------------------------------------------------------

=head3 guest_cpu

    Descriptions:
        The <cpu> element of one guest.

        A pseries guest takes the CPU model and the topology of the hypervisor, and that
        replaces the cpumode of vm.othersettings. host-passthrough and host-model read the
        host CPU, which an emulated guest does not run, so only a kvm domain takes them.
        Otherwise the profile names the CPU, if it names one.
    Arguments:
        $profile - the hash reference from guest_arch_profile
        %args - cpumode: the cpumode of vm.othersettings; cputype: the cputype of the
                hypervisor; cores: the CPU count of the guest; threads: the threads per core
                of the hypervisor
    Returns:
        a hash reference for the <cpu> element, or undef for no element

=cut

#-------------------------------------------------------
sub guest_cpu {
    my ($profile, %args) = @_;
    if ($profile->{pseries}) {
        my %cpu = (topology => { sockets => 1, cores => $args{cores}, threads => $args{threads} });
        $cpu{model} = $args{cputype} if $args{cputype};
        return \%cpu;
    }
    my $cpumode = $args{cpumode};
    if (defined $cpumode
        and ($cpumode eq 'host-passthrough' or $cpumode eq 'host-model')
        and $profile->{domtype} eq 'kvm') {
        return { mode => $cpumode };
    }
    return undef unless defined $profile->{cpu_mode};
    my %cpu = (mode => $profile->{cpu_mode});
    if (defined $profile->{cpu_model}) {
        $cpu{match} = 'exact';
        $cpu{model} = { content => $profile->{cpu_model} };
    }
    return \%cpu;
}

#-------------------------------------------------------

=head3 guest_emulator

    Descriptions:
        The emulator a guest names in its domain. A pseries guest on a ppc64 hypervisor
        names qemu-system-ppc64. libvirt resolves the emulator of every other guest from its
        own capabilities.
    Arguments:
        $profile - the hash reference from guest_arch_profile
        $hyp_cpumodel - the cpumodel of the hypervisor, or undef
    Returns:
        the emulator path, or undef

=cut

#-------------------------------------------------------
sub guest_emulator {
    my ($profile, $hyp_cpumodel) = @_;
    return undef unless $profile->{pseries};
    return undef unless defined($hyp_cpumodel) and $hyp_cpumodel eq 'ppc64';
    return '/usr/bin/qemu-system-ppc64';
}

#-------------------------------------------------------

=head3 preferred_video_model

    Descriptions:
        The first wanted video model that the hypervisor offers.

        The video models of a machine type come from the emulator build, not from the
        architecture: the aarch64 emulator of a host can carry no virtio-gpu device while its
        riscv64 emulator does. libvirt refuses a domain that names a model its emulator has
        no device for, so the model is read from the capabilities of the hypervisor.

        Capabilities that do not state the video models are unavailable, not empty. No model
        is guessed then. <video supported="no"> and a list that holds no wanted model both
        leave the guest with no video device.
    Arguments:
        $caps - the domain capabilities of the hypervisor as XML::Simple XMLin returns them
                with ForceArray => [ 'enum', 'value' ] and KeyAttr => [], or undef when the
                query failed
        $wanted - the models to look for, in order
        $caps_error - the error of the capability query, or undef
    Returns:
        the video model, or undef for no video device.
        Dies when the capabilities are unavailable.

=cut

#-------------------------------------------------------
sub preferred_video_model {
    my ($caps, $wanted, $caps_error) = @_;
    my $video;
    $video = $caps->{devices}->{video}
      if ref($caps) eq 'HASH' and ref($caps->{devices}) eq 'HASH';
    if (ref($video) eq 'HASH' and defined $video->{supported} and $video->{supported} eq 'no') {
        return undef;
    }
    my $offered;
    if (ref($video) eq 'HASH' and ref($video->{enum}) eq 'ARRAY') {
        foreach my $enum (@{ $video->{enum} }) {
            next unless ref($enum) eq 'HASH';
            next unless defined $enum->{name} and $enum->{name} eq 'modelType';
            $offered = { map { $_ => 1 } @{ $enum->{value} || [] } };
        }
    }
    unless ($offered) {
        my $why = defined $caps_error ? $caps_error : 'no video model list';
        $why =~ s/\s+$//;
        die "Cannot choose a video model: the domain capabilities of the hypervisor are "
          . "unavailable ($why). Set vm.vidmodel for the node.\n";
    }
    foreach my $model (@$wanted) {
        return $model if $offered->{$model};
    }
    return undef;
}

#-------------------------------------------------------

=head3 guest_video_model

    Descriptions:
        The video model of one guest. vm.vidmodel wins. Otherwise a profile with
        video_prefer takes the first preferred model the hypervisor offers, and every other
        guest takes the video model of its profile.
    Arguments:
        $profile - the hash reference from guest_arch_profile
        $vidmodel - vm.vidmodel of the node, or undef
        $caps - the parsed domain capabilities, as for preferred_video_model, or undef
        $caps_error - the error of the capability query, or undef
    Returns:
        the video model, or undef for no video device.
        Dies as preferred_video_model does.

=cut

#-------------------------------------------------------
sub guest_video_model {
    my ($profile, $vidmodel, $caps, $caps_error) = @_;
    return $vidmodel if defined $vidmodel;
    return $profile->{video} unless $profile->{video_prefer};
    return preferred_video_model($caps, $profile->{video_prefer}, $caps_error);
}

#-------------------------------------------------------

=head3 split_disk_spec

    Descriptions:
        Split one vmstorage entry into its location and its storage model, and name the
        device prefix of that model.

        An entry states its model as a "=<model>" suffix. Without one, the first true value
        of @defaults is the model. The prefix is sd for scsi, vd for virtio and hd for any
        other model.
    Arguments:
        $spec - one vmstorage entry
        @defaults - the models to use, in order, when the entry states none
    Returns:
        ($location, $model, $prefix). $model is undef when nothing names one.

=cut

#-------------------------------------------------------
sub split_disk_spec {
    my ($spec, @defaults) = @_;

    # A failed substitution leaves $1 as the last capture of the caller. Read $1 only when
    # this substitution matches.
    my $model;
    if ($spec =~ s/=(.*)//) {
        $model = $1;
    }
    unless ($model) {
        ($model) = grep { $_ } @defaults;
    }
    return ($spec, $model, disk_prefix($model));
}

#-------------------------------------------------------

=head3 disk_prefix

    Descriptions:
        The device name prefix of a storage model.
    Arguments:
        $model - the storage model, or undef
    Returns:
        sd for scsi, vd for virtio, hd otherwise

=cut

#-------------------------------------------------------
sub disk_prefix {
    my ($model) = @_;
    return 'hd' unless defined $model;
    return 'sd' if $model eq 'scsi';
    return 'vd' if $model eq 'virtio';
    return 'hd';
}

#-------------------------------------------------------

=head3 pool_disk_bus

    Descriptions:
        The bus of a disk on a libvirt storage pool. libvirt reads the bus out of the device
        name when the disk states none: hd* is ide, sd* is scsi, vd* is virtio. The disk
        states the same bus.
    Arguments:
        $device - the device name of the volume
    Returns:
        the bus, or undef for any other name

=cut

#-------------------------------------------------------
sub pool_disk_bus {
    my ($device) = @_;
    return undef unless defined $device;
    return 'virtio' if $device =~ /^vd/;
    return 'ide'    if $device =~ /^hd/;
    return 'scsi'   if $device =~ /^sd/;
    return undef;
}

#-------------------------------------------------------

=head3 cdrom_prefix

    Descriptions:
        The device name prefix of the optical drive of a guest. A vd* name does not work for
        an optical drive, so vmstoragemodel virtio uses sd, as scsi does. Otherwise the
        profile names the prefix: the riscv64 virt machine has no IDE controller.
    Arguments:
        $profile - the hash reference from guest_arch_profile
        $storagemodel - vm.storagemodel of the node, or undef
    Returns:
        the prefix

=cut

#-------------------------------------------------------
sub cdrom_prefix {
    my ($profile, $storagemodel) = @_;
    if (defined $storagemodel and ($storagemodel eq 'virtio' or $storagemodel eq 'scsi')) {
        return 'sd';
    }
    return $profile->{cd_prefix};
}

#-------------------------------------------------------

=head3 vm_othersettings

    Descriptions:
        The vm.othersettings of one node.

        The read creates no vm table and no vm row. An rvalue dereference chain
        autovivifies its intermediate links.
    Arguments:
        $confdata - the table data of the kvm plugin, or undef
        $node - the node name
    Returns:
        the othersettings value, or undef when the node has no vm row

=cut

#-------------------------------------------------------
sub vm_othersettings {
    my ($confdata, $node) = @_;
    return undef unless ref($confdata) eq 'HASH';
    my $vm   = $confdata->{vm} or return undef;
    my $rows = $vm->{$node}    or return undef;
    my $row  = $rows->[0]      or return undef;
    return $row->{othersettings};
}

#-------------------------------------------------------

=head3 requested_firmware

    Descriptions:
        The firmware a node asks for in vm.othersettings. No node asks by default, so an
        existing guest keeps the firmware of its machine type.

        efi asks for UEFI. efi-secureboot asks for UEFI that verifies what it boots.
    Arguments:
        $othersettings - vm.othersettings of the node, or undef
    Returns:
        the value of the firmware: setting, or undef

=cut

#-------------------------------------------------------
sub requested_firmware {
    my ($othersettings) = @_;
    return undef unless defined $othersettings;
    foreach my $setting (split /;/, $othersettings) {
        return $1 if $setting =~ /^\s*firmware:(.*)/;
    }
    return undef;
}

#-------------------------------------------------------

=head3 firmware_error

    Descriptions:
        The refusal of a firmware value that libvirt cannot select. A node with a typo must
        not stay on SeaBIOS without a message, nor lose a Secure Boot requirement it asked
        for.
    Arguments:
        $firmware - the value from requested_firmware, or undef
        $node - the node name
    Returns:
        the error message, or undef when the value is efi, efi-secureboot or undef

=cut

#-------------------------------------------------------
sub firmware_error {
    my ($firmware, $node) = @_;
    return undef if !defined($firmware) or $firmware =~ /^efi(?:-secureboot)?$/;
    return "vm.othersettings firmware:$firmware names no firmware libvirt can select for $node. Use firmware:efi or firmware:efi-secureboot.";
}

#-------------------------------------------------------

=head3 guest_os

    Descriptions:
        The <os> element of one guest, in the hash form XML::Simple XMLout writes.

        A ppc64le hypervisor gets no <bios useserial>. A profile without bios drops it too.
        A machine type from vm.othersettings replaces the machine type of the profile.

        A profile with secureboot states <loader secure='yes'/>. libvirt reads it while it
        selects the firmware and keeps only the descriptors that carry secure-boot, so a
        hypervisor with no such firmware refuses the domain. Without the element the guest
        takes whichever firmware the hypervisor prefers, and the domain says nothing about
        whether that firmware verifies what it boots.
    Arguments:
        $profile - the hash reference from guest_arch_profile
        %args - hyp_cpumodel: the cpumodel of the hypervisor; bootorder: vm.bootorder of the
                node; machine: the machine: setting of vm.othersettings
    Returns:
        a hash reference for the <os> element

=cut

#-------------------------------------------------------
sub guest_os {
    my ($profile, %args) = @_;
    my %os = (type => { content => 'hvm' });
    unless (defined($args{hyp_cpumodel}) and $args{hyp_cpumodel} eq 'ppc64le') {
        $os{bios}->{useserial} = 'yes';
    }
    if (defined $args{bootorder}) {
        foreach my $dev (split(/[:,]/, $args{bootorder})) {
            $dev = 'network' if ($dev eq 'net' or $dev eq 'n');
            push @{ $os{boot} }, { dev => $dev };
        }
    } else {
        $os{boot} = [ { dev => 'network' }, { dev => 'hd' } ];
    }
    $os{type}->{arch}    = $profile->{arch}     if defined $profile->{arch};
    $os{type}->{machine} = $profile->{machine}  if defined $profile->{machine};
    $os{firmware}        = $profile->{firmware} if defined $profile->{firmware};
    $os{loader}->{secure} = 'yes' if $profile->{secureboot};
    delete $os{bios} unless $profile->{bios};
    $os{type}->{machine} = $args{machine} if defined $args{machine};
    return \%os;
}

#-------------------------------------------------------

=head3 clock_offset

    Descriptions:
        The clock offset of one guest. vm.clockoffset wins. Otherwise a Windows guest uses
        localtime and every other guest uses utc.
    Arguments:
        $clockoffset - vm.clockoffset of the node, or undef
        $os - nodetype.os of the node, or undef
    Returns:
        the clock offset

=cut

#-------------------------------------------------------
sub clock_offset {
    my ($clockoffset, $os) = @_;
    return $clockoffset if defined $clockoffset;
    return 'localtime' if (defined($os) and $os =~ /win.*/);
    return 'utc';
}

#-------------------------------------------------------

=head3 reconfigure_domain

    Descriptions:
        Apply the clock offset, memory, CPU count and boot order of a node to the XML of
        an existing domain. Every other element of the domain stays as it is.

        XML::LibXML is loaded here, not by this module, so the other subs need only core Perl.
    Arguments:
        $xml - the domain XML
        %args - clock_offset: the result of clock_offset; memory: the memory in KiB, or
                undef; vcpus: the vcpus value of the vm row, or undef; bootorder:
                vm.bootorder, or undef
    Returns:
        the new domain XML, or 0 when the domain needs no change

=cut

#-------------------------------------------------------
sub reconfigure_domain {
    my ($xml, %args) = @_;
    require XML::LibXML;
    my $parser   = XML::LibXML->new();
    my $domdesc  = $parser->parse_string($xml);
    my @bootdevs = $domdesc->findnodes("/domain/os/boot");
    my $needfixin = 0;
    my $clock = $domdesc->findnodes("/domain/clock")->[0];
    if ($clock->getAttribute("offset") ne $args{clock_offset}) {
        $needfixin = 1;
        $clock->setAttribute("offset", $args{clock_offset});
    }
    if (defined $args{memory}) {
        $needfixin = 1;
        $domdesc->findnodes("/domain/memory/text()")->[0]->setData($args{memory});
        foreach ($domdesc->findnodes("/domain/currentMemory/text()")) {
            $_->setData($args{memory});
        }
    }
    if (defined $args{vcpus}) {
        $needfixin = 1;
        $domdesc->findnodes("/domain/vcpu/text()")->[0]->setData($args{vcpus});
    }
    if (defined $args{bootorder}) {
        my @oldbootdevs;
        my @expectedorder = split(/[:,]/, $args{bootorder});
        foreach (@expectedorder) {
            my $currdev = shift @bootdevs;
            if ("net" eq $_ or "n" eq $_) {
                $_ = "network";
            }
            unless ($currdev and $currdev->getAttribute("dev") eq $_) {
                $needfixin = 1;
            }
            if ($currdev) {
                push @oldbootdevs, $currdev;
            }
        }
        if (scalar(@bootdevs)) {
            $needfixin = 1;
            push @oldbootdevs, @bootdevs;
        }
        return 0 unless $needfixin;

        foreach (@oldbootdevs) {
            $_->parentNode->removeChild($_);
        }
        my $osnode = $domdesc->findnodes("/domain/os")->[0];
        foreach (@expectedorder) {
            $osnode->appendChild($parser->parse_balanced_chunk('<boot dev="' . $_ . '"/>'));
        }
    }
    return $needfixin ? $domdesc->toString() : 0;
}

1;
