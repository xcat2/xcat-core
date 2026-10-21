#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::Postage;
use xCAT::SvrUtils;

# The Subiquity autoinstall installs the template's fixed packages and the osimage pkglist in one
# apt transaction, and the template names chrony. The shared compute.pkglist names ntp for the
# releases before Subiquity, and on the Subiquity releases ntp pulls ntpsec, which conflicts with
# chrony, so those releases need their own default list. The lists are resolved the way
# mkinstall resolves them and their packages are read the way ospkgs reads them.

my $repo     = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $install  = "$repo/xCAT-server/share/xcat/install/ubuntu";
my $template = "$install/compute.subiquity.tmpl";
plan skip_all => 'the Ubuntu install directory is not here' unless -d $install && -f $template;

sub packages_in {
    my ($path) = @_;
    return { map { $_ => 1 } grep { length } split /,/, xCAT::Postage::get_pkglist_tex($path) };
}

sub resolved {
    my ( $os, $arch ) = @_;
    return xCAT::SvrUtils->get_pkglist_file_name( $install, 'compute', $os, $arch, $os =~ /^(ubuntu\d+\.\d+)/ ? $1 : $os );
}

open( my $tfh, '<', $template ) or die "$template: $!";
my $body = do { local $/; <$tfh> };
close($tfh);
my ($block) = $body =~ /^  packages:\n((?:    - .*\n)+)/m;
my %fixed = map { $_ => 1 } ( $block =~ /^    - ([^#\s]+)$/mg );
ok( $fixed{chrony}, 'the Subiquity template names chrony among its fixed packages' );

my %time_daemon = map { $_ => 1 } qw(chrony ntp ntpsec);
foreach my $case ( [ 'ubuntu20.04.6', 'x86_64' ], [ 'ubuntu20.04.6', 'ppc64le' ],
                   [ 'ubuntu22.04.5', 'x86_64' ], [ 'ubuntu22.04.5', 'ppc64le' ],
                   [ 'ubuntu24.04.4', 'x86_64' ], [ 'ubuntu24.04.4', 'ppc64le' ], [ 'ubuntu24.04.4', 'riscv64' ],
                   [ 'ubuntu26.04.1', 'x86_64' ], [ 'ubuntu26.04.1', 'riscv64' ] ) {
    my ( $os, $arch ) = @$case;
    my $file = resolved( $os, $arch );
    ok( $file, "$os $arch resolves a compute pkglist" ) or next;
    my $packages = packages_in($file);
    ok( $packages->{chrony}, "$os $arch: the list names chrony, the daemon the template installs" );
    ok( !$packages->{ntp} && !$packages->{ntpdate}, "$os $arch: ... and not ntp, which would conflict with it" );
    my @daemons = grep { $time_daemon{$_} } keys %{ { %fixed, %$packages } };
    is( scalar(@daemons), 1, "$os $arch: the autoinstall transaction carries exactly one time daemon" );
}

# The releases before Subiquity keep the shared list and its ntp.
my $legacy = resolved( 'ubuntu16.04.7', 'x86_64' );
is( $legacy, "$install/compute.pkglist", '16.04 still resolves the shared list' );
ok( packages_in($legacy)->{ntp}, '... which keeps ntp for the releases where chrony was not the default' );

done_testing();
