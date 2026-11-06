#!/usr/bin/env perl
# vm.othersettings firmware: chooses the firmware of a KVM guest, and until now it accepted
# one value, efi. That leaves Secure Boot to libvirt firmware autoselection, which picks a
# descriptor by host policy: on a host whose best match enrolls keys, the guest refuses an
# unsigned boot loader with "Access Denied".
#
# That decides whether a node can network boot over IPv6 at all. A DHCPv6 bootfile-url is
# written only for a grub2 node, and the grub2 image xCAT serves is built with grub2-mkimage
# and is not signed, so a guest with Secure Boot enforced downloads it and will not start it.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use XCAT::Test::File qw(repo_path);

use xCAT::KVMUtils;

# A guest as kvm.pm writes it before the features are added.
my $PLAIN = <<'XML';
<domain type='kvm'>
  <name>cn01</name>
  <os firmware='efi'>
    <type arch='x86_64' machine='q35'>hvm</type>
    <boot dev='network' />
  </os>
</domain>
XML

# ---- which values the setting accepts -------------------------------------------------------
is( xCAT::KVMUtils::firmware_error( undef, 'cn01' ), undef, 'a node that asks for no firmware is accepted' );
is( xCAT::KVMUtils::firmware_error( 'efi', 'cn01' ), undef, 'firmware:efi is accepted' );
is( xCAT::KVMUtils::firmware_error( 'efi-secureboot', 'cn01' ),
    undef, 'firmware:efi-secureboot is accepted' );
is( xCAT::KVMUtils::firmware_error( 'efi-insecure', 'cn01' ),
    undef, 'firmware:efi-insecure is accepted' );

my $refusal = xCAT::KVMUtils::firmware_error( 'bios', 'cn01' );
like( $refusal, qr/\bcn01\b/, 'a value libvirt cannot select names the node' );
like( $refusal, qr/efi-insecure/, '... and names the value that turns Secure Boot off' );

# ---- what each value asks of Secure Boot ----------------------------------------------------
is( xCAT::KVMUtils::secure_boot_request('efi'), undef,
    'firmware:efi leaves Secure Boot to libvirt autoselection' );
is( xCAT::KVMUtils::secure_boot_request('efi-secureboot'), 'yes', 'efi-secureboot requires it' );
is( xCAT::KVMUtils::secure_boot_request('efi-insecure'),   'no',  'efi-insecure requires it off' );
is( xCAT::KVMUtils::secure_boot_request(undef), undef, 'no firmware setting asks nothing' );

# ---- the guest XML ---------------------------------------------------------------------------
# features_of <xml> -- the name => enabled map of the <firmware> element of <os>
sub features_of {
    my ($xml) = @_;
    my %feature;
    my ($block) = $xml =~ m{<firmware>(.*?)</firmware>}s;
    return %feature unless defined $block;
    while ( $block =~ /<feature\s+([^>]*?)\/>/g ) {
        my $attrs = $1;
        my ($name)    = $attrs =~ /name=['"]([^'"]+)['"]/;
        my ($enabled) = $attrs =~ /enabled=['"]([^'"]+)['"]/;
        $feature{$name} = $enabled if defined $name;
    }
    return %feature;
}

my $plain = xCAT::KVMUtils::with_firmware_features( $PLAIN, 'efi' );
is_deeply( { features_of($plain) }, {},
    'firmware:efi adds no firmware element, so autoselection is unchanged' );
like( $plain, qr/firmware=['"]efi['"]/, '... and the guest still asks for EFI' );

my $insecure = xCAT::KVMUtils::with_firmware_features( $PLAIN, 'efi-insecure' );
is_deeply( { features_of($insecure) }, { 'secure-boot' => 'no', 'enrolled-keys' => 'no' },
    'efi-insecure turns Secure Boot off, and the keys with it' );
like( $insecure, qr/firmware=['"]efi['"]/, '... and the guest still asks for EFI' );

# libvirt refuses enrolled-keys enabled beside secure-boot disabled, which is why the keys
# follow Secure Boot rather than being left to the descriptor.
my $secure = xCAT::KVMUtils::with_firmware_features( $PLAIN, 'efi-secureboot' );
is_deeply( { features_of($secure) }, { 'secure-boot' => 'yes', 'enrolled-keys' => 'yes' },
    'efi-secureboot requires Secure Boot and enrolled keys' );

# A guest with no <os firmware=...> is not an EFI guest and must not gain a firmware element.
my $bios = $PLAIN;
$bios =~ s/ firmware='efi'//;
is_deeply( { features_of( xCAT::KVMUtils::with_firmware_features( $bios, 'efi-insecure' ) ) },
    {}, 'a guest that does not ask for EFI gains no firmware element' );

# ---- the profile still names the firmware libvirt understands -------------------------------
for my $value (qw(efi efi-secureboot efi-insecure)) {
    my $profile = xCAT::KVMUtils::guest_arch_profile( 'x86_64', 'x86_64', $value );
    is( $profile->{firmware}, 'efi', "firmware:$value gives the guest firmware='efi'" );
}

done_testing();
