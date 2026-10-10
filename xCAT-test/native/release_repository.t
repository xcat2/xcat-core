#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(copy);
use File::Path qw(make_path);
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
BAIL_OUT('run package builds as an unprivileged user') unless $>;
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
ok(-f "$root/RPMS/noarch/$rpm", 'real release RPM was built') or BAIL_OUT('missing release RPM');
my $requirements = command($root, 'rpm', '-qp', '--requires', "$root/RPMS/noarch/$rpm");
like($requirements, qr/^dnf$/m, 'release package requires DNF');
my $files = command($root, 'rpm', '-qp', '--qf', '[%{FILENAMES}\t%{FILEFLAGS}\n]', "$root/RPMS/noarch/$rpm");
for my $repo (qw(xcat-core xcat-dep xcat-dep-common)) {
    like($files, qr{^/etc/yum\.repos\.d/\Q$repo\E\.repo\t17$}m, "$repo remains config(noreplace)");
}
make_path("$root/work/build-utils/lib/XCAT");
copy(repo_path('buildrpms.pl'), "$root/work/buildrpms.pl") or die $!;
copy(repo_path('build-utils/lib/XCAT/BuildUtils.pm'), "$root/work/build-utils/lib/XCAT/BuildUtils.pm") or die $!;
write_text("$root/work/Version", "9.9.9\n");
write_text("$root/work/Gitepoch", "1600000000\n");
write_text("$root/work/Gitinfo", ('a' x 40) . "\n");
make_path("$root/input/SRPMS");
copy("$root/RPMS/noarch/$rpm", "$root/input/$rpm") or die $!;
copy("$root/SRPMS/$srpm", "$root/input/SRPMS/$srpm") or die $!;
copy("$root/RPMS/noarch/$rpm", "$root/input/xCAT-release-latest.noarch.rpm") or die $!;

for my $signed (0, 1) {
    for my $attempt (1, 2) {
        command("$root/work", $^X, 'buildrpms.pl', '--merge-core-repos',
            '--target', 'alma+epel-10-x86_64', '--release', '1',
            '--output-dir', "$root/output", '--input-core-repos', "$root/input",
            $signed ? ('--gpg-sign', '--gpg-key-name', 'package@example.test') : ());
        check_repository("$root/output", $signed, "merge signed=$signed run=$attempt");
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
command("$root/work", 'unshare', '--user', '--map-root-user', '--mount',
    'bash', repo_path('xCAT-test/native/fixtures/buildrpms-namespace.sh'),
    'sh', '-c', 'trap \'gpgconf --homedir "$GNUPGHOME" --kill gpg-agent\' EXIT; "$@"', 'sign-test',
    $^X, 'buildrpms.pl', '--package', 'xCAT-release', '--target', $target,
    '--release', '1', '--nproc', '1', '--gpg-sign', '--gpg-key-name', 'package@example.test');
check_repository($cached, 1, 'cached build finalization');

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
    is($rc, 0, "$args[0] completes") or do { diag($out, $err); BAIL_OUT("@args failed"); };
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

sub check_repository {
    my ($directory, $signed, $label) = @_;
    my $alias = "$directory/xCAT-release-latest.noarch.rpm";
    ok(-f $alias, "$label publishes the alias") or BAIL_OUT('missing bootstrap alias');
    is(read_binary($alias), read_binary("$directory/$rpm"), "$label alias has final RPM bytes");
    is((stat($alias))[2] & 0777, 0644, "$label alias is readable");
    my @packages = primary_packages($directory);
    is(scalar(@packages), 1, "$label indexes the release package once");
    for my $package (@packages) {
        my ($location) = $package->findnodes('./*[local-name()="location"]');
        is($location->getAttribute('href'), $rpm, "$label indexes the versioned filename only");
    }
    if ($signed) {
        for my $repo ($directory, "$directory/SRPMS") {
            command($root, 'gpg', '--verify', "$repo/repodata/repomd.xml.asc", "$repo/repodata/repomd.xml");
        }
        my $signature = command($root, 'rpm', '-qp', '--qf', '%{RSAHEADER:pgpsig}', $alias);
        like($signature, qr/RSA.*Key ID/i, "$label alias carries the package signature");
        isnt(read_binary($alias), read_binary("$root/RPMS/noarch/$rpm"), "$label signing changed the unsigned RPM");
    }
}
