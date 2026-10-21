#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Errno qw(EIO);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Find qw(find);
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
use xCAT::Schema;
our (%XCATSITEVALS, %GLOBAL_TAB_HASH, %GLOBAL_SN_HASH, %GLOBAL_TABDUMP_HASH, @exclude_nodes);

BEGIN { $INC{'xCAT/Table.pm'} = 1; }
use xCAT::TableUtils;
use xCAT::NetworkUtils;
{
    package xCAT::Table;
    our (%rows, @networks, @writes);
    sub new {
        my ($class, $table, %options) = @_;
        die 'Only the optional iscsi table may be initialized'
          if $options{-create} && $table ne 'iscsi' && !exists($rows{$table});
        if ($table eq 'iscsi' && !exists($rows{$table})) {
            return unless $options{-create};
            $rows{$table} = {};
        }
        return bless { table => $table }, $class;
    }
    sub getNodeAttribs {
        my ($self, $node, $columns) = @_;
        my %valid = map { $_ => 1 } @{$xCAT::Schema::tabspec{$self->{table}}{cols}};
        die 'Requested an unknown table column' if $columns && grep { !$valid{$_} } @$columns;
        return Storable::dclone($rows{$self->{table}}{$node} || {});
    }
    sub getAllEntries { return Storable::dclone([values %{$rows{$_[0]{table}} || {}}]); }
    sub getAllAttribs {
        my ($self) = @_;
        return @{Storable::dclone(\@networks)} if $self->{table} eq 'networks';
        return @{getAllEntries($self)};
    }
    sub getAllNodeAttribs { return getAllAttribs(@_); }
    sub getAttribs {
        my ($self, $keys) = @_;
        for my $row (@{getAllEntries($self)}) {
            next if grep { !defined($row->{$_}) || !defined($keys->{$_}) || $row->{$_} ne $keys->{$_} } keys %$keys;
            return $row;
        }
        return;
    }
    sub getNodesAttribs {
        my ($self, $nodes) = @_;
        return { map { $_ => [$self->getNodeAttribs($_)] } @$nodes };
    }
    sub getAllAttribsWhere {
        die 'Only the empty management-node query is provided' unless $_[0]{table} eq 'nodelist';
        return;
    }
    sub setAttribs { push @writes, [@_]; die 'Unexpected database write'; }
    sub close { return; }
}
{
    package xCAT::TableUtils;
    no warnings 'redefine';
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
        my ($class, $name) = @_;
        return $addresses{$name} if exists($addresses{$name});
        return $name if $name =~ /\A(?:\d+\.){3}\d+\z/;
        return $name if $name =~ /\A[0-9a-f]*:[0-9a-f:]+\z/;
        return;
    }
    sub thishostisnot { return $_[1] ne '192.0.2.1' && $_[1] ne '198.51.100.1'; }
    sub my_ip_facing { return @facing; }
    sub ip_forwarding_enabled { return $forwarding; }
    sub gethostnameandip () { return ('mn', '192.0.2.1'); }
}
{ package xCAT_monitoring::monitorctrl; sub getNodeConfData { return {}; } }
require xCAT::Utils;
my $plugin = $ENV{XCAT_FREEBSD_PLUGIN} || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsd.pm";
require $plugin;

my $temporary = abs_path(tempdir(CLEANUP => 1));
my ($root, $media, $image, $state_directory, $prepare_count, $inspect_count, $extra_cmdline);
my $sequence = 0;
my $prepare = \&xCAT::FreeBSDInstall::prepare;
my $read_state = \&xCAT::FreeBSDInstall::state;
my $inspect = \&xCAT::FreeBSDImage::inspect_media;
{
    no warnings 'redefine';
    *xCAT::FreeBSDInstall::prepare = sub { ++$prepare_count; return $prepare->(@_, directory => $state_directory); };
    *xCAT::FreeBSDInstall::state = sub { return $read_state->(@_, directory => $state_directory); };
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
    my $format = shift || 'xcat-mfsbsd-1';
    my $install_contract = shift;
    my $postscript_contract = shift;
    my $network_contract = shift;
    my $disk_record_contract = shift;
    my $disk_selection_contract = shift;
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
    if ($format eq 'xcat-mfsbsd-2') {
        delete @files{map { "usr/freebsd-dist/$_" } qw(MANIFEST base.txz kernel.txz)};
        my @postscript_runtime = $postscript_contract ? qw(usr/local/libexec/xcat-postscript
            usr/local/libexec/xcat-postscript-packages usr/local/libexec/freebsd-pkg-resolve
            usr/local/libexec/xcat-postboot) : ();
        my @runtime_paths = qw(
            usr/local/sbin/xcat-install usr/local/libexec/xcat-install-lib.sh
            usr/local/share/xcat/installerconfig.tmpl usr/sbin/bsdinstall
            usr/libexec/bsdinstall/script usr/libexec/bsdinstall/pkgbase
            usr/libexec/bsdinstall/umount usr/libexec/flua usr/local/sbin/pkg-static
        );
        if (($install_contract || '') =~ /\Axcat-freebsd-install-[3456]\z/x) {
            @runtime_paths = map { (split(/\t/x, $_))[1] }
                grep { /^file\t/x } split(/\n/x, read_file("$FindBin::Bin/../fixtures/freebsd-storage-runtime.tsv"));
        }
        push @runtime_paths, qw(usr/local/libexec/xcat-network.sh usr/local/libexec/confignetwork-freebsd.awk
            boot/modules/if_infiniband.ko boot/modules/if_lagg.ko boot/modules/bridgestp.ko
            boot/modules/if_bridge.ko boot/modules/if_vlan.ko)
            if $network_contract;
        $files{'xcat/runtime.tsv'} = "format\txcat-freebsd-runtime-2\n"
          . "target\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000\n"
          . "pkg-version\t2.6.2\nbsdinstall-contract\txcat-freebsd-pkgbase-1\n"
          . join('', map { "file\t$_\t" . sha256_hex("runtime $_") . "\n" } sort(@postscript_runtime, @runtime_paths));
    }
    write_file("$root/media/$_", $files{$_}) for keys %files;
    write_file("$root/media/xcat/mfsbsd.json", JSON->new->canonical->encode({
        format => $format, release => '15.1-RELEASE', arch => 'amd64',
        ($format eq 'xcat-mfsbsd-2' ? (mfsbsd_commit => 'a' x 40) : ()),
        (defined($install_contract) ? (install_contract => $install_contract) : ()),
        (defined($postscript_contract) ? (postscript_contract => $postscript_contract) : ()),
        (defined($network_contract) ? (network_contract => $network_contract) : ()),
        (defined($disk_record_contract) ? (disk_record_contract => $disk_record_contract) : ()),
        (defined($disk_record_contract) || defined($disk_selection_contract)
            ? (disk_selection_contract => 'xcat-freebsd-disk-selection-1') : ()),
        files => {map { $_ => sha256_hex($files{$_}) } keys %files} }));
    $media = xCAT::FreeBSDImage::import_media("$root/media", $xCAT::TableUtils::installroot);
    $image = "freebsd15.1-x86_64-install-compute-" . substr($media->{digest}, 0, 12);
    write_file("$root/key.pub", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE\n");
    write_file("$root/settings", "authorized_keys_file=$root/key.pub\n");
    write_file("$root/node1.disk", "target_disk=vtbd0\ntarget_disk_ident=TEST_SERIAL\nfilesystem=zfs\n");
    %xCAT::Table::rows = (
        osimage => {$image => {imagename => $image, imagetype => 'freebsd', osname => 'FreeBSD',
            osvers => 'freebsd15.1', osarch => 'x86_64', provmethod => 'install', profile => 'compute'}},
        freebsdimage => {$image => {imagename => $image, pkgdir => $media->{pkgdir} || $media->{bootdir},
            template => "$root/settings", partitionfile => "$root/#NODE#.disk"}},
        nodetype => {node1 => {os => 'freebsd15.1', arch => 'x86_64', provmethod => $image, profile => 'compute'}},
        noderes => {node1 => {netboot => 'xnba'}},
        mac => {node1 => {mac => '525400123456'}}, iscsi => {},
    );
    @xCAT::Table::networks = ({net => '192.0.2.0', mask => '255.255.255.0', domain => 'example.test'});
    %xCAT::TableUtils::site = (master => 'mn', nameservers => '192.0.2.1', xcatiport => '3002', sharedtftp => 0);
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

sub definition_rejection {
    my ($change, $pattern, $label) = @_;
    rejection($change, $pattern, $label);
    is($inspect_count, 0, "$label is rejected before media inspection");
    ok(!-e "$root/install-files/autoinst/freebsd/node1", "$label publishes no installer configuration");
    ok(!-e $state_directory, "$label creates no lifecycle state");
    is_deeply(\@xCAT::Table::writes, [], "$label performs no database write");
    return;
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

sub definition_versions {
    for my $version (undef, '', '1') {
        fixture();
        $xCAT::Table::rows{freebsdimage}{$image}{imageversion} = $version if defined($version);
        my $label = !defined($version) ? 'absent' : length($version) ? 'explicit one' : 'empty';
        my ($boot, $errors) = install();
        is_deeply($errors, [], "$label version retains legacy installation");
        is($boot->{node1}[0]{kernel}, 'xcat/freebsd/node1/boot/pxeboot', "$label version publishes the native loader");
        my $prepared = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
        is($prepared->{phase}, 'prepared', "$label version prepares the real lifecycle");
        my $published = read_file("$root/install-files/autoinst/freebsd/node1/$prepared->{generation}.conf");
        like($published, qr{^dist_url=http://[^\n]+/usr/freebsd-dist$}mx,
            "$label version preserves the distribution-set runtime contract");
    }
    fixture();
    $xCAT::Table::rows{freebsdimage}{$image}{$_} = '' for qw(imageversion bootdir pkglist otherpkgdir otherpkglist);
    my ($boot, $errors) = install();
    is_deeply($errors, [], 'empty v2-only metadata retains legacy installation');
    ok(exists($boot->{node1}), 'empty v2-only metadata does not suppress legacy boot publication');

    for my $version ('0', '3', '01', '2 ', "1\n", '-1', 'pkgbase') {
        my $label = $version;
        $label =~ s/\n/\\n/gx;
        definition_rejection(sub { $xCAT::Table::rows{freebsdimage}{$image}{imageversion} = $version },
            qr/imageversion[ ]must[ ]be[ ]1[ ]or[ ]2/x, "invalid imageversion $label");
    }
    for my $field (qw(bootdir pkglist otherpkgdir otherpkglist)) {
        definition_rejection(sub { $xCAT::Table::rows{freebsdimage}{$image}{$field} = "$root/policy" },
            qr/\Q$field\E[ ]requires[ ]imageversion=2/x, "legacy image with $field");
    }
    rejection(sub {
        $xCAT::Table::rows{freebsdimage}{$image}{imageversion} = '2';
        $xCAT::Table::rows{freebsdimage}{$image}{bootdir} = $media->{pkgdir};
        $xCAT::Table::rows{freebsdimage}{$image}{pkglist} = "$root/base.pkglist";
        $xCAT::Table::rows{freebsdimage}{$image}{otherpkgdir} = "$root/applications";
        $xCAT::Table::rows{freebsdimage}{$image}{otherpkglist} = "$root/applications.pkglist";
    }, qr/bootdir[ ]requires[ ]an[ ]xcat-mfsbsd-2/x,
        'version two pointing at valid legacy media');
    definition_rejection(sub {
        $xCAT::Table::rows{freebsdimage}{$image}{imageversion} = '2';
        $xCAT::Table::rows{freebsdimage}{$image}{bootdir} = 'relative/path';
    }, qr/bootdir/x, 'version two with an invalid boot directory');
    return;
}

subtest 'image definition versions preserve legacy installation and validate pkgbase media' => \&definition_versions;

sub boot_only_rejection {
    for my $layout (qw(boot legacy)) {
        fixture('xcat-mfsbsd-2');
        my $pkgdir = $media->{bootdir};
        if ($layout eq 'legacy') {
            my $relocated = "$xCAT::TableUtils::installroot/freebsd15.1/x86_64/$media->{digest}";
            rename($pkgdir, $relocated) or croak $!;
            $pkgdir = $relocated;
        }
        $xCAT::Table::rows{freebsdimage}{$image}{pkgdir} = $pkgdir;
        my ($boot, $errors) = install();
        is(scalar(@$errors), 1, "$layout path returns one node error");
        like($errors->[0]{node}[0]{error}[0], qr/xcat-mfsbsd-1|legacy.*bundle[ ]format/ix,
            "$layout path identifies the incompatible media format");
        ok(!exists($boot->{node1}), "$layout path removes stale boot parameters");
        is($inspect_count, 1, "$layout path uses the real boot-bundle inspector");
        is($prepare_count, 0, "$layout path is rejected before lifecycle preparation");
        ok(!-e $state_directory, "$layout path creates no lifecycle state");
        ok(!-e "$root/install-files/autoinst/freebsd/node1", "$layout path creates no installer configuration");
        ok(!-e "$root/tftp/xcat/freebsd/node1", "$layout path creates no node boot tree");
        is_deeply(\@xCAT::Table::writes, [], "$layout path performs no database writes");
    }
    fixture('xcat-mfsbsd-2');
    $xCAT::Table::rows{freebsdimage}{$image}{imageversion} = '2';
    $xCAT::Table::rows{freebsdimage}{$image}{bootdir} = $media->{bootdir};
    my ($boot, $errors) = install();
    like($errors->[0]{node}[0]{error}[0], qr/policy/ix,
        'an imported boot-only artifact also requires the administrator package policy');
    is($inspect_count, 1, 'version two inspects its boot media before planning');
    is($prepare_count, 0, 'missing package policy is rejected before lifecycle preparation');
    ok(!exists($boot->{node1}), 'missing package policy removes stale boot parameters');
    ok(!-e $state_directory, 'missing package policy creates no lifecycle state');
    return;
}

subtest 'boot-only media cannot arm a legacy installation' => \&boot_only_rejection;

subtest 'pkgbase installation publishes a native source-bound package plan' => sub {
    plan(skip_all => 'Native pkg, solver and Linux container root are required')
      unless $^O eq 'linux' && $> == 0 && defined($ENV{XCAT_FREEBSD_NATIVE_PKG})
      && defined($ENV{XCAT_FREEBSD_NATIVE_SOLVER});
    require XCAT::Test::FreeBSDRepoFixture;
    require xCAT::FreeBSDPkg;
    require xCAT::FreeBSDRepo;
    require xCAT::FreeBSDRepoImport;
    require xCAT::FreeBSDPackagePlan;
    my $native = "$temporary/native";
    make_path("$native/empty", "$native/repos");
    my $json = JSON->new->utf8->canonical;
    my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
    my $solver = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_SOLVER}) };
    $tool->{sha256} = sha256_hex(read_file($tool->{path}));
    $solver->{sha256} = sha256_hex(read_file($solver->{path}));
    my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
    if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
        $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
        $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
        $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
    }
    write_file("$native/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
        PKG_DBDIR => "$native/db", PKG_CACHEDIR => "$native/cache", REPOS_DIR => ["$native/repos"],
        REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
    my $command = sub {
        my $result = xCAT::FreeBSDPkg::run_command([@_], cwd => $native,
            environment => \%environment, timeout => 60, stdout_limit => 67108864);
        croak "Native fixture failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
        return $result->{stdout};
    };
    my $run_pkg = sub { return $command->($tool->{path}, '-C', "$native/pkg.conf", @_); };
    my $producer = XCAT::Test::FreeBSDRepoFixture->new(root => $native,
        command => $command, run_pkg => $run_pkg, write_file => \&write_file);
    my $source = $producer->release_tree(1);
    for my $name (qw(FreeBSD-ssh FreeBSD-bsdconfig)) {
        $producer->create_package("$source/usr/freebsd-packages/offline/All", $name,
            version => '15.1', origin => "base/$name", annotations => { FreeBSD_version => '1501000' });
    }
    $run_pkg->('repo', "$source/usr/freebsd-packages/offline");
    my $source_digest = xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest};
    my $policy = { format => 'xcat-freebsd-import-policy-1', tool => $tool, solver => $solver,
        releases => {}, repositories => {} };
    my $fresh = sub {
        fixture('xcat-mfsbsd-2', @_);
        my $publication = xCAT::FreeBSDRepoImport::import_release($source,
            $xCAT::TableUtils::installroot, tool => $tool,
            trust => { type => 'operator-trusted-release', digest => $source_digest });
        my $definition = $xCAT::Table::rows{freebsdimage}{$image};
        @{$definition}{qw(imageversion bootdir pkgdir pkglist otherpkgdir otherpkglist)} =
          ('2', $media->{bootdir}, "$publication->{path}/base", "$root/base.pkglist",
           "$publication->{path}/applications", "$root/apps.pkglist");
        write_file("$root/base.pkglist", "minimal\nkernel\n");
        write_file("$root/apps.pkglist", "application\n");
        write_file("$root/policy.json", $json->encode($policy));
        $xCAT::TableUtils::site{freebsdimportpolicy} = "$root/policy.json";
        return;
    };
    my $published = sub {
        my $current = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
        return ($current, read_file("$root/install-files/autoinst/freebsd/node1/$current->{generation}.conf"));
    };
    subtest 'public preparation reuses the retained OS identities' => sub {
        $fresh->('xcat-freebsd-install-3', undef, undef, 'xcat-freebsd-os-disks-1');
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\n");
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'automatic installation is prepared');
        return if @$errors;
        my ($current) = $published->();
        is_deeply($current->{os_policy}, {filesystem => 'ufs', target_disk => 'auto'},
            'media capability binds the automatic policy to the prepared generation');
        my $ok = eval { xCAT::FreeBSDInstall::transition('node1',
            'freebsd-install-v2 ' . $current->{generation} . ' ' . ('c' x 32) . " begin vtbd4\@OS_SERIAL\n",
            sub { return; }, directory => $state_directory); 1; };
        ok($ok, 'the prepared policy accepts the native selection') or do { diag($@); return; };
        my $record = ($published->())[0]{os_disks};
        xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\ndisk_action=erase\n");
        ($boot, $errors) = install();
        is_deeply($errors, [], 'automatic erase compiles with the controller record');
        return if @$errors;
        my ($reinstall, $content) = $published->();
        like($content, qr/^target_disk=vtbd4$/mx, 'published policy names the previous OS disk');
        like($content, qr/^target_disk_ident=OS_SERIAL$/mx, 'published policy pins the previous serial');
        is_deeply($reinstall->{os_policy}, $record->{layout}, 'new authorization requires the recorded identity');
        xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
        $xCAT::Table::rows{noderes}{node1}{servicenode} = 'sn';
        $state_directory = "$root/new-standby-state";
        my $metadata = {epoch => 'a' x 32, coordinator => '198.51.100.1', server => '192.0.2.1'};
        my @operations;
        my $pool_params = {};
        my @responses;
        my $pool_prepare = sub {
            @responses = (); $pool_params = {};
            xCAT_plugin::freebsd::process_request({command => ['mkinstall'], node => ['node1'],
            bootparams => \$pool_params, _freebsd_pool => [encode_json({node1 => $metadata})]},
            sub { push @responses, shift; }, sub {
                my $request = shift;
                push @operations, [$request->{arg}[0], decode_json($request->{arg}[1])];
                return {data => [encode_json({format => 'xcat-freebsd-pool-1', node => 'node1',
                    operation => $request->{arg}[0], result => {epoch => $metadata->{epoch},
                        phase => 'prepared', os_disks => $record}})]};
            });
            return;
        };
        $pool_prepare->();
        is_deeply(\@responses, [], 'service-node preparation reads the coordinator record');
        is_deeply([map { $_->[0] } @operations], [qw(inspect register)],
            'inspection precedes registration through the public producer');
        is_deeply($operations[-1][1]{os_policy}, $record->{layout}, 'registration binds the concrete disk policy');
        is_deeply(($published->())[0]{os_disks}, $record, 'local state retains the coordinator record');
        delete $xCAT::Table::rows{noderes}{node1}{servicenode};
        ($boot, $errors) = install();
        like($errors->[0]{node}[0]{error}[0], qr/retained[ ]OS[ ]disk[ ]record/x,
            'moving from a pool to a fixed owner cannot reuse an automatic erase policy');
        ok(!exists($boot->{node1}), 'changed scope publishes no automatic boot parameters');
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=vtbd4\ntarget_disk_ident=OS_SERIAL\nswap_size=0\n");
        ($boot, $errors) = install();
        is_deeply($errors, [], 'explicit verified identities permit the owner-scope change');
        ok(!exists(($published->())[0]{service_pool}), 'explicit preparation adopts the fixed owner scope');
        ok(!exists(($published->())[0]{os_disks}), 'scope change discards the old local record');
        my $explicit_generation = ($published->())[0]{generation};
        (undef, $errors) = install();
        is_deeply($errors, [], 'identical explicit migration preparation can be repeated');
        is(($published->())[0]{generation}, $explicit_generation, 'identical migration preparation retains its generation');
        for my $cancelled (0, 1) {
            xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory) if $cancelled;
            for my $erase ('', "disk_action=erase\n") {
                write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\n" . $erase);
                ($boot, $errors) = install();
                like($errors->[0]{node}[0]{error}[0], qr/(?:explicit[ ]OS[ ]disks|retained[ ]OS[ ]disk[ ]record)/x,
                    'preparation or cancellation alone does not refresh a migrated record');
                ok(!exists($boot->{node1}), 'unrefreshed migration cannot arm automatic installation');
            }
        }
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=vtbd4\ntarget_disk_ident=OS_SERIAL\nswap_size=0\n");
        (undef, $errors) = install();
        is_deeply($errors, [], 'explicit migration can be retried');
        my $migrated = ($published->())[0];
        xCAT::FreeBSDInstall::transition('node1',
            'freebsd-install-v2 ' . $migrated->{generation} . ' ' . ('d' x 32) . " begin vtbd4\@OS_SERIAL\n",
            sub { return; }, directory => $state_directory);
        ok(!exists(($published->())[0]{os_disk_rebind}), 'authorization clears the migration restriction');
        $record = ($published->())[0]{os_disks};
        xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\ndisk_action=erase\n");
        (undef, $errors) = install();
        is_deeply($errors, [], 'automatic reinstall resumes with the refreshed record');
        $xCAT::Table::rows{noderes}{node1}{servicenode} = 'sn';
        for my $old_pool (0, 1) {
            if ($old_pool) {
                xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
                xCAT::FreeBSDInstall::prepare('node1', 'b' x 64, directory => $state_directory,
                    previous_os_disks => $record, os_policy => $record->{layout},
                    service_pool => {%$metadata, coordinator => '198.51.100.2'});
            }
            $pool_prepare->();
            like($responses[0]{node}[0]{error}[0], qr/retained[ ]OS[ ]disk[ ]record/x,
                $old_pool ? 'coordinator change rejects automatic record reuse' : 'fixed-to-pool change rejects automatic record reuse');
            ok(!exists($pool_params->{node1}), 'changed pool scope publishes no automatic boot parameters');
        }
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=vtbd4\ntarget_disk_ident=OS_SERIAL\nswap_size=0\n");
        $metadata->{epoch} = 'b' x 32;
        $pool_prepare->();
        is_deeply(\@responses, [], 'explicit pool migration prepares the member');
        if (@responses) { diag(explain(\@responses)); return; }
        ok(($published->())[0]{os_disk_rebind}, 'member waits for a fresh coordinator record');
        write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\ndisk_action=erase\n");
        $pool_prepare->();
        like($responses[0]{node}[0]{error}[0], qr/retained[ ]OS[ ]disk[ ]record/x,
            'unchanged coordinator record cannot clear the pending migration');
        $record = {%$record, generation => 'f' x 32, attempt => 'e' x 32};
        $metadata->{epoch} = 'e' x 32;
        $pool_prepare->();
        is_deeply(\@responses, [], 'automatic policy accepts the record refreshed by another member');
        if (@responses) { diag(explain(\@responses)); return; }
        ok(!exists(($published->())[0]{os_disk_rebind}), 'public preparation clears the standby restriction');
    };
    subtest 'failure before authorization permits automatic selection to retry' => sub {
        for my $capability (undef, 'xcat-freebsd-os-disks-1') {
            $fresh->('xcat-freebsd-install-3', undef, undef, $capability, 'xcat-freebsd-disk-selection-1');
            write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\n");
            my (undef, $errors) = install();
            is_deeply($errors, [], 'automatic selection is initially prepared');
            if (@$errors) { diag(explain($errors)); next; }
            my $generation = ($published->())[0]{generation};
            xCAT::FreeBSDInstall::transition('node1',
                'freebsd-install-v1 ' . $generation . ' ' . ('c' x 32) . " failed\n",
                sub { return; }, directory => $state_directory);
            xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
            (undef, $errors) = install();
            is_deeply($errors, [], 'unstarted attempt does not require manual serial assignments');
            if (@$errors) { diag(explain($errors)); next; }
            my (undef, $content) = $published->();
            like($content, qr/^disk_selection=empty$/mx, 'retry retains automatic blank-disk selection');
        }
    };
    subtest 'unrecorded attempts cannot silently start another automatic selection' => sub {
        $fresh->('xcat-freebsd-install-3', undef, undef, 'xcat-freebsd-os-disks-1');
        my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $state_directory);
        xCAT::FreeBSDInstall::transition('node1',
            'freebsd-install-v1 ' . $generation . ' ' . ('c' x 32) . " begin\n",
            sub { return; }, directory => $state_directory);
        xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
        my $explicit = read_file("$root/node1.disk");
        for my $rearmed (0, 1) {
            if ($rearmed) {
                write_file("$root/node1.disk", $explicit);
                my (undef, $errors) = install();
                is_deeply($errors, [], 'explicit migration can prepare the verified disks');
            }
            write_file("$root/node1.disk", "filesystem=ufs\ntarget_disk=auto\nswap_size=0\n");
            my ($boot, $errors) = install();
            like($errors->[0]{node}[0]{error}[0], qr/unrecorded[ ]attempt/x,
                'known prior installation without a record requires explicit disks');
            ok(!exists($boot->{node1}), 'no automatic boot parameters are published');
        }
    };
    subtest 'grouped reinstall renders recorded primary and auxiliary roles' => sub {
        $fresh->('xcat-freebsd-install-6', undef, undef, 'xcat-freebsd-os-disks-1');
        my $grouped_policy = "filesystem=zfs\nzfs_topology=mirror\nzfs_vdevs=auto:2\nswap_mode=none\nswap_size=0\n"
            . "zfs_log_vdevs=vtbd2\@LOG\nzfs_cache_vdevs=vtbd3\@CACHE\nzfs_special_vdevs=vtbd4\@SPECIAL0,vtbd5\@SPECIAL1\n";
        write_file("$root/node1.disk", $grouped_policy);
        my (undef, $errors) = install();
        is_deeply($errors, [], 'automatic grouped policy prepares with auxiliary devices');
        return if @$errors;
        my ($current) = $published->();
        my $ok = eval { xCAT::FreeBSDInstall::transition('node1',
            'freebsd-install-v2 ' . $current->{generation} . ' ' . ('c' x 32) . " begin vtbd0\@OS0,vtbd1\@OS1\n",
            sub { return; }, directory => $state_directory); 1; };
        ok($ok, 'grouped selection is retained') or return;
        xCAT::FreeBSDInstall::cancel('node1', directory => $state_directory);
        write_file("$root/node1.disk", $grouped_policy . "disk_action=erase\n");
        (undef, $errors) = install();
        is_deeply($errors, [], 'grouped automatic reinstall prepares');
        return if @$errors;
        my (undef, $content) = $published->();
        for my $line ('zfs_vdevs=vtbd0@OS0,vtbd1@OS1', 'zfs_log_vdevs=vtbd2@LOG',
            'zfs_cache_vdevs=vtbd3@CACHE', 'zfs_special_vdevs=vtbd4@SPECIAL0,vtbd5@SPECIAL1', 'disk_action=erase') {
            like($content, qr/^\Q$line\E$/mx, 'published policy retains its recorded role');
        }
        unlike($content, qr/^disk_selection=/mx, 'native reinstall cannot choose another blank disk');
    };
    subtest 'early virtual networking uses the existing adapter inventory' => sub {
        $fresh->('xcat-freebsd-install-3', undef, 'xcat-freebsd-bootstrap-1');
        write_file("$root/settings", "authorized_keys_file=$root/key.pub\nbootstrap_interface=bridge0\n");
        write_file("$root/install-files/postscripts/confignetwork-freebsd.awk",
            read_file("$FindBin::Bin/../../xCAT/postscripts/confignetwork-freebsd.awk"));
        $xCAT::Table::rows{nics}{node1} = {
            nictypes => 'vtnet0!ethernet,bridge0!bridge', nicdevices => 'bridge0!vtnet0',
            nicextraparams => 'bridge0!STP=no', nicsadapter => 'vtnet0!mac=52:54:00:12:34:56 linkstate=UP',
        };
        $xCAT::Table::networks[0]{mtu} = '9000';
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'the public producer accepts ordinary nics table fields');
        diag(explain($errors)) if @$errors;
        return if @$errors;
        my ($current, $content) = $published->();
        my ($description) = $content =~ /^bootstrap_network_base64=(.+)$/mx;
        require xCAT::FreeBSDNetwork;
        my $values = xCAT::FreeBSDNetwork::decode($description);
        is($values->{interface}, 'bridge0', 'the published address owner is the bridge');
        is($values->{NICMACS}, 'vtnet0!52:54:00:12:34:56', 'the physical MAC comes from nicsadapter');
        is($values->{mtu}, '9000', 'the existing network MTU reaches the installer');
        my $text = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
        my @chunks = $text =~ /^xcat_network_[0-9]+="([A-Za-z0-9+\/=]+)"$/mgx;
        is(join('', @chunks), $description, 'loader and downloaded configuration carry the same topology');
        $xCAT::Table::rows{nics}{node1}{nicsadapter} = '';
        ($boot, $errors) = install();
        like($errors->[0]{node}[0]{error}[0], qr/MAC|physical/x, 'missing adapter identity cannot prepare a new installation');
        is(($published->())[0]{generation}, $current->{generation}, 'rejected inventory preserves the prepared generation');
    };
    subtest 'real public command, immutable configuration and retry' => sub {
        $fresh->();
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'pkgbase mkinstall succeeds through the real resolver');
        diag(explain($errors)) if @$errors;
        return if @$errors;
        is($boot->{node1}[0]{kernel}, 'xcat/freebsd/node1/boot/pxeboot', 'native loader is published');
        my ($current, $content) = $published->();
        is($current->{phase}, 'prepared', 'pkgbase lifecycle is armed only after publication');
        like($content, qr/^format=xcat-freebsd-install-2$/mx, 'the published configuration uses the pkgbase contract');
        like($content, qr{^install_url=http://192\.0\.2\.1:80/install$}mx, 'the configured HTTP alias is retained');
        unlike($content, qr/^dist_url=/mx, 'pkgbase configuration contains no legacy distribution URL');
        my ($digest) = $content =~ /^package_plan_sha256=([0-9a-f]{64})$/mx;
        ok(defined($digest), 'configuration pins the published package plan');
        return unless defined($digest);
        my $path = "$root/install-files/freebsd15.1/x86_64/plans/$digest.plan";
        my $plan = xCAT::FreeBSDPackagePlan::inspect($path, $xCAT::TableUtils::installroot)->{plan};
        my $plan_bytes = read_file($path);
        like($plan_bytes, qr/\Aformat\txcat-freebsd-package-plan-1\n/x,
            'installation publishes the format accepted by the native decoder');
        ok(!exists($plan->{scope}), 'installation plan has no update scope');
        is_deeply([sort map { $_->{name} } @{$plan->{packages}}], [sort qw(
            FreeBSD-ssh FreeBSD-bsdconfig FreeBSD-set-minimal FreeBSD-kernel-generic pkg application)],
            'the published plan includes requested base and DVD roots plus required target tools');
        like($content, qr/^boot_media_sha256=\Q$media->{digest}\E$/mx, 'configuration binds imported boot media');
        my $runtime = read_file("$root/tftp/xcat/freebsd/node1/xcat/runtime.tsv");
        like($content, qr/^runtime_sha256=\Q@{[sha256_hex($runtime)]}\E$/mx, 'configuration binds the published runtime descriptor');
        my $loader_text = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
        like($loader_text, qr/\Q@{[sha256_hex($content)]}\E/x, 'the loader pins exact installer configuration bytes');
        ($boot, $errors) = install();
        is_deeply($errors, [], 'identical pkgbase retry succeeds');
        is(($published->())[0]{generation}, $current->{generation}, 'identical retry retains its generation');
        is(read_file($path), $plan_bytes, 'identical retry preserves immutable plan bytes');
        write_file("$root/base.pkglist", "base\nkernel\n");
        ($boot, $errors) = install();
        is_deeply($errors, [], 'changed base selection can prepare a new installation');
        return if @$errors;
        my ($next, $next_content) = $published->();
        isnt($next->{generation}, $current->{generation}, 'changed plan creates a new generation');
        unlike($next_content, qr/^package_plan_sha256=\Q$digest\E$/mx, 'changed selection changes the pinned plan');
        my $attempt_id = 'c' x 32;
        xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $next->{generation} $attempt_id begin\n",
            sub {}, directory => $state_directory);
        ($boot, $errors) = install();
        like($errors->[0]{node}[0]{error}[0], qr/active|already|installation/ix, 'active pkgbase installation cannot be rearmed');
        is(($published->())[1], $next_content, 'active installation keeps the original configuration');
        is_deeply(\@xCAT::Table::writes, [], 'planning and publication leave image database policy unchanged');
    };
    subtest 'an image without applications still publishes an installation plan' => sub {
        $fresh->();
        delete @{$xCAT::Table::rows{freebsdimage}{$image}}{qw(otherpkgdir otherpkglist)};
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'base-only image prepares through the public command');
        return if @$errors;
        ok(exists($boot->{node1}), 'base-only image receives native boot parameters');
        my ($current, $content) = $published->();
        is($current->{phase}, 'prepared', 'the base-only installation is armed');
        my ($digest) = $content =~ /^package_plan_sha256=([0-9a-f]{64})$/mx;
        ok(defined($digest), 'configuration pins the base-only plan');
        return unless defined($digest);
        my $path = "$root/install-files/freebsd15.1/x86_64/plans/$digest.plan";
        my $plan = xCAT::FreeBSDPackagePlan::inspect($path, $xCAT::TableUtils::installroot)->{plan};
        like(read_file($path), qr/\Aformat\txcat-freebsd-package-plan-1\n/x,
            'base-only roots do not select the update-only plan format');
        ok(!exists($plan->{scope}), 'base-only installation has no update scope');
        is_deeply($plan->{applications}, [], 'the plan has no application roots');
        is_deeply([sort map { $_->{name} } @{$plan->{packages}}], [sort qw(
            FreeBSD-ssh FreeBSD-bsdconfig FreeBSD-set-minimal FreeBSD-kernel-generic pkg)],
            'base-only plan retains the required installation tools');
        done_testing();
    };
    for my $contract (qw(xcat-freebsd-install-3 xcat-freebsd-install-4)) {
    subtest "enhanced boot settings reach the native loader and configuration with $contract" => sub {
        $fresh->($contract);
        $extra_cmdline = 'hint.example=install R::hint.example=target';
        $xCAT::Table::rows{nodehm}{node1} = { serialport => '0', serialspeed => '115200', serialflow => 'none' };
        write_file("$root/settings", "authorized_keys_file=$root/key.pub\nbootstrap=static\n");
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'enhanced public mkinstall succeeds with the real resolver');
        diag(explain($errors)) if @$errors;
        return if @$errors;
        my ($current, $content) = $published->();
        like($content, qr/^format=xcat-freebsd-install-3$/mx, 'published configuration names the declared contract');
        like($content, qr/^bootstrap=static$/mx, 'static bootstrap is bound to the generation');
        like($content, qr/^console_port=0$/mx, 'nodehm console policy enters the configuration');
        my $text = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
        like($text, qr/^hint\.example="install"$/mx, 'installation options reach the actual per-node loader');
        unlike($text, qr/^hint\.example="target"$/mx, 'R:: options stay out of installation boot');
        like($text, qr/^xcat_bootstrap_ipv4="192\.0\.2\.10"$/mx, 'loader has static bootstrap data before HTTP');
        like($text, qr/^hw\.uart\.console="io:0x3f8,br:115200"$/mx, 'loader uses the selected native console');
        like($text, qr/\Q@{[sha256_hex($content)]}\E/x, 'loader pins the enhanced configuration');
        ($boot, $errors) = install();
        is_deeply($errors, [], 'identical enhanced retry succeeds');
        is(($published->())[0]{generation}, $current->{generation}, 'identical enhanced retry keeps its generation');
        $extra_cmdline = 'hint.example=install R::hint.example=changed';
        ($boot, $errors) = install();
        is_deeply($errors, [], 'changed persistent option prepares a new generation');
        isnt(($published->())[0]{generation}, $current->{generation}, 'persistent options participate in lifecycle identity');
    };
    }
    subtest 'ordered multi-disk policy reaches public provisioning' => sub {
        $fresh->('xcat-freebsd-install-4');
        write_file("$root/node1.disk", "filesystem=zfs\nzfs_topology=raid10\n"
            . "zfs_vdevs=vtbd3\@D,vtbd1\@B;vtbd2\@C,vtbd0\@A\nswap_mode=none\n");
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'public mkinstall accepts a complete multi-disk runtime');
        diag(explain($errors)) if @$errors;
        return if @$errors;
        my ($current, $content) = $published->();
        like($content, qr/^format=xcat-freebsd-install-4$/mx, 'multi-disk configuration declares format4');
        like($content, qr/^zfs_vdevs=vtbd3\@D,vtbd1\@B;vtbd2\@C,vtbd0\@A$/mx, 'published configuration retains declared mirror groups');
        unlike($content, qr/^target_disk(?:_ident)?=/mx, 'multi-disk configuration has no legacy single-disk target');
        my $text = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
        like($text, qr/\Q@{[sha256_hex($content)]}\E/x, 'loader pins the actual multi-disk configuration');
        ($boot, $errors) = install();
        is_deeply($errors, [], 'identical multi-disk preparation is reusable');
        is(($published->())[0]{generation}, $current->{generation}, 'identical preparation retains its generation');
    };
    subtest 'public preparation freezes boot scripts before arming' => sub {
        $fresh->('xcat-freebsd-install-3', 'xcat-freebsd-postscripts-1');
        require xCAT::FreeBSDPostscript;
        require xCAT::Postage;
        local %XCATSITEVALS = (installdir => $xCAT::TableUtils::installroot,
            master => 'mn', sshbetweennodes => 'NOGROUPS', runbootscripts => 'yes');
        local %GLOBAL_TAB_HASH = ();
        local %GLOBAL_SN_HASH = ();
        local %GLOBAL_TABDUMP_HASH = ();
        local @exclude_nodes = ();
        $xCAT::TableUtils::site{installdir} = $xCAT::TableUtils::installroot;
        $xCAT::TableUtils::site{runbootscripts} = 'yes';
        $xCAT::Table::rows{$_} = {} for qw(linuximage nimimage);
        $xCAT::Table::rows{nodelist}{node1} = { node => 'node1', groups => 'compute' };
        $xCAT::Table::rows{postscripts} = {
            xcatdefaults => { node => 'xcatdefaults', postscripts => 'configure "two words"', postbootscripts => 'boot-script' },
            node1 => { node => 'node1', postscripts => 'node-script', postbootscripts => '' },
        };
        my $scripts = "$xCAT::TableUtils::installroot/postscripts";
        write_file("$scripts/mypostscript.tmpl", <<'BOOT_TEMPLATE');
#!/bin/sh
UPDATENODE=0
OSVER=#TABLE:nodetype:$NODE:os#
ARCH=#TABLE:nodetype:$NODE:arch#
PROFILE=#TABLE:nodetype:$NODE:profile#
PROVMETHOD=#TABLE:nodetype:$NODE:provmethod#
# postscripts-start-here
#INCLUDE_POSTSCRIPTS_LIST#
# postscripts-end-here
# postbootscripts-start-here
#INCLUDE_POSTBOOTSCRIPTS_LIST#
# postbootscripts-end-here
BOOT_TEMPLATE
        write_file("$scripts/$_", "#!/bin/sh\nprintf '%s\\n' original\n") for qw(configure node-script boot-script);
        my $prepare_boot = \&xCAT::FreeBSDPostscript::prepare_boot;
        my $boot_store = "$root/postscript-state";
        no warnings 'redefine';
        local *xCAT::FreeBSDPostscript::prepare_boot = sub { return $prepare_boot->(@_, directory => $boot_store); };
        my ($boot, $errors) = install();
        is_deeply($errors, [], 'public mkinstall prepares real boot selections and imported package plans');
        if (@$errors) {
            diag(explain($errors));
            find({ no_chdir => 1, wanted => sub {
                my $path = $File::Find::name;
                return unless $path =~ m{/(?:failure|stderr|setup|outcome[.]json|callbacks[.]jsonl)\z}x && -f $path && -s $path;
                diag("$path\n" . read_file($path));
            } }, $boot_store) if -d $boot_store;
        }
        return if @$errors;
        my ($armed, $content) = $published->();
        my $selections = $armed->{postscript_preparations};
        is(ref($selections), 'HASH', 'published generation retains its boot preparation binding');
        return unless ref($selections) eq 'HASH';
        my $first = xCAT::FreeBSDPostscript::compile_execution($selections->{firstboot}, directory => $boot_store);
        my $repeat = xCAT::FreeBSDPostscript::compile_execution($selections->{repeat}, directory => $boot_store);
        is_deeply([map { pack('H*', $_->{name}) } @{$first->{entries}}],
            [qw(configure node-script boot-script)], 'first boot preserves defaults and node ordering');
        is_deeply([map { pack('H*', $_->{name}) } @{$repeat->{entries}}], ['boot-script'], 'repeat selection omits postscripts');
        is($first->{manifest}{source_id}, $repeat->{manifest}{source_id}, 'public preparation shares one frozen source');
        ($boot, $errors) = install();
        is_deeply($errors, [], 'unchanged retry prepares successfully');
        is(($published->())[0]{generation}, $armed->{generation}, 'unchanged script bytes reuse their generation');
        write_file("$scripts/configure", "#!/bin/sh\nprintf '%s\\n' replacement\n");
        ($boot, $errors) = install();
        is_deeply($errors, [], 'changed script prepares a separate generation');
        my ($changed) = $published->();
        isnt($changed->{generation}, $armed->{generation}, 'script content changes the public installation generation');
        isnt($changed->{postscript_preparations}{firstboot}, $selections->{firstboot}, 'changed content is bound to the new preparation');
        is_deeply(xCAT::FreeBSDPostscript::compile_execution($selections->{firstboot}, directory => $boot_store),
            $first, 'previous generation retains its original driver');
        $xCAT::TableUtils::site{runbootscripts} = 'no';
        $XCATSITEVALS{runbootscripts} = 'no';
        ($boot, $errors) = install();
        is_deeply($errors, [], 'disabled repeat policy prepares successfully');
        my ($disabled) = $published->();
        isnt($disabled->{generation}, $changed->{generation}, 'repeat policy changes the public generation');
        is(xCAT::FreeBSDPostscript::compile_execution($disabled->{postscript_preparations}{repeat},
            directory => $boot_store)->{enabled}, 0, 'new generation cannot repeat scripts when disabled');
        $xCAT::Table::rows{noderes}{node1}{servicenode} = 'sn';
        my $metadata = {epoch => 'a' x 32, coordinator => '198.51.100.1', server => '192.0.2.1'};
        my $pool_install = sub {
            my $params = {};
            my @errors;
            xCAT_plugin::freebsd::process_request({command => ['mkinstall'], node => ['node1'],
                bootparams => \$params, _freebsd_pool => [encode_json({node1 => $metadata})]},
                sub { push @errors, shift; }, sub {
                    my $request = shift;
                    return {data => [encode_json({format => 'xcat-freebsd-pool-1', node => 'node1',
                        operation => $request->{arg}[0], result => {epoch => $metadata->{epoch}, phase => 'prepared'}})]};
                });
            return ($params, \@errors);
        };
        ($boot, $errors) = $pool_install->();
        is_deeply($errors, [], 'new pool epoch seals actual boot scripts');
        my ($pooled) = $published->();
        my $pool_driver = xCAT::FreeBSDPostscript::compile_execution(
            $pooled->{postscript_preparations}{firstboot}, directory => $boot_store);
        write_file("$scripts/configure", "#!/bin/sh\nprintf '%s\\n' next-epoch\n");
        ($boot, $errors) = $pool_install->();
        is_deeply($errors, [], 'server recovery reuses the existing sealed preparation');
        is_deeply(($published->())[0], $pooled, 'same epoch retains the registered generation and script binding');
        is_deeply(xCAT::FreeBSDPostscript::compile_execution(
            $pooled->{postscript_preparations}{firstboot}, directory => $boot_store),
            $pool_driver, 'server recovery cannot change the sealed script bytes');
        $metadata->{epoch} = 'b' x 32;
        ($boot, $errors) = $pool_install->();
        is_deeply($errors, [], 'new pool epoch prepares changed scripts');
        ($disabled) = $published->();
        isnt($disabled->{postscript_preparations}{firstboot}, $pooled->{postscript_preparations}{firstboot},
            'explicit pool preparation captures the changed scripts');
        delete $xCAT::Table::rows{noderes}{node1}{servicenode};
        my $published_loader = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
        write_file("$scripts/mypostscript.tmpl", 'invalid template');
        my $armed_count = $prepare_count;
        ($boot, $errors) = install();
        is(scalar(@$errors), 1, 'unusable template fails public preparation');
        ok(!exists($boot->{node1}), 'unusable template returns no launch parameters');
        is($prepare_count, $armed_count, 'unusable template cannot arm an installation');
        is_deeply(xCAT::FreeBSDInstall::state('node1', directory => $state_directory), $disabled,
            'unusable replacement preserves the previous protected state');
        is(read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf"), $published_loader,
            'unusable replacement preserves the previous loader');
    };
    my $reject = sub {
        my ($change, $pattern, $label) = @_;
        $fresh->();
        $change->();
        my ($boot, $errors) = install();
        is(scalar(@$errors), 1, "$label returns one node error");
        like($errors->[0]{node}[0]{error}[0], $pattern, "$label identifies its cause");
        ok(!exists($boot->{node1}), "$label removes stale boot parameters");
        is($prepare_count, 0, "$label cannot arm installation");
        ok(!-e $state_directory && !-e "$root/install-files/autoinst/freebsd/node1"
            && !-e "$root/tftp/xcat/freebsd/node1", "$label publishes no lifecycle or boot state");
        return;
    };
    subtest 'invalid package selections and policy fail before arming' => sub {
        for my $scope (qw(base applications)) {
            $reject->(sub {
                my $bad = dclone($policy);
                $bad->{scope} = $scope;
                write_file("$root/policy.json", $json->encode($bad));
            }, qr/Unknown[ ]FreeBSD[ ]import[ ]policy[ ]field/x, "policy injection of $scope scope");
        }
        $reject->(sub { $extra_cmdline = 'hint.example=install' },
            qr/require.*runtime/x, 'old pkgbase runtime with enhanced boot options');
        $reject->(sub { write_file("$root/settings", "authorized_keys_file=$root/key.pub\nbootstrap=static\n") },
            qr/require.*runtime/x, 'old pkgbase runtime with static bootstrap');
        $reject->(sub { write_file("$root/apps.pkglist", "missing-application\n") },
            qr/missing|absent|application/ix, 'missing application');
        $reject->(sub {
            my $bad = dclone($policy);
            $bad->{solver}{sha256} = '0' x 64;
            write_file("$root/policy.json", $json->encode($bad));
        }, qr/checksum|digest|sha256/ix, 'changed solver identity');
        $reject->(sub {
            chmod(oct('0644'), "$media->{bootdir}/xcat/runtime.tsv") or croak $!;
            write_file("$media->{bootdir}/xcat/runtime.tsv", "invalid\n");
        }, qr/checksum|runtime/ix, 'changed boot runtime');
    };
    subtest 'changed package-list bytes cannot bind a prepared generation' => sub {
        $fresh->();
        my $run = \&xCAT::FreeBSDPkg::run_command;
        my $changed = 0;
        my ($boot, $errors);
        {
            no warnings 'redefine';
            local *xCAT::FreeBSDPkg::run_command = sub {
                my ($argv, @options) = @_;
                my $result = $run->($argv, @options);
                if ($argv->[0] eq $solver->{path} && grep { $_ eq 'resolve' } @$argv) {
                    write_file("$root/apps.pkglist", "# changed while resolving\napplication\n");
                    ++$changed;
                }
                return $result;
            };
            ($boot, $errors) = install();
        }
        is($changed, 1, 'the actual native solver completed before the package list changed');
        like($errors->[0]{node}[0]{error}[0], qr/request[ ]changed[ ]during[ ]resolution/x,
            'equal package roots do not conceal changed request bytes');
        is($prepare_count, 0, 'changed request never arms installation');
        ok(!exists($boot->{node1}) && !-e $state_directory, 'changed request leaves no boot parameters or lifecycle state');
    };
    ok(!-e "$native/package-script-executed", 'planning never executes package installation scripts');
    ok(!-e '/var/db/pkg' && !-l '/var/db/pkg', 'planning leaves the default package database absent');
    is(xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest}, $source_digest, 'native source fixture is unchanged');
};

rejection(sub {$xCAT::Table::rows{iscsi}{node1} = {server => 'san', target => 'iqn.test'}}, qr/iSCSI/, 'SAN conflict');
rejection(sub {$extra_cmdline = 'console=ttyS0'}, qr/Reserved boot option/, 'reserved extra kernel arguments');
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
        my $announced = 0;
        my $announce = sub {
            return if $announced++;
            print {$second_ready_writer} "preparing\n" or die $!;
            close($second_ready_writer);
        };
        local *xCAT::FreeBSDInstall::state = sub {
            $announce->();
            return $read_state->(@_, directory => $state_directory);
        };
        local *xCAT::FreeBSDInstall::prepare = sub {
            $announce->();
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
for my $acknowledged (0, 1) {
    fixture();
    my (undef, $previous_errors) = install();
    is_deeply($previous_errors, [], 'an existing preparation is available before pool registration');
    my $before = read_file("$state_directory/node1.json");
    my $previous_loader = read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf");
    $xCAT::Table::rows{noderes}{node1}{servicenode} = 'sn';
    my $metadata = {epoch => 'a' x 32, coordinator => '198.51.100.1', server => '192.0.2.1'};
    my $pool_params = {node1 => [{kernel => 'stale'}]};
    my (@responses, @registrations);
    xCAT_plugin::freebsd::process_request({command => ['mkinstall'], node => ['node1'],
        bootparams => \$pool_params, _freebsd_pool => [JSON->new->encode({node1 => $metadata})]},
        sub { push @responses, shift; }, sub {
            my $request = shift;
            return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
                operation => 'inspect', result => {epoch => $metadata->{epoch}, phase => 'prepared'}})]}
                if $request->{arg}[0] eq 'inspect';
            push @registrations, $request;
            is(read_file("$state_directory/node1.json"), $before, 'registration precedes local state replacement');
            is(read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf"), $previous_loader,
                'registration precedes boot publication');
            return {} unless $acknowledged;
            return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
                operation => 'register', result => {epoch => $metadata->{epoch}, phase => 'prepared'}})]};
        });
    is(scalar(@registrations), 1, 'prepared server registers one local generation') or next;
    my $registration = JSON->new->decode($registrations[0]{arg}[1]);
    my $retained = xCAT::FreeBSDInstall::state('node1', directory => $state_directory);
    is($registration->{master}, '192.0.2.1', 'registration names the node-facing server');
    if ($acknowledged) {
        is($registration->{generation}, $retained->{generation}, 'registration identifies the durable local generation');
        is_deeply($retained->{service_pool}, $metadata, 'local state binds callbacks to the coordinator epoch');
        is_deeply(\@responses, [], 'acknowledged pool preparation succeeds');
        ok(exists($pool_params->{node1}), 'acknowledged generation supplies native boot parameters');
    } else {
        ok(@responses, 'missing registration acknowledgement is reported');
        ok(!exists($pool_params->{node1}), 'unregistered generation supplies no boot parameters');
        is(read_file("$state_directory/node1.json"), $before, 'rejected registration preserves local state');
        is(read_file("$root/tftp/xcat/freebsd/node1/boot/loader.conf"), $previous_loader,
            'rejected registration preserves the working boot entry');
    }
}
done_testing();
