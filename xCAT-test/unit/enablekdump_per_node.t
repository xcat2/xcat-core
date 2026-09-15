#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(slurp_repo_file);

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::Sandbox qw(replace_required assert_no_host_paths stub_bin run_confined);

# The postscript uses GNU sed -i, which behaves differently on BSD.
plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';

my $source = slurp_repo_file('xCAT/postscripts/enablekdump');

# enablekdump reads the host's kernel command line and release files to choose what to write:
# an ifcfg file for the boot NIC, /etc/kdump.conf, /etc/sysconfig/kdump and, on SUSE, a rebuilt
# initrd under /boot. Every one of those paths points into $root, the commands that change or
# probe the host come from the stub directory, and a path the rewrites miss stops the test.
my @REWRITES = (
    [ '/proc/cmdline'          => 'proc/cmdline' ],
    [ '/etc/SuSE-release'      => 'etc/SuSE-release' ],
    [ '/etc/SUSE-brand'        => 'etc/SUSE-brand' ],
    [ '/etc/fedora-release'    => 'etc/fedora-release' ],
    [ '/etc/redhat-release'    => 'etc/redhat-release' ],
    [ '/etc/kdump.conf'        => 'etc/kdump.conf' ],
    [ '/etc/sysconfig/kdump'   => 'etc/sysconfig/kdump' ],
    [ '/etc/dracut.conf'       => 'etc/dracut.conf' ],
    [ '/tmp/dracut.conf'       => 'tmp/dracut.conf' ],
    [ '/tmp/createdir'         => 'tmp/createdir' ],
    [ '/etc/init.d/boot.kdump' => 'etc/init.d/boot.kdump' ],
    [ '/lib/mkinitrd'          => 'lib/mkinitrd' ],
    [ '/boot/'                 => 'boot/' ],
    [ '/var/tmp/tempinit'      => 'var/tmp/tempinit' ],
    [ '/var/lib/dhcpcd'        => 'var/lib/dhcpcd' ],
    [ '/root/tmp/'             => 'root/tmp/' ],
    # The staging mount point stands in for the mounted NFS export.
    [ '/mnt/kdumpsetup' => 'target' ],
);
my @COMMANDS = (
    [ '/usr/sbin/rpcinfo -p',          'rpcinfo -p' ],
    [ '/bin/mount -o',                 'mount -o' ],
    [ '/bin/umount -l $MOUNTPATH',     'umount -l $MOUNTPATH' ],
    [ '/sbin/ip link show',            'ip link show' ],
    [ '/sbin/ip -oneline link show',   'ip -oneline link show' ],
    [ '/sbin/ifconfig $ETHX',          'ifconfig $ETHX' ],
    [ '/sbin/mkinitrd',                'mkinitrd' ],
);

#-------------------------------------------------------------------------------

=head3 run_enablekdump

    Descriptions: Runs a staged copy of enablekdump for the RHEL NFS dump path. The dump target
                  is a local directory standing in for the mounted NFS export.
    Arguments:
        %opt - osver, node, sysconfig (initial /etc/sysconfig/kdump), cmdline (the kernel
               command line the node booted with), redhat_release (create the release file)
    Returns: a hash of the scratch root and the files the postscript wrote

=cut

#-------------------------------------------------------------------------------
sub run_enablekdump {
    my (%opt) = @_;
    my $osver     = $opt{osver};
    my $node      = $opt{node} || 'n01';
    my $sysconfig = defined $opt{sysconfig} ? $opt{sysconfig} : "KDUMP_COMMANDLINE=\"\"\nKDUMP_COMMANDLINE_APPEND=\"\"\n";

    my $root = tempdir( CLEANUP => 1 );
    make_path( map {"$root/$_"} qw(etc/sysconfig/network-scripts etc/sysconfig/network target proc tmp) );

    # /etc/sysconfig/kdump must exist for the in-place seds to land.
    write_file( "$root/etc/sysconfig/kdump", $sysconfig );
    write_file( "$root/proc/cmdline", defined $opt{cmdline} ? $opt{cmdline} : "\n" );
    write_file( "$root/etc/redhat-release", "Red Hat Enterprise Linux release 8.10\n" ) if $opt{redhat_release};
    # xcatlib.sh is sourced; only restartservice is needed and is a no-op here.
    write_file( "$root/xcatlib.sh", "restartservice(){ :; }\n" );

    my $src = $source;
    replace_required( \$src, $_->[0], "$root/$_->[1]" ) foreach @REWRITES;
    replace_required( \$src, @$_ ) foreach @COMMANDS;
    assert_no_host_paths( $src, root => $root, allow => [qr/^\s*#/] );
    write_file( "$root/enablekdump", $src );
    chmod 0755, "$root/enablekdump";

    my $bin = stub_bin(
        dir   => "$root/bin",
        tools => [qw(sh bash awk sed grep cat mkdir uname tr sort dirname cut mv)],
        stubs => {
            logger => 'exit 0',
            mount  => 'exit 0',
            umount => 'exit 0',
            # No NFS server answers, so the version probe is empty and the mount is skipped;
            # the per-node mkdir and kdump.conf rendering still run against the target.
            rpcinfo  => 'exit 0',
            ifconfig => 'exit 0',
            ip => q{printf '%s\n' '2: eth7: <BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq state UP    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff'},
        },
    );

    my ( $status, $output ) = run_confined(
        cmd => ["$root/enablekdump"],
        bin => $bin,
        env => {
            DUMP   => 'nfs://192.0.2.1/dumparea',
            XCAT   => '192.0.2.1:eth0',
            OSVER  => $osver,
            ARCH   => 'x86_64',
            NODE   => $node,
            MNTDIR => $root,
        },
        writable => [$root],
        dir      => $root,
    );

    return {
        root       => $root,
        target     => "$root/target",
        output     => $output,
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
    my ( $p, $c ) = @_;
    open my $fh, '>', $p or die "open $p: $!";
    print {$fh} $c;
    close $fh;
    return;
}

# --- RHEL 8: per-node, no shared-root writes -------------------------------
{
    my $r = run_enablekdump( osver => 'rhels8.0', node => 'n01' );

    like( $r->{kdump_conf}, qr{^path\s+/n01/var/crash$}m, 'kdump.conf points the dump path at the node subdirectory' )
        or diag( $r->{output} );
    unlike( $r->{kdump_conf}, qr{^path\s+/var/crash$}m, 'kdump.conf does not use the shared /var/crash path' );
    ok( -d "$r->{target}/n01/var/crash", 'the node subdirectory is created on the target' );
    ok( !-e "$r->{target}/var/crash",    'nothing is created at the shared export root' );
    ok( !-e "$r->{target}/proc",         'no dummy proc file is written on RHEL 8' );
}

# --- RHEL 7: keeps the dracut workaround, but per-node ----------------------
{
    my $r = run_enablekdump( osver => 'rhels7.9', node => 'n07' );

    like( $r->{sysconfig}, qr{root=nfs:192\.0\.2\.1:/dumparea/n07}, 'the RHEL 7 root= workaround points at the node subdirectory' );
    ok( -e "$r->{target}/n07/proc", 'the RHEL 7 dummy proc is written under the node subdirectory' );
    ok( !-e "$r->{target}/proc",    'the RHEL 7 dummy proc is not written at the shared root' );
}

# --- RHEL 7 migration: a legacy shared root= is replaced, not kept ----------
# A node configured by the previous script carries root=nfs:<server>:<export>
# in KDUMP_COMMANDLINE_APPEND. dracut takes the last root= on the command
# line, so leaving the legacy value behind would defeat the migration.
{
    my $legacy = qq{KDUMP_COMMANDLINE=""\n}
      . qq{KDUMP_COMMANDLINE_APPEND="root=nfs:192.0.2.1:/dumparea rd.neednet=1 rootflags=nofail foo-root=bar rd.foo.root=bar"\n};
    my $r = run_enablekdump( osver => 'rhels7.9', node => 'n07', sysconfig => $legacy );

    my ($append) = $r->{sysconfig} =~ m{^KDUMP_COMMANDLINE_APPEND="([^"]*)"}m;
    my @roots = grep {/^root=/} split ' ', defined $append ? $append : '';
    is( scalar @roots, 1, 'exactly one root= remains after migrating a legacy config' );
    is( $roots[0], 'root=nfs:192.0.2.1:/dumparea/n07', 'the remaining root= points at the node subdirectory' );
    like( $append, qr{(?:^|\s)rd\.neednet=1(?:\s|$)},    'unrelated options on the legacy line are preserved' );
    like( $append, qr{(?:^|\s)rootflags=nofail(?:\s|$)}, 'rootflags= is not mistaken for a root= token' );
    like( $append, qr{(?:^|\s)foo-root=bar(?:\s|$)},     'a root= suffix after a dash is not stripped' );
    like( $append, qr{(?:^|\s)rd\.foo\.root=bar(?:\s|$)}, 'a root= suffix after a dot is not stripped' );

    # Re-running against its own output must not stack another root=.
    my $r2 = run_enablekdump( osver => 'rhels7.9', node => 'n07', sysconfig => $r->{sysconfig} );
    my ($append2) = $r2->{sysconfig} =~ m{^KDUMP_COMMANDLINE_APPEND="([^"]*)"}m;
    is( $append2, $append, 'a second run leaves KDUMP_COMMANDLINE_APPEND unchanged' );
}

# --- the kernel command line is the node's, not the host's ------------------
# KDUMP_COMMANDLINE keeps the console= and crashkernel= options of the command line the node
# booted with. The test supplies that command line; the host running the test has its own.
{
    my $r = run_enablekdump( osver => 'rhels8.0', node => 'n03', cmdline => "console=ttyS0 quiet crashkernel=256M\n" );

    like( $r->{sysconfig}, qr{^KDUMP_COMMANDLINE="\s*console=ttyS0\s+crashkernel=256M\s*"}m,
        'KDUMP_COMMANDLINE carries the console and crashkernel options of the node command line' )
        or diag( $r->{sysconfig} );
}

# --- a node booted with BOOTIF gets an ifcfg file for that NIC --------------
# The file lands under MNTDIR, which the test sets to the scratch root; on a host booted the same
# way, an unset MNTDIR would put it under the host's /etc.
{
    my $r = run_enablekdump(
        osver          => 'rhels8.0',
        node           => 'n09',
        cmdline        => "BOOTIF=01-aa-bb-cc-dd-ee-ff quiet\n",
        redhat_release => 1,
    );

    ok( -e "$r->{root}/etc/sysconfig/network-scripts/ifcfg-eth7",
        'the ifcfg file for the BOOTIF NIC is created under MNTDIR' )
        or diag( $r->{output} );
}

done_testing();
