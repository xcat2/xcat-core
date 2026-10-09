#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(slurp_repo_file);

my $spec = slurp_repo_file('xCAT-release/xCAT-release.spec');
like($spec, qr/^Name:\s+xCAT-release$/m, 'package has the expected name');
like($spec, qr/^Source0:\s+xCAT-release-%\{version\}\.tar\.gz$/m, 'source archive follows the package name');
like($spec, qr/^BuildArch:\s+noarch$/m, 'package is architecture independent');
like($spec, qr/^Requires:\s+dnf$/m, 'package is limited to DNF-based systems');
like($spec, qr/^%config\(noreplace\) .*xcat-core\.repo$/m, 'core repo preserves local changes');
like($spec, qr/^%config\(noreplace\) .*xcat-dep\.repo$/m, 'dependency repo preserves local changes');
like($spec, qr/^%config\(noreplace\) .*xcat-dep-common\.repo$/m, 'common dependency repo preserves local changes');
like($spec, qr{RPM-GPG-KEY-xCAT}, 'package installs the signing key');

my $core = slurp_repo_file('xCAT-release/xcat-core.repo');
assert_repo_security($core, 'core');
like(
    $core,
    qr{^baseurl=https://xcat\.org/files/xcat/repos/yum/latest/xcat-core$}m,
    'core repo uses the stable HTTPS endpoint'
);

my $dep = slurp_repo_file('xCAT-release/xcat-dep.repo');
assert_repo_security($dep, 'dependency');
like(
    $dep,
    qr{^baseurl=https://xcat\.org/files/xcat/repos/yum/latest/xcat-dep/rh\$releasever/\$basearch$}m,
    'dependency repo follows the DNF release and architecture variables'
);

my $common_dep = slurp_repo_file('xCAT-release/xcat-dep-common.repo');
assert_repo_security($common_dep, 'common dependency');
like(
    $common_dep,
    qr/^skip_if_unavailable=1$/m,
    'an unavailable common repository does not block package operations',
);
like(
    $common_dep,
    qr{^baseurl=https://xcat\.org/files/xcat/repos/yum/latest/xcat-dep/common$}m,
    'common dependency repo is independent of the management-node distribution'
);

my $key = slurp_repo_file('xCAT-release/RPM-GPG-KEY-xCAT');
like($key, qr/^-----BEGIN PGP PUBLIC KEY BLOCK-----$/m, 'signing key is ASCII armored');
is(
    sha256_hex($key),
    '72076f25ce4929d34a67e305327a37f89c964d3cbf1821e3afad4907c9d91249',
    'packaged key matches the published xCAT signing key'
);

done_testing();

sub assert_repo_security {
    my ($content, $label) = @_;
    like($content, qr/^enabled=1$/m, "$label repo is enabled");
    like($content, qr/^gpgcheck=1$/m, "$label repo verifies packages");
    like($content, qr/^repo_gpgcheck=1$/m, "$label repo verifies repository metadata");
    like(
        $content,
        qr{^gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-xCAT$}m,
        "$label repo uses the packaged signing key"
    );
}
