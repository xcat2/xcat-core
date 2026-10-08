#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::SELinux;

like($INC{'xCAT/SELinux.pm'}, qr/\Q$FindBin::Bin\E/,
    'xCAT::SELinux comes from this checkout, not from /opt/xcat');

# The stateless images whose initramfs carries the xCAT relabel hook.
my @supported = qw(rhels8.10 rhels9.6 rhels10.0 alma9.4 alma10.0 rocky8.10 rocky10.0
  ol9.5 centos-stream9 openeuler22.03sp4 openeuler24.03sp3);

# Images built from the older dracut module, which has no relabel hook.
my @unsupported = qw(rhels7.9 rhels6.10 centos7 ol7.9 fedora13 sles15.6 ubuntu24.04);

foreach my $osver (@supported) {
    is(xCAT::SELinux->kcmdline_selinux('enforcing', $osver), '',
        "$osver enforcing adds nothing to the kernel command line");
    is(xCAT::SELinux->kcmdline_selinux('permissive', $osver), 'enforcing=0',
        "$osver permissive boots with enforcing=0");
    is(xCAT::SELinux->kcmdline_selinux('disabled', $osver), 'selinux=0',
        "$osver disabled boots with selinux=0");
    ok(xCAT::SELinux->netboot_supported($osver), "$osver supports SELinux on a stateless node");
}

foreach my $osver (@unsupported) {
    foreach my $mode (qw(enforcing permissive disabled)) {
        is(xCAT::SELinux->kcmdline_selinux($mode, $osver), 'selinux=0',
            "$osver $mode boots with selinux=0, because its initramfs cannot label the root");
    }
    ok(!xCAT::SELinux->netboot_supported($osver), "$osver does not support SELinux on a stateless node");
}

is(xCAT::SELinux->kcmdline_selinux(undef, 'rhels9.6'), 'selinux=0',
    'an unresolved mode boots with selinux=0');
is(xCAT::SELinux->kcmdline_selinux('enforcing', undef), 'selinux=0',
    'an unknown OS boots with selinux=0');

done_testing();
