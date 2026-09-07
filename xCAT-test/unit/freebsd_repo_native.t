#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use Symbol qw(gensym);
use Test::More;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
my $tmp = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
    $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
    $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
    $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
}

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    return defined($bytes) ? $bytes : '';
}

sub write_file {
    my ($path, $bytes) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub command {
    my @argv = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@argv, cwd => $tmp, environment => \%environment,
        timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub run_pkg {
    my @arguments = @_;
    return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments);
}

sub rejects {
    my ($action, $pattern, $description) = @_;
    my $ok = eval { $action->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    like($error, $pattern, "$description diagnostic");
    return;
}

sub new_directory {
    my $path = "$tmp/tree-" . ++$sequence;
    make_path($path);
    return $path;
}

sub create_package {
    my ($directory, $name, %options) = @_;
    my $manifest = { name => $name, version => '1', origin => "misc/$name",
        comment => 'Repository inspection fixture', desc => 'Repository inspection fixture',
        maintainer => 'root@example.invalid', www => 'https://example.invalid', prefix => '/usr/local',
        abi => 'FreeBSD:15:amd64', arch => 'freebsd:15:x86:64', flatsize => 0,
        licenselogic => 'single', licenses => ['BSD2CLAUSE'], annotations => { FreeBSD_version => '1500068' },
        scripts => { 'post-install' => "touch '$tmp/package-script-executed'" }, %options };
    my $input = "$tmp/manifest-" . ++$sequence;
    write_file($input, $json->encode($manifest));
    make_path($directory);
    run_pkg('create', '-M', $input, '-r', "$tmp/empty", '-o', $directory);
    return "$directory/$name-$manifest->{version}.pkg";
}

sub repository {
    my ($signed, $definitions) = @_;
    my $root = new_directory();
    for my $definition (@$definitions) {
        create_package("$root/All", @$definition);
    }
    run_pkg('repo', $root, $signed ? ("rsa:$tmp/repo.key") : ());
    return $root;
}

sub clone_tree {
    my $source = shift;
    my $root = new_directory();
    command('/usr/bin/cp', '-a', "$source/.", $root);
    return $root;
}

sub inspect {
    my ($root, %options) = @_;
    return xCAT::FreeBSDRepo::inspect_repository($root, tool => $tool,
        trust => { type => 'operator-trusted-tree', digest => xCAT::FreeBSDRepo::snapshot_tree($root)->{digest} },
        %options);
}

sub catalogue_data {
    my $root = shift;
    return $json->decode(command('/usr/bin/tar', '-xOf', "$root/data.pkg", 'data'));
}

sub write_catalogues {
    my ($root, $data, $fallback) = @_;
    my $stage = new_directory();
    write_file("$stage/data", $json->encode($data));
    $fallback = $data->{packages} unless defined($fallback);
    write_file("$stage/packagesite.yaml", join('', map { $json->encode($_) . "\n" } @$fallback));
    for my $pair (['data', 'data'], ['packagesite', 'packagesite.yaml']) {
        command('/usr/bin/tar', '--zstd', '-cf', "$root/$pair->[0].pkg", '-C', $stage, $pair->[1]);
    }
    return;
}

sub pubkey {
    my $name = shift;
    return { type => 'pubkey', path => "$tmp/$name.pub", sha256 => sha256_hex(read_file("$tmp/$name.pub")) };
}

make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
$tool->{sha256} = sha256_hex(read_file($tool->{path}));
is(run_pkg('-v'), "2.8.2\n", 'fixtures use the pinned native pkg version');
for my $name (qw(repo wrong)) {
    command('/usr/bin/openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', "$tmp/$name.key");
    chmod(oct('0600'), "$tmp/$name.key") or croak $!;
    command('/usr/bin/openssl', 'pkey', '-in', "$tmp/$name.key", '-pubout', '-out', "$tmp/$name.pub");
}
my @definitions = (['test-dep'], ['test-app', deps => { 'test-dep' => { origin => 'misc/test-dep', version => '1' } }]);
my $signed = repository(1, \@definitions);
my $unsigned = repository(0, \@definitions);

sub success_cases {
    my $before = xCAT::FreeBSDRepo::snapshot_tree($signed);
    local $ENV{PKG_DBDIR} = "$tmp/forbidden-db";
    local $ENV{REPOS_DIR} = "$tmp/forbidden-repos";
    local $ENV{LD_PRELOAD} = '/must/not/load.so';
    my $result = inspect($signed, trust => pubkey('repo'));
    is($result->{format}, 'xcat-freebsd-repository-1', 'native repository result has a versioned format');
    is($result->{native_validated}, 1, 'both signed catalogues and their archives validate');
    is($result->{selection_validated}, 0, 'repository validation does not claim dependency selection');
    is(scalar(keys %{$result->{packages}}), 2, 'all native package identities are retained');
    is(scalar(keys %{$result->{archives}}), 2, 'every package has a validated archive');
    is($result->{tree}{native_validated}, 0, 'source snapshot alone remains unvalidated');
    is_deeply($result->{trust}, { type => 'pubkey', sha256 => pubkey('repo')->{sha256} }, 'trust descriptor excludes host paths');
    is_deeply($result->{tree}, $before, 'native inspection preserves source bytes and links');
    is(inspect($signed, trust => pubkey('repo'))->{digest}, $result->{digest}, 'repeat inspection is deterministic');
    my ($app) = grep { $_->{name} eq 'test-app' } values %{$result->{packages}};
    is_deeply($app->{deps}, { 'test-dep' => { origin => 'misc/test-dep', version => '1' } }, 'complete original dependency metadata is retained');
    is(inspect($unsigned)->{native_validated}, 1, 'unsigned repository requires and accepts an explicit pinned-tree policy');
    ok(!-e "$tmp/forbidden-db" && !-e "$tmp/forbidden-repos", 'inherited package paths are not used');
    ok(!-e "$tmp/package-script-executed", 'archive inspection does not execute package scripts');
    my $aliases = clone_tree($unsigned);
    make_path("$aliases/Latest");
    symlink('../All/test-app-1.pkg', "$aliases/Latest/test-app.pkg") or croak $!;
    symlink('All', "$aliases/alias:15") or croak $!;
    is(scalar(keys %{inspect($aliases)->{archives}}), 2, 'valid archive and directory aliases do not duplicate packages');
    my $nested = new_directory();
    command('/usr/bin/cp', '-a', $unsigned, "$nested/FreeBSD:15:amd64");
    symlink('FreeBSD:15:amd64', "$nested/freebsd:15:x86:64") or croak $!;
    is(inspect($nested, catalogue_prefix => 'FreeBSD:15:amd64')->{catalogue_prefix}, 'FreeBSD:15:amd64',
        'prefixed repository retains the native ABI directory');
    return;
}

sub trust_cases {
    rejects(sub { inspect($signed, trust => pubkey('wrong')) }, qr/Native[ ]pkg[ ]catalogue[ ](?:update|query)[ ]failed/x,
        'a wrong signing key cannot pass by falling back to another catalogue');
    rejects(sub { inspect($unsigned, trust => pubkey('repo')) }, qr/Native[ ]pkg[ ]catalogue[ ](?:update|query)[ ]failed/x,
        'an unsigned repository is not accepted under a public-key policy');
    rejects(sub { inspect($unsigned, trust => undef) }, qr/explicit repository trust/, 'trust is mandatory');
    rejects(sub { inspect($unsigned, trust => { type => 'none' }) }, qr/Unsupported repository trust/, 'no implicit unsigned policy');
    rejects(sub { inspect($unsigned, trust => { type => 'operator-trusted-tree', digest => '0' x 64 }) },
        qr/Trusted repository tree checksum/, 'pinned tree mismatch is rejected');
    rejects(sub { inspect($signed, trust => { %{pubkey('repo')}, sha256 => '0' x 64 }) },
        qr/public-key[ ]checksum/x, 'public key identity is pinned');
    rejects(sub { inspect($signed, tool => { %$tool, sha256 => '0' x 64 }) }, qr/executable checksum/,
        'native tool identity is pinned');
    if (exists($tool->{library_digest})) {
        rejects(sub { inspect($signed, tool => { %$tool, library_digest => '0' x 64 }) }, qr/library checksum/,
            'native private libraries are pinned');
    }
    rejects(sub { inspect($signed, catalogue_prefix => '../escape') }, qr/Invalid repository catalogue prefix/,
        'catalogue prefix cannot traverse outside the source');
    rejects(sub { inspect($signed, unknown => 1) }, qr/Unknown native repository option/, 'unknown repository options fail');
    rejects(sub { xCAT::FreeBSDRepo::inspect_repository($signed, 'tool') }, qr/options must be pairs/,
        'odd repository options fail before native execution');
    return;
}

sub catalogue_cases {
    my $one = repository(1, [['test-dep']]);
    my $mismatch = clone_tree($signed);
    copy("$one/packagesite.pkg", "$mismatch/packagesite.pkg") or croak $!;
    rejects(sub { inspect($mismatch, trust => pubkey('repo')) }, qr/Repository catalogue records disagree/,
        'two independently signed but different catalogue populations are rejected');
    for my $case (
        ['duplicate identity', sub { push @{$_[0]{packages}}, $_[0]{packages}[0] }, qr/Duplicate package identity/],
        ['different fallback comment', sub { $_[1][0]{comment} = 'different' }, qr/Repository catalogue records disagree/],
        ['different fallback vital', sub { $_[1][0]{vital} = JSON::true }, qr/Repository catalogue records disagree/],
        ['nonempty groups', sub { $_[0]{groups} = ['group'] }, qr/Unsupported nonempty data catalogue groups/],
        ['unknown top-level field', sub { $_[0]{extension} = 1 }, qr/Unsupported data catalogue field/],
        ['forged package size', sub { ++$_[0]{packages}[0]{pkgsize} }, qr/Package archive size mismatch/],
        ['forged embedded comment', sub { $_[0]{packages}[0]{comment} = 'forged' }, qr/Package archive metadata mismatch/],
        ['uncopied extension', sub { $_[0]{packages}[0]{unrecognized_security_field} = 'value' }, qr/Package archive metadata mismatch/],
        ['archive path escape', sub { $_[0]{packages}[0]{repopath} = '../outside.pkg' }, qr/Invalid[ ]package[ ]archive[ ]path/x],
        ['invalid checksum', sub { $_[0]{packages}[0]{sum} = 'not-a-checksum' }, qr/Invalid package archive checksum/],
        ['wrong typed checksum', sub { $_[0]{packages}[0]{sum} =~ s/.$/Z/x }, qr/Native pkg archive checksum failed/],
    ) {
        my $root = clone_tree($unsigned);
        my $data = catalogue_data($root);
        my $fallback = $json->decode($json->encode($data->{packages}));
        $case->[1]->($data, $fallback);
        write_catalogues($root, $data, $case->[0] =~ /\Adifferent[ ]fallback[ ]/x ? $fallback : undef);
        rejects(sub { inspect($root) }, $case->[2], "rejects $case->[0]");
    }
    for my $case (
        ['include directive', ".include \"/etc/passwd\";\n", qr/Unsupported repository metadata syntax/],
        ['duplicate metadata key', "version = 2;\n", qr/Duplicate repository metadata key/],
        ['unknown metadata key', "extension = 1;\n", qr/Unsupported repository metadata key/],
    ) {
        my $root = clone_tree($unsigned);
        write_file("$root/meta.conf", read_file("$root/meta.conf") . $case->[1]);
        rejects(sub { inspect($root) }, $case->[2], "rejects $case->[0]");
    }
    my $bad_meta = clone_tree($unsigned);
    my $meta = read_file("$bad_meta/meta");
    $meta =~ s/filesite[ ]=[ ]"files"/filesite = "filesite"/x;
    write_file("$bad_meta/meta", $meta);
    rejects(sub { inspect($bad_meta) }, qr/Repository metadata files disagree/, 'meta and meta.conf must agree');
    for my $file (qw(data.pkg packagesite.pkg)) {
        my $root = clone_tree($signed);
        write_file("$root/$file", 'not an archive');
        rejects(sub { inspect($root, trust => pubkey('repo')) }, qr/Cannot read repository catalogue member/,
            "damaged $file cannot be masked by fallback");
    }
    return;
}

sub archive_cases {
    my $native_failure = qr/Native[ ]pkg[ ]catalogue.*failed/x;
    for my $filename (qw(test-app-1.pkg test-dep-1.pkg)) {
        my $missing = clone_tree($unsigned);
        unlink("$missing/All/$filename") or croak $!;
        rejects(sub { inspect($missing) }, qr/Missing package archive/, "missing $filename fails the complete inventory");
        my $damaged = clone_tree($unsigned);
        my $bytes = read_file("$damaged/All/$filename");
        substr($bytes, -1, 1, chr(ord(substr($bytes, -1)) ^ 1));
        write_file("$damaged/All/$filename", $bytes);
        rejects(sub { inspect($damaged) }, qr/Native pkg archive checksum failed/, "same-size corruption in $filename is rejected");
    }
    my $extra = clone_tree($unsigned);
    copy("$extra/All/test-app-1.pkg", "$extra/All/uncatalogued.pkg") or croak $!;
    rejects(sub { inspect($extra) }, qr/Uncatalogued package archive/, 'unlisted regular package archives are not silently accepted');
    for my $case (
        ['wrong ABI', { abi => 'FreeBSD:15:aarch64' }, qr/(?:Unsupported[ ]package[ ]ABI|$native_failure)/x],
        ['future OSVERSION', { annotations => { FreeBSD_version => '1501001' } }, qr/(?:Incompatible[ ]package[ ]OSVERSION|$native_failure)/x],
    ) {
        my $root = repository(0, [['test-package', %{$case->[1]}]]);
        rejects(sub { inspect($root) }, $case->[2], "rejects $case->[0]");
    }
    for my $abi ('FreeBSD:15:amd64', 'FreeBSD:15:*', 'FreeBSD:15', 'FreeBSD:*', 'FreeBSD') {
        my $root = repository(0, [['test-package', abi => $abi, annotations => {}]]);
        is(inspect($root)->{native_validated}, 1, "accepts native ABI $abi without an OSVERSION annotation");
    }
    return;
}

sub release_tree {
    my $dvd = shift;
    my @base = map { [$_, version => '15.1', origin => "base/$_",
        annotations => { FreeBSD_version => '1501000' }] }
      qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base);
    push @base, ['pkg', version => '2.6.2_1', origin => 'ports-mgmt/pkg'];
    my $repo = repository(0, \@base);
    my $root = new_directory();
    write_file("$root/bin/freebsd-version", "USERLAND_VERSION=\"15.1-RELEASE\"\nexit 99\n");
    write_file("$root/bin/sh", "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62));
    make_path("$root/usr/freebsd-packages");
    command('/usr/bin/cp', '-a', $repo, "$root/usr/freebsd-packages/offline");
    if ($dvd) {
        my $apps = "$root/packages/FreeBSD:15:amd64";
        create_package("$apps/All/Hashed", 'pkg', version => '2.6.2_1', origin => 'ports-mgmt/pkg', comment => 'Application bootstrap');
        rename("$apps/All/Hashed/pkg-2.6.2_1.pkg", "$apps/All/Hashed/pkg-2.6.2_1~fixture.pkg") or croak $!;
        create_package("$apps/All/Hashed", 'application');
        run_pkg('repo', $apps);
        make_path("$apps/Latest");
        symlink('../All/pkg-2.6.2_1.pkg', "$apps/Latest/pkg.pkg") or croak $!;
        symlink('FreeBSD:15:amd64', "$root/packages/freebsd:15:x86:64") or croak $!;
    }
    return $root;
}

sub inspect_release {
    my ($root, %options) = @_;
    return xCAT::FreeBSDRepo::inspect_release($root, tool => $tool,
        trust => { type => 'operator-trusted-release', digest => xCAT::FreeBSDRepo::inspect_release_tree($root)->{digest} },
        %options);
}

sub release_cases {
    is(xCAT::FreeBSDRepo::inspect_release(new_directory()), undef, 'unrelated media is not claimed by the native inspector');
    rejects(sub { xCAT::FreeBSDRepo::inspect_release(new_directory(), 'tool') }, qr/options must be pairs/,
        'odd release options fail before native execution');
    my $disc = release_tree(0);
    my $base = inspect_release($disc);
    is_deeply([sort keys %{$base->{repositories}}], ['base'], 'base-only release media needs no application repository');
    is($base->{release}, '15.1-RELEASE', 'release identity agrees with native base package versions');
    is($base->{repositories}{base}{bootstrap}{version}, '2.6.2_1', 'bootstrap version is independent of the base release version');
    is($base->{selection_validated}, 0, 'release inspection does not claim install selection closure');
    rejects(sub { inspect_release($disc, trust => undef) }, qr/pinned[ ]operator-trusted[ ]release/x, 'release trust must be explicit');
    rejects(sub { inspect_release($disc, trust => { type => 'operator-trusted-release', digest => '0' x 64 }) },
        qr/Trusted release checksum/, 'release trust binds media identities and both repository trees');
    my $dvd = release_tree(1);
    my $result = inspect_release($dvd);
    my $apps = $result->{repositories}{applications};
    is(scalar(keys %{$apps->{repository}{archives}}), 2, 'DVD application packages are all natively validated');
    is_deeply($apps->{link_repairs}, [{ path => 'FreeBSD:15:amd64/Latest/pkg.pkg',
        from => '../All/pkg-2.6.2_1.pkg', to => '../All/Hashed/pkg-2.6.2_1~fixture.pkg',
        archive => 'FreeBSD:15:amd64/All/Hashed/pkg-2.6.2_1~fixture.pkg', sha256 => $apps->{bootstrap}{sha256} }],
        'known DVD link repair binds a unique validated application archive');
    isnt($apps->{bootstrap}{sha256}, $result->{repositories}{base}{bootstrap}{sha256},
        'same bootstrap name and version in base and applications do not conflate archive identity');
    ok(-l "$dvd/packages/FreeBSD:15:amd64/Latest/pkg.pkg" && !-e "$dvd/packages/FreeBSD:15:amd64/Latest/pkg.pkg",
        'inspection describes the repair without changing release media');
    rejects(sub { inspect("$dvd/packages", catalogue_prefix => 'FreeBSD:15:amd64') }, qr/Dangling repository link/,
        'generic repository validation cannot use the release-only dangling-link exception');
    my $wrong_alias = clone_tree($dvd);
    my $alias = "$wrong_alias/packages/FreeBSD:15:amd64/Latest/pkg.pkg";
    unlink($alias) or croak $!;
    symlink('../All/Hashed/application-1.pkg', $alias) or croak $!;
    rejects(sub { inspect_release($wrong_alias) }, qr/bootstrap alias names a different archive/,
        'an existing bootstrap alias must resolve to the selected pkg archive');
    my $correct_alias = clone_tree($dvd);
    my $correct = "$correct_alias/packages/FreeBSD:15:amd64/Latest/pkg.pkg";
    unlink($correct) or croak $!;
    symlink('../All/Hashed/pkg-2.6.2_1~fixture.pkg', $correct) or croak $!;
    is_deeply(inspect_release($correct_alias)->{repositories}{applications}{link_repairs}, [],
        'a valid bootstrap alias requires no repair');
    for my $case (
        ['wrong base version', sub { create_package("$_[0]/All", 'FreeBSD-runtime', version => '15.0',
            origin => 'base/FreeBSD-runtime', annotations => { FreeBSD_version => '1501000' });
            unlink("$_[0]/All/FreeBSD-runtime-15.1.pkg") or croak $! }, qr/Incompatible release base package/],
        ['missing kernel', sub { unlink("$_[0]/All/FreeBSD-kernel-generic-15.1.pkg") or croak $! }, qr/Missing release base packages/],
        ['multiple bootstraps', sub { create_package("$_[0]/All", 'pkg', version => '3', origin => 'ports-mgmt/pkg') },
            qr/exactly one pkg bootstrap/],
        ['wrong bootstrap origin', sub { create_package("$_[0]/All", 'pkg', version => '2.6.2_1', origin => 'misc/pkg') },
            qr/Incompatible release pkg bootstrap identity/],
    ) {
        my $root = clone_tree($disc);
        my $base_repo = "$root/usr/freebsd-packages/offline";
        $case->[1]->($base_repo);
        run_pkg('repo', $base_repo);
        rejects(sub { inspect_release($root) }, $case->[2], "release rejects $case->[0]");
    }
    return;
}

sub change_cases {
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my $source = clone_tree($unsigned);
    my $changed = 0;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my @arguments = @_;
            my $result = $original_runner->(@arguments);
            write_file("$source/changed", 'source changed after initial snapshot') unless $changed++;
            return $result;
        };
        rejects(sub { inspect($source) }, qr/Repository changed during native inspection/,
            'a source change during real native commands prevents publication of a validated result');
    }
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, 'source-change command double is restored');
    my $executable = "$tmp/mutable-pkg";
    copy($tool->{path}, $executable) or croak $!;
    chmod(oct('0700'), $executable) or croak $!;
    $changed = 0;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my @arguments = @_;
            my $result = $original_runner->(@arguments);
            write_file($executable, read_file($executable) . "\0") unless $changed++;
            return $result;
        };
        rejects(sub { inspect($unsigned, tool => { %$tool, path => $executable }) }, qr/Native pkg executable checksum mismatch/,
            'a native executable change after initial pin verification is detected');
    }
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, 'tool-change command double is restored');
    return;
}

success_cases();
trust_cases();
catalogue_cases();
archive_cases();
release_cases();
change_cases();
ok(!-e "$tmp/package-script-executed", 'no negative case executed an installation script');
done_testing();
