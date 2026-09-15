#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

plan skip_all => 'requires Linux root and a private mount namespace'
  unless $^O eq 'linux' && $> == 0
  && system('unshare', '--mount', '--propagation', 'private', '/bin/true') == 0;
plan skip_all => 'requires the native DNF executable'
  unless -x '/usr/bin/dnf' && -d '/etc/yum.repos.d';

my $postscripts = File::Spec->rel2abs("$FindBin::Bin/../../xCAT/postscripts");
unless (-x "$postscripts/otherpkgs") {
    require xCAT::TableUtils;
    $postscripts = xCAT::TableUtils->getInstallDir() . '/postscripts';
}

my $dir = tempdir(CLEANUP => 1);
make_path("$dir/bin");
write_text("$dir/bin/dnf", <<'SH');
#!/bin/sh
printf '%s\n' "$*" >> "$DNF_TRACE"
case " $* " in
    *" list "*) exit "$DNF_LIST_RC" ;;
    *" install "*) exit "$DNF_INSTALL_RC" ;;
esac
exit 0
SH
write_text("$dir/bin/rpm", <<'SH');
#!/bin/sh
case "$1" in
    --version) echo 'RPM version 4.18.2'; exit 0 ;;
esac
printf '%s\n' "$*" >> "$RPM_TRACE"
exit 1
SH
for my $name (qw(logger mount)) {
    write_text("$dir/bin/$name", "#!/bin/sh\nexit 0\n");
}
write_text("$dir/bin/dpkg", "#!/bin/sh\nexit 1\n");
write_text("$dir/bin/wget", "#!/bin/sh\nprintf 'wget\\n' >> \"\$RPM_TRACE\"\nexit 1\n");
chmod 0755, glob("$dir/bin/*");
my $wrapper = "$dir/run";
write_text($wrapper, <<'SH');
#!/bin/bash
set -e
/bin/mount --bind "$TEST_REPOS" /etc/yum.repos.d
exec "$@"
SH
chmod 0755, $wrapper;
write_text("$dir/bash-env", <<'SH');
echo()
{
    case "$*" in
        'Warning: the packages '*fallback*|'Warning: the packages '*falling\ back*)
            printf 'direct RPM fallback\n' >> "$RPM_TRACE"
            builtin echo "$@"
            exit 81
            ;;
    esac
    builtin echo "$@"
}
SH

for my $caller (qw(ospkgs otherpkgs)) {
    for my $os (qw(openeuler20.03sp4 openeuler22.03sp4 openeuler24.03sp1 openeuler24.03sp3 openeuler24.03sp4 openeuler24.03 rhels9.6)) {
        my ($rc, $output, $repos, $dnf, $rpm) = run_case($caller, $os, 0, 0);
        is($rc, 0, "$caller $os completes its package operation") or diag($output);
        like($dnf, qr/\binstall .*native-test/, "$caller $os reaches package installation");
        if ($os =~ /^openeuler/) {
            like($repos, qr/baseurl=http:\/\/192\.0\.2\.1:8080\/install\/\Q$os\E\/x86_64\n/,
                "$caller $os keeps the native package directory");
            unlike($repos, qr/(?:BaseOS|AppStream)/, "$caller $os does not invent EL subrepositories");
            unlike($repos, qr/gpgcheck=0|skip_if_unavailable=True/, "$caller $os requires signatures and available repositories");
            like($dnf, qr/--setopt=strict=1 --setopt=\*\.skip_if_unavailable=False --setopt=\*\.gpgcheck=1/,
                "$caller $os makes DNF reject missing packages and unavailable repositories");
            if ($caller eq 'otherpkgs') {
                like($repos, qr{gpgkey=http://192\.0\.2\.1:8080/install/otherpkgs/native/repodata/repomd\.xml\.key},
                    "$caller $os uses the declared native package repository key");
            }
        } else {
            like($repos, qr/gpgcheck=0\nskip_if_unavailable=True/, "$caller preserves existing EL repository policy");
            unlike($dnf, qr/--setopt=strict/, "$caller preserves existing EL package command");
            like($repos, qr{/BaseOS\n}, "$caller preserves the EL BaseOS path");
            like($repos, qr{/AppStream\n}, "$caller preserves the EL AppStream path");
        }
        is($rpm, '', "$caller $os does not invoke direct RPM or recursive package download");
    }
    my ($rc, $output) = run_case($caller, 'openeuler24.03sp3', 0, 23);
    is($rc, 23, "$caller propagates a native DNF install failure") or diag($output);
}
my ($rc, $output, $repos, $dnf, $rpm) = run_case('otherpkgs', 'openeuler24.03sp3', 1, 0);
isnt($rc, 0, 'an unresolved native package fails the complete otherpkgs postscript');
like($output, qr/required native package native-test could not be resolved/, 'the unresolved package is identified');
unlike($dnf, qr/\b(?:upgrade|install)\b/, 'resolution failure stops before package mutation');
is($rpm, '', 'resolution failure does not fall back to unsigned direct RPM installation');

for my $empty (0, 1) {
    my ($rc, $output, $repos, $dnf, $rpm) = run_case('otherpkgs', 'openeuler24.03sp3', 0, 0, 1, $empty);
    my $label = $empty ? 'repository-only without extra packages' : 'repository-only with extra packages';
    is($rc, 0, "$label completes") or diag($output);
    like($repos, qr{baseurl=http://192\.0\.2\.1:8080/install/openeuler24\.03sp3/x86_64\n},
        "$label writes the native OS repository");
    unlike($repos, qr/gpgcheck=0|skip_if_unavailable=True/, "$label retains native repository policy");
    unlike($dnf, qr/\b(?:install|upgrade)\b/, "$label does not install or upgrade packages");
    unlike($output, qr/unary operator expected|integer expression expected/, "$label has no missing-index arithmetic error");
    is($rpm, '', "$label does not fall back to direct RPM installation");
}

done_testing();

sub run_case {
    my ($caller, $os, $list_rc, $install_rc, $repoonly, $empty) = @_;
    my $run = tempdir(DIR => $dir, CLEANUP => 1);
    make_path("$run/repos");
    local %ENV = %ENV;
    delete @ENV{qw(BASH_ENV ENV ENVLIST OTHERPKGDIR_INTERNET KERNELDIR SDKDIR NODESETSTATE OSPKGDIR VERBOSE)};
    @ENV{qw(PATH TEST_REPOS DNF_TRACE RPM_TRACE DNF_LIST_RC DNF_INSTALL_RC)} =
      ("$dir/bin:$ENV{PATH}", "$run/repos", "$run/dnf", "$run/rpm", $list_rc, $install_rc);
    $ENV{BASH_ENV} = "$dir/bash-env";
    @ENV{qw(OSVER ARCH MASTER NFSSERVER HTTPPORT INSTALLDIR UPDATENODE)} =
      ($os, 'x86_64', '192.0.2.1', '192.0.2.1', 8080, '/install', 1);
    @ENV{qw(OSPKGS OTHERPKGDIR OTHERPKGS_INDEX OTHERPKGS1)} =
      ('native-test', '/install/otherpkgs', 1, 'native/native-test');
    delete @ENV{qw(OTHERPKGS_INDEX OTHERPKGS1)} if $empty;
    my $pid = open(my $pipe, '-|');
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        chdir($run) or die "chdir: $!";
        open(STDERR, '>&', STDOUT) or die "stderr: $!";
        exec 'unshare', '--mount', '--propagation', 'private', $wrapper,
          "$postscripts/$caller", ($repoonly ? '--repoonly' : ());
        die "exec: $!";
    }
    my $output = do { local $/; <$pipe> } // '';
    close($pipe);
    my $rc = $? >> 8;
    my $repos = join('', map { read_text($_) } sort glob("$run/repos/*.repo"));
    return ($rc, $output, $repos, -f "$run/dnf" ? read_text("$run/dnf") : '',
        -f "$run/rpm" ? read_text("$run/rpm") : '');
}

sub read_text {
    my ($path) = @_;
    open(my $file, '<', $path) or die "read $path: $!";
    return do { local $/; <$file> };
}

sub write_text {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or die "write $path: $!";
    print {$file} $text or die "write $path: $!";
    close($file) or die "close $path: $!";
}
