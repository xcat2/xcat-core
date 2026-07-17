#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::Schema;
use xCAT::SvrUtils;

sub build_nfsroot {
    return xCAT::SvrUtils->build_statelite_nfsroot_parameter('192.0.2.1', '/install/netboot/test/rootimg', shift);
}

my ($parameter, $error) = build_nfsroot(undef);
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro', 'unset options preserve the read-only default');
is($error, undef, 'unset options are valid');

($parameter, $error) = build_nfsroot('');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro', 'empty options preserve the read-only default');
is($error, undef, 'empty options are valid');

($parameter, $error) = build_nfsroot('noac,actimeo=0');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro,noac,actimeo=0', 'additional options follow the mandatory read-only option');
is($error, undef, 'valid additional options are accepted');

($parameter, $error) = build_nfsroot('ro,nfsvers=4.1');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro,nfsvers=4.1', 'a redundant read-only option is normalized');
is($error, undef, 'a redundant read-only option is valid');

($parameter, $error) = build_nfsroot('clientaddr=2001:db8::1');
is($parameter, 'root=nfs:192.0.2.1:/install/netboot/test/rootimg:ro,clientaddr=2001:db8::1', 'option values may contain colons');
is($error, undef, 'an option value containing colons is valid');

foreach my $invalid ('rw', 'RW', 'noac,rw', 'defaults', 'noac, actimeo=0', 'noac,,actimeo=0') {
    ($parameter, $error) = build_nfsroot($invalid);
    is($parameter, undef, "invalid option list '$invalid' is rejected");
    like($error, qr/^nfsrootopts /, "invalid option list '$invalid' reports the attribute name");
    like(
        xCAT::SvrUtils->validate_statelite_nfsroot_options($invalid),
        qr/^nfsrootopts /,
        "command-time validation rejects '$invalid'"
    );
}

is(xCAT::SvrUtils->validate_statelite_nfsroot_options(undef), undef, 'command-time validation accepts an unset value');
is(xCAT::SvrUtils->validate_statelite_nfsroot_options(''), undef, 'command-time validation accepts an empty value');
is(xCAT::SvrUtils->validate_statelite_nfsroot_options('noac,actimeo=0'), undef, 'command-time validation accepts valid options');

ok(
    scalar(grep { $_ eq 'nfsrootopts' } @{ $xCAT::Schema::tabspec{osimage}->{cols} }),
    'osimage table includes nfsrootopts'
);
is(
    $xCAT::Schema::defspec{osimage}->{attrhash}->{nfsrootopts}->{tabentry},
    'osimage.nfsrootopts',
    'osimage object exposes nfsrootopts'
);

foreach my $plugin (qw(anaconda debian sles)) {
    my $path = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/$plugin.pm";
    open(my $fh, '<', $path) or die "Unable to read $path: $!";
    my $source = do { local $/; <$fh> };
    close($fh);
    like($source, qr/build_statelite_nfsroot_parameter/, "$plugin statelite renderer uses the shared NFS-root builder");
    like($source, qr/'rootfstype',\s*'nfsrootopts'/, "$plugin reads nfsrootopts with the statelite root type");
}

done_testing();
