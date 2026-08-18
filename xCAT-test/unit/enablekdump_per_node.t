#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $script = "$FindBin::Bin/../../xCAT/postscripts/enablekdump";
plan skip_all => 'enablekdump not found' unless -r $script;
# The postscript uses GNU sed -i, which behaves differently on BSD.
plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';

my $source = read_file($script);

# Run the RHEL NFS path of enablekdump against a scratch tree. The dump target
# is a local directory standing in for the mounted NFS export, so we can check
# what the postscript writes to it and to /etc/kdump.conf.
sub run_enablekdump {
    my (%opt) = @_;
    my $osver = $opt{osver};
    my $node  = $opt{node} || 'n01';
    my $sysconfig = defined $opt{sysconfig} ? $opt{sysconfig}
        : "KDUMP_COMMANDLINE=\"\"\nKDUMP_COMMANDLINE_APPEND=\"\"\n";

    my $root = tempdir(CLEANUP => 1);
    make_path("$root/etc/sysconfig", "$root/target", "$root/bin");

    # /etc/sysconfig/kdump must exist for the in-place seds to land.
    write_file("$root/etc/sysconfig/kdump", $sysconfig);
    # xcatlib.sh is sourced; only restartservice is needed and is a no-op here.
    write_file("$root/xcatlib.sh", "restartservice(){ :; }\n");
    write_file("$root/bin/logger", "#!/bin/sh\nexit 0\n");
    chmod 0755, "$root/bin/logger";

    my $src = $source;
    # Redirect everything the postscript touches into the scratch tree.
    $src =~ s{/etc/kdump\.conf}{$root/etc/kdump.conf}g;
    $src =~ s{/etc/sysconfig/kdump}{$root/etc/sysconfig/kdump}g;
    $src =~ s{/etc/dracut\.conf}{$root/etc/dracut.conf}g;
    $src =~ s{/tmp/dracut\.conf}{$root/tmp/dracut.conf}g;
    # No real NFS server: make the version probe empty so the mount is skipped;
    # the per-node mkdir and kdump.conf rendering still run against the target.
    $src =~ s{/usr/sbin/rpcinfo}{/bin/false}g;
    $src =~ s{/bin/mount}{true}g;
    $src =~ s{/bin/umount}{true}g;
    # Point the staging mount point at the scratch target that stands in for the
    # mounted NFS export.
    $src =~ s{/mnt/kdumpsetup}{$root/target}g;

    write_file("$root/enablekdump", $src);
    chmod 0755, "$root/enablekdump";

    my $dump = "nfs://10.0.0.1/dumparea";
    system(qq{cd '$root' && DUMP='$dump' XCAT='10.0.0.1:eth0' OSVER='$osver' }
         . qq{ARCH='x86_64' NODE='$node' PATH="$root/bin:\$PATH" ./enablekdump >/dev/null 2>&1});

    return {
        root       => $root,
        target     => "$root/target",
        kdump_conf => read_file("$root/etc/kdump.conf"),
        sysconfig  => read_file("$root/etc/sysconfig/kdump"),
    };
}

sub read_file {
    my ($p) = @_;
    return '' unless -e $p;
    open my $fh, '<', $p or die "open $p: $!";
    local $/;
    return <$fh>;
}

sub write_file {
    my ($p, $c) = @_;
    open my $fh, '>', $p or die "open $p: $!";
    print {$fh} $c;
    close $fh;
    return;
}

# --- RHEL 8: per-node, no shared-root writes -------------------------------
{
    my $r = run_enablekdump(osver => 'rhels8.0', node => 'n01');

    like($r->{kdump_conf}, qr{^path\s+/n01/var/crash$}m,
        'kdump.conf points the dump path at the node subdirectory');
    unlike($r->{kdump_conf}, qr{^path\s+/var/crash$}m,
        'kdump.conf does not use the shared /var/crash path');
    ok(-d "$r->{target}/n01/var/crash", 'the node subdirectory is created on the target');
    ok(!-e "$r->{target}/var/crash", 'nothing is created at the shared export root');
    ok(!-e "$r->{target}/proc", 'no dummy proc file is written on RHEL 8');
}

# --- RHEL 7: keeps the dracut workaround, but per-node ----------------------
{
    my $r = run_enablekdump(osver => 'rhels7.9', node => 'n07');

    like($r->{sysconfig}, qr{root=nfs:10\.0\.0\.1:/dumparea/n07},
        'the RHEL 7 root= workaround points at the node subdirectory');
    ok(-e "$r->{target}/n07/proc", 'the RHEL 7 dummy proc is written under the node subdirectory');
    ok(!-e "$r->{target}/proc", 'the RHEL 7 dummy proc is not written at the shared root');
}

# --- RHEL 7 migration: a legacy shared root= is replaced, not kept ----------
# A node configured by the previous script carries root=nfs:<server>:<export>
# in KDUMP_COMMANDLINE_APPEND. dracut takes the last root= on the command
# line, so leaving the legacy value behind would defeat the migration.
{
    my $legacy = qq{KDUMP_COMMANDLINE=""\n}
               . qq{KDUMP_COMMANDLINE_APPEND="root=nfs:10.0.0.1:/dumparea rd.neednet=1 rootflags=nofail foo-root=bar rd.foo.root=bar"\n};
    my $r = run_enablekdump(osver => 'rhels7.9', node => 'n07',
        sysconfig => $legacy);

    my ($append) = $r->{sysconfig} =~ m{^KDUMP_COMMANDLINE_APPEND="([^"]*)"}m;
    my @roots = grep { /^root=/ } split ' ', defined $append ? $append : '';
    is(scalar @roots, 1, 'exactly one root= remains after migrating a legacy config');
    is($roots[0], 'root=nfs:10.0.0.1:/dumparea/n07',
        'the remaining root= points at the node subdirectory');
    like($append, qr{(?:^|\s)rd\.neednet=1(?:\s|$)},
        'unrelated options on the legacy line are preserved');
    like($append, qr{(?:^|\s)rootflags=nofail(?:\s|$)},
        'rootflags= is not mistaken for a root= token');
    like($append, qr{(?:^|\s)foo-root=bar(?:\s|$)},
        'a root= suffix after a dash is not stripped');
    like($append, qr{(?:^|\s)rd\.foo\.root=bar(?:\s|$)},
        'a root= suffix after a dot is not stripped');

    # Re-running against its own output must not stack another root=.
    my $r2 = run_enablekdump(osver => 'rhels7.9', node => 'n07',
        sysconfig => $r->{sysconfig});
    my ($append2) = $r2->{sysconfig} =~ m{^KDUMP_COMMANDLINE_APPEND="([^"]*)"}m;
    is($append2, $append, 'a second run leaves KDUMP_COMMANDLINE_APPEND unchanged');
}

done_testing();
