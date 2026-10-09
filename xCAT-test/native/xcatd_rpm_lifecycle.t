#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use File::Path qw(make_path);
use XCAT::Test::File qw(slurp_repo_file);
use XCAT::Test::RPM;

plan skip_all => 'Native RPM distribution and Linux namespaces are required'
    unless $^O eq 'linux' && -f '/etc/redhat-release';

my $first = XCAT::Test::RPM->build('xCAT-server', 1);
my $second = XCAT::Test::RPM->build('xCAT-server', 2);
my $template = slurp_repo_file('xCAT-server/etc/init.d/xcatd');

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag "$result[1]$result[2]";
    unlike($result[2], qr/scriptlet failed|scriptlet failure/i, "$label completes scriptlets");
}

for my $mode (qw(systemd legacy)) {
    for my $state (qw(enabled disabled masked unregistered)) {
        subtest "$mode $state upgrade" => sub {
            my $root = XCAT::Test::RPM->new;
            $root->write('/etc/os-release', 'ID=rhel' . "\nVERSION_ID=\"" . ($mode eq 'systemd' ? '8.10' : '6.10') . "\"\n");
            succeeds('fresh transaction', $root->install($first));
            if ($mode eq 'systemd') {
                ok(!-e $root->path('/etc/init.d/xcatd'), 'systemd install omits legacy init');
                ok(-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'fresh systemd install is enabled');
                $root->record_command('/opt/xcat/sbin/xcatd');
                succeeds('execute installed unit start command', $root->start_unit('/usr/lib/systemd/system/xcatd.service'));
                is($root->read('/calls'), "xcatd <-p> </run/xcatd.pid>\n", 'unit starts the daemon without a legacy script');
                succeeds('disable service', $root->run('systemctl', 'disable', 'xcatd.service')) if $state ne 'enabled';
            } else {
                is($root->read('/etc/rc.d/init.d/xcatd'), $template, 'fresh legacy install has packaged bytes');
                for my $level (3..5) {
                    ok(-l $root->path("/etc/rc.d/rc$level.d/S85xcatd"), "fresh install enables runlevel $level");
                }
                succeeds('disable legacy service', $root->run('chkconfig', 'xcatd', 'off')) if $state eq 'disabled';
                succeeds('unregister legacy service', $root->run('chkconfig', '--del', 'xcatd')) if $state eq 'unregistered' || $state eq 'masked';
                $root->write('/etc/rc.d/init.d/xcatd', "$template\n# previous package template\n", 0755);
            }
            if ($state eq 'masked') {
                symlink('/dev/null', $root->path('/etc/systemd/system/xcatd.service')) or die "symlink: $!";
            }
            succeeds('upgrade transaction', $root->install($second));
            if ($mode eq 'systemd') {
                is(-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service') ? 1 : 0,
                    $state eq 'enabled' ? 1 : 0, 'upgrade preserves systemd enablement');
            } else {
                my @links = glob $root->path('/etc/rc.d/rc[2345].d/S*xcatd');
                is(scalar @links, $state eq 'enabled' ? 3 : 0, 'upgrade preserves legacy enablement');
                my @disabled = glob $root->path('/etc/rc.d/rc[2345].d/K*xcatd');
                is(scalar @disabled, $state eq 'disabled' ? 4 : $state eq 'enabled' ? 1 : 0,
                    'upgrade preserves disabled versus unregistered runlevels');
                is($root->read('/etc/rc.d/init.d/xcatd'), $template, 'upgrade refreshes packaged legacy bytes');
            }
            is(readlink($root->path('/etc/systemd/system/xcatd.service')), '/dev/null', 'upgrade preserves mask') if $state eq 'masked';
            succeeds('erase transaction', $root->run('rpm', '--nodeps', '-e', 'xCAT-server'));
            ok(!-e $root->path('/etc/rc.d/init.d/xcatd'), 'erase removes generated legacy script');
            ok(!-e $root->path('/var/lib/xcat/xcatd-init-compat-managed'), 'erase removes managed marker');
            my @links = glob $root->path('/etc/rc.d/rc[0-6].d/[SK]*xcatd');
            is(scalar @links, 0, 'erase clears runlevel links');
            ok(!-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'erase clears systemd enablement');
        };
    }
}

for my $content (qw(edited symlink identical)) {
    subtest "erase preserves administrator $content script" => sub {
        my $root = XCAT::Test::RPM->new;
        $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"6.10\"\n");
        if ($content eq 'symlink') {
            $root->write('/etc/rc.d/init.d/admin-xcatd', $template, 0755);
            symlink('admin-xcatd', $root->path('/etc/rc.d/init.d/xcatd')) or die "symlink: $!";
        } else {
            $root->write('/etc/rc.d/init.d/xcatd', $content eq 'identical' ? $template : "$template\n# administrator edit\n", 0755);
        }
        succeeds('install over administrator file', $root->install($first));
        succeeds('erase package', $root->run('rpm', '--nodeps', '-e', 'xCAT-server'));
        ok(-e $root->path('/etc/rc.d/init.d/xcatd'), 'erase keeps administrator script');
        return unless -e $root->path('/etc/rc.d/init.d/xcatd');
        is($root->read('/etc/rc.d/init.d/xcatd'), $content eq 'edited' ? "$template\n# administrator edit\n" : $template,
            'erase preserves administrator bytes');
        is(readlink($root->path('/etc/rc.d/init.d/xcatd')), 'admin-xcatd', 'erase preserves symlink') if $content eq 'symlink';
    };
}

for my $direction (qw(legacy-to-systemd systemd-to-legacy)) {
    subtest $direction => sub {
        my $root = XCAT::Test::RPM->new;
        my ($from, $to) = $direction eq 'legacy-to-systemd' ? ('6.10', '8.10') : ('8.10', '6.10');
        $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"$from\"\n");
        succeeds('install original init target', $root->install($first));
        $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"$to\"\n");
        succeeds('upgrade after init transition', $root->install($second));
        if ($to eq '8.10') {
            ok(!-e $root->path('/etc/rc.d/init.d/xcatd'), 'systemd transition removes legacy script');
            my @links = glob $root->path('/etc/rc.d/rc[0-6].d/[SK]*xcatd');
            is(scalar @links, 0, 'systemd transition removes runlevel links');
            ok(-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'systemd transition preserves enabled state');
        } else {
            is($root->read('/etc/rc.d/init.d/xcatd'), $template, 'legacy transition materializes init script');
            ok(!-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service'), 'legacy transition clears systemd enablement');
            for my $level (3..5) {
                ok(-l $root->path("/etc/rc.d/rc$level.d/S85xcatd"), "legacy transition enables runlevel $level");
            }
        }
    };
}

subtest 'relocated legacy package' => sub {
    my $root = XCAT::Test::RPM->new;
    $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"6.10\"\n");
    succeeds('relocated install', $root->install($first, '--prefix', '/srv/xcat'));
    is(readlink($root->path('/usr/sbin/xcatd')), '/srv/xcat/sbin/xcatd', 'daemon link uses relocated prefix');
    is($root->read('/etc/rc.d/init.d/xcatd'), $template, 'relocated helper installs legacy template');
    succeeds('relocated erase', $root->run('rpm', '--nodeps', '-e', 'xCAT-server'));
    ok(!-e $root->path('/etc/rc.d/init.d/xcatd'), 'relocated helper removes managed script');
};

my $old = XCAT::Test::RPM->build_fixture('legacy-init');
for my $target ('6.10', '8.10') {
    for my $state (qw(enabled disabled unregistered)) {
        subtest "old payload upgrade $target $state" => sub {
            my $root = XCAT::Test::RPM->new;
            $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"$target\"\n");
            succeeds('install old init payload', $root->install($old));
            succeeds('register old defaults', $root->run('chkconfig', '--add', 'xcatd')) unless $state eq 'unregistered';
            succeeds('disable old service', $root->run('chkconfig', 'xcatd', 'off')) if $state eq 'disabled';
            succeeds('upgrade old payload ownership', $root->install($first));
            if ($target eq '6.10') {
                ok(-f $root->path('/etc/init.d/xcatd'), 'posttrans restores the legacy script after old payload removal');
                is($root->read('/etc/init.d/xcatd'), $template, 'restored script has packaged bytes') if -f $root->path('/etc/init.d/xcatd');
                ok(-f $root->path('/var/lib/xcat/xcatd-init-compat-managed'), 'posttrans tracks restored ownership');
                my @enabled = glob $root->path('/etc/rc.d/rc[2345].d/S*xcatd');
                my @disabled = glob $root->path('/etc/rc.d/rc[2345].d/K*xcatd');
                is(scalar @enabled, $state eq 'enabled' ? 3 : 0, 'old upgrade preserves enabled runlevels');
                is(scalar @disabled, $state eq 'disabled' ? 4 : $state eq 'enabled' ? 1 : 0, 'old upgrade preserves disabled registration');
            } else {
                ok(!-e $root->path('/etc/init.d/xcatd'), 'systemd upgrade removes old init payload');
                is(-l $root->path('/etc/systemd/system/multi-user.target.wants/xcatd.service') ? 1 : 0,
                    $state eq 'enabled' ? 1 : 0, 'old upgrade preserves systemd enablement');
            }
            succeeds('erase upgraded package', $root->run('rpm', '--nodeps', '-e', 'xCAT-server'));
            ok(!-e $root->path('/etc/init.d/xcatd'), 'erase removes the restored managed script');
        };
    }
}

my $suse = XCAT::Test::RPM->build('xCAT-server', 1, '--define', 'suse_version 1500');
for my $target (['el', $first, 0], ['suse', $suse, 1]) {
    subtest "$target->[0] empty init directory" => sub {
        my $root = XCAT::Test::RPM->new(init_directory => 1);
        $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"8.10\"\n");
        succeeds('install current package into directory layout', $root->install($target->[1]));
        succeeds('upgrade current package in directory layout', $root->install($target->[1], '--replacepkgs'));
        is(-d $root->path('/etc/init.d') ? 1 : 0, $target->[2], 'upgrade respects init-directory ownership');
    };
}

for my $state (qw(masked custom-enabled custom-disabled)) {
    subtest "fresh legacy install preserves $state registration" => sub {
        my $root = XCAT::Test::RPM->new;
        $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"6.10\"\n");
        my @expected;
        if ($state eq 'masked') {
            symlink('/dev/null', $root->path('/etc/systemd/system/xcatd.service')) or die "symlink: $!";
        } else {
            $root->write('/etc/init.d/xcatd', $template, 0755);
            push @expected, $root->path('/etc/rc.d/rc3.d/' . ($state eq 'custom-enabled' ? 'S' : 'K') . '85xcatd');
            symlink('../init.d/xcatd', $expected[0]) or die "symlink: $!";
        }
        succeeds('install with administrator registration', $root->install($first));
        my @actual = glob $root->path('/etc/rc.d/rc[0-6].d/[SK]??xcatd');
        is_deeply(\@actual, \@expected, 'fresh install preserves the exact runlevel layout');
    };
}

for my $mode (qw(systemd legacy)) {
    for my $proc (0, 1) {
      for my $available ($mode eq 'systemd' ? (0, 1) : (0)) {
        subtest "$mode service dispatch proc=$proc manager=$available" => sub {
            my $root = XCAT::Test::RPM->new;
            $root->{live} = $proc;
            $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"" . ($mode eq 'systemd' ? '8.10' : '6.10') . "\"\n");
            make_path($root->path('/run/systemd/system')) if $available;
            $root->record_command('/usr/sbin/systemctl');
            for my $event (['install', $first], ['upgrade', $second]) {
                $root->write('/calls', '');
                succeeds("$event->[0] dispatch transaction", $root->install($event->[1]));
                my @reloads = $root->read('/calls') =~ /^(systemctl <daemon-reload>)$/mg;
                is_deeply(\@reloads, $available ? ['systemctl <daemon-reload>'] : [],
                    "$event->[0] reloads service definitions only with systemd available");
            }
            $root->record_command('/etc/init.d/xcatd') if $mode eq 'legacy';
            $root->write('/calls', '');
            succeeds('erase dispatch transaction', $root->run('rpm', '--nodeps', '-e', 'xCAT-server'));
            my @stops = $root->read('/calls') =~ /^((?:systemctl <stop> <xcatd.service>|xcatd <stop>))$/mg;
            my $stop = $mode eq 'systemd' ? 'systemctl <stop> <xcatd.service>' : 'xcatd <stop>';
            is_deeply(\@stops, $proc && ($available || $mode eq 'legacy') ? [$stop] : [],
                'erase stops the available service only with proc');
        };
      }
    }
}

done_testing();
