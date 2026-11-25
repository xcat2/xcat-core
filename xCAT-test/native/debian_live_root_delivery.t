#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(read_binary write_binary);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Lifecycle;
use XCAT::Test::Process qw(run_command);

plan skip_all => 'Run as an ordinary user on Debian or Ubuntu'
    unless $^O eq 'linux' && $< != 0 && -f '/etc/debian_version';
my $work = tempdir(CLEANUP => 1);
make_path(map { "$work/$_" } qw(source home bin capture));
for my $entry (qw(.gitignore builddebs.pl build-utils Version Release perl-xCAT xCAT-server xCATsn)) {
    XCAT::Test::Lifecycle::checked('cp', '-a', repo_path($entry), "$work/source/");
}
XCAT::Test::Lifecycle::checked('git', 'init', '-b', 'master', "$work/source");
XCAT::Test::Lifecycle::checked('git', '-C', "$work/source", 'add', '-A');
write_binary("$work/bin/dpkg-buildpackage", <<'SH');
#!/bin/sh
set -eu
case "${XCAT_TEST_FAIL_BUILD:-}" in
    yes) exit 27 ;;
    dangling)
        rm debian/xcat-live-root-functions
        ln -s absent-helper debian/xcat-live-root-functions
        exit 27 ;;
    directory)
        rm debian/xcat-live-root-functions
        mkdir debian/xcat-live-root-functions
        exit 27 ;;
    TERM|KILL)
        kill -"$XCAT_TEST_FAIL_BUILD" "$XCAT_TEST_BUILDER_PID"
        exit 27 ;;
    capture)
        cp debian/xcat-live-root-functions "$XCAT_TEST_CAPTURE"
        exit 27 ;;
esac
/usr/bin/dpkg-buildpackage "$@"
destination="$XCAT_SOURCE_CAPTURE/${PWD##*/}"
mkdir -p "$destination"
cp ../*.dsc ../*.tar.gz "$destination/"
SH
chmod oct('0755'), "$work/bin/dpkg-buildpackage" or die "chmod wrapper: $!";
{
    local %ENV = (%ENV, HOME => "$work/home", SOURCE_DATE_EPOCH => 1750000000,
        PATH => "$work/bin:/usr/bin:/bin", LC_ALL => 'C', XCAT_SOURCE_CAPTURE => "$work/capture");
    my ($status, $output) = run_command($^X, "$work/source/builddebs.pl",
        '--package', 'perl-xCAT', '--package', 'xCAT-server', '--package', 'xCATsn',
        '--dist', 'noble', '--release', 'test1', '--dest', "$work/output");
    is($status, 0, 'builds all three packages through the production Debian builder') or diag $output;
    die 'package build failed' if $status;
}

for my $package (qw(xCAT-server xCATsn)) {
    subtest "$package standalone source export" => sub {
        my $link = "$work/source/$package/debian/xcat-live-root-functions";
        ok(-l $link, 'the checkout retains its shared source link after building');
        is(readlink($link), '../../perl-xCAT/debian/xcat-live-root-functions',
            'the checkout link still names the original source');
        my @sources = glob "$work/capture/$package/*.dsc";
        is(scalar @sources, 1, 'captures one source package') or return;
        my $extracted = "$work/capture/$package/extracted";
        XCAT::Test::Lifecycle::checked('dpkg-source', '--no-check', '-x', $sources[0], $extracted);
        ok(-f "$extracted/debian/xcat-live-root-functions" && !-l "$extracted/debian/xcat-live-root-functions",
            'source export carries a regular helper without sibling packages');
        is(read_binary("$extracted/debian/xcat-live-root-functions"),
            read_binary("$work/source/perl-xCAT/debian/xcat-live-root-functions"),
            'the exported helper preserves the canonical bytes');
        my $rebuilt = XCAT::Test::Lifecycle::build_deb('extracted', "$work/capture/$package");
        for my $live (0, 1) {
            my $root = XCAT::Test::Lifecycle->new;
            $root->{live} = $live;
            $root->write('/calls', '');
            my ($script, @args);
            if ($package eq 'xCAT-server') {
                $script = 'prerm';
                @args = ('remove');
                local $root->{deb} = $rebuilt;
                my @unpack = $root->run('/bin/sh', '-ec',
                    'dpkg-deb -x /package.deb /unpacked; mkdir -p /opt/xcat/share/xcat; ' .
                    'cp -a /unpacked/opt/xcat/share/xcat/scripts /opt/xcat/share/xcat/');
                is($unpack[0], 0, 'stage the rebuilt runtime helpers') or diag "$unpack[1]$unpack[2]";
                $root->record_command('/test-bin/systemctl');
                $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=24.04\n");
                $root->write('/run/systemd/system/.fixture', '') if $live;
            } else {
                $script = 'postinst';
                @args = ('configure');
                $root->record_command('/test-bin/update-rc.d');
                $root->record_command('/etc/init.d/apache2');
                $root->record_command('/etc/init.d/xcatd');
                $root->record_command('/test-bin/a2enmod');
                $root->write('/etc/apache2/conf-enabled/.fixture', '');
            }
            my ($status, $out, $err) = $root->deb_script($rebuilt, $script, @args);
            is($status, 0, 'rebuilt control script executes without a sibling source helper') or diag "$out$err";
            unlike("$out$err", qr/not found/, 'the rebuilt script has no missing command');
            if (!$live) {
                unlike($root->read('/calls'), qr/(?:<start>|<stop>|<reload>|<--now>)/,
                    'the rebuilt script performs no live service action in an offline root');
            } elsif ($package eq 'xCAT-server') {
                like($root->read('/calls'), qr/^systemctl <stop> <xcatd\.service>$/m,
                    'rebuilt removal stops xcatd in a live root');
                like($root->read('/calls'), qr/^systemctl <disable> <--now> <xcat-uftp-listener\.service>$/m,
                    'rebuilt removal stops the live UFTP listener');
            } else {
                like($root->read('/calls'), qr/^xcatd <start>$/m,
                    'rebuilt service-node configuration starts xcatd in a live root');
                like($root->read('/calls'), qr/^apache2 <reload>$/m,
                    'rebuilt service-node configuration reloads Apache in a live root');
            }
        }
    };
}

for my $failure (qw(yes dangling directory)) {
    subtest "failed build cleanup ($failure)" => sub {
        my $link = "$work/source/xCAT-server/debian/xcat-live-root-functions";
        my $control = read_binary("$work/source/xCAT-server/debian/control");
        my $changelog = read_binary("$work/source/xCAT-server/debian/changelog");
        local %ENV = (%ENV, HOME => "$work/home", SOURCE_DATE_EPOCH => 1750000000,
            PATH => "$work/bin:/usr/bin:/bin", LC_ALL => 'C', XCAT_TEST_FAIL_BUILD => $failure);
        my ($status, $output) = run_command($^X, "$work/source/builddebs.pl",
            '--package', 'xCAT-server', '--dist', 'noble', '--release', 'test2',
            '--dest', "$work/failed-output");
        isnt($status, 0, 'the package build failure reaches the caller');
        like($output, qr/dpkg-buildpackage failed/, 'failure comes from the package builder');
        if ($failure eq 'directory') {
            like($output, qr/Cannot restore link/, 'a blocked restoration is also reported');
            rmdir $link or die "remove obstructing fixture directory: $!";
        } else {
            is(readlink($link), '../../perl-xCAT/debian/xcat-live-root-functions',
                'failure restores the shared source link');
        }
        is(read_binary("$work/source/xCAT-server/debian/control"), $control,
            'failure restores dependency metadata');
        is(read_binary("$work/source/xCAT-server/debian/changelog"), $changelog,
            'failure restores the changelog');
        if ($failure eq 'directory') {
            ok(-l "$work/source/.xCAT-server-live-root.build-link", 'blocked cleanup retains the recovery record');
            $ENV{XCAT_TEST_FAIL_BUILD} = 'capture';
            $ENV{XCAT_TEST_CAPTURE} = "$work/directory-recovered-helper";
            my ($retry, $message) = run_command($^X, "$work/source/builddebs.pl",
                '--package', 'xCAT-server', '--dist', 'noble', '--release', 'test2',
                '--dest', "$work/failed-output");
            isnt($retry, 0, 'the recovery build reaches the requested builder failure');
            like($message, qr/dpkg-buildpackage failed/, 'the next build gets past source recovery');
            if (ok(-f "$work/directory-recovered-helper", 'recovery supplies a helper to the next package build')) {
                is(read_binary("$work/directory-recovered-helper"),
                    read_binary("$work/source/perl-xCAT/debian/xcat-live-root-functions"),
                    'directory-fault recovery stages the canonical bytes');
            }
            ok(-l $link && !-l "$work/source/.xCAT-server-live-root.build-link",
                'the directory-fault case leaves source sharing restored');
        }
    };
}

for my $case ([TERM => 0], [KILL => 0], [KILL => 1]) {
    my ($signal, $discard_record) = @{$case};
    subtest "SIG$signal recovery (discard record=$discard_record)" => sub {
        my $source = tempdir(DIR => $work, CLEANUP => 1);
        XCAT::Test::Lifecycle::checked('cp', '-a', "$work/source/.", $source);
        my $link = "$source/xCAT-server/debian/xcat-live-root-functions";
        my $record = '.xCAT-server-live-root.build-link';
        ok(-l $link, 'the signal case starts with a shared source link') or return;
        ok(!-e "$source/$record" && !-l "$source/$record", 'the signal case starts without recovery residue') or return;
        local %ENV = (%ENV, HOME => "$work/home", SOURCE_DATE_EPOCH => 1750000000,
            PATH => "$work/bin:/usr/bin:/bin", LC_ALL => 'C', XCAT_TEST_FAIL_BUILD => $signal);
        my @builder = ($^X, "$source/builddebs.pl", '--package', 'xCAT-server',
            '--dist', 'noble', '--release', 'test3', '--dest', "$work/cancelled-output");
        my ($status, $out, $err) = XCAT::Test::Lifecycle::command('/bin/sh', '-c',
            'export XCAT_TEST_BUILDER_PID=$$; exec "$@"', 'cancel-test', @builder);
        is($status, $signal eq 'TERM' ? 143 : 137, 'the real builder ends with the requested signal')
            or diag "$out$err";
        ok(-f $link && !-l $link, 'the interruption leaves a materialized helper');
        ok(-l "$source/$record", 'the interruption retains the source-link record');
        XCAT::Test::Lifecycle::checked('git', '-C', $source, 'clean', $discard_record ? '-fdx' : '-fd', '--', $record);
        is(-l "$source/$record" ? 1 : 0, $discard_record ? 0 : 1,
            'ordinary Git cleanup preserves recovery; forced ignored-file cleanup removes it');
        my $canonical = "$source/perl-xCAT/debian/xcat-live-root-functions";
        my $refreshed = read_binary($canonical) . "# refreshed after $signal\n";
        write_binary($canonical, $refreshed);
        $ENV{XCAT_TEST_FAIL_BUILD} = 'capture';
        $ENV{XCAT_TEST_CAPTURE} = "$work/resumed-helper";
        unlink "$work/resumed-helper" or die "remove previous capture: $!" if -e "$work/resumed-helper";
        my ($resume_status, $output) = run_command(@builder);
        if ($discard_record) {
            isnt($resume_status, 0, 'a stale copy with no recovery record fails closed');
            like($output, qr/stale live-root helper/, 'the diagnostic identifies the stale source copy');
            ok(!-e "$work/resumed-helper", 'stale bytes never reach the package tools');
            return;
        }
        isnt($resume_status, 0, 'the resumed build reaches the deliberate builder failure');
        like($output, qr/dpkg-buildpackage failed/, 'the resumed build acquires its lock and reaches the builder');
        ok(-f "$work/resumed-helper", 'the resumed build delivers a helper to the package tools') or return;
        is(read_binary("$work/resumed-helper"), $refreshed,
            'the next build consumes the current canonical helper, not the interrupted copy');
        is(readlink($link),
            '../../perl-xCAT/debian/xcat-live-root-functions', 'recovery restores source sharing');
        ok(!-e "$source/$record" && !-l "$source/$record", 'recovery consumes its record');
    };
}

done_testing;
