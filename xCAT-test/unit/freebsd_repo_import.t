#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(O_RDWR O_CREAT LOCK_EX LOCK_NB);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use POSIX qw(mkfifo);
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
plan(skip_all => 'Native repository import tests require Linux execution') unless $^O eq 'linux';
plan(skip_all => 'Native pkg database fixtures require container root') if $> != 0;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
    $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
    $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
    $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
}
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);

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
    my $result = xCAT::FreeBSDPkg::run_command(\@argv, cwd => $tmp,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub run_pkg {
    my @arguments = @_;
    return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments);
}

sub new_directory {
    return $fixture->new_directory();
}

sub clone_tree {
    my $source = shift;
    my $root = new_directory();
    command('/usr/bin/cp', '-a', "$source/.", $root);
    return $root;
}

sub pubkey {
    my $name = shift;
    return { type => 'pubkey', path => "$tmp/$name.pub",
        sha256 => sha256_hex(read_file("$tmp/$name.pub")) };
}

sub import_repository {
    my ($source, $installroot, %options) = @_;
    my %native = (tool => $tool, trust => pubkey('repo'), %options);
    return xCAT::FreeBSDRepoImport::import_repository($source, $installroot, %native);
}

sub import_release {
    my ($source, $installroot, %options) = @_;
    my %native = (tool => $tool,
        trust => { type => 'operator-trusted-release',
            digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} }, %options);
    return xCAT::FreeBSDRepoImport::import_release($source, $installroot, %native);
}

sub rejects {
    my ($action, $pattern, $description) = @_;
    my $ok = eval { $action->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    like($error, $pattern, "$description diagnostic");
    return;
}

sub publication_parent {
    return "$_[0]/freebsd15.1/x86_64/repositories";
}

sub no_publication {
    my ($root, $description) = @_;
    my $parent = publication_parent($root);
    my @entries;
    if (-d $parent) {
        opendir(my $dh, $parent) or croak $!;
        @entries = sort grep { $_ ne '.' && $_ ne '..' && $_ ne '.repository-import.lock' } readdir($dh);
        closedir($dh) or croak $!;
    }
    is_deeply(\@entries, [], $description);
    return;
}

sub protected_tree {
    my ($root, $description) = @_;
    my $tree = xCAT::FreeBSDRepo::snapshot_tree($root);
    my @bad;
    for my $relative ('', sort keys %{$tree->{entries}}) {
        my $path = length($relative) ? "$root/$relative" : $root;
        my @state = lstat($path);
        next if -l _;
        my $directory = -d _;
        push @bad, $relative if ($state[2] & oct('7777')) != ($directory ? oct('0555') : oct('0444'))
          || $state[4] != $> || (!$directory && ($state[3] != 1 || $state[9] <= 0));
    }
    is_deeply(\@bad, [], $description);
    return;
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
my $signed = $fixture->repository(1, \@definitions);
make_path("$signed/Latest");
symlink('../All/test-app-1.pkg', "$signed/Latest/test-app.pkg") or croak $!;
symlink('All', "$signed/alias") or croak $!;
my $source_tree = xCAT::FreeBSDRepo::snapshot_tree($signed);
my $installroot = new_directory();
my $published;

sub publication_cases {
    $published = import_repository($signed, $installroot);
    is($published->{format}, 'xcat-freebsd-repo-import-1', 'import descriptor is versioned');
    is($published->{kind}, 'repository', 'generic repository kind is explicit');
    is($published->{native_validated}, 1, 'publication follows real native validation');
    is($published->{selection_validated}, 0, 'publication does not claim dependency selection');
    is($published->{reused}, 0, 'first publication is new');
    is($published->{path}, publication_parent($installroot) . "/$published->{digest}", 'digest determines the immutable destination');
    is_deeply($published->{source}{tree}, $source_tree, 'descriptor retains original provenance');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$published->{path}/repository"), $source_tree,
        'unrepaired published repository has the original complete tree');
    is(readlink("$published->{path}/repository/Latest/test-app.pkg"), '../All/test-app-1.pkg', 'relative archive alias is preserved');
    is(readlink("$published->{path}/repository/alias"), 'All', 'relative directory alias is preserved');
    is(read_file("$published->{path}/repository.pub"), read_file("$tmp/repo.pub"), 'public trust file is copied into the import');
    is($published->{trust_files}{'repository.pub'}{sha256}, pubkey('repo')->{sha256}, 'manifest binds its copied trust file');
    my $manifest_bytes = read_file("$published->{path}/manifest.json");
    my %descriptor = %$published;
    delete @descriptor{qw(path reused)};
    is_deeply($json->decode($manifest_bytes), \%descriptor, 'published JSON describes the public result without local runtime fields');
    is(index($manifest_bytes, $tmp), -1, 'provenance does not bind temporary source or tool paths');
    protected_tree($published->{path}, 'all published files and directories have immutable operational metadata');
    my @shared;
    my @changed_times;
    for my $relative (sort keys %{$source_tree->{entries}}) {
        next unless $source_tree->{entries}{$relative}{type} eq 'file';
        my @before = stat("$signed/$relative");
        my @after = stat("$published->{path}/repository/$relative");
        push @shared, $relative if $before[0] == $after[0] && $before[1] == $after[1];
        push @changed_times, $relative if $before[9] != $after[9];
    }
    is_deeply(\@shared, [], 'published files have independent inodes from mutable input');
    is_deeply(\@changed_times, [], 'publication preserves positive source file mtimes');
    my @before = stat("$published->{path}/manifest.json");
    my $reused = import_repository($signed, $installroot);
    is($reused->{reused}, 1, 'identical repeat verifies and reuses the destination');
    is($reused->{path}, $published->{path}, 'identical repeat retains the immutable path');
    my @after = stat("$published->{path}/manifest.json");
    is_deeply([@after[0, 1, 9]], [@before[0, 1, 9]], 'reuse does not replace or retimestamp the manifest');
    rejects(sub { import_repository($signed, $installroot, nonoverwrite => 1) }, qr/destination already exists/,
        'nonoverwrite rejects an existing identical import');
    is(read_file("$published->{path}/manifest.json"), $manifest_bytes, 'nonoverwrite preserves the original manifest bytes');
    my $relocated = clone_tree($signed);
    my $key_directory = new_directory();
    copy("$tmp/repo.pub", "$key_directory/repo.pub") or croak $!;
    my $same = import_repository($relocated, $installroot,
        trust => { %{pubkey('repo')}, path => "$key_directory/repo.pub" });
    is($same->{reused}, 1, 'identical source and key under different paths reuse the import');
    is($same->{digest}, $published->{digest}, 'input path changes do not change provenance identity');
    my $other = import_repository($signed, $installroot,
        trust => { type => 'operator-trusted-tree', digest => $source_tree->{digest} });
    isnt($other->{digest}, $published->{digest}, 'different trust provenance receives a different immutable identity');
    is(read_file("$published->{path}/manifest.json"), $manifest_bytes, 'different provenance does not overwrite a prior descriptor');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'all successful imports leave source bytes and links unchanged');
    my $prefixed = new_directory();
    command('/usr/bin/cp', '-a', $signed, "$prefixed/FreeBSD:15:amd64");
    symlink('FreeBSD:15:amd64', "$prefixed/freebsd:15:x86:64") or croak $!;
    my $with_prefix = import_repository($prefixed, new_directory(), catalogue_prefix => 'FreeBSD:15:amd64');
    is($with_prefix->{repositories}{repository}{catalogue_prefix}, 'FreeBSD:15:amd64', 'generic publication retains its explicit native catalogue prefix');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$with_prefix->{path}/repository"),
        xCAT::FreeBSDRepo::snapshot_tree($prefixed), 'prefixed publication preserves complete ABI directory and alias');
    protected_tree($with_prefix->{path}, 'prefixed repository publication is protected');
    return;
}

sub release_cases {
    my $disc = $fixture->release_tree(0);
    my $base = import_release($disc, new_directory());
    is_deeply([sort keys %{$base->{repositories}}], ['base'], 'native base-only media publishes without applications');
    is($base->{kind}, 'release', 'release provenance remains distinct from a generic repository');
    is($base->{source}{release}, '15.1-RELEASE', 'release identity is retained');
    is($base->{selection_validated}, 0, 'base-only publication is not an executable installation selection');
    protected_tree($base->{path}, 'base-only publication is protected');
    my $dvd = $fixture->release_tree(1);
    my $before = xCAT::FreeBSDRepo::inspect_release_tree($dvd);
    my $result = import_release($dvd, new_directory());
    is_deeply([sort keys %{$result->{repositories}}], [qw(applications base)], 'native DVD media publishes both independent repositories');
    is_deeply($result->{source}{media}, $before, 'manifest retains the original release media identity');
    my $application = $result->{repositories}{applications};
    my $original = $result->{source}{repositories}{applications}{repository}{tree};
    my $repair = $application->{link_repairs};
    is_deeply($repair, [{ path => 'FreeBSD:15:amd64/Latest/pkg.pkg',
        from => '../All/pkg-2.6.2_1.pkg', to => '../All/Hashed/pkg-2.6.2_1~fixture.pkg',
        archive => 'FreeBSD:15:amd64/All/Hashed/pkg-2.6.2_1~fixture.pkg',
        sha256 => $result->{source}{repositories}{applications}{bootstrap}{sha256} }],
        'descriptor records exactly the approved bootstrap link repair');
    my $expected_entries = $json->decode($json->encode($original->{entries}));
    $expected_entries->{'FreeBSD:15:amd64/Latest/pkg.pkg'}{target} = '../All/Hashed/pkg-2.6.2_1~fixture.pkg';
    is_deeply($application->{tree}{entries}, $expected_entries, 'derived entries differ only by the exact approved link target');
    isnt($application->{tree}{digest}, $original->{digest}, 'original and repaired tree identities stay distinct');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$result->{path}/applications"), $application->{tree},
        'published applications match the declared derived tree');
    is(readlink("$result->{path}/applications/FreeBSD:15:amd64/Latest/pkg.pkg"),
        '../All/Hashed/pkg-2.6.2_1~fixture.pkg', 'published bootstrap resolves to the validated hashed archive');
    is(readlink("$dvd/packages/FreeBSD:15:amd64/Latest/pkg.pkg"), '../All/pkg-2.6.2_1.pkg', 'original DVD link is not changed');
    is_deeply(xCAT::FreeBSDRepo::inspect_release_tree($dvd), $before, 'release publication preserves all original media entries');
    protected_tree($result->{path}, 'DVD publication is protected');
    return;
}

sub destination_cases {
    my @cases = (
        ['changed catalogue', sub { write_file("$_[0]/repository/data.pkg", 'changed') }],
        ['changed archive bytes', sub { my $path = "$_[0]/repository/All/test-app-1.pkg";
            my $bytes = read_file($path); substr($bytes, -1, 1, chr(ord(substr($bytes, -1, 1)) ^ 1));
            write_file($path, $bytes) }],
        ['extra repository data', sub { write_file("$_[0]/repository/unexpected", 'extra') }],
        ['changed manifest', sub { write_file("$_[0]/manifest.json", "{}\n") }],
        ['extra import data', sub { write_file("$_[0]/unexpected", 'extra') }],
        ['changed trust file', sub { write_file("$_[0]/repository.pub", 'different key') }],
        ['changed link', sub { my $path = "$_[0]/repository/Latest/test-app.pkg";
            unlink($path) or croak $!; symlink('../All/test-dep-1.pkg', $path) or croak $! }],
        ['extra link', sub { symlink('All/test-app-1.pkg', "$_[0]/repository/extra-link") or croak $! }],
        ['writable file', sub { chmod(oct('0644'), "$_[0]/repository/data.pkg") or croak $! }],
        ['writable directory', sub { chmod(oct('0755'), "$_[0]/repository/All") or croak $! }],
        ['writable import root', sub { chmod(oct('0755'), $_[0]) or croak $! }],
        ['zero file timestamp', sub { utime(0, 0, "$_[0]/repository/All/test-app-1.pkg") == 1 or croak $! }],
        ['hard-linked file', sub { link("$_[0]/repository/data.pkg", new_directory() . '/linked') or croak $! }],
        ['different file owner', sub { chown(65534, 65534, "$_[0]/repository/data.pkg") == 1 or croak $! }],
    );
    for my $case (@cases) {
        my $root = clone_tree($installroot);
        my $destination = publication_parent($root) . "/$published->{digest}";
        $case->[1]->($destination);
        my $metadata_drift = qr/(?:operational[ ]metadata|different[ ]owner)/x;
        my $drift = qr/(?:differs|permissions|$metadata_drift)/x;
        rejects(sub { import_repository($signed, $root) }, $drift,
            "reuse rejects $case->[0]");
    }
    return;
}

sub lock_cases {
    my $open_error = qr/Cannot[ ]open[ ]repository[ ]import[ ]lock/x;
    my $unsafe_error = qr/Unsafe[ ]repository[ ]import[ ]lock/x;
    for my $case (
        ['symlink', sub { my $other = new_directory() . '/lock'; write_file($other, '');
            chmod(oct('0600'), $other) or croak $!; symlink($other, $_[0]) or croak $! }],
        ['hard link', sub { my $other = new_directory() . '/lock'; write_file($other, '');
            chmod(oct('0600'), $other) or croak $!; link($other, $_[0]) or croak $! }],
        ['wrong mode', sub { write_file($_[0], ''); chmod(oct('0644'), $_[0]) or croak $! }],
        ['nonempty', sub { write_file($_[0], 'state'); chmod(oct('0600'), $_[0]) or croak $! }],
        ['wrong owner', sub { write_file($_[0], ''); chmod(oct('0600'), $_[0]) or croak $!;
            chown(65534, 65534, $_[0]) == 1 or croak $! }],
        ['FIFO', sub { mkfifo($_[0], oct('0600')) == 0 or croak $! }],
    ) {
        my $root = new_directory();
        my $parent = publication_parent($root);
        make_path($parent);
        $case->[1]->("$parent/.repository-import.lock");
        rejects(sub { import_repository($signed, $root) }, qr/(?:$open_error|$unsafe_error)/x,
            "$case->[0] lock is rejected");
        no_publication($root, "$case->[0] lock creates no stage or destination");
    }
    my $lock_path = publication_parent($installroot) . '/.repository-import.lock';
    sysopen(my $lock, $lock_path, O_RDWR | O_CREAT, oct('0600')) or croak $!;
    flock($lock, LOCK_EX | LOCK_NB) or croak $!;
    rejects(sub { import_repository($signed, $installroot) }, qr/busy or cannot be locked/,
        'an existing import cannot bypass a held publication lock');
    close($lock) or croak $!;
    is(import_repository($signed, $installroot)->{reused}, 1, 'explicit retry after lock release verifies and reuses the import');
    my $actual = new_directory();
    make_path("$actual/nested");
    my $alias = new_directory() . '/alias';
    symlink($actual, $alias) or croak $!;
    rejects(sub { import_repository($signed, "$alias/nested") }, qr/symlinked publication directory/,
        'a symlinked publication ancestor is rejected');
    no_publication("$actual/nested", 'ancestor rejection leaves its actual target unchanged');
    my $intermediate = new_directory();
    symlink($actual, "$intermediate/freebsd15.1") or croak $!;
    rejects(sub { import_repository($signed, $intermediate) }, qr/symlinked publication directory/,
        'a symlinked generated publication parent is rejected');
    my $writable = new_directory();
    chmod(oct('0777'), $writable) or croak $!;
    rejects(sub { import_repository($signed, $writable) }, qr/Writable publication directory/,
        'an unprotected install root is rejected');
    my $source_alias = new_directory() . '/source';
    symlink($signed, $source_alias) or croak $!;
    rejects(sub { import_repository($source_alias, new_directory()) }, qr/symlinked import source/,
        'a symlinked source root is rejected');
    rejects(sub { import_repository($signed, $signed) }, qr/publication directory cannot be inside its source/,
        'publication cannot recursively modify its own source');
    return;
}

sub preflight_cases {
    for my $case (
        ['missing tool', { tool => { path => "$tmp/no-pkg", sha256 => '0' x 64 } }, qr/(?:executable|file|open)/ix],
        ['missing private library directory', { tool => { %$tool, library_directory => "$tmp/no-libraries", library_digest => '0' x 64 } }, qr/(?:library|directory|root)/ix],
        ['missing trust', { trust => undef }, qr/explicit repository trust/],
        ['missing key', { trust => { %{pubkey('repo')}, path => "$tmp/no-key" } }, qr/(?:file|open|key)/ix],
        ['wrong key', { trust => pubkey('wrong') }, qr/Native[ ]pkg[ ]catalogue[ ](?:update|query)[ ]failed/x],
    ) {
        my $root = new_directory();
        rejects(sub { import_repository($signed, $root, %{$case->[1]}) }, $case->[2], "$case->[0] fails before publication");
        no_publication($root, "$case->[0] leaves no destination or staging directory");
    }
    my $missing = clone_tree($signed);
    unlink("$missing/All/test-dep-1.pkg") or croak $!;
    my $root = new_directory();
    my $missing_payload = qr/Missing[ ]package[ ]archive/x;
    my $dangling_link = qr/Dangling[ ]repository[ ]link/x;
    rejects(sub { import_repository($missing, $root) }, qr/(?:$missing_payload|$dangling_link)/x,
        'a missing catalogued payload is rejected');
    no_publication($root, 'missing payload exposes no publication');
    my $unsigned = $fixture->repository(0, \@definitions);
    $root = new_directory();
    rejects(sub { import_repository($unsigned, $root) }, qr/Native[ ]pkg[ ]catalogue[ ](?:update|query)[ ]failed/x,
        'unsigned catalogues cannot satisfy required public-key trust');
    no_publication($root, 'unsigned trust failure exposes no publication');
    my $zero = clone_tree($signed);
    utime(0, 0, "$zero/All/test-app-1.pkg") == 1 or croak $!;
    $root = new_directory();
    rejects(sub { import_repository($zero, $root) }, qr/positive timestamp/,
        'zero source archive mtime cannot produce an unusable file repository');
    no_publication($root, 'zero source mtime cleans the private stage');
    return;
}

## no critic (Variables::ProtectPrivateVars)
sub filesystem_cases {
    my $copy_file = \&xCAT::FreeBSDRepoImport::_copy_file;
    my $copy_count = 1 + scalar(grep { $_->{type} eq 'file' } values %{$source_tree->{entries}});
    for my $position (['first', 1], ['middle', int($copy_count / 2)], ['final', $copy_count]) {
        my $root = new_directory();
        my $called = 0;
        {
            local *xCAT::FreeBSDRepoImport::_copy_file = gensym();
            *xCAT::FreeBSDRepoImport::_copy_file = sub {
                ++$called;
                $copy_file->(@_);
                croak 'injected positioned copy failure' if $called == $position->[1];
                return;
            };
            rejects(sub { import_repository($signed, $root) }, qr/injected positioned copy failure/,
                "$position->[0] file-copy failure aborts publication");
        }
        is($called, $position->[1], "$position->[0] failure reaches the intended copy position");
        no_publication($root, "$position->[0] file-copy failure leaves no stage or destination");
    }
    my @cases = (
        ['changed staged bytes', sub { $copy_file->(@_); write_file($_[1], read_file($_[1]) . 'changed') }, qr/differs/],
        ['extra staged entry', sub { $copy_file->(@_); my $stage = $_[1];
            $stage =~ s{(/\.repository-stage\.[^/]+).*\z}{$1}x;
            write_file("$stage/extra", 'unexpected') }, qr/differs/],
        ['changed source after copying', sub { $copy_file->(@_); write_file("$_[3]/late-entry", 'changed') }, qr/source changed during publication/],
        ['changed source before copying', sub { my $bytes = read_file($_[0]);
            substr($bytes, -1, 1, chr(ord(substr($bytes, -1, 1)) ^ 1));
            write_file($_[0], $bytes); $copy_file->(@_[0 .. 2]) }, qr/source file changed during copying/],
    );
    for my $case (@cases) {
        my $source = clone_tree($signed);
        my $root = new_directory();
        my $called = 0;
        {
            local *xCAT::FreeBSDRepoImport::_copy_file = gensym();
            *xCAT::FreeBSDRepoImport::_copy_file = sub {
                return $copy_file->(@_) if $called++;
                return $case->[1]->(@_, $source);
            };
            rejects(sub { import_repository($source, $root) }, $case->[2], "$case->[0] aborts publication");
        }
        ok($called, "$case->[0] reaches the filesystem adapter after real native validation");
        no_publication($root, "$case->[0] removes its stage and leaves no visible import");
    }
    my $root = clone_tree($installroot);
    my $candidate = clone_tree($signed);
    write_file("$candidate/repository-note", 'new source provenance');
    my $before = xCAT::FreeBSDRepo::snapshot_tree(publication_parent($root));
    my $renames = 0;
    {
        local *xCAT::FreeBSDRepoImport::_rename = gensym();
        *xCAT::FreeBSDRepoImport::_rename = sub { ++$renames; croak 'injected rename failure' };
        rejects(sub { import_repository($candidate, $root) }, qr/injected rename failure/, 'rename failure is propagated');
    }
    is($renames, 1, 'rename failure occurs after complete staged verification');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree(publication_parent($root)), $before,
        'rename failure removes only its stage and preserves existing publications');
    is(import_repository($candidate, $root)->{reused}, 0, 'explicit retry after rename failure publishes a new import');
    is(import_repository($signed, $root)->{reused}, 1, 'earlier immutable publication still verifies after failure and retry');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'unrelated original source remains unchanged');
    return;
}
## use critic

subtest 'signed repository publication and reuse' => \&publication_cases;
subtest 'base-only and DVD release publication' => \&release_cases;
subtest 'existing destination tampering is rejected' => \&destination_cases;
subtest 'publication paths and lock objects are protected' => \&lock_cases;
subtest 'preflight errors expose no imported tree' => \&preflight_cases;
subtest 'filesystem failures and mutation clean only the private stage' => \&filesystem_cases;
ok(!-e "$tmp/package-script-executed", 'publication never executes a package lifecycle script');
done_testing();
