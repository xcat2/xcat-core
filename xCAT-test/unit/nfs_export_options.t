#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw/tempdir/;
use Test::More;

use xCAT::SvrUtils;

my $dir = tempdir(CLEANUP => 1);
my $exports = "$dir/exports";

open(my $fh, '>', $exports) or die "Unable to write $exports: $!";
print $fh <<'EOF';
# comment
/install *(rw,no_root_squash,sync,no_subtree_check) # install tree
/tftpboot -rw,no_root_squash
/other host1(rw) host2(ro,insecure)
EOF
close($fh);

ok(xCAT::SvrUtils->nfs_export_exists('/install', files => [$exports]), 'target export is detected');
ok(!xCAT::SvrUtils->nfs_export_exists('/missing', files => [$exports]), 'missing export is not detected');

ok(
    xCAT::SvrUtils->ensure_nfs_export_option('/install', 'insecure', files => [$exports]),
    'missing option is added to target export'
);
my $content = do { local $/; open(my $rfh, '<', $exports) or die $!; <$rfh> };
like($content, qr{^/install \*\(rw,no_root_squash,sync,no_subtree_check,insecure\) # install tree$}m, 'target export gains insecure and keeps comment');
like($content, qr{^/tftpboot -rw,no_root_squash$}m, 'non-target export is unchanged');
like($content, qr{^/other host1\(rw\) host2\(ro,insecure\)$}m, 'unrelated multi-client export is unchanged');

ok(
    !xCAT::SvrUtils->ensure_nfs_export_option('/install', 'insecure', files => [$exports]),
    'existing option is not duplicated'
);

ok(
    xCAT::SvrUtils->ensure_nfs_export_option('/tftpboot', 'insecure', files => [$exports]),
    'dash-style export gains option'
);
$content = do { local $/; open(my $rfh, '<', $exports) or die $!; <$rfh> };
like($content, qr{^/tftpboot -rw,no_root_squash,insecure$}m, 'dash-style export is updated correctly');

done_testing();
