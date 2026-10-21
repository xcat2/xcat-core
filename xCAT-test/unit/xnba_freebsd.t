#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::More;
use xCAT::FreeBSDInstall;

BEGIN {
    for my $module (qw(Scope MsgUtils Utils BootUtils TableUtils ServiceNodeUtils Usage Table NetworkUtils)) {
        $INC{"xCAT/$module.pm"} = 1;
    }
}

{
    package xCAT::TableUtils;
    our $tftpdir;
    sub getTftpDir { return $tftpdir; }
    sub get_site_attribute { return $_[1] eq 'httpport' ? '8080' : (); }
    package xCAT::MsgUtils;
    sub trace { return; }
    sub message { return; }
    package xCAT::BootUtils;
    sub volatile_addkcmdline { return $_[0]; }
    package xCAT::NetworkUtils;
    sub determinehostname { return 'manager'; }
    sub checkNodeIPaddress { return { ip => '192.0.2.10' }; }
    package xCAT::Table;
    our (%rows, @lookups);
    sub new { return bless { table => $_[1] }, $_[0]; }
    sub getNodesAttribs {
        my ($self, $nodes, $attributes) = @_;
        my %result;
        for my $node (@$nodes) {
            my $row = $rows{$self->{table}}{$node} || {};
            $result{$node} = [{map { $_ => $row->{$_} } grep { exists($row->{$_}) } @$attributes}];
        }
        return \%result;
    }
    sub getAttribs {
        my ($self, $key) = @_;
        push @lookups, $self->{table};
        my ($name) = values %$key;
        return $rows{$self->{table}}{$name};
    }
}

my $temporary = abs_path(tempdir(CLEANUP => 1));
$xCAT::TableUtils::tftpdir = "$temporary/tftp";
my $plugin = $ENV{XCAT_XNBA_PLUGIN}
  || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/xnba.pm";
require $plugin;

my $sequence = 0;
my $type = { os => 'freebsd15.1', arch => 'x86_64', provmethod => 'freebsd-image' };
my $params = { kernel => 'xcat/freebsd/node1/boot/pxeboot', initrd => '', kcmdline => '', addkcmdline => '' };
my $state_directory;
my $cancel_calls = 0;
my $real_cancel = \&xCAT::FreeBSDInstall::cancel;
{
    no warnings 'redefine';
    *xCAT::FreeBSDInstall::cancel = sub {
        ++$cancel_calls;
        return $real_cancel->($_[0], directory => $state_directory);
    };
}

sub write_file {
    my ($path, $content) = @_;
    make_path(File::Basename::dirname($path));
    open(my $handle, '>', $path) or die "$path: $!";
    print {$handle} $content;
    close($handle) or die "$path: $!";
}

sub read_file {
    my $path = shift;
    return undef unless -f $path;
    open(my $handle, '<', $path) or die "$path: $!";
    local $/;
    my $content = <$handle>;
    close($handle) or die "$path: $!";
    return $content;
}

sub fixture {
    my $tftp = "$temporary/tftp-" . ++$sequence;
    write_file("$tftp/xcat/freebsd/node1/boot/pxeboot", 'BIOS loader');
    write_file("$tftp/xcat/freebsd/node1/boot/loader.efi", 'UEFI loader');
    for my $extension ('', '.uefi', '.pxelinux', '.elilo') {
        write_file("$tftp/xcat/xnba/nodes/node1$extension", "old script\n");
    }
    $state_directory = "$temporary/state-$sequence";
    $cancel_calls = 0;
    undef $::XNBA_pxelinux_required;
    undef $::XNBA_addkcmdlinehandled;
    @xCAT::Table::lookups = ();
    return $tftp;
}

sub render {
    my ($tftp, $bootparams, $state, $nodetype, $linux, $iscsi, $node) = @_;
    $node = 'node1' unless defined($node);
    my %boots = ($node => [dclone($bootparams || {})]);
    my %chains = ($node => [{currstate => $state}]);
    my %targets = ($node => [$iscsi || {}]);
    return xCAT_plugin::xnba::setstate($node, \%boots, \%chains, {}, \%targets,
        $tftp, $linux || {}, $nodetype);
}

subtest 'native loader scripts replace legacy scripts' => sub {
    my $tftp = fixture();
    my $state = 'install freebsd15.1-x86_64-compute';
    my @result = render($tftp, $params, $state, $type,
        {boottarget => 'unrelated-linux', addkcmdline => 'root=/dev/sda'});
    is_deeply(\@result, [0, ''], 'native installation renders successfully');
    is(read_file("$tftp/xcat/xnba/nodes/node1"),
        "#!gpxe\n#$state\n" . 'chain tftp://${next-server}/xcat/freebsd/node1/boot/pxeboot' . "\n",
        'BIOS chains the native loader without a Linux command line');
    is(read_file("$tftp/xcat/xnba/nodes/node1.uefi"),
        "#!gpxe\n#$state\n" . 'chain tftp://${next-server}/xcat/freebsd/node1/boot/loader.efi' . "\n",
        'UEFI chains the matching native loader without script root-path settings');
    is(xCAT_plugin::xnba::getstate('node1', $tftp), $state, 'existing state reader recognizes native script');
    ok(!-e "$tftp/xcat/xnba/nodes/node1.pxelinux", 'stale PXELINUX script is removed');
    ok(!-e "$tftp/xcat/xnba/nodes/node1.elilo", 'stale elilo script is removed');
    ok(!$::XNBA_pxelinux_required, 'native loading does not require PXELINUX');
    is((stat("$tftp/xcat/xnba/nodes/node1"))[2] & 0777, 0644, 'BIOS script is readable by TFTP');
    is((stat("$tftp/xcat/xnba/nodes/node1.uefi"))[2] & 0777, 0644, 'UEFI script is readable by TFTP');
    is_deeply(\@xCAT::Table::lookups, [], 'native route never queries Linux boot policy');
    is($cancel_calls, 0, 'installation rendering does not cancel ownership');
};

for my $attribute (qw(initrd kcmdline addkcmdline)) {
    for my $value ('nonempty', '0', []) {
        subtest "reject nonempty $attribute " . (ref($value) || $value) => sub {
            my $tftp = fixture();
            my $invalid = {%$params, $attribute => $value};
            my ($rc, $error) = render($tftp, $invalid, 'install', $type);
            is($rc, 1, 'invalid bootparams fail');
            like($error, qr/\Q$attribute\E must be empty/, 'error identifies the invalid attribute');
            is(read_file("$tftp/xcat/xnba/nodes/node1"), "old script\n", 'validation failure preserves BIOS script');
            is(read_file("$tftp/xcat/xnba/nodes/node1.uefi"), "old script\n", 'validation failure preserves UEFI script');
        };
    }
}

for my $kernel ('xcat/freebsd/node2/boot/pxeboot', '../pxeboot', 'xcat/os/kernel', "xcat/freebsd/node1/boot/pxeboot\nexit", []) {
    subtest 'reject foreign or malformed native kernel' => sub {
        my $tftp = fixture();
        my ($rc, $error) = render($tftp, {%$params, kernel => $kernel}, 'install', $type);
        is($rc, 1, 'invalid loader path fails');
        like($error, qr/node native loader/, 'error identifies the loader contract');
        is(read_file("$tftp/xcat/xnba/nodes/node1"), "old script\n", 'invalid loader leaves previous script intact');
    };
}

for my $unsupported ({%$type, os => 'freebsd16'}, {%$type, arch => 'aarch64'}, {%$type, arch => ''}) {
    my $tftp = fixture();
    my ($rc, $error) = render($tftp, $params, 'install', $unsupported);
    is($rc, 1, 'unsupported FreeBSD platform fails');
    like($error, qr/requires freebsd15\.1 and x86_64/, 'unsupported platform is explicit');
}

subtest 'missing native loader preserves existing scripts' => sub {
    my $tftp = fixture();
    unlink("$tftp/xcat/freebsd/node1/boot/loader.efi") or die $!;
    my ($rc, $error) = render($tftp, $params, 'install', $type);
    is($rc, 1, 'missing UEFI loader fails');
    like($error, qr/Cannot read.*loader\.efi/, 'missing loader is identified');
    is(read_file("$tftp/xcat/xnba/nodes/node1"), "old script\n", 'BIOS script is not partially replaced');
};

subtest 'native identifiers cannot inject script lines or paths' => sub {
    my $tftp = fixture();
    my ($rc, $error) = render($tftp, $params, "install bad\nexit", $type);
    is($rc, 1, 'multiline state fails');
    like($error, qr/Invalid FreeBSD installation state/, 'state validation is explicit');
    ($rc, $error) = render($tftp, $params, 'install', $type, {}, {}, '../node1');
    is($rc, 1, 'path traversal node fails');
    like($error, qr/Invalid FreeBSD node name/, 'node validation is explicit');
    is(read_file("$tftp/xcat/xnba/nodes/node1"), "old script\n", 'invalid identifiers leave previous script unchanged');
};

subtest 'native script publication reports filesystem failure' => sub {
    my $tftp = fixture();
    unlink("$tftp/xcat/xnba/nodes/node1") or die $!;
    mkdir("$tftp/xcat/xnba/nodes/node1") or die $!;
    my ($rc, $error) = render($tftp, $params, 'install', $type);
    is($rc, 1, 'script publication failure is returned');
    like($error, qr/Cannot publish/, 'publication error is explicit');
    my @temporary_files = glob("$tftp/xcat/xnba/nodes/.freebsd.*");
    is_deeply(\@temporary_files, [], 'staging files are removed after failure');
};

subtest 'Linux direct kernel and MEMDISK behavior are unchanged' => sub {
    my $tftp = fixture();
    write_file("$xCAT::TableUtils::tftpdir/linux/vmlinuz", pack('H*', '504500006486'));
    my $linux = {kernel => 'linux/vmlinuz', initrd => 'linux/initrd', kcmdline => 'quiet ds=nocloud-net;s=http://192.0.2.1/seed/'};
    my ($rc) = render($tftp, $linux, 'install', {os => 'rhels9', arch => 'x86_64'});
    is($rc, 0, 'Linux kernel still renders');
    my $bios = read_file("$tftp/xcat/xnba/nodes/node1");
    like($bios, qr{imgfetch -n kernel http://\$\{next-server\}:8080/tftpboot/linux/vmlinuz}, 'Linux retains the configured HTTP port');
    like($bios, qr{imgargs kernel quiet ds=nocloud-net;s=http://192\.0\.2\.1/seed/ BOOTIF=}, 'Linux kernel arguments retain the semicolon');
    unlike($bios, qr/chain tftp:/, 'Linux kernel is not treated as a native loader');
    like(read_file("$tftp/xcat/xnba/nodes/node1.uefi"), qr/imgexec kernel/, 'modern Linux retains direct EFI-stub boot');
    write_file("$xCAT::TableUtils::tftpdir/sles11/vmlinuz", pack('H*', '504500006486'));
    ($rc) = render($tftp, {%$linux, kernel => 'sles11/vmlinuz', initrd => 'sles11/initrd'}, 'install', {os => 'sles11', arch => 'x86_64'});
    is($rc, 0, 'SLES 11 still renders');
    like(read_file("$tftp/xcat/xnba/nodes/node1.uefi"), qr{chain http://\$\{next-server\}:8080/tftpboot/xcat/elilo-x64\.efi}, 'SLES 11 retains the legacy elilo path despite its EFI stub');
    ($rc) = render($tftp, {kernel => 'xcat/memdisk', initrd => 'disk.img'}, 'install', {os => 'dos', arch => 'x86'});
    is($rc, 0, 'MEMDISK still renders');
    ok($::XNBA_pxelinux_required, 'legacy MEMDISK still requires PXELINUX');
    like(read_file("$tftp/xcat/xnba/nodes/node1.pxelinux"), qr/KERNEL xcat\/memdisk/, 'legacy PXELINUX payload is preserved');
};

subtest 'nodetype and installation state are required for native routing' => sub {
    my $tftp = fixture();
    my ($rc) = render($tftp, $params, 'install', {os => 'rhels9', arch => 'x86_64'});
    is($rc, 0, 'foreign OS follows existing renderer');
    unlike(read_file("$tftp/xcat/xnba/nodes/node1"), qr/chain tftp:/, 'loader-looking path alone does not select FreeBSD');
    ($rc) = render($tftp, {kernel => 'xcat/genesis.kernel.x86_64', initrd => 'xcat/genesis.fs.x86_64', kcmdline => 'destiny=shell'}, 'shell', $type);
    is($rc, 0, 'FreeBSD node retains the existing shell path');
    like(read_file("$tftp/xcat/xnba/nodes/node1"), qr/imgexec kernel/, 'shell still uses the Genesis renderer');
};

subtest 'boot never reads or cancels installation ownership' => sub {
    my $tftp = fixture();
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $state_directory);
    my $attempt = 'b' x 32;
    xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $generation $attempt begin", sub {}, directory => $state_directory);
    my $completed = eval {
        local $SIG{ALRM} = sub { die "boot acquired the installation lock\n"; };
        alarm(3);
        xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $generation $attempt complete", sub {
            my @result = render($tftp, $params, 'boot', $type);
            is_deeply(\@result, [0, ''], 'boot succeeds while completion holds the state lock');
        }, directory => $state_directory);
        alarm(0);
        1;
    };
    alarm(0);
    ok($completed, 'completion does not deadlock') or diag($@);
    is($cancel_calls, 0, 'boot never invokes cancellation');
    is(xCAT::FreeBSDInstall::state('node1', directory => $state_directory)->{phase}, 'installed', 'completion persists installed ownership');
    is(read_file("$tftp/xcat/xnba/nodes/node1"), "#!gpxe\n#boot\nexit\n", 'BIOS boot returns to firmware');
    is(read_file("$tftp/xcat/xnba/nodes/node1.uefi"), "#!gpxe\n#boot\nexit\n", 'UEFI boot replaces the installer with exit');
    render($tftp, {}, 'boot', {os => 'rhels9'}, {}, {server => '192.0.2.20', target => 'iqn.example'});
    like(read_file("$tftp/xcat/xnba/nodes/node1"), qr/hdboot\n/, 'existing iSCSI BIOS local-boot behavior is preserved');
};

subtest 'offline cancels real ownership before removing scripts' => sub {
    my $tftp = fixture();
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $state_directory);
    my @result = render($tftp, {}, 'offline', $type);
    is_deeply(\@result, [0, ''], 'offline succeeds without bootparams');
    is($cancel_calls, 1, 'offline invokes cancellation once');
    is(xCAT::FreeBSDInstall::state('node1', directory => $state_directory)->{phase}, 'cancelled', 'cancellation is persisted');
    for my $extension ('', '.uefi', '.pxelinux', '.elilo') {
        ok(!-e "$tftp/xcat/xnba/nodes/node1$extension", "offline removes $extension script");
    }
    my $accepted = eval {
        xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $generation " . ('b' x 32) . ' begin', sub {}, directory => $state_directory);
        1;
    };
    ok(!$accepted, 'cancelled generation cannot begin installation');
    like($@, qr/not armed/, 'stale installer receives a refusal');
};

subtest 'offline cancellation failure preserves scripts and is reported' => sub {
    my $tftp = fixture();
    xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $state_directory);
    write_file("$state_directory/node1.json", '{broken');
    my ($rc, $error) = render($tftp, {}, 'offline', $type);
    is($rc, 1, 'unsafe ownership state makes offline fail');
    like($error, qr/Invalid state file/, 'real lifecycle failure reaches nodeset');
    is(read_file("$tftp/xcat/xnba/nodes/node1"), "old script\n", 'failed cancellation leaves scripts unchanged');
};

subtest 'Linux offline does not enter the FreeBSD lifecycle' => sub {
    my $tftp = fixture();
    my ($rc) = render($tftp, {}, 'offline', {os => 'rhels9', arch => 'x86_64'});
    is($rc, 0, 'Linux offline succeeds');
    is($cancel_calls, 0, 'Linux offline does not cancel FreeBSD ownership');
    ok(!-e $state_directory, 'Linux offline creates no FreeBSD state directory');
};

subtest 'nodeset passes nodetype identity through the public request path' => sub {
    my $tftp = fixture();
    %xCAT::Table::rows = (
        noderes => {node1 => {tftpdir => $tftp}},
        chain => {node1 => {currstate => 'install freebsd15.1-x86_64-compute'}},
        nodetype => {node1 => $type},
        linuximage => {'freebsd-image' => {boottarget => 'unrelated-linux', addkcmdline => 'bad'}},
    );
    my (@responses, @commands);
    local $::XCATROOT = "$temporary/root";
    xCAT_plugin::xnba::process_request({command => ['nodeset'], node => ['node1'], arg => ['osimage=freebsd-image'], _disparatetftp => [0]},
        sub { push @responses, dclone($_[0]); }, sub {
            my ($request) = @_;
            push @commands, $request->{command}[0];
            $request->{bootparams}{node1} = [dclone($params)] if $request->{command}[0] eq 'setdestiny';
        });
    is_deeply(\@responses, [], 'public request reports no errors or PXELINUX warning');
    like(read_file("$tftp/xcat/xnba/nodes/node1"), qr{chain tftp://\$\{next-server\}/xcat/freebsd/node1/boot/pxeboot}, 'bulk nodetype lookup reaches native renderer');
    is_deeply(\@xCAT::Table::lookups, [], 'FreeBSD image is never looked up in linuximage');
    is_deeply(\@commands, [qw(runbeginpre setdestiny makedhcp runendpre)], 'existing nodeset hooks and DHCP update remain ordered');
};

done_testing();
