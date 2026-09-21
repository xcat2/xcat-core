#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json encode_json);
use Test::More;

plan skip_all => 'requires Linux root and a private mount namespace'
  unless $^O eq 'linux' && $> == 0
  && system('unshare', '--mount', '--propagation', 'private', '/bin/true') == 0;
for my $tool (qw(dnf rpm rpmbuild rpmsign createrepo_c gpg python3 runuser)) {
    plan skip_all => "requires $tool" unless system('sh', '-c', 'command -v "$1" >/dev/null', 'sh', $tool) == 0;
}
plan skip_all => 'requires the packaged openEuler key path'
  unless -f '/etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler';

my $postscripts = File::Spec->rel2abs("$FindBin::Bin/../../xCAT/postscripts");
unless (-x "$postscripts/otherpkgs") {
    require xCAT::TableUtils;
    $postscripts = xCAT::TableUtils->getInstallDir() . '/postscripts';
}
my $dir = tempdir(CLEANUP => 1);
my $case_index = 0;
chmod 0755, $dir;
make_path("$dir/bin", "$dir/fixtures", "$dir/gnupg");
chmod 0700, "$dir/gnupg";
write_text("$dir/build-fixtures.py", <<'PY');
from pathlib import Path
import os, shutil, subprocess, sys
b = Path(sys.argv[1]); home = b / 'gnupg'; top = b / 'build'
top.mkdir(); top.chmod(0o777)
subprocess.run(['gpg', '--homedir', str(home), '--batch', '--passphrase', '', '--quick-generate-key',
                'xCAT repository test <repo-test@example.invalid>', 'rsa2048', 'sign', '0'], check=True)
key = b / 'key.asc'
key.write_bytes(subprocess.check_output(['gpg', '--homedir', str(home), '--armor', '--export']))
specs = [('oe-scope-os', '1', '', 'old'), ('oe-scope-os', '2', '', 'os'),
         ('oe-scope-os', '3', '', 'vendor'), ('oe-scope-dependency', '1', '', 'os'),
         ('oe-scope-extra', '1', 'Requires: oe-scope-dependency = 1', 'other/native')]
for name, version, requires, repo in specs:
    spec = b / (name + '-' + version + '.spec')
    spec.write_text('''Name: %s
Version: %s
Release: 1
Summary: Isolated package repository fixture
License: MIT
BuildArch: noarch
AutoReqProv: no
%s
%%description
Isolated package repository fixture.
%%install
mkdir -p %%{buildroot}/usr/share/oe-scope
echo %%{version} > %%{buildroot}/usr/share/oe-scope/%%{name}
%%files
/usr/share/oe-scope/%%{name}
''' % (name, version, requires))
    subprocess.run(['runuser', '-u', 'nobody', '--', 'rpmbuild', '--define', '_topdir ' + str(top), '-bb', str(spec)], check=True)
    rpm = top / 'RPMS/noarch' / (name + '-' + version + '-1.noarch.rpm')
    subprocess.run(['rpmsign', '--define', '_gpg_name repo-test@example.invalid',
                    '--define', '_gpg_path ' + str(home), '--addsign', str(rpm)], check=True)
    dest = b / 'fixtures' / repo; dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rpm, dest / rpm.name)
for repo in ('old', 'os', 'vendor', 'other/native'):
    dest = b / 'fixtures' / repo
    subprocess.run(['createrepo_c', str(dest)], check=True)
    shutil.copyfile(key, dest / 'repodata/repomd.xml.key')
PY
my ($fixture_rc, $fixture_output) = capture('python3', "$dir/build-fixtures.py", $dir);
is($fixture_rc, 0, 'signed RPM fixtures are built by an unprivileged user') or BAIL_OUT($fixture_output);

write_text("$dir/bin/dnf", <<'PY');
#!/usr/bin/python3
import json, os, pathlib, sys
import dnf.rpm
args = sys.argv[1:]
with open(os.environ['DNF_TRACE'], 'a') as out:
    out.write(json.dumps(args) + '\n')
if 'clean' not in args and os.environ.get('REMOVE_REPO'):
    for path in pathlib.Path('/etc/yum.repos.d').glob(os.environ['REMOVE_REPO']):
        path.unlink()
os.execv('/usr/bin/dnf', ['dnf', '--installroot=' + os.environ['TEST_ROOT'],
    '--releasever=' + dnf.rpm.detect_releasever('/'), '--setopt=reposdir=/etc/yum.repos.d',
    '--setopt=install_weak_deps=False', '--setopt=tsflags=noscripts', '--noplugins'] + args)
PY
write_text("$dir/bin/mount", <<'SH');
#!/bin/sh
printf '%s on %s type nfs\n' "$NFSSERVER" "$INSTALLDIR"
SH
write_text("$dir/bin/rpm", <<'SH');
#!/bin/sh
case "$1" in --version) exec /usr/bin/rpm "$@" ;; esac
printf '%s\n' "$*" >> "$RPM_TRACE"
exit 79
SH
for my $name (qw(logger dpkg wget)) {
    write_text("$dir/bin/$name", "#!/bin/sh\nexit 1\n");
}
write_text("$dir/run", <<'SH');
#!/bin/bash
set -e
/bin/mount --bind "$TEST_REPOS" /etc/yum.repos.d
/bin/mount --bind "$TEST_KEY" /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler
exec "$@"
SH
chmod 0755, glob("$dir/bin/*"), "$dir/run";

my $os = run_case('ospkgs');
is($os->{rc}, 0, 'native ospkgs succeeds with an unreachable enabled publisher repository') or diag($os->{output});
is($os->{packages}{'oe-scope-os'}, '2', 'native ospkgs installs from the generated OS repository');
is($os->{keys}, 1, 'DNF imports the configured OS key into the initially empty RPM database');
ok($os->{vendor_preserved}, 'the publisher repository file is preserved byte for byte');
strict_transactions($os, 'ospkgs');

my $keep = run_case('ospkgs', keeprepo => 1);
isnt($keep->{rc}, 0, 'native keeprepo retains the unavailable publisher repository failure');
ok(!exists $keep->{packages}{'oe-scope-os'}, 'keeprepo failure does not install the requested package');
ok($keep->{vendor_preserved}, 'keeprepo preserves the publisher repository file');
my $keep_available = run_case('ospkgs', keeprepo => 1, vendor_available => 1);
is($keep_available->{rc}, 0, 'native keeprepo can use an available publisher repository') or diag($keep_available->{output});
is($keep_available->{packages}{'oe-scope-os'}, '3', 'keeprepo permits the newer publisher package');

my $other = run_case('otherpkgs', seed_old => 1);
is($other->{rc}, 0, 'native otherpkgs completes with an unreachable publisher repository') or diag($other->{output});
is($other->{packages}{'oe-scope-extra'}, '1', 'otherpkgs installs the requested extra package');
is($other->{packages}{'oe-scope-dependency'}, '1', 'the actual DNF solver installs its required OS dependency');
is($other->{packages}{'oe-scope-os'}, '1', 'otherpkgs upgrade does not apply unrelated generated OS updates');
ok($other->{vendor_preserved}, 'otherpkgs preserves the publisher repository file');
strict_transactions($other, 'otherpkgs');

for my $case (['ospkgs', 'xCAT-openeuler*-path*.repo'],
              ['otherpkgs', 'xCAT-openeuler*-path*.repo'],
              ['otherpkgs', 'xCAT-otherpkgs*.repo']) {
    my ($caller, $pattern) = @$case;
    my $missing = run_case($caller, remove_repo => $pattern, vendor_available => 1);
    isnt($missing->{rc}, 0, "$caller rejects missing generated repository $pattern");
    is(scalar keys %{$missing->{packages}}, 0, "$caller does not substitute publisher packages for $pattern");
    is($missing->{rpm}, '', "$caller does not bypass DNF after missing $pattern");
}
my $key_missing = run_case('ospkgs', empty_key => 1);
isnt($key_missing->{rc}, 0, 'an unusable declared OS key rejects the signed package');
is(scalar keys %{$key_missing->{packages}}, 0, 'missing trust does not disable package signature verification');
is($key_missing->{keys}, 0, 'an unusable key does not import another trust source');

for my $caller (qw(ospkgs otherpkgs)) {
    my $legacy = run_case($caller, osver => 'rhels9.6', vendor_available => 1);
    is($legacy->{rc}, 0, "$caller retains existing EL package behavior") or diag($legacy->{output});
    if ($caller eq 'ospkgs') {
        is($legacy->{packages}{'oe-scope-os'}, '3', 'EL ospkgs retains its publisher repository selection');
    } else {
        is($legacy->{packages}{'oe-scope-dependency'}, '1', 'EL otherpkgs retains distribution dependency resolution');
    }
    ok(!grep({ grep { /^--setopt=strict=/ } @$_ } @{$legacy->{dnf}}), "$caller does not impose the native strict wrapper on EL");
    ok($legacy->{vendor_preserved}, "$caller retains the legacy publisher-file behavior");
}

SKIP: {
    my $rpm = $ENV{XCAT_NATIVE_KEY_RPM};
    skip 'set XCAT_NATIVE_KEY_RPM to a verified native openEuler-gpg-keys RPM for publisher-key import', 3
      unless defined($rpm) && -f $rpm;
    my $repo = "$dir/native-key-repo";
    make_path($repo);
    require File::Copy;
    File::Copy::copy($rpm, "$repo/native-key.rpm") or die "copy native key RPM: $!";
    my ($rc, $out) = capture('createrepo_c', $repo);
    is($rc, 0, 'the official native key package fixture has repository metadata') or diag($out);
    my $native = run_case('ospkgs', osrepo => $repo, package => 'openEuler-gpg-keys', native_key => 1);
    is($native->{rc}, 0, 'DNF installs the real native signed package using the packaged openEuler key') or diag($native->{output});
    is($native->{keys}, 1, 'the empty RPM database imports only the declared native key');
}
done_testing();

sub strict_transactions {
    my ($run, $caller) = @_;
    my @transactions = grep { grep { /^(?:list|install|upgrade|remove)$/ } @$_ } @{$run->{dnf}};
    ok(@transactions > 0, "$caller invokes the real package manager");
    for my $flag ('--setopt=strict=1', '--setopt=*.gpgcheck=1', '--setopt=*.skip_if_unavailable=False') {
        ok(!grep({ my $args = $_; !grep { $_ eq $flag } @$args } @transactions), "$caller retains $flag for every transaction");
    }
    is($run->{rpm}, '', "$caller avoids direct RPM fallback");
}

sub run_case {
    my ($caller, %options) = @_;
    my $run = tempdir(DIR => $dir, CLEANUP => 1);
    make_path("$run/repos", "$run/root", "$run/media");
    my $key = $options{native_key} ? '/etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler' : "$dir/key.asc";
    if ($options{empty_key}) {
        write_text("$run/empty-key", '');
        $key = "$run/empty-key";
    }
    my $vendor = '[publisher]' . "\nname=publisher\nenabled=1\nskip_if_unavailable=False\ngpgcheck=1\ngpgkey=file://$dir/key.asc\nbaseurl=file://"
      . ($options{vendor_available} ? "$dir/fixtures/vendor" : "$run/unavailable") . "\n";
    write_text("$run/repos/openEuler.repo", $vendor);
    if ($options{seed_old}) {
        my ($rc, $output) = capture('/usr/bin/rpm', '--root', "$run/root", '--import', "$dir/key.asc");
        die $output if $rc;
        ($rc, $output) = capture('/usr/bin/rpm', '--root', "$run/root", '-i', "$dir/fixtures/old/oe-scope-os-1-1.noarch.rpm");
        die $output if $rc;
    }
    local %ENV = %ENV;
    delete @ENV{qw(BASH_ENV ENV ENVLIST OTHERPKGDIR_INTERNET KERNELDIR SDKDIR NODESETSTATE VERBOSE)};
    @ENV{qw(PATH TEST_REPOS TEST_ROOT TEST_KEY DNF_TRACE RPM_TRACE REMOVE_REPO)} =
      ("$dir/bin:$ENV{PATH}", "$run/repos", "$run/root", $key, "$run/dnf", "$run/rpm", $options{remove_repo} // '');
    @ENV{qw(OSVER ARCH MASTER NFSSERVER HTTPPORT INSTALLDIR UPDATENODE)} =
      ($options{osver} // 'openeuler24.03sp3', 'x86_64', '192.0.2.1', '192.0.2.1', 8080, "$run/media", 1);
    @ENV{qw(OSPKGDIR OSPKGS OTHERPKGDIR OTHERPKGS_INDEX OTHERPKGS1)} =
      ($options{osrepo} // "$dir/fixtures/os", $options{package} // 'oe-scope-os', "$dir/fixtures/other", 1, 'native/oe-scope-extra');
    my ($rc, $output) = capture('unshare', '--mount', '--propagation', 'private', "$dir/run",
        "$postscripts/$caller", ($options{keeprepo} ? '--keeprepo' : ()));
    my ($query_rc, $packages) = capture('/usr/bin/rpm', '--root', "$run/root", '-qa', '--qf', '%{NAME} %{VERSION}\n');
    my (%packages, $keys);
    $keys = 0;
    for my $line (split /\n/, $packages) {
        next unless $line =~ /^(\S+) (\S+)$/;
        if ($1 eq 'gpg-pubkey') { $keys++ } else { $packages{$1} = $2 }
    }
    my $result = { rc => $rc, output => $output, packages => \%packages, keys => $keys,
      vendor_preserved => read_text("$run/repos/openEuler.repo") eq $vendor,
      dnf => [map { decode_json($_) } split /\n/, read_text("$run/dnf")], rpm => read_text("$run/rpm") };
    if (my $evidence = $ENV{XCAT_TEST_EVIDENCE}) {
        make_path($evidence);
        write_text("$evidence/" . ++$case_index . "-$caller.json", encode_json({ %$result, options => \%options }) . "\n");
    }
    return $result;
}

sub capture {
    my (@command) = @_;
    my $pid = open(my $pipe, '-|');
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        open(STDERR, '>&', STDOUT) or die "stderr: $!";
        exec @command;
        die "exec: $!";
    }
    my $output = do { local $/; <$pipe> } // '';
    close($pipe);
    return ($? >> 8, $output);
}

sub read_text {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $file, '<', $path) or die "read $path: $!";
    return do { local $/; <$file> };
}

sub write_text {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or die "write $path: $!";
    print {$file} $text or die "write $path: $!";
    close($file) or die "close $path: $!";
}
