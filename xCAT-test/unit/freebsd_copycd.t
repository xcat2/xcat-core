#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Compress::Gzip qw(gzip);
use JSON;
use Storable qw(dclone);
use Test::More;

our ($mock_system, $mock_readpipe);
BEGIN {
    $INC{'xCAT/Table.pm'} = 1;
    $INC{'xCAT/TableUtils.pm'} = 1;
    *CORE::GLOBAL::system = sub {
        return $mock_system->(@_) if $mock_system;
        return CORE::system(@_);
    };
    *CORE::GLOBAL::readpipe = sub {
        return $mock_readpipe->(@_) if $mock_readpipe;
        return CORE::readpipe($_[0]);
    };
}

{
    package xCAT::Table;
    our (%rows, %faults, @operations, $on_write);
    sub fault {
        my ($operation, $table) = @_;
        push @operations, [$operation, $table];
        return delete $faults{"$operation/$table"};
    }
    sub new {
        my ($class, $table, %options) = @_;
        return undef if fault('open', $table);
        die 'Registration must use autocommit' unless $options{-autocommit};
        return bless { table => $table }, $class;
    }
    sub getAllEntries {
        my ($self, $all) = @_;
        die 'Disabled entries must be visible' unless $all;
        return undef if fault('read', $self->{table});
        return Storable::dclone([values %{ $rows{$self->{table}} || {} }]);
    }
    sub setAttribs {
        my ($self, $key, $values) = @_;
        my $table = $self->{table};
        my ($name) = values %$key;
        my $fault = fault('write', $table) || '';
        $on_write->($table) if $on_write;
        die "injected write exception\n" if $fault eq 'die';
        return (undef, 'injected write failure') if $fault eq 'error';
        return 0 if $fault eq 'silent';
        $rows{$table}{$name} = { %$key, %$values };
        die "injected post-write exception\n" if $fault eq 'after';
        return 0;
    }
    sub delEntries {
        my ($self, $key) = @_;
        my ($name) = values %$key;
        return if fault('delete', $self->{table});
        delete $rows{$self->{table}}{$name};
        return;
    }
    sub close { return; }
}

{
    package xCAT::TableUtils;
    our $installroot;
    sub getInstallDir { return $installroot; }
}

my $plugin = $ENV{XCAT_FREEBSD_PLUGIN}
  || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsd.pm";
require $plugin;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;

sub write_file {
    my ($path, $data) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or die "$path: $!";
    binmode($fh);
    print $fh $data;
    close($fh) or die "$path: $!";
}

sub fixture {
    my $format = shift || 'xcat-mfsbsd-1';
    my $root = "$tmp/media-" . ++$sequence;
    my $efi = "\0" x 512;
    substr($efi, 0, 2) = 'MZ';
    substr($efi, 60, 4) = pack('V', 128);
    substr($efi, 128, 4) = "PE\0\0";
    substr($efi, 132, 2) = pack('v', 0x8664);
    substr($efi, 152, 2) = pack('v', 0x20b);
    substr($efi, 220, 2) = pack('v', 10);
    my $elf = "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62);
    my ($kernel, $mfsroot);
    gzip(\$elf => \$kernel) or die $IO::Compress::Gzip::GzipError;
    my $ramdisk = 'installer fixture';
    gzip(\$ramdisk => \$mfsroot) or die $IO::Compress::Gzip::GzipError;
    my %payload = (
        'boot/pxeboot' => 'BIOS loader', 'boot/loader.efi' => $efi,
        'boot/loader.conf' => "mfs_name=\"/mfsroot\"\n",
        'boot/defaults/loader.conf' => 'loader defaults',
        'boot/lua/loader.lua' => 'loader entry',
        'boot/kernel/kernel.gz' => $kernel, 'mfsroot.gz' => $mfsroot,
        'usr/freebsd-dist/base.txz' => 'base set',
        'usr/freebsd-dist/kernel.txz' => 'kernel set',
    );
    $payload{'usr/freebsd-dist/MANIFEST'} = join('', map {
        "$_\t" . sha256_hex($payload{"usr/freebsd-dist/$_"}) . "\t1\tbase\tfixture\ton\n";
    } qw(base.txz kernel.txz));
    if ($format eq 'xcat-mfsbsd-2') {
        delete @payload{map { "usr/freebsd-dist/$_" } qw(MANIFEST base.txz kernel.txz)};
        $payload{'xcat/runtime.tsv'} = "format\txcat-freebsd-runtime-2\n"
          . "target\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000\n"
          . "pkg-version\t2.6.2\nbsdinstall-contract\txcat-freebsd-pkgbase-1\n"
          . join('', map { "file\t$_\t" . sha256_hex("runtime $_") . "\n" } sort qw(
              usr/local/sbin/xcat-install usr/local/libexec/xcat-install-lib.sh
              usr/local/share/xcat/installerconfig.tmpl usr/sbin/bsdinstall
              usr/libexec/bsdinstall/script usr/libexec/bsdinstall/pkgbase
              usr/libexec/bsdinstall/umount usr/libexec/flua usr/local/sbin/pkg-static
          ));
    }
    write_file("$root/$_", $payload{$_}) for keys %payload;
    my $manifest = JSON->new->canonical->encode({
        format => $format, release => '15.1-RELEASE', arch => 'amd64',
        ($format eq 'xcat-mfsbsd-2' ? (mfsbsd_commit => 'a' x 40) : ()),
        files => { map { $_ => sha256_hex($payload{$_}) } keys %payload },
    });
    write_file("$root/xcat/mfsbsd.json", $manifest);
    return ($root, sha256_hex($manifest));
}

sub fresh {
    %xCAT::Table::rows = ();
    %xCAT::Table::faults = ();
    @xCAT::Table::operations = ();
    $xCAT::Table::on_write = undef;
    $xCAT::TableUtils::installroot = "$tmp/install-" . ++$sequence;
    make_path($xCAT::TableUtils::installroot);
    return;
}

sub run_copy {
    my ($source, @args) = @_;
    my $request = { command => ['copycd'], arg => ['-m', $source, @args] };
    my @responses;
    xCAT_plugin::freebsd::process_request($request,
        sub { push @responses, dclone($_[0]); }, sub { die 'Unexpected subrequest'; });
    return ($request, \@responses);
}

sub errors {
    my $responses = shift;
    return join('', map { @{ $_->{error} || [] } } @$responses);
}

sub writes {
    return grep { $_->[0] eq 'write' } @xCAT::Table::operations;
}

sub row_count {
    my $count = 0;
    $count += keys %{ $xCAT::Table::rows{$_} } for keys %xCAT::Table::rows;
    return $count;
}

my ($source, $digest) = fixture();
my $suffix = substr($digest, 0, 12);
my $image = "freebsd15.1-x86_64-install-compute-$suffix";
my $distro = "freebsd15.1-x86_64-$suffix";
sub destination { return "$xCAT::TableUtils::installroot/freebsd15.1/x86_64/$digest"; }

is(xCAT_plugin::freebsd::handled_commands()->{copycd}, 'freebsd', 'plugin registers the media dispatch command');

subtest 'unrelated media and commands are not claimed' => sub {
    fresh();
    my ($request, $responses) = run_copy($tmp, '-n', 'rhels9');
    is($request->{command}[0], 'copycd', 'unrelated request remains available');
    is_deeply($responses, [], 'unrelated media produces no response');
    is(scalar(writes()), 0, 'unrelated media produces no database writes');
    my $other = { command => ['other'], arg => [] };
    xCAT_plugin::freebsd::process_request($other, sub { die 'Unexpected response'; });
    is_deeply($other, { command => ['other'], arg => [] }, 'unhandled command remains unchanged');
};

subtest 'inspection validates without staging or registration' => sub {
    fresh();
    my ($request, $responses) = run_copy($source, '-i', '-f', '/media/installer.iso');
    is_deeply($request, {}, 'identified media is claimed');
    is(errors($responses), '', 'inspection succeeds');
    like($responses->[0]{info}[0], qr/DISTNAME:freebsd15\.1\nARCH:x86_64\nDIGEST:$digest/, 'inspection reports canonical identity');
    ok(!-e "$xCAT::TableUtils::installroot/freebsd15.1", 'inspection creates no media directory');
    is_deeply(\@xCAT::Table::operations, [], 'inspection does not open image tables');
};

subtest 'default import publishes a FreeBSD image after its dependencies' => sub {
    fresh();
    my ($request, $responses) = run_copy($source, '-f', '/media/installer.iso');
    is(errors($responses), '', 'import succeeds');
    is_deeply($request, {}, 'successful import is claimed');
    ok(-f destination() . '/boot/loader.efi', 'real importer stages the UEFI loader');
    ok(-f destination() . '/usr/freebsd-dist/base.txz', 'real importer stages distribution sets');
    is_deeply($xCAT::Table::rows{osdistro}{$distro}, {
        osdistroname => $distro, basename => 'freebsd', majorversion => '15',
        minorversion => '1', arch => 'x86_64', type => 'FreeBSD', dirpaths => destination(),
    }, 'distribution is registered as FreeBSD');
    is_deeply($xCAT::Table::rows{freebsdimage}{$image}, {
        imagename => $image, pkgdir => destination(),
    }, 'FreeBSD image has no implicit template or disk target');
    is_deeply($xCAT::Table::rows{osimage}{$image}, {
        imagename => $image, imagetype => 'freebsd', osname => 'FreeBSD',
        osvers => 'freebsd15.1', osarch => 'x86_64', provmethod => 'install',
        profile => 'compute', osdistroname => $distro,
    }, 'generic image uses the FreeBSD schema');
    is_deeply([map { $_->[1] } writes()], [qw(osdistro freebsdimage osimage)], 'image visibility follows dependency registration');
    ok(!exists($xCAT::Table::rows{linuximage}), 'Linux image table is untouched');
    like(join('', map { @{ $_->{data} || [] } } @$responses), qr/\Q$image\E/, 'response identifies the registered image');
};

subtest 'noosimage and subsequent normal import' => sub {
    fresh();
    my (undef, $responses) = run_copy($source, '-o');
    is(errors($responses), '', 'noosimage import succeeds');
    is_deeply([map { $_->[1] } writes()], ['osdistro'], 'noosimage writes only the distribution');
    ok(-f destination() . '/mfsroot.gz', 'noosimage still imports the installer');
    (undef, $responses) = run_copy($source);
    is(errors($responses), '', 'normal import completes the missing image definitions');
    is(row_count(), 3, 'three definitions exist after completing registration');
};

subtest 'reimport preserves administrator policy' => sub {
    fresh();
    run_copy($source);
    $xCAT::Table::rows{freebsdimage}{$image}{template} = '/install/custom/settings';
    $xCAT::Table::rows{freebsdimage}{$image}{partitionfile} = '/install/custom/disks';
    $xCAT::Table::rows{osimage}{$image}{profile} = 'storage';
    $xCAT::Table::rows{osimage}{$image}{comments} = 'site policy';
    my $before = dclone(\%xCAT::Table::rows);
    @xCAT::Table::operations = ();
    my (undef, $responses) = run_copy($source);
    is(errors($responses), '', 'reimport succeeds');
    is_deeply(\%xCAT::Table::rows, $before, 'all existing values remain unchanged');
    is(scalar(writes()), 0, 'reimport performs no database writes');
    (undef, $responses) = run_copy($source, '-w');
    like(errors($responses), qr/destination already exists/, 'nonoverwrite rejects the existing generation');
    is_deeply(\%xCAT::Table::rows, $before, 'nonoverwrite leaves policy unchanged');
};

for my $option (['-n', 'freebsd15.1'], ['-a', 'x86_64'], ['-p', '/install/custom'], ['-s'], ['--unknown'], ['extra']) {
    subtest "unsupported arguments @$option" => sub {
        fresh();
        my ($request, $responses) = run_copy($source, @$option);
        is_deeply($request, {}, 'identified media remains claimed on error');
        ok(length(errors($responses)), 'invalid option produces an error');
        is_deeply($responses->[-1]{errorcode}, [1], 'error has a failing return code');
        is(scalar(writes()), 0, 'invalid option causes no database writes');
        ok(!-e destination(), 'invalid option causes no media publication');
    };
}

for my $case (['xcat/mfsbsd.json', '{broken', qr/JSON/], ['usr/freebsd-dist/base.txz', 'corrupt', qr/SHA256 mismatch/]) {
    subtest "invalid media $case->[0]" => sub {
        fresh();
        my ($bad) = fixture();
        write_file("$bad/$case->[0]", $case->[1]);
        my ($request, $responses) = run_copy($bad);
        is_deeply($request, {}, 'invalid FreeBSD media is claimed');
        like(errors($responses), $case->[2], 'validation error reaches the caller');
        is(scalar(writes()), 0, 'invalid media is not registered');
    };
}

for my $table (qw(osdistro freebsdimage osimage)) {
    for my $kind (qw(error silent die after)) {
        subtest "$table $kind write failure" => sub {
            fresh();
            $xCAT::Table::faults{"write/$table"} = $kind;
            my (undef, $responses) = run_copy($source);
            ok(length(errors($responses)), 'write failure reaches the caller');
            is(row_count(), 0, 'new rows are removed after failure');
            like(errors($responses), qr/Imported media retained/, 'retained media is reported');
            ok(-f destination() . '/mfsroot.gz', 'validated media remains available for retry');
            (undef, $responses) = run_copy($source);
            is(errors($responses), '', 'retry completes registration');
            is(row_count(), 3, 'retry produces one complete image');
        };
    }
    for my $operation (qw(open read)) {
        subtest "$table preflight $operation failure" => sub {
            fresh();
            $xCAT::Table::faults{"$operation/$table"} = 1;
            my (undef, $responses) = run_copy($source);
            like(errors($responses), qr/Cannot (?:open|read) $table/, 'preflight failure reaches the caller');
            is(scalar(writes()), 0, 'all rows are preflighted before any write');
            is(row_count(), 0, 'failed preflight creates no definitions');
        };
    }
}

subtest 'partial image retry does not roll back pre-existing distribution' => sub {
    fresh();
    run_copy($source, '-o');
    my $before = dclone(\%xCAT::Table::rows);
    $xCAT::Table::faults{'write/osimage'} = 'error';
    my (undef, $responses) = run_copy($source);
    ok(length(errors($responses)), 'later image registration fails');
    is_deeply($xCAT::Table::rows{osdistro}, $before->{osdistro}, 'pre-existing distribution remains unchanged');
    is(row_count(), 1, 'only the pre-existing definition remains');
};

for my $collision_table (qw(osdistro freebsdimage osimage)) {
    subtest "$collision_table disabled and conflicting entries" => sub {
        fresh();
        run_copy($source);
        my $name = $collision_table eq 'osdistro' ? $distro : $image;
        $xCAT::Table::rows{$collision_table}{$name}{disable} = 'yes';
        my $before = dclone(\%xCAT::Table::rows);
        @xCAT::Table::operations = ();
        my (undef, $responses) = run_copy($source);
        like(errors($responses), qr/is disabled/, 'disabled definition is not treated as absent');
        is_deeply(\%xCAT::Table::rows, $before, 'disabled state is preserved');
        is(scalar(writes()), 0, 'disabled collision causes no writes');
        delete $xCAT::Table::rows{$collision_table}{$name}{disable};
        my $attribute = $collision_table eq 'osdistro' ? 'dirpaths' : $collision_table eq 'freebsdimage' ? 'pkgdir' : 'imagetype';
        $xCAT::Table::rows{$collision_table}{$name}{$attribute} = 'different';
        $before = dclone(\%xCAT::Table::rows);
        (undef, $responses) = run_copy($source);
        like(errors($responses), qr/does not match/, 'identity collision is rejected');
        is_deeply(\%xCAT::Table::rows, $before, 'conflicting definition is preserved');
    };
}

subtest 'cleanup failure is reported and does not stop later cleanup' => sub {
    fresh();
    $xCAT::Table::faults{'write/osimage'} = 'error';
    $xCAT::Table::faults{'delete/freebsdimage'} = 1;
    my (undef, $responses) = run_copy($source);
    like(errors($responses), qr/Cleanup failed for freebsdimage/, 'failed compensation is explicit');
    ok(exists($xCAT::Table::rows{freebsdimage}{$image}), 'undeleted row remains visible for recovery');
    ok(!exists($xCAT::Table::rows{osdistro}{$distro}), 'other cleanup still runs');
    ok(!exists($xCAT::Table::rows{osimage}{$image}), 'failed image is not published');
};

subtest 'cleanup preserves an entry changed by another writer' => sub {
    fresh();
    $xCAT::Table::faults{'write/osimage'} = 'error';
    $xCAT::Table::on_write = sub {
        return unless $_[0] eq 'osimage';
        $xCAT::Table::rows{freebsdimage}{$image}{comments} = 'concurrent policy';
    };
    my (undef, $responses) = run_copy($source);
    like(errors($responses), qr/entry changed during registration/, 'changed entry prevents destructive compensation');
    is($xCAT::Table::rows{freebsdimage}{$image}{comments}, 'concurrent policy', 'other writer data is preserved');
};

subtest 'registration rejects a symlink lock without database writes' => sub {
    fresh();
    xCAT::FreeBSDImage::import_media($source, $xCAT::TableUtils::installroot);
    symlink("$tmp/lock-target", dirname(destination()) . '/.mfsbsd-register.lock') or die $!;
    my (undef, $responses) = run_copy($source);
    like(errors($responses), qr/Cannot open media registration lock/, 'symlink lock is rejected');
    is(scalar(writes()), 0, 'unsafe lock causes no database writes');
    ok(!-e "$tmp/lock-target", 'lock target is not created');
};

sub boot_only_copycd {
    fresh();
    run_copy($source);
    my $before = dclone(\%xCAT::Table::rows);
    my ($boot_source, $boot_digest) = fixture('xcat-mfsbsd-2');
    my $bootdir = "$xCAT::TableUtils::installroot/freebsd15.1/x86_64/boot/$boot_digest";
    @xCAT::Table::operations = ();
    my ($request, $responses) = run_copy($boot_source, '-i');
    is_deeply($request, {}, 'boot-only inspection claims its bundle');
    is(errors($responses), '', 'boot-only inspection succeeds');
    like($responses->[0]{info}[0], qr/DISTNAME:freebsd15\.1\nARCH:x86_64\nDIGEST:$boot_digest/x,
        'inspection reports the boot bundle identity');
    ok(!-e $bootdir, 'inspection does not publish boot media');
    is_deeply(\@xCAT::Table::operations, [], 'inspection does not open image tables');
    for my $args ([], ['-o']) {
        @xCAT::Table::operations = ();
        ($request, $responses) = run_copy($boot_source, @$args);
        is_deeply($request, {}, 'boot-only import claims its bundle');
        is(errors($responses), '', 'boot-only import succeeds with or without noosimage');
        ok(-f "$bootdir/boot/loader.efi" && -f "$bootdir/xcat/runtime.tsv", 'the real importer publishes the boot payload and descriptor');
        ok(!-e "$bootdir/usr", 'the imported boot tree has no distribution payload');
        like(join('', map { @{$_->{data} || []} } @$responses), qr/\Q$bootdir\E/x,
            'the response identifies the boot directory');
        unlike(join('', map { @{$_->{data} || []} } @$responses), qr/Created|osimage/x,
            'the response does not claim image registration');
        is_deeply(\@xCAT::Table::operations, [], 'boot-only import never opens registration tables');
        is_deeply(\%xCAT::Table::rows, $before, 'existing legacy definitions remain unchanged');
    }
    (undef, $responses) = run_copy($boot_source, '-w');
    like(errors($responses), qr/already[ ]exists/x, 'boot-only nonoverwrite rejects an existing bundle');
    is_deeply(\@xCAT::Table::operations, [], 'nonoverwrite does not open registration tables');
    is_deeply(\%xCAT::Table::rows, $before, 'nonoverwrite retains all prior definitions');
    return;
}

subtest 'boot-only copycd never registers or changes image definitions' => \&boot_only_copycd;

subtest 'an invalid boot-only marker never falls through to native release import' => sub {
    fresh();
    my ($boot_source) = fixture('xcat-mfsbsd-2');
    write_file("$boot_source/bin/freebsd-version", '15.1-RELEASE');
    write_file("$boot_source/xcat/mfsbsd.json", '{broken');
    my ($request, $responses) = run_copy($boot_source);
    is_deeply($request, {}, 'the invalid marker still claims the bundle');
    like(errors($responses), qr/JSON/x, 'the marker failure crosses the public callback');
    is_deeply($responses->[-1]{errorcode}, [1], 'the callback returns failure');
    is_deeply(\@xCAT::Table::operations, [], 'native repository policy and image tables are not opened');
    ok(!-e "$xCAT::TableUtils::installroot/freebsd15.1", 'no native or boot import is published');
};

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/copycds.pm";
for my $dispatch_case (['import'], ['inspection', '-i'], ['noosimage', '-o'], ['failure'],
    ['boot import'], ['boot inspection', '-i'], ['boot noosimage', '-o'], ['boot failure']) {
    subtest "copycds dispatch $dispatch_case->[0]" => sub {
        fresh();
        my $boot_only = $dispatch_case->[0] =~ /\Aboot[ ]/x;
        my ($mounted) = fixture($boot_only ? 'xcat-mfsbsd-2' : 'xcat-mfsbsd-1');
        write_file("$mounted/boot/pxeboot", 'corrupt') if $dispatch_case->[0] =~ /failure\z/x;
        my $iso = "$tmp/install.iso";
        write_file($iso, 'ISO fixture');
        my (@commands, @responses, @dispatched);
        local $mock_system = sub { push @commands, join(' ', @_); return 0; };
        local $mock_readpipe = sub { return "$iso: ISO 9660 CD-ROM filesystem data\n"; };
        local @ARGV;
        xCAT_plugin::copycds::process_request({
            command => ['copycds'], arg => [@$dispatch_case[1 .. $#$dispatch_case], $iso], cwd => [$tmp],
        }, sub { push @responses, dclone($_[0]); }, sub {
            my ($request, $callback) = @_;
            push @dispatched, dclone($request);
            $request->{arg}[1] = $mounted;
            xCAT_plugin::freebsd::process_request($request, $callback);
        });
        is(scalar(@dispatched), 1, 'copycds dispatches exactly one subrequest');
        is($dispatched[0]{command}[0], 'copycd', 'ISO uses the established copycd path');
        like($commands[2], qr/mount -t udf,iso9660 -o ro,loop/, 'ISO is requested as a read-only mount');
        like($commands[-2], qr/^umount /, 'outer wrapper requests unmount after completion');
        like($commands[-1], qr/^rm -rf /, 'outer wrapper removes its mountpoint');
        unlike(errors(\@responses), qr/could not identify/, 'callback identifies the FreeBSD handler');
        if ($dispatch_case->[0] =~ /failure\z/x) {
            like(errors(\@responses), qr/SHA256 mismatch/, 'validation error crosses both callback boundaries');
        } else {
            is(errors(\@responses), '', 'outer request succeeds');
        }
        my $expected = $dispatch_case->[0] eq 'import' ? 3 : $dispatch_case->[0] eq 'noosimage' ? 1 : 0;
        is(row_count(), $expected, 'forwarded option controls database registration');
        is_deeply(\@xCAT::Table::operations, [], 'the boot-only wrapper never opens image tables') if $boot_only;
    };
}

done_testing();
