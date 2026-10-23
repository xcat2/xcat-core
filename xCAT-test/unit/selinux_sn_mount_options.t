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

foreach my $mode (qw(enforcing permissive enabled)) {
    is(xCAT::SELinux->nfs_mount_options('rw,nolock', 'public_content_t', $mode),
        'rw,nolock,context=system_u:object_r:public_content_t:s0',
        "a $mode service node mounts /install as public_content_t");
    is(xCAT::SELinux->nfs_mount_options('vers=4,rw,nolock', 'tftpdir_t', $mode),
        'vers=4,rw,nolock,context=system_u:object_r:tftpdir_t:s0',
        "a $mode service node mounts /tftpboot as tftpdir_t");
}

# The kernel refuses context= when SELinux is off, so the mount must not carry it.
foreach my $mode ('disabled', undef) {
    my $name = defined $mode ? $mode : 'undef';
    is(xCAT::SELinux->nfs_mount_options('rw,nolock', 'public_content_t', $mode), 'rw,nolock',
        "a service node in mode $name mounts /install as before");
}

is(xCAT::SELinux->nfs_mount_options('timeo=14,intr', 'public_content_t', 'enforcing'),
    'timeo=14,intr,context=system_u:object_r:public_content_t:s0',
    'the fstab options get the same context');

done_testing();
