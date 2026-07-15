#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::Utils;

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));
my $tmpdir = tempdir(CLEANUP => 1);
my $fips_status = File::Spec->catfile($tmpdir, 'fips_enabled');

write_file($fips_status, "1\n");
ok(xCAT::Utils->isFIPS($fips_status), 'kernel status 1 enables FIPS mode');

write_file($fips_status, "0\n");
ok(!xCAT::Utils->isFIPS($fips_status), 'kernel status 0 disables FIPS mode');
write_file($fips_status, "  1  \n");
ok(xCAT::Utils->isFIPS($fips_status), 'kernel status permits surrounding whitespace');
write_file($fips_status, "enabled\n");
ok(!xCAT::Utils->isFIPS($fips_status), 'malformed kernel status does not enable FIPS mode');
write_file($fips_status, '');
ok(!xCAT::Utils->isFIPS($fips_status), 'empty kernel status does not enable FIPS mode');
ok(!xCAT::Utils->isFIPS(File::Spec->catfile($tmpdir, 'missing')), 'missing kernel status is not FIPS mode');

my $xcatconfig = read_file('xCAT-server/sbin/xcatconfig');
like(
    $xcatconfig,
    qr/my \$generate_dsa = !xCAT::Utils->isFIPS\(\).*?\$platform =~ \/el.*?\$1 < 10/s,
    'xcatconfig wires the FIPS predicate into the existing EL version gate'
);

my $mknb = read_file('xCAT-server/lib/xcat/plugins/mknb.pm');
like(
    $mknb,
    qr/if \(!xCAT::Utils->isFIPS\(\).*?ssh-keygen -t dsa/s,
    'mknb wires the FIPS predicate into DSA host-key generation'
);
like(
    $mknb,
    qr/if \(-r "\/etc\/xcat\/hostkeys\/ssh_host_dsa_key"\).*?copy/s,
    'mknb treats the management-node DSA host key as optional'
);

foreach my $file (
    'xCAT-genesis-scripts/etc/init.d/functions',
    'xCAT-genesis-scripts/usr/bin/doxcat',
) {
    my $script = read_file($file);
    like(
        $script,
        qr/grep -q '\^1\$' \/proc\/sys\/crypto\/fips_enabled.*?ssh-keygen[^\n]*-t dsa/s,
        "$file guards the DSA command with the kernel FIPS state"
    );
}

my $statelite = read_file('xCAT-server/share/xcat/netboot/add-on/statelite/add_ssh');
like(
    $statelite,
    qr/if \[ -r \/etc\/xcat\/hostkeys\/ssh_host_dsa_key \]; then.*?cp/s,
    'statelite copies a DSA host key only when one exists'
);

my $sudoer = read_file('xCAT/postscripts/sudoer');
like(
    $sudoer,
    qr/if \[ -r \/xcatpost\/hostkeys\/ssh_host_dsa_key\.pub \]; then.*?cat/s,
    'sudoer accepts installations without a DSA public key'
);

done_testing();

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile($repo_root, split m{/}, $file);
    open(my $fh, '<', $path) or die "open $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $contents;
}

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "open $path: $!";
    print {$fh} $contents;
    close($fh) or die "close $path: $!";
}
