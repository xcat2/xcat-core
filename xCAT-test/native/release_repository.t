#!/usr/bin/env perl
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path remove_tree);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use FindBin;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use XML::LibXML;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Package qw(run_in);

plan skip_all => 'requires Linux package tools' unless $^O eq 'linux';
die('run package builds as an unprivileged user') unless $>;
my $root = tempdir(CLEANUP => 1);
make_path(map { "$root/$_" } qw(home home/keys SOURCES BUILD BUILDROOT RPMS SRPMS SPECS work));
chmod 0700, "$root/home/keys" or die $!;
local %ENV = (%ENV, HOME => "$root/home", GNUPGHOME => "$root/home/keys", LC_ALL => 'C');
delete @ENV{qw(PERL5LIB PERL5OPT PERLLIB)};
write_text("$root/home/.rpmmacros", "%__gpg /usr/bin/gpg\n");
command($root, 'gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
    '--quick-generate-key', 'Package Test <package@example.test>', 'rsa2048', 'sign', '0');
END {
    local $?;
    system('gpgconf', '--homedir', "$root/home/keys", '--kill', 'gpg-agent') if defined $root;
}
command($root, 'tar', '-czf', "$root/SOURCES/xCAT-release-9.9.9.tar.gz",
    '-C', repo_path('.'), 'xCAT-release');
command($root, 'rpmbuild', '-ba', '--define', "_topdir $root",
    '--define', 'version 9.9.9', '--define', 'release 1', repo_path('xCAT-release/xCAT-release.spec'));
my $rpm = 'xCAT-release-9.9.9-1.noarch.rpm';
my $srpm = 'xCAT-release-9.9.9-1.src.rpm';
ok(-f "$root/RPMS/noarch/$rpm", 'real release RPM was built') or die('missing release RPM');
my $requirements = command($root, 'rpm', '-qp', '--requires', "$root/RPMS/noarch/$rpm");
like($requirements, qr/^dnf$/m, 'release package requires DNF');
my $files = command($root, 'rpm', '-qp', '--qf', '[%{FILENAMES}\t%{FILEFLAGS}\n]', "$root/RPMS/noarch/$rpm");
for my $repo (qw(xcat-core xcat-dep xcat-dep-common)) {
    like($files, qr{^/etc/yum\.repos\.d/\Q$repo\E\.repo\t17$}m, "$repo remains config(noreplace)");
}
for my $relative (qw(buildrpms.pl build-utils/lib/XCAT/BuildUtils.pm
    build-utils/lib/XCAT/NFSLock.pm
    build-utils/sync-fips-policy build-utils/fips-policy.sh
    xCAT-genesis-scripts/usr/lib/xcat/fips.sh xCAT/postscripts/xcatlib.sh)) {
    make_path(dirname("$root/work/$relative"));
    copy(repo_path($relative), "$root/work/$relative") or die "copy $relative: $!";
}
write_text("$root/work/Version", "9.9.9\n");
write_text("$root/work/Gitepoch", "1600000000\n");
write_text("$root/work/Gitinfo", ('a' x 40) . "\n");
make_path("$root/input/SRPMS");
copy("$root/RPMS/noarch/$rpm", "$root/input/$rpm") or die $!;
copy("$root/SRPMS/$srpm", "$root/input/SRPMS/$srpm") or die $!;
copy("$root/RPMS/noarch/$rpm", "$root/input/xCAT-release-latest.noarch.rpm") or die $!;

my $rpmsign = command($root, 'sh', '-c', 'command -v rpmsign');
chomp $rpmsign;
make_path("$root/bin");
copy(repo_path('xCAT-test/native/fixtures/rpmsign-preserve-mtime.sh'), "$root/bin/rpmsign") or die $!;
chmod 0755, "$root/bin/rpmsign" or die $!;
local $ENV{XCAT_TEST_RPMSIGN} = $rpmsign;
local $ENV{PATH} = "$root/bin:$ENV{PATH}";

for my $signed (0, 1) {
    for my $attempt (1, 2) {
        my $before = $signed && $attempt == 1 ? package_stats("$root/input") : undef;
        command("$root/work", $^X, 'buildrpms.pl', '--merge-core-repos',
            '--target', 'alma+epel-10-x86_64', '--release', '1',
            '--output-dir', "$root/output", '--input-core-repos', "$root/input",
            $signed ? ('--gpg-sign', '--gpg-key-name', 'package@example.test') : ());
        check_repository("$root/output", $signed, "merge signed=$signed run=$attempt", $before);
        if ($signed) {
            copy("$root/output/$rpm", "$root/input/$rpm") or die $!;
            copy("$root/output/SRPMS/$srpm", "$root/input/SRPMS/$srpm") or die $!;
        }
    }
}

my $target = 'alma+epel-10-x86_64';
my $cached = "$root/work/dist/$target/rpms";
make_path("$cached/SRPMS", "$root/mock", "$root/locks");
copy("$root/RPMS/noarch/$rpm", "$cached/$rpm") or die $!;
copy("$root/SRPMS/$srpm", "$cached/SRPMS/$srpm") or die $!;
command($root, 'cp', '-a', repo_path('xCAT-release'), "$root/work/xCAT-release");
write_text("$root/mock/xCAT-release-$target.cfg", "# cached build\n");
write_text("$root/os-release", "ID=almalinux\nVERSION_ID=10\n");
local $ENV{BUILD_FIXTURE} = $root;
for my $attempt (1, 2) {
    my $before = $attempt == 1 ? package_stats($cached) : undef;
    command("$root/work", 'unshare', '--user', '--map-root-user', '--mount',
        'bash', repo_path('xCAT-test/native/fixtures/buildrpms-namespace.sh'),
        'sh', '-c', 'trap \'gpgconf --homedir "$GNUPGHOME" --kill gpg-agent\' EXIT; "$@"', 'sign-test',
        $^X, 'buildrpms.pl', '--package', 'xCAT-release', '--target', $target,
        '--release', '1', '--nproc', '1', '--gpg-sign', '--gpg-key-name', 'package@example.test');
    check_repository($cached, 1, "cached build finalization run=$attempt", $before);
}

write_text("$root/work/schedule.pl", <<'PERL');
BEGIN {
    require Parallel::ForkManager;
    no warnings 'redefine';
    *Parallel::ForkManager::start = sub {
        print "scheduled $_[1]\n" if defined $_[1];
        return 1;
    };
    *Parallel::ForkManager::wait_all_children = sub { };
}
do './buildrpms.pl';
die $@ if $@;
PERL
my $schedule = command("$root/work", 'unshare', '--user', '--map-root-user', '--mount',
    'bash', repo_path('xCAT-test/native/fixtures/buildrpms-namespace.sh'),
    $^X, 'schedule.pl', '--target', $target, '--release', '1', '--nproc', '1');
is(scalar(grep { $_ eq "scheduled xCAT-release-$target" } split /\n/, $schedule), 1,
    'default build schedules the release package once');

command($root, 'gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
    '--quick-generate-key', 'Source Test <source@example.test>', 'rsa2048', 'sign', '0');
my $source_key = command($root, 'gpg', '--armor', '--export', 'source@example.test');
write_text("$root/source.key", $source_key);
command($root, 'rpm', '--dbpath', "$root/source-rpmdb", '--import', "$root/source.key");
command($root, 'gpg', '--output', "$root/source-keyring.gpg", '--export', 'source@example.test');
for my $state (qw(empty unsigned signed no-alias alias-only)) {
    subtest "source-only with $state binaries" => sub {
        remove_tree($cached);
        make_path("$cached/SRPMS");
        copy("$root/SRPMS/$srpm", "$cached/SRPMS/$srpm") or die $!;
        if ($state ne 'empty' && $state ne 'alias-only') {
            command($root, 'cp', '-a', "$root/output/.", $cached);
            copy("$root/SRPMS/$srpm", "$cached/SRPMS/$srpm") or die $!;
            if ($state eq 'unsigned') {
                copy("$root/RPMS/noarch/$rpm", "$cached/$rpm") or die $!;
                command($root, 'createrepo_c', '--excludes', 'SRPMS/*',
                    '--excludes', 'xCAT-release-latest.noarch.rpm', $cached);
                command($root, 'gpg', '--batch', '--yes', '--armor', '--detach-sign',
                    '--default-key', 'package@example.test', "$cached/repodata/repomd.xml");
            }
            check_package_index($cached, $rpm, 'initial binary repository');
        }
        if ($state eq 'no-alias') {
            unlink "$cached/xCAT-release-latest.noarch.rpm" or die $!;
        } elsif ($state ne 'empty') {
            # Keep an older alias to detect replacement even when the versioned RPM still exists.
            copy("$root/RPMS/noarch/$rpm", "$cached/xCAT-release-latest.noarch.rpm") or die $!;
            chmod 0600, "$cached/xCAT-release-latest.noarch.rpm" or die $!;
            utime 1600000000, 1600000000, "$cached/xCAT-release-latest.noarch.rpm" or die $!;
        }
        my $before = binary_snapshot($cached);
        for my $attempt (0, 1, 2) {
            my $signed = $attempt > 0 ? 1 : 0;
            my $label = "$state source-only signed=$signed run=$attempt";
            my ($rc, $out, $err) = run_in("$root/work", 'unshare', '--user', '--map-root-user', '--mount',
                'bash', repo_path('xCAT-test/native/fixtures/buildrpms-namespace.sh'),
                'sh', '-c', 'trap \'gpgconf --homedir "$GNUPGHOME" --kill gpg-agent\' EXIT; "$@"',
                'source-test', $^X, 'buildrpms.pl', '--package', 'xCAT-release', '--target', $target,
                '--release', '1', '--nproc', '1', '--source-only',
                $signed ? ('--gpg-sign', '--gpg-key-name', 'source@example.test') : ());
            unless (is($rc, 0, "$label completes")) {
                diag($out, $err);
                return;
            }
            is_deeply(binary_snapshot($cached), $before,
                "$label preserves all binary file bytes, modes and mtimes");
            check_package_index("$cached/SRPMS", $srpm, $label);
            if ($signed) {
                my $signature = command($root, 'rpmkeys', '--dbpath', "$root/source-rpmdb",
                    '--checksig', "$cached/SRPMS/$srpm");
                like($signature, qr/\bsignatures OK\b/, "$label verifies the source RPM signature");
                command($root, 'gpgv', '--keyring', "$root/source-keyring.gpg",
                    "$cached/SRPMS/repodata/repomd.xml.asc",
                    "$cached/SRPMS/repodata/repomd.xml");
                is(read_binary("$cached/SRPMS/repodata/repomd.xml.key"), $source_key,
                    "$label exports the source signing key");
                isnt(read_binary("$cached/SRPMS/$srpm"), read_binary("$root/SRPMS/$srpm"),
                    "$label signs the source RPM");
            } else {
                is(read_binary("$cached/SRPMS/$srpm"), read_binary("$root/SRPMS/$srpm"),
                    "$label leaves the source RPM unsigned");
            }
        }
    };
}

unlink "$root/input/$rpm" or die $!;
command("$root/work", $^X, 'buildrpms.pl', '--merge-core-repos',
    '--target', $target, '--release', '1', '--output-dir', "$root/output",
    '--input-core-repos', "$root/input");
ok(!-e "$root/output/xCAT-release-latest.noarch.rpm", 'missing release package leaves no stale alias');
is_deeply([primary_packages("$root/output")], [], 'missing release package leaves an empty binary index');
done_testing();

sub command {
    my ($directory, @args) = @_;
    my ($rc, $out, $err) = run_in($directory, @args);
    is($rc, 0, "$args[0] completes") or do { diag($out, $err); die("@args failed"); };
    return $out;
}

sub primary_packages {
    my ($directory) = @_;
    my $repomd = XML::LibXML->load_xml(location => "$directory/repodata/repomd.xml");
    my ($location) = $repomd->findnodes('//*[local-name()="data"][@type="primary"]/*[local-name()="location"]');
    die 'missing primary metadata' unless $location;
    my $path = "$directory/" . $location->getAttribute('href');
    my $xml;
    if ($path =~ /\.gz$/) {
        gunzip $path => \$xml, Transparent => 0 or die $GunzipError;
    } elsif ($path =~ /\.zst$/) {
        my ($rc, $out, $err) = run_in($directory, 'zstd', '-dc', $path);
        die "Cannot decode primary metadata: $err" if $rc;
        $xml = $out;
    } else {
        die "Unsupported primary metadata format: $path";
    }
    return XML::LibXML->load_xml(string => $xml)->findnodes('//*[local-name()="package"]');
}

sub package_stats {
    my ($directory) = @_;
    return {map { $_ => [(stat("$directory/$_"))[7, 9]] } ($rpm, "SRPMS/$srpm")};
}

sub binary_snapshot {
    my ($directory) = @_;
    my %files;
    find({no_chdir => 1, wanted => sub {
        if ($File::Find::name eq "$directory/SRPMS") {
            $File::Find::prune = 1;
            return;
        }
        return unless -f $File::Find::name;
        my $relative = substr($File::Find::name, length($directory) + 1);
        $files{$relative} = [sha256_hex(read_binary($File::Find::name)), (stat($File::Find::name))[2, 9]];
    }}, $directory);
    return \%files;
}

sub check_package_index {
    my ($repo, $filename, $label) = @_;
    my @indexed = primary_packages($repo);
    is(scalar(@indexed), 1, "$label indexes one $filename");
    for my $package (@indexed) {
        my ($location) = $package->findnodes('./*[local-name()="location"]');
        is($location->getAttribute('href'), $filename, "$label locates $filename");
        my ($checksum) = $package->findnodes('./*[local-name()="checksum"]');
        is($checksum->getAttribute('type'), 'sha256', "$label uses SHA256 for $filename");
        is($checksum->textContent, sha256_hex(read_binary("$repo/$filename")),
            "$label metadata matches final $filename bytes");
    }
}

sub check_repository {
    my ($directory, $signed, $label, $before) = @_;
    is_deeply(package_stats($directory), $before, "$label signing preserves package sizes and mtimes")
        if $before;
    my $alias = "$directory/xCAT-release-latest.noarch.rpm";
    ok(-f $alias, "$label publishes the alias") or die('missing bootstrap alias');
    is(read_binary($alias), read_binary("$directory/$rpm"), "$label alias has final RPM bytes");
    is((stat($alias))[2] & 0777, 0644, "$label alias is readable");
    for my $entry ([$directory, $rpm], ["$directory/SRPMS", $srpm]) {
        check_package_index(@$entry, $label);
    }
    if ($signed) {
        for my $repo ($directory, "$directory/SRPMS") {
            command($root, 'gpg', '--verify', "$repo/repodata/repomd.xml.asc", "$repo/repodata/repomd.xml");
        }
        my $signature = command($root, 'rpm', '-qp', '--qf', '%{RSAHEADER:pgpsig}', $alias);
        like($signature, qr/RSA.*Key ID/i, "$label alias carries the package signature");
        isnt(read_binary($alias), read_binary("$root/RPMS/noarch/$rpm"), "$label signing changed the unsigned RPM");
        isnt(read_binary("$directory/SRPMS/$srpm"), read_binary("$root/SRPMS/$srpm"),
            "$label signing changed the unsigned SRPM");
    }
}
