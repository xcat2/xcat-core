#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Slurper qw(read_text write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';
my $postscripts = repo_path('xCAT/postscripts');
BAIL_OUT('enablekdump and xcatlib.sh are required')
    unless -r "$postscripts/enablekdump" && -r "$postscripts/xcatlib.sh";

sub run_enablekdump {
    my (%opt) = @_;
    my $osver = $opt{osver};
    my $node  = $opt{node} // 'n01';
    my $sysconfig = defined $opt{sysconfig} ? $opt{sysconfig}
        : "KDUMP_COMMANDLINE=\"\"\nKDUMP_COMMANDLINE_APPEND=\"\"\n";

    my $root = sandbox_root();
    make_path("$root/etc/sysconfig", "$root/etc/systemd/system", "$root/mnt/kdumpsetup", "$root/sbin");
    write_text("$root/etc/sysconfig/kdump", $sysconfig);
    write_text("$root/etc/systemd/system/kdump.service", "[Service]\n");
    write_text("$root/etc/dracut.conf", "hostonly=yes\n");
    write_text("$root/cmdline", $opt{cmdline} // 'console=ttyS0 crashkernel=256M unrelated=value');
    write_text("$root/sbin/rpcinfo", "#!/bin/sh\nprintf '100003 4 tcp 2049 nfs\\n'\n");
    write_text("$root/bin/mount", "#!/bin/sh\nprintf 'mount %s\\n' \"\$*\" >> /fixture/calls\n");
    write_text("$root/bin/umount", "#!/bin/sh\nprintf 'umount %s\\n' \"\$*\" >> /fixture/calls\n");
    write_text("$root/bin/hostname", "#!/bin/sh\nprintf 'fallback-node\\n'\n");
    write_text("$root/bin/systemctl", <<'SH');
#!/bin/sh
printf 'systemctl %s\n' "$*" >> /fixture/calls
test ! -e /etc/dracut.conf || exit 98
exit "$RESTART_STATUS"
SH
    chmod 0755, "$root/sbin/rpcinfo", map { "$root/bin/$_" } qw(mount umount hostname systemctl);
    my ($rc, $output) = sandbox_run($root, {
        read_only => {$postscripts => '/postscripts', "$root/cmdline" => '/proc/cmdline',
            "$root/sbin" => '/usr/sbin', "$root/bin/mount" => '/bin/mount',
            "$root/bin/umount" => '/bin/umount'},
        writable => {"$root/mnt" => '/mnt'},
        env => {DUMP => $opt{dump} // 'nfs://192.0.2.1/dumparea', XCAT => '192.0.2.1:eth0',
            OSVER => $osver, ARCH => 'x86_64', NODE => $node,
            RESTART_STATUS => $opt{restart_status} // 0}}, '/bin/bash', '/postscripts/enablekdump');
    is($rc, $opt{restart_status} // 0, 'the complete postscript returns the service result') or diag($output);
    is(read_file("$root/etc/dracut.conf"), "hostonly=yes\n", 'dracut configuration is restored');
    ok(!-e "$root/tmp/dracut.conf", 'the temporary dracut copy is removed');

    return {
        root       => $root,
        target     => "$root/mnt/kdumpsetup",
        kdump_conf => read_file("$root/etc/kdump.conf"),
        sysconfig  => read_file("$root/etc/sysconfig/kdump"),
        calls      => read_file("$root/calls"),
    };
}

sub read_file {
    my ($p) = @_;
    return '' unless -e $p;
    return read_text($p);
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

    like($r->{sysconfig}, qr{root=nfs:192\.0\.2\.1:/dumparea/n07},
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
               . qq{KDUMP_COMMANDLINE_APPEND="root=nfs:192.0.2.1:/dumparea rd.neednet=1 rootflags=nofail foo-root=bar rd.foo.root=bar"\n};
    my $r = run_enablekdump(osver => 'rhels7.9', node => 'n07',
        sysconfig => $legacy);

    my ($append) = $r->{sysconfig} =~ m{^KDUMP_COMMANDLINE_APPEND="([^"]*)"}m;
    my @roots = grep { /^root=/ } split ' ', defined $append ? $append : '';
    is(scalar @roots, 1, 'exactly one root= remains after migrating a legacy config');
    is($roots[0], 'root=nfs:192.0.2.1:/dumparea/n07',
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

{
    my $r = run_enablekdump(osver => 'rhels8.0', node => '', restart_status => 7);
    is($r->{calls}, "mount -o vers=4 192.0.2.1:/dumparea /mnt/kdumpsetup\nsystemctl restart kdump\numount -l /mnt/kdumpsetup\n",
        'a failed service restart still unmounts the dump target');
    like($r->{kdump_conf}, qr{^path /fallback-node/var/crash$}m, 'missing NODE uses the short hostname');
    like($r->{sysconfig}, qr{console=ttyS0.*crashkernel=256M}, 'kdump keeps console and crashkernel options');
    unlike($r->{sysconfig}, qr{unrelated=value}, 'kdump omits unrelated kernel options');
}
{
    my $r = run_enablekdump(osver => 'rhels8.0', dump => '', cmdline => '');
    is($r->{kdump_conf}, '', 'an unconfigured dump server writes no kdump configuration');
    is($r->{calls}, '', 'an unconfigured dump server does not mount or restart anything');
}
done_testing();
