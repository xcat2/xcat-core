#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Find ();
use Test::More;

use xCAT::SELinux;

like($INC{'xCAT/SELinux.pm'}, qr/\Q$FindBin::Bin\E/,
    'xCAT::SELinux comes from this checkout, not from /opt/xcat');

# A stateless root is a cpio archive unpacked into tmpfs. It starts unlabelled, and no
# measured boot of a stateless node has reached enforcing. So every stateless node gets
# selinux=0, whatever its OS and whatever mode noderes.selinux and site.selinux resolve.
my @osvers = qw(rhels8.10 rhels9.6 rhels10.0 alma9.4 alma10.0 rocky8.10 rocky10.0
  ol9.5 centos-stream9 openeuler22.03sp4 openeuler24.03sp3 rhels7.9 fedora13
  sles15.6 ubuntu24.04);

foreach my $osver (@osvers) {
    ok(!xCAT::SELinux->netboot_supported($osver),
        "$osver does not support SELinux on a stateless node");
    foreach my $mode (qw(enforcing permissive disabled)) {
        is(xCAT::SELinux->kcmdline_selinux($mode, $osver), 'selinux=0',
            "$osver $mode boots with selinux=0");
    }
}

is(xCAT::SELinux->kcmdline_selinux(undef, 'rhels9.6'), 'selinux=0',
    'an unresolved mode boots with selinux=0');
is(xCAT::SELinux->kcmdline_selinux('enforcing', undef), 'selinux=0',
    'an unknown OS boots with selinux=0');
ok(!xCAT::SELinux->netboot_supported(undef), 'an unknown OS is not supported either');

# kcmdline_selinux still answers for each mode, so the day a stateless node is measured
# booting enforcing only netboot_supported has to change. These three hold that contract.
{
    no warnings 'redefine';
    local *xCAT::SELinux::netboot_supported = sub { return 1; };
    is(xCAT::SELinux->kcmdline_selinux('enforcing', 'rhels10.0'), '',
        'an enforcing node adds nothing to the kernel command line');
    is(xCAT::SELinux->kcmdline_selinux('permissive', 'rhels10.0'), 'enforcing=0',
        'a permissive node boots with enforcing=0');
    is(xCAT::SELinux->kcmdline_selinux('disabled', 'rhels10.0'), 'selinux=0',
        'a disabled node boots with selinux=0');
}

# The product must carry no stateless relabel hook: a hook that loads the policy denies
# every later exec in the initramfs, and a hook that only labels the root leaves systemd
# unable to relabel /dev and /run after switch_root. Both were measured on AlmaLinux 10.1.
my $netboot = "$FindBin::Bin/../../xCAT-server/share/xcat/netboot";
my (@hooks, @control);
File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            push @hooks,   $File::Find::name if $File::Find::name =~ m{/xcat-selinux-relabel\.sh$};
            push @control, $File::Find::name if $File::Find::name =~ m{/xcatroot$};
        },
}, $netboot);

# The positive control: the same walk finds the xcatroot of every dracut generation, so
# an empty hook list means the hooks are gone, not that the walk looked nowhere.
ok(scalar(@control) >= 5,
    "the walk of the netboot tree finds @{[scalar @control]} xcatroot scripts");
is_deeply([ sort @hooks ], [], 'no dracut module ships a stateless SELinux relabel hook');

done_testing();
