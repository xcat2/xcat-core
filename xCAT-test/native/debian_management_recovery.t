#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use File::Slurper qw(read_binary write_binary);
use XCAT::Test::Lifecycle;

plan skip_all => 'Run as an ordinary user on Debian or Ubuntu'
    unless $^O eq 'linux' && $< != 0 && -f '/etc/debian_version';
my $deb = XCAT::Test::Lifecycle::build_deb('xCAT');
my $fault = tempdir(CLEANUP => 1);
XCAT::Test::Lifecycle::checked('dpkg-deb', '-R', $deb, "$fault/package");
write_binary("$fault/package/DEBIAN/preinst", "#!/bin/sh\nexit 17\n");
chmod 0755, "$fault/package/DEBIAN/preinst" or die "chmod failing preinst: $!";
XCAT::Test::Lifecycle::checked('dpkg-deb', '--root-owner-group', '-b', "$fault/package", "$fault/failure.deb");
for my $script (qw(preinst postinst postrm)) {
    unlink "$fault/package/DEBIAN/$script" or die "remove legacy fixture script: $!"
        if -f "$fault/package/DEBIAN/$script";
}
my $control = read_binary("$fault/package/DEBIAN/control");
$control =~ s/^Version:.*$/Version: 2.0/m or die 'legacy fixture has no Version';
write_binary("$fault/package/DEBIAN/control", $control);
XCAT::Test::Lifecycle::checked('dpkg-deb', '--root-owner-group', '-b', "$fault/package", "$fault/legacy.deb");

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag "$result[1]$result[2]";
}

sub management_root {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/opt/xcat/share/xcat/scripts/xHRM', '');
    $root->write('/opt/xcat/sbin/xcatconfig', <<'SH', oct('755'));
#!/bin/sh
printf '%s\n' "$*" >> /config-calls
if [ -f /config-fail ]; then exit 17; fi
SH
    $root->write('/etc/init.d/apache2', <<'SH', oct('755'));
#!/bin/sh
if [ -f /apache-fail ]; then exit 19; fi
SH
    $root->write('/config-calls', '');
    return $root;
}

for my $case (qw(fresh-retry fresh-reinstall fresh-abort-retry fresh-legacy-return removed-fresh-retry removed-fresh-abort removed-fresh-legacy-return upgrade-retry apache-retry cleared-tmp
                 failed-remove failed-purge abort-remove abort-retry)) {
    subtest $case => sub {
        my $root = management_root();
        if ($case !~ /^fresh/) {
            succeeds('install the previous package', $root->install_deb(
                $case eq 'removed-fresh-legacy-return' ? "$fault/legacy.deb" : $deb));
        }
        if ($case =~ /^removed-fresh/) {
            succeeds('remove the configured package but keep its conffiles',
                $root->run('dpkg', '--force-depends', '--remove', 'xcat'));
        }
        my $fresh_install = $case =~ /^(?:fresh|removed-fresh)/;
        my $remove_after_failure = $case =~ /^(?:failed|abort)-(?:remove|purge)$/;
        $root->write('/config-calls', '');
        $root->write($case eq 'apache-retry' ? '/apache-fail' : '/config-fail', '')
            unless $case =~ /^abort/;
        my ($status, $out, $err) = $root->install_deb($case =~ /^abort/ ? "$fault/failure.deb" : $deb);
        isnt($status, 0, 'the injected transaction failure reaches dpkg');
        like($err, $case =~ /^abort/ ? qr/pre-installation script.*exit status 17/
            : $case eq 'apache-retry' ? qr/post-installation script.*exit status 19/
            : qr/post-installation script.*exit status 17/, 'failure comes from the intended boundary');
        is($root->read('/config-calls'), $case =~ /^abort/ ? ''
            : $fresh_install ? "-i\n" : "-u -V\n", 'the first attempt uses the intended configuration mode');
        unlink $root->path('/config-fail') if -f $root->path('/config-fail');
        unlink $root->path('/apache-fail') if -f $root->path('/apache-fail');
        if ($case eq 'fresh-abort-retry' || $case eq 'removed-fresh-abort') {
            my ($aborted, $out, $err) = $root->install_deb("$fault/failure.deb");
            isnt($aborted, 0, 'a later unpack can also fail before fresh configuration succeeds');
            like($err, qr/pre-installation script.*exit status 17/, 'the later failure reaches the intended preinst');
        }
        if ($case =~ /legacy-return$/) {
            succeeds('configure an older package without context hooks', $root->install_deb("$fault/legacy.deb"));
        }
        if ($case eq 'cleared-tmp') {
            unlink $root->path('/tmp/xCAT_upgrade.tmp') or die "clear temporary marker: $!";
        }
        $root->write('/config-calls', '');
        for my $service (qw(installservice udpservice mainservice)) {
            $root->write("/tmp/xcat/$service.pid", "$service\n");
        }
        my $fresh = $case eq 'fresh-retry' || $remove_after_failure;
        if ($remove_after_failure) {
            succeeds('remove the failed transaction', $root->run('dpkg', '--force-depends',
                $case eq 'failed-purge' ? '--purge' : '--remove', 'xcat'));
            succeeds('reinstall after removal', $root->install_deb($deb));
        } elsif ($case =~ /reinstall|abort|legacy-return|removed-fresh/) {
            succeeds('retry the package transaction', $root->install_deb($deb));
        } else {
            succeeds('retry configuration through dpkg',
                $root->run('dpkg', '--force-depends', '--configure', 'xcat'));
        }
        is($root->read('/config-calls'), $fresh ? "-i\n" : "-u -V\n",
            'configure retry retains context and a new transaction follows dpkg mode');
        for my $service (qw(installservice udpservice mainservice)) {
            my $directory = $fresh ? '/tmp/xcat' : '/var/run/xcat';
            my $file = "$directory/$service.pid";
            is(-f $root->path($file) ? $root->read($file) : undef,
                "$service\n", 'PID relocation follows the recovered mode');
        }
        ok(!-e $root->path('/var/lib/xcat/configure-state'), 'successful configuration clears persistent transaction state');
        ok(!-e $root->path('/tmp/xCAT_upgrade.tmp'), 'successful configuration clears the legacy marker');
        succeeds('the package is configured', $root->run('/bin/sh', '-c',
            q{test "$(dpkg-query -W -f='${Status}' xcat)" = 'install ok installed'}));
    };
}

for my $case (qw(unpacked-reinstall unpacked-abort legacy-unpacked-reinstall upgrade-unpacked-marker-loss)) {
    subtest $case => sub {
        my $root = management_root();
        my $upgrade = $case eq 'upgrade-unpacked-marker-loss';
        succeeds('configure the package before an unpacked upgrade', $root->install_deb($deb)) if $upgrade;
        $root->write('/config-calls', '');
        local $root->{deb} = $case eq 'legacy-unpacked-reinstall' ? "$fault/legacy.deb" : $deb;
        succeeds('unpack without configuring the package',
            $root->run('dpkg', '--force-depends', '--unpack', '/package.deb'));
        is($root->read('/config-calls'), '', 'unpack does not run configuration');
        if ($upgrade) {
            unlink $root->path('/tmp/xCAT_upgrade.tmp') or die "clear temporary marker: $!";
        }
        if ($case eq 'unpacked-abort') {
            my ($status, $out, $err) = $root->install_deb("$fault/failure.deb");
            isnt($status, 0, 'an unpacked retry can fail');
            like($err, qr/pre-installation script.*exit status 17/, 'the retry fails at the intended preinst');
        }
        for my $service (qw(installservice udpservice mainservice)) {
            $root->write("/tmp/xcat/$service.pid", "$service\n");
        }
        if ($case eq 'unpacked-abort') {
            succeeds('configure after the aborted unpacked retry',
                $root->run('dpkg', '--force-depends', '--configure', 'xcat'));
        } else {
            succeeds('repeat the unpacked transaction and configure', $root->install_deb($deb));
        }
        is($root->read('/config-calls'), $upgrade ? "-u -V\n" : "-i\n",
            'never-configured packages stay fresh and unpacked upgrades retain context');
        for my $service (qw(installservice udpservice mainservice)) {
            my $directory = $upgrade ? '/var/run/xcat' : '/tmp/xcat';
            my $file = "$directory/$service.pid";
            is(-f $root->path($file) ? $root->read($file) : undef,
                "$service\n", 'PID relocation follows the pending configuration');
        }
        ok(!-e $root->path('/var/lib/xcat/configure-state'), 'configuration clears persistent transaction state');
        ok(!-e $root->path('/tmp/xCAT_upgrade.tmp'), 'configuration clears the legacy marker');
    };
}

for my $parent_mode (undef, oct('750')) {
    subtest defined $parent_mode ? 'existing state parent' : 'new state parent' => sub {
        my $root = XCAT::Test::Lifecycle->new;
        if (defined $parent_mode) {
            $root->write('/var/lib/xcat/retained', 'unrelated state');
            chmod $parent_mode, $root->path('/var/lib/xcat') or die "chmod parent: $!";
        }
        local $root->{deb} = $deb;
        succeeds('unpack the management control scripts', $root->run('dpkg-deb', '-e', '/package.deb', '/tmp/control'));
        succeeds('record a fresh transaction with a normal umask', $root->run('/bin/sh', '-c',
            'umask 022; /bin/sh /tmp/control/preinst install'));
        is((stat($root->path('/var/lib/xcat')))[2] & oct('7777'), $parent_mode // oct('755'),
            'the shared parent retains its intended permissions');
        is((stat($root->path('/var/lib/xcat/configure-state')))[2] & oct('7777'), oct('700'),
            'transaction directory is private');
        is((stat($root->path('/var/lib/xcat/configure-state/context')))[2] & oct('7777'), oct('600'),
            'transaction context is private');
        $root->write('/var/lib/xcat/configure-state/context', "invalid\n");
        my ($status, $out, $err) = $root->deb_script($deb, 'postinst', 'configure', '2.0');
        isnt($status, 0, 'invalid context stops configuration');
        like($err, qr{Invalid xCAT configuration context in /var/lib/xcat/configure-state/context},
            'the diagnostic identifies the invalid file');
        $root->write('/tmp/xCAT_upgrade.tmp', '');
        succeeds('a new upgrade replaces stale context', $root->deb_script($deb, 'preinst', 'upgrade', '2.0'));
    };
}

done_testing;
