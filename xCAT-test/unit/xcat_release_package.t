#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));

my $spec = read_file('xcat-release/xcat-release.spec');
like($spec, qr/^Name:\s+xcat-release$/m, 'package has the expected name');
like($spec, qr/^BuildArch:\s+noarch$/m, 'package is architecture independent');
like($spec, qr/^%config\(noreplace\) .*xcat-core\.repo$/m, 'core repo preserves local changes');
like($spec, qr/^%config\(noreplace\) .*xcat-dep\.repo$/m, 'dependency repo preserves local changes');
like($spec, qr{RPM-GPG-KEY-xCAT}, 'package installs the signing key');

my $core = read_file('xcat-release/xcat-core.repo');
assert_repo_security($core, 'core');
like(
    $core,
    qr{^baseurl=https://xcat\.org/files/xcat/repos/yum/latest/xcat-core$}m,
    'core repo uses the stable HTTPS endpoint'
);

my $dep = read_file('xcat-release/xcat-dep.repo');
assert_repo_security($dep, 'dependency');
like(
    $dep,
    qr{^baseurl=https://xcat\.org/files/xcat/repos/yum/latest/xcat-dep/rh\$releasever/\$basearch$}m,
    'dependency repo follows the DNF release and architecture variables'
);

my $key = read_file('xcat-release/RPM-GPG-KEY-xCAT');
like($key, qr/^-----BEGIN PGP PUBLIC KEY BLOCK-----$/m, 'signing key is ASCII armored');
is(
    sha256_hex($key),
    '72076f25ce4929d34a67e305327a37f89c964d3cbf1821e3afad4907c9d91249',
    'packaged key matches the published xCAT signing key'
);

my $builder = read_file('buildrpms.pl');
like($builder, qr/^\s+xcat-release\s*$/m, 'default RPM build includes xcat-release');
like(
    $builder,
    qr/unlink \$alias.*?createrepo_dir\(\$repodir/s,
    'stable bootstrap alias is excluded from repository metadata'
);
like(
    $builder,
    qr/cp \$release_rpms\[0\], \$alias/,
    'repository export creates the stable bootstrap filename'
);

done_testing();

sub assert_repo_security {
    my ($content, $label) = @_;
    like($content, qr/^enabled=1$/m, "$label repo is enabled");
    like($content, qr/^gpgcheck=1$/m, "$label repo verifies packages");
    like(
        $content,
        qr{^gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-xCAT$}m,
        "$label repo uses the packaged signing key"
    );
}

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile($repo_root, split m{/}, $file);
    open(my $fh, '<', $path) or die "open $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $contents;
}
