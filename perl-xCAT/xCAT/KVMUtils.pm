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
    Arguments:
        $guest_arch - nodetype.arch of the node, or undef
        $hyp_cpumodel - the cpumodel of the hypervisor, or undef
    Returns:
        a hash reference of the profile

=cut

#-------------------------------------------------------
sub guest_arch_profile {
    my ($guest_arch, $hyp_cpumodel) = @_;
    my %profile = (
        domtype      => 'kvm',
        arch         => undef,
        machine      => undef,
        firmware     => undef,
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

1;
