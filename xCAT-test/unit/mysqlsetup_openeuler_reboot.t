#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use xCAT::Utils;

BEGIN {
    *CORE::GLOBAL::exit = sub {
        die bless { status => $_[0] || 0 }, 'MysqlSetupTestExit';
    };
}

my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/db", "$tmp/systemd", "$tmp/upstart", "$tmp/sysv");
local $ENV{XCATROOT} = repo_path('xCAT-server');
local $ENV{XCATCFG} = "SQLite:$tmp/db";
my $script = $ENV{XCAT_MYSQLSETUP_SOURCE} || repo_path('xCAT-client/bin/mysqlsetup');
my ($help, $load_error);
{
    local @ARGV = ('--help');
    open(my $output, '>', \$help) or die $!;
    local *STDOUT = $output;
    do $script;
    $load_error = $@;
}
is(ref($load_error), 'MysqlSetupTestExit', 'the complete CLI reaches its help exit');
is(ref($load_error) ? $load_error->{status} : undef, 0, 'help exits successfully');
like($help, qr/mysqlsetup/, 'help prints the CLI usage');
die("Unable to load complete mysqlsetup: $load_error")
  unless ref($load_error) eq 'MysqlSetupTestExit' && $load_error->{status} == 0;

my $service_map = \&xCAT::Utils::servicemap;
sub reboot_case {
    my ($os, $mariadb, $unit, $command_status, $debian, $platform) = @_;
    unlink glob "$tmp/systemd/*";
    if (defined $unit) {
        open(my $fh, '>', "$tmp/systemd/$unit.service") or die $!;
        close($fh) or die $!;
    }
    local $::osname = $platform || 'Linux';
    local $::linuxos = $os;
    local $::MariaDB = $mariadb;
    local $::debianflag = $debian || 0;
    local $::RUNCMD_RC = 0;
    my (@commands, @messages);
    my $continued = 0;
    no warnings 'redefine';
    local *xCAT::Utils::servicemap = sub {
        my ($service, $manager) = @_;
        my @directories = ("$tmp/sysv", "$tmp/systemd", "$tmp/upstart");
        my @suffixes = ('', '.service', '.conf');
        return $service_map->($service, {
            searches => [{ paths => [$directories[$manager]], suffix => $suffixes[$manager] }],
        });
    };
    local *xCAT::Utils::runcmd = sub {
        my ($class, $command) = @_;
        push @commands, $command;
        $::RUNCMD_RC = $command_status;
        return ();
    };
    local *xCAT::MsgUtils::message = sub {
        my ($class, $level, $message) = @_;
        push @messages, [$level, $message];
    };
    eval {
        main::mysqlreboot();
        $continued = 1;
    };
    my $error = $@;
    die $error if $error && ref($error) ne 'MysqlSetupTestExit';
    return {
        commands => \@commands, messages => \@messages,
        status => $error ? $error->{status} : 0, continued => $continued,
    };
}

for my $os (qw(openeuler20 openeuler20.03sp4 openeuler22.03sp4 openeuler24.03 openeuler24.03sp1 openeuler24.03sp3 openeuler24.03sp4)) {
    for my $mariadb (0, 1) {
        my $result = reboot_case($os, $mariadb, 'mariadb', 0);
        is_deeply($result->{commands}, ['systemctl enable mariadb'], "$os database $mariadb enables the installed native unit");
        is($result->{status}, 0, "$os database $mariadb succeeds");
        is_deeply($result->{messages}, [], "$os database $mariadb has no enable error");
    }
}

for my $unit (qw(mysqld mysql)) {
    my $result = reboot_case('openeuler24.03sp3', 0, $unit, 0);
    is_deeply($result->{commands}, ["systemctl enable $unit"], "native MySQL resolves the installed $unit unit");
}

for my $os (qw(openeuler20.03sp4 openeuler22.03sp4 openeuler24.03sp3)) {
    for my $failure (['command failure', 'mariadb', 42], ['missing unit', undef, 0]) {
        my ($label, $unit, $status) = @$failure;
        my $result = reboot_case($os, 1, $unit, $status);
        is($result->{status}, 1, "$os $label fails the CLI");
        is($result->{continued}, 0, "$os $label prevents later setup");
        is_deeply($result->{commands}, defined($unit) ? ['systemctl enable mariadb'] : [], "$os $label executes only the available unit command");
        is($result->{messages}[0][0], 'E', "$os $label reports an error");
        like($result->{messages}[0][1], qr/enable MySQL\/MariaDB on reboot/, "$os $label identifies boot enablement");
    }
}

for my $case (
    ['rhels9.6', 1, 0, 'chkconfig mariadb on'],
    ['rhels9.6', 0, 0, 'chkconfig mysqld on'],
    ['ol9', 1, 0, 'chkconfig mariadb on'],
    ['rocky9', 0, 0, 'chkconfig mysqld on'],
    ['alma9', 1, 0, 'chkconfig mariadb on'],
    ['sles15', 1, 0, 'chkconfig mariadb on'],
    ['sles12', 1, 0, 'chkconfig mysql on'],
    ['sles12', 0, 0, 'chkconfig mysql on'],
    ['ubuntu24.04', 1, 1, 'update-rc.d mysql defaults'],
    ['ubuntu24.04', 0, 1, 'update-rc.d mysql defaults'],
    ['custom-openeuler24.03', 1, 0, 'chkconfig mysql on'],
    ['openeuler', 1, 0, 'chkconfig mysql on'],
) {
    my ($os, $mariadb, $debian, $command) = @$case;
    my $result = reboot_case($os, $mariadb, 'mariadb', 0, $debian);
    is_deeply($result->{commands}, [$command], "$os database $mariadb retains its legacy command");
    is($result->{continued}, 1, "$os database $mariadb retains successful continuation");
}
my $legacy_failure = reboot_case('rhels9.6', 1, 'mariadb', 42);
is($legacy_failure->{status}, 0, 'legacy enable failure retains its prior return behavior');
is($legacy_failure->{continued}, 1, 'legacy enable failure retains continuation');
like($legacy_failure->{messages}[0][1], qr/MySQL will not restart on reboot/, 'legacy enable failure retains its diagnostic');
my $aix = reboot_case('openeuler24.03sp3', 1, 'mariadb', 0, 0, 'AIX');
is_deeply($aix->{commands}, ['fgrep mysql /etc/inittab'], 'AIX retains precedence and its existing inittab check');

done_testing();
