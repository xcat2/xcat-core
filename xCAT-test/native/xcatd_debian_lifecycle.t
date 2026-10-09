#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(write_binary);
use Digest::MD5 qw(md5_hex);
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::Lifecycle;
use XCAT::Test::File qw(slurp_repo_file);

plan skip_all => 'Run on Linux with dpkg-buildpackage; other missing prerequisites fail'
    unless $^O eq 'linux' && -x '/usr/bin/dpkg-buildpackage';
my $deb = XCAT::Test::Lifecycle::build_deb('xCAT-server');
my $version = XCAT::Test::Lifecycle::checked('dpkg-deb', '-f', $deb, 'Version');
chomp $version;
my $template = slurp_repo_file('xCAT-server/etc/init.d/xcatd');
my $depends = XCAT::Test::Lifecycle::checked('dpkg-deb', '-f', $deb, 'Depends');
my @dependencies = split /\s*,\s*/, $depends;
ok(grep(/^ucf(?:\s*\([^)]+\))?\s*$/, @dependencies), 'built package requires ucf');

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag($result[1] . $result[2]);
}

for my $mode (qw(systemd legacy explicit-legacy unknown)) {
    subtest "$mode package lifecycle" => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->write('/etc/os-release', $mode eq 'systemd' ? "ID=ubuntu\nVERSION_ID=\"24.04\"\n"
            : $mode eq 'legacy' ? "ID=ubuntu\nVERSION_ID=\"14.04\"\n" : "ID=fixture\n");
        $root->write('/sbin/init', '', 0755) if $mode eq 'explicit-legacy';
        my $modern = $mode eq 'systemd' || $mode eq 'unknown';
        succeeds('fresh package transaction', $root->install_deb($deb));
        my %checksums = map { reverse split /\s+/, $_ } split /\n/,
            $root->read('/opt/xcat/share/xcat/scripts/xcatd.md5sum');
        is($checksums{'2.17.0'}, '0b1eea60994ff79faa9a8d0bcd53c558', 'package recognizes the pre-transition template');
        is($checksums{'2.18.0'}, '8797eef6731719e0eacff59612b3e916', 'package recognizes the 2.18.0 template');
        ok(grep($_ eq md5_hex($template), values %checksums), 'package recognizes its current legacy template');
        my $init = $root->path('/etc/init.d/xcatd');
        if ($modern) {
            ok(!-e $init && !-l $init, 'systemd target has no legacy script');
            ok(-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'fresh service is enabled');
            $root->record_command('/opt/xcat/sbin/xcatd');
            succeeds('execute installed unit start command', $root->start_unit('/usr/lib/systemd/system/xcatd.service'));
            is($root->read('/calls'), "xcatd <-p> </run/xcatd.pid>\n", 'unit starts the daemon without a legacy script');
            succeeds('disable service', $root->run('systemctl', 'disable', 'xcatd.service'));
        } else {
            is($root->read('/etc/init.d/xcatd'), $template, 'legacy template installed');
            ok(-x $init, 'legacy script is executable');
            succeeds('disable legacy service', $root->run('update-rc.d', 'xcatd', 'disable'));
            $root->write('/etc/init.d/xcatd', "$template\n# local configuration\n", 0755);
        }
        succeeds('upgrade transaction', $root->install_deb($deb));
        if ($modern) {
            ok(!-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'upgrade keeps disabled state');
            ok(!-e $root->path('/var/lib/xcat/xcatd-init-state/context'), 'reconfiguration has no preinst context');
            succeeds('reconfigure the installed package', $root->deb_script($deb, 'postinst', 'configure', $version));
            ok(!-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'reconfiguration preserves administrator disablement');
            succeeds('mask service', $root->run('systemctl', 'mask', 'xcatd.service'));
            succeeds('upgrade masked service', $root->install_deb($deb));
            is(readlink($root->path('/etc/systemd/system/xcatd.service')), '/dev/null', 'upgrade keeps mask');
        } else {
            is($root->read('/etc/init.d/xcatd'), "$template\n# local configuration\n", 'upgrade keeps administrator edits');
            my @enabled = glob $root->path('/etc/rc[2345].d/S*xcatd');
            is(scalar @enabled, 0, 'upgrade keeps disabled runlevels');
            my @disabled = glob $root->path('/etc/rc[2345].d/K*xcatd');
            ok(@disabled, 'upgrade retains disabled registration');
        }
        ok(!-e $root->path('/var/lib/xcat/xcatd-init-state/context'), 'successful configuration clears transaction context');
        if ($modern) {
            succeeds('unmask before removal', $root->run('systemctl', 'unmask', 'xcatd.service'));
            succeeds('enable before removal', $root->run('systemctl', 'enable', 'xcatd.service'));
            ok(-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'removal starts with an enabled service');
        }
        succeeds('remove package', $root->run('dpkg', '--force-depends', '--remove', 'xcat-server'));
        ok(!-e $root->path('/usr/sbin/xcatd') && !-l $root->path('/usr/sbin/xcatd'), 'remove clears daemon link');
        ok(!-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'remove clears systemd registration');
        my @registration = glob $root->path('/etc/rc?.d/[SK]??xcatd');
        is_deeply(\@registration, [], 'remove clears legacy registration');
        for my $suffix (qw(ucf-old ucf-new ucf-dist dpkg-bak dpkg-backup dpkg-remove)) {
            $root->write("/etc/init.d/xcatd.$suffix", 'backup fixture');
        }
        $root->write('/tmp/ucf-template', 'registered fixture');
        succeeds('register a ucf checksum', $root->run('ucf', '/tmp/ucf-template', '/etc/init.d/xcatd'));
        succeeds('register ucf ownership', $root->run('ucfr', 'xcat-server', '/etc/init.d/xcatd'));
        succeeds('purge package', $root->run('dpkg', '--purge', 'xcat-server'));
        ok(!-e $init && !-l $init, 'purge clears legacy configuration');
        ok(!-e $root->path('/var/lib/xcat/xcatd-init-state/state'), 'purge clears durable transition state');
        my @backups = glob $root->path('/etc/init.d/xcatd.*');
        is_deeply(\@backups, [], 'purge removes conffile backup artifacts');
        for my $file (qw(hashfile registry)) {
            my $contents = -f $root->path("/var/lib/ucf/$file") ? $root->read("/var/lib/ucf/$file") : '';
            unlike($contents, qr{(?:^|\s)/etc/init\.d/xcatd(?:\s|$)}, "purge removes ucf $file entry");
        }
    };
}

subtest 'legacy conffile migration through dpkg' => sub {
    my $package = tempdir(CLEANUP => 1);
    make_path("$package/old/DEBIAN", "$package/old/etc/init.d");
    write_binary("$package/old/DEBIAN/control", "Package: xcat-server\nVersion: 2.0\nArchitecture: all\nMaintainer: xCAT <xcat-user\@lists.sourceforge.net>\nDescription: legacy init conffile fixture\n");
    write_binary("$package/old/DEBIAN/conffiles", "/etc/init.d/xcatd\n");
    write_binary("$package/old/etc/init.d/xcatd", $template);
    chmod 0755, "$package/old/etc/init.d/xcatd" or die "chmod: $!";
    XCAT::Test::Lifecycle::checked('dpkg-deb', '--root-owner-group', '--build', "$package/old", "$package/old.deb");
    for my $state (qw(enabled disabled unregistered deleted)) {
        subtest $state => sub {
            my $root = XCAT::Test::Lifecycle->new;
            $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=24.04\n");
            succeeds('install old conffile package', $root->install_deb("$package/old.deb"));
            if ($state eq 'deleted') {
                unlink $root->path('/etc/init.d/xcatd') or die "unlink: $!";
            } else {
                $root->write('/etc/init.d/xcatd', "$template\n# administrator edit\n", 0750);
            }
            if ($state eq 'enabled' || $state eq 'disabled') {
                make_path($root->path('/etc/rc3.d'));
                symlink '../init.d/xcatd', $root->path('/etc/rc3.d/' . ($state eq 'enabled' ? 'S' : 'K') . '85xcatd') or die "symlink: $!";
            }
            if ($state eq 'disabled' || $state eq 'unregistered') {
                $root->record_command('/usr/sbin/systemctl', '/host-usr/bin/systemctl');
            }
            succeeds('upgrade to native service package', $root->install_deb($deb));
            ok(!-e $root->path('/etc/init.d/xcatd'), 'modern target removes active legacy script');
            my $enabled = -l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service') ? 1 : 0;
            is($enabled, $state eq 'enabled' ? 1 : 0, 'migration preserves prior registration');
            like($root->read('/calls'), qr/^systemctl <disable> <xcatd\.service>$/m,
                'legacy migration requests disable through the real service tool') if $state eq 'disabled' || $state eq 'unregistered';
            if ($state ne 'deleted') {
                is($root->read('/var/lib/xcat/xcatd-init-state/xcatd'), "$template\n# administrator edit\n", 'migration stashes edited bytes');
            }
            $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=14.04\n");
            succeeds('return to legacy target', $root->install_deb($deb));
            if ($state eq 'deleted') {
                ok(!-e $root->path('/etc/init.d/xcatd'), 'administrator deletion survives return');
            } else {
                is($root->read('/etc/init.d/xcatd'), "$template\n# administrator edit\n", 'return restores administrator bytes');
                is((stat($root->path('/etc/init.d/xcatd')))[2] & 07777, 0750, 'return restores mode');
            }
        };
    }
};

for my $action (qw(abort-install abort-upgrade remove purge upgrade failed-upgrade disappear)) {
    subtest "postrm $action recovery" => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=14.04\n");
        my $state = '/var/lib/xcat/xcatd-init-state';
        for my $file (qw(state xcatd context context.tmp.123 pending-xcatd pending-deleted pending-enabled pending-xcatd.tmp.123)) {
            $root->write("$state/$file", "retained $file\n");
        }
        $root->write('/var/lib/xcat/xcatd-systemd-mode', 'retained marker');
        succeeds('complete maintainer script', $root->deb_script($deb, 'postrm', $action));
        my $retained = $action eq 'upgrade' || $action eq 'failed-upgrade' ? 1 : 0;
        for my $file (qw(context context.tmp.123)) {
            is(-e $root->path("$state/$file") ? 1 : 0, $retained, "$action $file retention");
        }
        is(-e $root->path('/var/lib/xcat/xcatd-systemd-mode') ? 1 : 0,
            $action eq 'purge' ? 0 : 1, 'systemd marker retention');
        for my $file (qw(state xcatd)) {
            is(-e $root->path("$state/$file") ? 1 : 0, $action eq 'purge' ? 0 : 1, "$file retention");
        }
        for my $file (qw(pending-xcatd pending-deleted pending-enabled pending-xcatd.tmp.123)) {
            is(-e $root->path("$state/$file") ? 1 : 0, $action eq 'purge' || $action eq 'abort-install' ? 0 : 1, "$file retention");
        }
    };
}

subtest 'abort-install removes an empty state directory' => sub {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=14.04\n");
    my $state = '/var/lib/xcat/xcatd-init-state';
    for my $file (qw(context context.tmp.123 pending-xcatd pending-enabled pending-deleted pending-xcatd.tmp.123)) {
        $root->write("$state/$file", 'aborted attempt');
    }
    succeeds('abort before durable state exists', $root->deb_script($deb, 'postrm', 'abort-install'));
    ok(!-e $root->path($state), 'abort-install removes the empty state directory');
};

subtest 'preinst failure preserves durable state' => sub {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=14.04\n");
    $root->write('/var/lib/xcat/xcatd-init-state/state', 'durable state');
    $root->write('/test-bin/mv', "#!/bin/sh\nexit 17\n", 0755);
    my ($status, $out, $err) = $root->deb_script($deb, 'preinst', 'install');
    isnt($status, 0, 'context rename failure fails the transaction');
    is($root->read('/var/lib/xcat/xcatd-init-state/state'), 'durable state', 'failure retains prior durable state');
    my @temporary = glob $root->path('/var/lib/xcat/xcatd-init-state/context.tmp.*');
    is(scalar @temporary, 0, 'failure removes context temporary');
};

for my $command (qw(cp mv)) {
    subtest "preinst cleans up after $command failure" => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=24.04\n");
        $root->write('/etc/init.d/xcatd', $template, 0750);
        my $partial = $command eq 'cp' ? 'printf partial > "$destination"' : ':';
        $root->write("/test-bin/$command", "#!/bin/sh\n" .
            'for destination; do :; done' . "\n" .
            'case "$destination" in /var/lib/xcat/xcatd-init-state/pending-xcatd*)' . "\n" .
            "$partial\nexit 17;;\nesac\nexec /host-usr/bin/$command \"\$\@\"\n", 0755);
        my ($status) = $root->deb_script($deb, 'preinst', 'upgrade', '2.18.0');
        isnt($status, 0, 'failed pending capture stops preinst');
        my @pending = glob $root->path('/var/lib/xcat/xcatd-init-state/pending-*');
        is_deeply(\@pending, [], 'failed pending capture removes partial evidence');
        is($root->read('/etc/init.d/xcatd'), $template, 'failed capture preserves administrator bytes');
        is((stat($root->path('/etc/init.d/xcatd')))[2] & 07777, 0750, 'failed capture preserves administrator mode');
    };
}

for my $helper (
    ['unsupported', "exit 2", 0],
    ['command-aware', undef, 0],
    ['malformed', "printf '%s\\n' malformed", 1],
    ['failure', "exit 7", 7],
) {
    subtest "preinst with $helper->[0] installed helper" => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=14.04\n");
        $root->write('/etc/init.d/xcatd', $template, 0755);
        make_path($root->path('/etc/rc.d/rc3.d'));
        symlink('/etc/init.d/xcatd', $root->path('/etc/rc.d/rc3.d/S85xcatd')) or die "symlink: $!";
        $root->write('/opt/xcat/share/xcat/scripts/xcatd-init-compat',
            defined $helper->[1] ? "#!/bin/sh\n$helper->[1]\n" : slurp_repo_file('xCAT-server/share/xcat/scripts/xcatd-init-compat'), 0755);
        my ($status, $out, $err) = $root->deb_script($deb, 'preinst', 'upgrade', '2.0');
        is($status, $helper->[2], 'complete preinst propagates the detector result') or diag "$out$err";
        if ($status == 0) {
            is($root->read('/var/lib/xcat/xcatd-init-state/pending-enabled'), "unregistered\n", 'RPM-only links do not enable a Debian service');
            is($root->read('/var/lib/xcat/xcatd-init-state/pending-xcatd'), $template, 'pre-unpack capture keeps the conffile');
            is((stat($root->path('/var/lib/xcat/xcatd-init-state/context')))[2] & 07777, 0600, 'context is private');
        }
    };
}

for my $suffix (qw(dpkg-bak dpkg-backup dpkg-remove)) {
    subtest "preinst recovers $suffix" => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=\"24.04\"\n");
        $root->write("/etc/init.d/xcatd.$suffix", "administrator recovery\n", 0750);
        succeeds('recover interrupted conffile transition', $root->deb_script($deb, 'preinst', 'upgrade', '2.18.0'));
        my $pending = '/var/lib/xcat/xcatd-init-state/pending-xcatd';
        ok(-f $root->path($pending), 'recovery stages the conffile backup');
        if (-f $root->path($pending)) {
            is($root->read($pending), "administrator recovery\n", 'recovery preserves backup bytes');
            is((stat($root->path($pending)))[2] & 07777, 0750, 'recovery preserves backup mode');
        }
    };
}

subtest 'obsolete conffile is package omission' => sub {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=\"24.04\"\n");
    $root->write('/var/lib/dpkg/status', $root->read('/var/lib/dpkg/status') .
        "\nPackage: xcat-server\nStatus: install ok installed\nArchitecture: all\nVersion: 2.18.0\n" .
        "Maintainer: xCAT <xcat-user\@lists.sourceforge.net>\nDescription: obsolete conffile fixture\n" .
        "Conffiles:\n /etc/init.d/xcatd 8797eef6731719e0eacff59612b3e916 obsolete\n\n");
    succeeds('capture obsolete conffile metadata', $root->deb_script($deb, 'preinst', 'upgrade', '2.18.0'));
    ok(-f $root->path('/var/lib/xcat/xcatd-systemd-mode'), 'obsolete conffile records package omission');
    ok(!-e $root->path('/var/lib/xcat/xcatd-init-state/pending-deleted'), 'package omission is not an administrator deletion');
};

subtest 'invalid postinst context fails closed' => sub {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=\"24.04\"\n");
    succeeds('install before invalid-context retry', $root->install_deb($deb));
    my $state = '/var/lib/xcat/xcatd-init-state';
    my $before = $root->read("$state/state");
    $root->write("$state/context", "invalid\n");
    my ($status, $out, $err) = $root->deb_script($deb, 'postinst', 'configure', $version);
    isnt($status, 0, 'invalid transaction context fails configuration');
    like($err, qr/Invalid xcatd package transition context/, 'failure identifies the invalid context');
    is($root->read("$state/state"), $before, 'invalid context leaves durable state unchanged');
};

subtest 'failed configuration can be retried' => sub {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=24.04\n");
    $root->write('/test-bin/ln', <<'SHELL', 0755);
#!/bin/sh
for destination; do :; done
case "$destination" in /usr/sbin/xcatd) exit 17;; esac
exec /host-usr/bin/ln "$@"
SHELL
    my ($status) = $root->install_deb($deb);
    isnt($status, 0, 'late configuration failure stops the transaction');
    my $context = '/var/lib/xcat/xcatd-init-state/context';
    ok(-f $root->path($context), 'late failure retains transaction context');
    is($root->read($context), "fresh\n", 'retry retains the original transition') if -f $root->path($context);
    unlink $root->path('/test-bin/ln') or die "unlink: $!";
    succeeds('retry package configuration', $root->run('dpkg', '--force-depends', '--configure', 'xcat-server'));
    is(readlink($root->path('/usr/sbin/xcatd')), '/opt/xcat/sbin/xcatd', 'retry creates the daemon link');
    ok(!-e $root->path($context), 'successful retry clears transaction context');
};

subtest 'preinst discards stale pending evidence' => sub {
    my $root = XCAT::Test::Lifecycle->new;
    $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=\"24.04\"\n");
    my $state = '/var/lib/xcat/xcatd-init-state';
    for my $file (qw(pending-xcatd pending-enabled pending-deleted pending-xcatd.tmp.123)) {
        $root->write("$state/$file", "stale evidence\n");
    }
    succeeds('begin installation without installed conffile metadata', $root->deb_script($deb, 'preinst', 'install'));
    my @pending = glob $root->path("$state/pending-*");
    is_deeply(\@pending, [], 'preinst discards pending evidence without installed ownership');
};

for my $mode (qw(systemd legacy)) {
    for my $proc (0, 1) {
      for my $available ($mode eq 'systemd' ? (0, 1) : (0)) {
        subtest "$mode service dispatch proc=$proc manager=$available" => sub {
            my $root = XCAT::Test::Lifecycle->new;
            $root->{live} = $proc;
            $root->write('/etc/os-release', "ID=ubuntu\nVERSION_ID=\"" . ($mode eq 'systemd' ? '24.04' : '14.04') . "\"\n");
            make_path($root->path('/run/systemd/system')) if $available;
            $root->record_command('/usr/sbin/systemctl');
            $root->record_command('/test-bin/update-rc.d');
            for my $event (qw(install upgrade)) {
                $root->write('/calls', '');
                succeeds("$event dispatch transaction", $root->install_deb($deb));
                my @reloads = $root->read('/calls') =~ /^(systemctl <daemon-reload>)$/mg;
                is_deeply(\@reloads, $available ? ['systemctl <daemon-reload>'] : [],
                    "$event reloads service definitions only with systemd available");
            }
            $root->record_command('/etc/init.d/xcatd') if $mode eq 'legacy';
            $root->write('/calls', '');
            succeeds('remove dispatch transaction', $root->run('dpkg', '--force-depends', '--remove', 'xcat-server'));
            my @stops = $root->read('/calls') =~ /^((?:systemctl <stop> <xcatd.service>|xcatd <stop>))$/mg;
            my $stop = $mode eq 'systemd' ? 'systemctl <stop> <xcatd.service>' : 'xcatd <stop>';
            is_deeply(\@stops, $proc && ($available || $mode eq 'legacy') ? [$stop] : [],
                'removal stops the available service only with proc');
        };
      }
    }
}

done_testing();
