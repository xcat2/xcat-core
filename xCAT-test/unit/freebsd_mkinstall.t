#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Errno qw(EIO);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Compress::Gzip qw(gzip);
use IO::Select;
use JSON;
use POSIX ();
use Storable qw(dclone);
use Test::More;
use xCAT::FreeBSDInstall;
use xCAT::FreeBSDImage;

BEGIN { $INC{"xCAT/$_.pm"} = 1 for qw(Table TableUtils); }
use xCAT::NetworkUtils;
{
    package xCAT::Table;
    our (%rows, @networks, @writes);
    sub new {
        my ($class, $table, %options) = @_;
        die 'Only the optional iscsi table may be initialized' unless defined($options{-create}) &&
            (!$options{-create} || $table eq 'iscsi');
        if ($table eq 'iscsi' && !exists($rows{$table})) {
            return unless $options{-create};
            $rows{$table} = {};
        }
        return bless { table => $table }, $class;
    }
    sub getNodeAttribs { return Storable::dclone($rows{$_[0]{table}}{$_[1]} || {}); }
    sub getAllEntries { return Storable::dclone([values %{$rows{$_[0]{table}} || {}}]); }
    sub getAllAttribs { return @{Storable::dclone(\@networks)}; }
    sub setAttribs { push @writes, [@_]; die 'Unexpected database write'; }
    sub close { return; }
}
{
    package xCAT::TableUtils;
    our (%site, $installroot, $tftpdir);
    sub getInstallDir { return $installroot; }
    sub getTftpDir { return $tftpdir; }
    sub get_site_attribute { return $site{$_[1]}; }
}
{
    package xCAT::NetworkUtils;
    no warnings 'redefine';
    our (%addresses, @facing, $forwarding);
    sub getipaddr {
        my ($class, $name, %options) = @_;
        die 'IPv4-only name resolution is required' unless $options{OnlyV4} ||
            $name =~ /\A(?:\d+\.){3}\d+\z/ || $name =~ /\A[0-9a-f]*:[0-9a-f:]+\z/;
        return $addresses{$name} if exists($addresses{$name});
        return $name if $name =~ /\A(?:\d+\.){3}\d+\z/;
        return $name if $name =~ /\A[0-9a-f]*:[0-9a-f:]+\z/;
        return;
    }
    sub thishostisnot { return $_[1] ne '192.0.2.1' && $_[1] ne '198.51.100.1'; }
    sub my_ip_facing { return @facing; }
    sub ip_forwarding_enabled { return $forwarding; }
}
require xCAT::Utils;
my $plugin = $ENV{XCAT_FREEBSD_PLUGIN} || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsd.pm";
require $plugin;

my $temporary = abs_path(tempdir(CLEANUP => 1));
my ($root, $media, $image, $state_directory, $prepare_count, $inspect_count, $extra_cmdline);
my $sequence = 0;
my $prepare = \&xCAT::FreeBSDInstall::prepare;
my $inspect = \&xCAT::FreeBSDImage::inspect_media;
{
    no warnings 'redefine';
    *xCAT::FreeBSDInstall::prepare = sub { ++$prepare_count; return $prepare->(@_, directory => $state_directory); };
    *xCAT::FreeBSDImage::inspect_media = sub { ++$inspect_count; return $inspect->(@_); };
}
sub write_file {
    my ($path, $text) = @_;
    make_path(dirname($path));
    open(my $file, '>', $path) or die "$path: $!";
    binmode($file);
    print {$file} $text or die $!;
    close($file) or die $!;
}
sub read_file {
    open(my $file, '<', $_[0]) or die "$_[0]: $!";
    return do { local $/; <$file> };
}
sub fixture {
    $root = "$temporary/case-" . ++$sequence;
    $xCAT::TableUtils::installroot = "$root/install-files";
    $xCAT::TableUtils::tftpdir = "$root/tftp";
    $state_directory = "$root/state";
    make_path($xCAT::TableUtils::installroot, $xCAT::TableUtils::tftpdir);
    my $efi = "\0" x 512;
    substr($efi, 0, 2) = 'MZ';
    substr($efi, 60, 4) = pack('V', 128);
    substr($efi, 128, 4) = "PE\0\0";
    substr($efi, 132, 2) = pack('v', 0x8664);
    substr($efi, 152, 2) = pack('v', 0x20b);
    substr($efi, 220, 2) = pack('v', 10);
    my $elf = "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62);
    my ($kernel, $ramdisk);
    gzip(\$elf => \$kernel) or die $IO::Compress::Gzip::GzipError;
    my $payload = 'test ramdisk';
    gzip(\$payload => \$ramdisk) or die $IO::Compress::Gzip::GzipError;
    my %files = ('boot/pxeboot' => 'native BIOS', 'boot/loader.efi' => $efi,
        'boot/loader.conf' => "mfs_load=\"YES\"\n", 'boot/defaults/loader.conf' => 'defaults',
        'boot/lua/loader.lua' => 'loader', 'boot/kernel/kernel.gz' => $kernel, 'mfsroot.gz' => $ramdisk,
        'usr/freebsd-dist/base.txz' => 'base', 'usr/freebsd-dist/kernel.txz' => 'kernel');
    $files{'usr/freebsd-dist/MANIFEST'} = join('', map {
        "$_\t" . sha256_hex($files{"usr/freebsd-dist/$_"}) . "\t1\tset\tSet\ton\n"
    } qw(base.txz kernel.txz));
    write_file("$root/media/$_", $files{$_}) for keys %files;
    write_file("$root/media/xcat/mfsbsd.json", JSON->new->canonical->encode({
        format => 'xcat-mfsbsd-1', release => '15.1-RELEASE', arch => 'amd64',
        files => {map { $_ => sha256_hex($files{$_}) } keys %files} }));
    $media = xCAT::FreeBSDImage::import_media("$root/media", $xCAT::TableUtils::installroot);
    $image = "freebsd15.1-x86_64-install-compute-" . substr($media->{digest}, 0, 12);
    write_file("$root/key.pub", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE\n");
    write_file("$root/settings", "authorized_keys_file=$root/key.pub\n");
    write_file("$root/node1.disk", "target_disk=vtbd0\ntarget_disk_ident=TEST_SERIAL\nfilesystem=zfs\n");
    %xCAT::Table::rows = (
        osimage => {$image => {imagename => $image, imagetype => 'freebsd', osname => 'FreeBSD',
            osvers => 'freebsd15.1', osarch => 'x86_64', provmethod => 'install', profile => 'compute'}},
        freebsdimage => {$image => {imagename => $image, pkgdir => $media->{pkgdir},
            template => "$root/settings", partitionfile => "$root/#NODE#.disk"}},
        nodetype => {node1 => {os => 'freebsd15.1', arch => 'x86_64', provmethod => $image, profile => 'compute'}},
        noderes => {node1 => {netboot => 'xnba'}},
        mac => {node1 => {mac => '525400123456'}}, iscsi => {},
    );
    @xCAT::Table::networks = ({net => '192.0.2.0', mask => '255.255.255.0', domain => 'example.test'});
    %xCAT::TableUtils::site = (master => 'mn', nameservers => '192.0.2.1', xcatiport => '3002');
    %xCAT::NetworkUtils::addresses = (mn => '198.51.100.1', node1 => '192.0.2.10', sn => '192.0.2.1');
    @xCAT::NetworkUtils::facing = (0, '192.0.2.1');
    $xCAT::NetworkUtils::forwarding = 0;
    ($prepare_count, $inspect_count) = (0, 0);
    $extra_cmdline = undef;
    @xCAT::Table::writes = ();
}
sub install {
    my @nodes = @_ ? @_ : ('node1');
    my $params = {map {$_ => [{kernel => 'stale'}]} @nodes};
    $params->{$_}[0]{addkcmdline} = $extra_cmdline for grep { defined($extra_cmdline) } @nodes;
    my @responses;
    xCAT_plugin::freebsd::process_request({command => ['mkinstall'], node => \@nodes, bootparams => \$params},
        sub { push @responses, $_[0]; });
    return ($params, \@responses);
}
sub rejection {
    my ($change, $pattern, $label) = @_;
    fixture();
    $change->();
    my ($params, $responses) = install();
    is(scalar(@$responses), 1, "$label returns one node error");
    like($responses->[0]{node}[0]{error}[0], $pattern, "$label identifies its cause");
    ok(!exists($params->{node1}), "$label removes stale boot parameters");
    is($prepare_count, 0, "$label is rejected before arming");
    ok(!-e "$root/tftp/xcat/freebsd/node1", "$label publishes no node boot path");
}

fixture();
is(xCAT_plugin::freebsd::handled_commands()->{mkinstall}, 'nodetype:os=(freebsd.*)', 'plugin owns FreeBSD mkinstall dispatch');
my ($params, $responses) = install();
is_deeply($responses, [], 'public mkinstall succeeds');
diag(explain($responses)) if @$responses;
is_deeply($params->{node1}, [{kernel => 'xcat/freebsd/node1/boot/pxeboot', initrd => '', kcmdline => '', addkcmdline => ''}],
    'mkinstall returns only the native loader contract');
my $state = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
is($state->{phase}, 'prepared', 'real lifecycle is prepared but not installing');
my $config_path = "$root/install-files/autoinst/freebsd/node1/$state->{generation}.conf";
my $config = read_file($config_path);
like($config, qr/^filesystem=zfs$/m, 'ZFS reaches the actual published configuration');
like($config, qr/^target_disk_ident=TEST_SERIAL$/m, 'exact disk identity reaches published configuration');
like($config, qr/^master=192\.0\.2\.1$/m, 'unassigned MN uses its node-facing address');
like($config, qr/^hostname=node1\.example\.test$/m, 'network domain reaches installed hostname');
like($config, qr{^dist_url=http://192\.0\.2\.1:80/install/freebsd15\.1/x86_64/[a-f0-9]{64}/usr/freebsd-dist$}m,
    'custom installdir uses the existing public /install alias');
my $loader = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
like($loader, qr{\Qhttp://192.0.2.1:80/install/autoinst/freebsd/node1/$state->{generation}.conf\E}, 'loader names the immutable HTTP configuration');
like($loader, qr/\Q@{[sha256_hex($config)]}\E/, 'loader pins the exact published configuration');
is_deeply(\@xCAT::Table::writes, [], 'mkinstall does not rewrite image or node database policy');
install();
is(xCAT::FreeBSDInstall::state('node1', directory => $state_directory)->{generation}, $state->{generation}, 'identical retry reuses its prepared generation');
my $attempt = 'b' x 32;
xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $state->{generation} $attempt begin\n", sub {}, directory => $state_directory);
($params, $responses) = install();
like($responses->[0]{node}[0]{error}[0], qr/active|already|installation/i, 'active installation cannot be rearmed');
is(read_file($config_path), $config, 'active installation retains its original configuration');

rejection(sub {$xCAT::Table::rows{iscsi}{node1} = {server => 'san', target => 'iqn.test'}}, qr/iSCSI/, 'SAN conflict');
rejection(sub {$extra_cmdline = 'console=ttyS0'}, qr/bootparams.addkcmdline/, 'unsupported extra kernel arguments');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{netboot} = 'pxe'}, qr/netboot=xnba/, 'other boot method');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{servicenode} = 'sn'}, qr/explicit xcatmaster/, 'unowned service-node assignment');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{xcatmaster} = '192.0.2.99'}, qr/selected xcatmaster/, 'remote installation owner');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{xcatmaster} = 'mn,sn'}, qr/single/, 'multiple installation owners');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{xcatmaster} = 'mn'}, qr/off-subnet/, 'unreachable local owner endpoint');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{nfsserver} = 'mn'}, qr/off-subnet/, 'unreachable local HTTP endpoint');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{tftpserver} = 'mn'}, qr/off-subnet/, 'unreachable local TFTP endpoint');
rejection(sub {$xCAT::Table::networks[0]{gateway} = '198.51.100.1'}, qr/gateway must/, 'off-subnet gateway');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{tftpserver} = '192.0.2.99'}, qr/Remote TFTP/, 'TFTP offload');
rejection(sub {$xCAT::Table::networks[0]{tftpserver} = '192.0.2.99'}, qr/Remote TFTP/, 'network-level TFTP offload');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{nfsserver} = '192.0.2.99'}, qr/Remote HTTP/, 'HTTP offload');
rejection(sub {push @xCAT::Table::networks, {%{$xCAT::Table::networks[0]}}}, qr/exactly one/, 'overlapping networks');
rejection(sub {@xCAT::Table::networks = ()}, qr/exactly one/, 'missing network');
for my $case ([undef, 'missing'], ['', 'empty'], ['24', 'prefix length'], ['/24', 'CIDR prefix'],
    ['not-a-mask.invalid', 'hostname'], ['255.255.255.999', 'out-of-range octet'],
    ['255.0.255.0', 'noncontiguous bits'], ['255.255.255', 'abbreviated address'],
    ['255.255.0255.0', 'leading zero'], ["255.255.255.0\n", 'trailing newline'],
    ['255.255.255.0junk', 'trailing text']) {
    my ($mask, $label) = @$case;
    rejection(sub {
        $xCAT::Table::networks[0]{netname} = 'provisioning';
        $xCAT::Table::networks[0]{mask} = $mask;
    }, qr/Invalid IPv4 mask for network provisioning/, "network mask with $label");
}
rejection(sub {
    push @xCAT::Table::networks, {net => '198.51.100.0', mask => ''};
}, qr/Invalid IPv4 mask for network 198\.51\.100\.0/, 'invalid additional IPv4 network');
rejection(sub {
    $xCAT::Table::networks[0]{net} = '192.0.2.10';
    $xCAT::Table::networks[0]{mask} = '255.255.255.255';
}, qr/off-subnet installation endpoint requires a gateway/, 'valid host mask retains gateway requirement');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{installnic} = 'em0'}, qr/installnic/, 'name-only interface selection');
rejection(sub {$xCAT::Table::rows{mac}{node1}{mac} .= '|52:54:00:12:34:57'}, qr/unambiguous/, 'ambiguous provisioning MAC');
rejection(sub {$xCAT::Table::rows{mac}{node1}{mac} = '525400123456!other'}, qr/unambiguous/, 'another node MAC alias');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{installnic} = '52:54:00:12:34:57'}, qr/belong/, 'foreign explicit MAC');
rejection(sub {$xCAT::Table::rows{osimage}{$image}{provmethod} = 'netboot'}, qr/install/, 'stateless image');
rejection(sub {$xCAT::Table::rows{freebsdimage}{$image}{disable} = 'yes'}, qr/disabled/, 'disabled extension');
rejection(sub {delete $xCAT::Table::rows{freebsdimage}{$image}{partitionfile}}, qr/configuration path/, 'missing disk policy');
rejection(sub {delete $xCAT::Table::rows{nodetype}{node1}{profile}}, qr/profile/, 'missing installation profile');
rejection(sub {$xCAT::Table::rows{nodetype}{node1}{profile} = "compute\nboot"}, qr/profile/, 'invalid installation profile');
rejection(sub {write_file("$root/node1.disk", "target_disk=vtbd0\nfilesystem=zfs\n")}, qr/target_disk_ident/, 'missing disk identity');
rejection(sub {$xCAT::TableUtils::site{httpmethod} = 'https'}, qr/HTTP distribution/, 'unsupported HTTPS policy');
rejection(sub {$xCAT::TableUtils::site{httpport} = '65536'}, qr/HTTP port/, 'invalid HTTP port');
rejection(sub {$xCAT::TableUtils::site{xcatiport} = 'invalid'}, qr/status port/, 'invalid status port');
rejection(sub {$xCAT::Table::rows{noderes}{node1}{nameservers} = '192.0.2.1,'}, qr/name server/, 'empty name server token');
rejection(sub {chmod(0666, "$root/node1.disk") or die $!}, qr/Unsafe configuration file/, 'writable disk policy');
rejection(sub {chmod(0666, "$root/key.pub") or die $!}, qr/Unsafe configuration file/, 'writable root public key');

for my $mask ('0.0.0.0', '255.255.255.254') {
    fixture();
    $xCAT::Table::networks[0]{mask} = $mask;
    $xCAT::NetworkUtils::addresses{node1} = '192.0.2.0' if $mask eq '255.255.255.254';
    ($params, $responses) = install();
    is_deeply($responses, [], "valid $mask network mask prepares installation");
    $state = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
    $config = read_file("$root/install-files/autoinst/freebsd/node1/$state->{generation}.conf");
    like($config, qr/^netmask=\Q$mask\E$/m, "valid $mask remains unchanged in published configuration");
}

fixture();
push @xCAT::Table::networks, {net => '2001:db8::', mask => '64'};
($params, $responses) = install();
is_deeply($responses, [], 'an IPv6 network row does not invalidate IPv4 installation');
ok(exists($params->{node1}), 'an IPv6 network row does not suppress native boot publication');

fixture();
delete $xCAT::TableUtils::site{master};
($params, $responses) = install();
is_deeply($responses, [], 'one local node-facing address can identify an otherwise unconfigured MN owner');
ok(exists($params->{node1}), 'the implicit local owner publishes native boot parameters');
for my $payload ('boot/pxeboot', 'usr/freebsd-dist/base.txz') {
    rejection(sub {
        chmod(0644, "$media->{pkgdir}/$payload") or die $!;
        write_file("$media->{pkgdir}/$payload", 'corrupted imported payload');
    }, qr/SHA256 mismatch/, "corrupted imported $payload");
}

fixture();
$xCAT::Table::rows{noderes}{node1} = {netboot => 'xnba', servicenode => 'sn', xcatmaster => 'sn', installnic => '52:54:00:12:34:56'};
$xCAT::Table::networks[0]{gateway} = '<xcatmaster>';
$xCAT::NetworkUtils::forwarding = 1;
($params, $responses) = install();
is_deeply($responses, [], 'explicit local service-node owner prepares installation');
$state = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
$config = read_file("$root/install-files/autoinst/freebsd/node1/$state->{generation}.conf");
like($config, qr/^gateway=192\.0\.2\.1$/m, 'forwarding controller resolves gateway placeholder');

fixture();
$xCAT::Table::rows{noderes}{node1}{xcatmaster} = 'mn';
$xCAT::Table::networks[0]{gateway} = '192.0.2.1';
($params, $responses) = install();
is_deeply($responses, [], 'off-subnet local owner is accepted with a node-subnet gateway');

fixture();
$xCAT::Table::rows{nodetype}{node2} = dclone($xCAT::Table::rows{nodetype}{node1});
$xCAT::Table::rows{noderes}{node2} = {netboot => 'pxe'};
($params, $responses) = install('node2', 'node1');
ok(exists($params->{node1}) && !exists($params->{node2}), 'one invalid node does not suppress a valid node');
is($responses->[0]{node}[0]{name}[0], 'node2', 'error identifies the failed node');
is($inspect_count, 1, 'one image is inspected once per mkinstall request');

fixture();
{
    no warnings qw(redefine once);
    local *xCAT::FreeBSDBoot::copy = sub { $! = EIO; return 0; };
    ($params, $responses) = install();
}
is(scalar(@$responses), 1, 'a boot payload copy failure returns one node error');
like($responses->[0]{node}[0]{error}[0], qr/Cannot copy/, 'publication failure retains the filesystem cause');
ok(!exists($params->{node1}), 'publication failure returns no stale boot parameters');
is($prepare_count, 1, 'publication failure occurs after real lifecycle preparation');
$state = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
is($state->{phase}, 'prepared', 'publication failure leaves a prepared retryable generation');
ok(!exists($state->{attempt}), 'publication failure does not claim a boot attempt');
ok(!-e "$root/tftp/xcat/freebsd/node1", 'failed boot publication leaves no active node loader');
$config_path = "$root/install-files/autoinst/freebsd/node1/$state->{generation}.conf";
$config = read_file($config_path);
like($config, qr/^generation=\Q$state->{generation}\E$/m, 'immutable configuration survives later boot publication failure');
my $failed_generation = $state->{generation};
($params, $responses) = install();
is_deeply($responses, [], 'an identical request retries the failed publication successfully');
ok(exists($params->{node1}), 'successful publication retry returns native boot parameters');
$state = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
is($state->{generation}, $failed_generation, 'publication retry preserves its prepared generation');
is(read_file($config_path), $config, 'publication retry preserves exact immutable configuration');
is(readlink("$root/tftp/xcat/freebsd/node1"), ".nodes/node1/$failed_generation", 'publication retry activates the matching generation');

fixture();
write_file("$root/node1-next.disk", "target_disk=vtbd0\ntarget_disk_ident=NEXT_SERIAL\nfilesystem=ufs\n");
pipe(my $first_ready_reader, my $first_ready_writer) or die $!;
pipe(my $release_reader, my $release_writer) or die $!;
pipe(my $first_result_reader, my $first_result_writer) or die $!;
my $publish = \&xCAT::FreeBSDBoot::publish;
my $first = fork();
die $! unless defined($first);
if (!$first) {
    close($first_ready_reader);
    close($release_writer);
    close($first_result_reader);
    my $token;
    my $ok = eval {
        no warnings 'redefine';
        local *xCAT::FreeBSDBoot::publish = sub {
            my ($node, %options) = @_;
            $token = $options{generation};
            print {$first_ready_writer} "$token\n" or die $!;
            close($first_ready_writer);
            die 'first publisher was not released' unless defined(scalar(<$release_reader>));
            return $publish->(@_);
        };
        my ($boot, $errors) = install();
        print {$first_result_writer} encode_json({params => $boot, errors => $errors, generation => $token}), "\n";
        close($first_result_writer);
        1;
    };
    warn $@ unless $ok;
    POSIX::_exit($ok ? 0 : 1);
}
close($first_ready_writer);
close($release_reader);
close($first_result_writer);
local $SIG{ALRM} = sub { kill('KILL', $first); die "First plugin publisher timed out\n"; };
alarm(15);
my $first_generation = <$first_ready_reader>;
die 'first plugin request did not reach publication' unless defined($first_generation);
chomp($first_generation);
close($first_ready_reader);
sysopen(my $lock_probe, "$state_directory/node1.lock", O_RDWR) or die $!;
ok(!flock($lock_probe, LOCK_EX | LOCK_NB), 'public mkinstall retains its node lock across boot publication');
close($lock_probe);
pipe(my $second_ready_reader, my $second_ready_writer) or die $!;
pipe(my $second_result_reader, my $second_result_writer) or die $!;
my $prepare_request = \&xCAT::FreeBSDInstall::prepare;
my $second = fork();
die $! unless defined($second);
if (!$second) {
    close($second_ready_reader);
    close($second_result_reader);
    close($release_writer);
    close($first_result_reader);
    $xCAT::Table::rows{freebsdimage}{$image}{partitionfile} = "$root/node1-next.disk";
    my $token;
    my $ok = eval {
        no warnings 'redefine';
        local *xCAT::FreeBSDInstall::prepare = sub {
            print {$second_ready_writer} "preparing\n" or die $!;
            close($second_ready_writer);
            return $prepare_request->(@_);
        };
        local *xCAT::FreeBSDBoot::publish = sub {
            my ($node, %options) = @_;
            $token = $options{generation};
            return $publish->(@_);
        };
        my ($boot, $errors) = install();
        print {$second_result_writer} encode_json({params => $boot, errors => $errors, generation => $token}), "\n";
        close($second_result_writer);
        1;
    };
    warn $@ unless $ok;
    POSIX::_exit($ok ? 0 : 1);
}
close($second_ready_writer);
close($second_result_writer);
local $SIG{ALRM} = sub { kill('KILL', $first, $second); die "Concurrent plugin requests timed out\n"; };
die 'second plugin request did not reach preparation' unless defined(scalar(<$second_ready_reader>));
close($second_ready_reader);
ok(!IO::Select->new($second_result_reader)->can_read(0.1), 'a different-policy request waits for prior publication');
is(decode_json(read_file("$state_directory/node1.json"))->{generation}, $first_generation,
    'waiting policy cannot replace the generation under publication');
print {$release_writer} "continue\n" or die $!;
close($release_writer);
my $first_result = decode_json(scalar(<$first_result_reader>));
close($first_result_reader);
my $second_result = decode_json(scalar(<$second_result_reader>));
close($second_result_reader);
waitpid($first, 0);
is($?, 0, 'first public plugin request exits successfully');
waitpid($second, 0);
is($?, 0, 'second public plugin request exits successfully');
alarm(0);
for my $result ($first_result, $second_result) {
    is_deeply($result->{errors}, [], 'serialized public plugin request reports no error');
    is_deeply($result->{params}{node1}, [{kernel => 'xcat/freebsd/node1/boot/pxeboot', initrd => '', kcmdline => '', addkcmdline => ''}],
        'serialized public plugin request returns native boot parameters');
}
isnt($first_result->{generation}, $second_result->{generation}, 'different disk policies receive different generations');
$state = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
is($state->{generation}, $second_result->{generation}, 'latest completed request owns controller state');
is(readlink("$root/tftp/xcat/freebsd/node1"), ".nodes/node1/$state->{generation}", 'stable loader and final controller generation agree');
$config_path = "$root/install-files/autoinst/freebsd/node1/$state->{generation}.conf";
$config = read_file($config_path);
$loader = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
like($loader, qr{node1/\Q$state->{generation}\E\.conf}, 'final loader selects its controller generation configuration');
like($loader, qr/\Q@{[sha256_hex($config)]}\E/, 'final loader pins the matching configuration bytes');
like($config, qr/^target_disk_ident=NEXT_SERIAL\nfilesystem=ufs$/m, 'final configuration uses the later disk policy');
like(read_file("$root/install-files/autoinst/freebsd/node1/$first_generation.conf"),
    qr/^target_disk_ident=TEST_SERIAL\nfilesystem=zfs$/m, 'earlier immutable configuration is preserved');

fixture();
delete $xCAT::Table::rows{iscsi};
($params, $responses) = install();
is_deeply($responses, [], 'a fresh database without an iscsi table can prepare local-disk installation');
is_deeply($xCAT::Table::rows{iscsi}, {}, 'preparation initializes only an empty optional iscsi table');
is($prepare_count, 1, 'optional table initialization does not suppress installation preparation');
done_testing();
