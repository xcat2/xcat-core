#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use xCAT::Utils;

our $test_cfgloc;
BEGIN {
    *CORE::GLOBAL::exit = sub { die bless { status => $_[0] || 0 }, 'PgSetupTestExit' };
    *CORE::GLOBAL::open = sub (*;$@) {
        return CORE::open($_[0], $_[1], $test_cfgloc)
          if @_ == 3 && defined($test_cfgloc) && !ref($_[2]) && $_[2] eq '/etc/xcat/cfgloc';
        return CORE::open($_[0], $_[1], $_[2]) if @_ == 3;
        return CORE::open($_[0], $_[1]) if @_ == 2;
        die 'Unexpected open form in pgsqlsetup fixture';
    };
}

my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/db", "$tmp/systemd", "$tmp/backup");
$test_cfgloc = "$tmp/cfgloc";
open(my $cfg, '>', $test_cfgloc) or die $!;
print {$cfg} "Pg:dbname=xcatdb|xcatadm|fixture\n";
close($cfg) or die $!;
local $ENV{XCATROOT} = repo_path('xCAT-server');
local $ENV{XCATCFG} = "SQLite:$tmp/db";
my $script = $ENV{XCAT_PGSQLSETUP_SOURCE} || repo_path('xCAT-client/bin/pgsqlsetup');
my ($help, $load_error);
{
    local @ARGV = ('--help');
    open(my $out, '>', \$help) or die $!;
    local *STDOUT = $out;
    do $script;
    $load_error = $@;
}
is(ref($load_error), 'PgSetupTestExit', 'the complete CLI reaches its help exit');
is(ref($load_error) ? $load_error->{status} : undef, 0, 'help exits successfully');
like($help, qr/pgsqlsetup/, 'help prints usage');
die("Unable to load complete pgsqlsetup: $load_error")
  unless ref($load_error) eq 'PgSetupTestExit' && $load_error->{status} == 0;

sub invoke {
    my ($callback) = @_;
    my ($continued, $result) = (0, undef);
    eval { $result = $callback->(); $continued = 1; };
    my $error = $@;
    die $error if $error && ref($error) ne 'PgSetupTestExit';
    return { status => $error ? $error->{status} : 0, continued => $continued, result => $result };
}

my $service_map = \&xCAT::Utils::servicemap;
sub reboot_case {
    my ($os, $status, $unit, $version, $platform) = @_;
    unlink glob "$tmp/systemd/*";
    if (defined $unit) {
        open(my $fh, '>', "$tmp/systemd/$unit.service") or die $!;
        close($fh) or die $!;
    }
    local $::osname = $platform || 'Linux';
    local $::linuxos = $os;
    local $::postgres9 = $version;
    my (@commands, @messages);
    no warnings 'redefine';
    local *xCAT::Utils::servicemap = sub {
        my ($service) = @_;
        return $service_map->($service, { searches => [{ paths => ["$tmp/systemd"], suffix => '.service' }] });
    };
    local *xCAT::Utils::runcmd = sub {
        push @commands, $_[1];
        $::RUNCMD_RC = $status;
        return ();
    };
    local *xCAT::MsgUtils::message = sub { push @messages, [@_[1, 2]] };
    my $result = invoke(\&main::pgreboot);
    return { %$result, commands => \@commands, messages => \@messages };
}

for my $os (qw(openeuler20 openeuler20.03sp4 openeuler22.03sp4 openeuler24.03 openeuler24.03sp1 openeuler24.03sp3 openeuler24.03sp4)) {
    my $result = reboot_case($os, 0, 'postgresql');
    is_deeply($result->{commands}, ['systemctl enable postgresql'], "$os enables the installed unit");
    is($result->{continued}, 1, "$os successful enable continues");
    is_deeply($result->{messages}, [], "$os successful enable has no error");
}
for my $os (qw(openeuler20.03sp4 openeuler22.03sp4 openeuler24.03sp3)) {
    for my $failure (['command failure', 42, 'postgresql'], ['missing unit', 0, undef]) {
        my ($label, $status, $unit) = @$failure;
        my $result = reboot_case($os, $status, $unit);
        is($result->{status}, 1, "$os $label fails the CLI");
        is($result->{continued}, 0, "$os $label prevents later setup");
        like($result->{messages}[0][1], qr/PostgreSQL will not restart/, "$os $label reports boot failure");
    }
}
for my $os (qw(rhels9.6 sles15 ubuntu24.04 openeuler custom-openeuler24.03)) {
    for my $status (0, 42) {
        my $result = reboot_case($os, $status, 'postgresql');
        is_deeply($result->{commands}, ['systemctl enable postgresql'], "$os status $status retains its service command");
        is($result->{continued}, 1, "$os status $status retains continuation");
    }
}
is_deeply(reboot_case('rhels6', 0, 'postgresql-9.2', 2)->{commands}, ['systemctl enable postgresql-9.2'], 'legacy versioned service selection remains');
is_deeply(reboot_case('openeuler24.03sp3', 0, 'postgresql', undef, 'AIX')->{commands}, [], 'AIX retains precedence');

sub setup_case {
    my ($os, $grant_status, $spawn_failure, $platform) = @_;
    local $::osname = $platform || 'Linux';
    local $::linuxos = $os;
    local $::dbname = 'fixturedb';
    local $::pgcmddir = '/fixture/bin';
    local $::installdir = '/fixture';
    local $::adminpassword = 'fixture';
    my (@grants, @messages, @roles);
    my $spawns = 0;
    no warnings 'redefine';
    local *main::runpgcmd_chkoutput = sub { return 0 };
    local *main::runpostgrescmd = sub { push @grants, $_[0]; return $grant_status };
    local *Expect::new = sub { bless {}, 'Expect' };
    local *Expect::exp_internal = sub { };
    local *Expect::log_stdout = sub { };
    local *Expect::spawn = sub { ++$spawns; return !$spawn_failure || $spawns != $spawn_failure };
    local *Expect::expect = sub { $_[2][1]->(); return () };
    local *Expect::send = sub { push @roles, $_[1] if $_[1] =~ /^CREATE USER/ };
    local *Expect::clear_accum = sub { };
    local *Expect::exp_continue = sub { };
    local *Expect::soft_close = sub { };
    local *Expect::DESTROY = sub { };
    local *xCAT::MsgUtils::message = sub { push @messages, [@_[1, 2]] };
    my $result = invoke(\&main::setupxcatdb);
    return { %$result, grants => \@grants, roles => \@roles, messages => \@messages };
}
for my $os (qw(openeuler20.03sp4 openeuler22.03sp4 openeuler24.03sp3)) {
    my $result = setup_case($os, 0, 0);
    is($result->{continued}, 1, "$os role setup succeeds");
    is(scalar @{$result->{roles}}, 2, "$os retains both role creation requests");
    is_deeply($result->{grants}, ['/fixture/bin/psql -v ON_ERROR_STOP=1 -d fixturedb -c "GRANT USAGE, CREATE ON SCHEMA public TO xcatadm, root"'], "$os checks the configured database grant for both existing roles");
    my $failed = setup_case($os, 256, 0);
    is($failed->{status}, 1, "$os grant failure fails the CLI");
    is($failed->{continued}, 0, "$os grant failure prevents restore");
    like(@{$failed->{messages}} ? $failed->{messages}[-1][1] : '', qr/Failed granting xCAT roles/, "$os grant failure reports the operation");
    for my $spawn (1, 2) {
        my $failure = setup_case($os, 0, $spawn);
        is($failure->{status}, 1, "$os role $spawn spawn failure fails the CLI");
        is($failure->{continued}, 0, "$os role $spawn spawn failure prevents restore");
        is_deeply($failure->{grants}, [], "$os role $spawn spawn failure does not grant access");
    }
}
for my $case (['rhels9.6', 'Linux'], ['sles15', 'Linux'], ['openeuler', 'Linux'], ['openeuler24.03sp3', 'AIX']) {
    my ($os, $platform) = @$case;
    my $result = setup_case($os, 256, 0, $platform);
    is_deeply($result->{grants}, [], "$platform $os retains its prior grants");
    is($result->{continued}, 1, "$platform $os retains setup continuation");
    is(setup_case($os, 0, 1, $platform)->{continued}, 1, "$platform $os retains spawn failure return behavior");
}

sub restore_case {
    my ($os, $restore_status, $start_status) = @_;
    local $::osname = 'Linux';
    local $::linuxos = $os;
    local $::backupdir = "$tmp/backup";
    local $::VERBOSE = 0;
    my (@steps, @messages);
    no warnings 'redefine';
    local *xCAT::Utils::runcmd = sub { push @steps, 'restore'; $::RUNCMD_RC = $restore_status; return () };
    local *xCAT::Utils::startservice = sub { push @steps, 'start ' . $_[1]; return $start_status };
    local *xCAT::MsgUtils::message = sub { push @messages, [@_[1, 2]] };
    my $result = invoke(\&main::restorexcatdb);
    return { %$result, steps => \@steps, messages => \@messages };
}
for my $os (qw(openeuler20.03sp4 openeuler22.03sp4 openeuler24.03sp3)) {
    my $ok = restore_case($os, 0, 0);
    is_deeply($ok->{steps}, ['restore', 'start xcatd'], "$os restores before starting xCAT");
    is($ok->{continued}, 1, "$os successful restore and start continue");
    my $restore = restore_case($os, 42, 0);
    is($restore->{status}, 1, "$os retains restore failure propagation");
    is_deeply($restore->{steps}, ['restore'], "$os restore failure prevents startup");
    my $start = restore_case($os, 0, 42);
    is($start->{status}, 1, "$os startup failure fails the CLI");
    is($start->{continued}, 0, "$os startup failure prevents the success continuation");
    like($start->{messages}[-1][1], qr/Failed to start xcatd/, "$os startup failure identifies xCAT");
}
for my $os (qw(rhels9.6 sles15 ubuntu24.04 openeuler)) {
    my $result = restore_case($os, 0, 42);
    is($result->{continued}, 1, "$os retains startup failure continuation");
    is($result->{result}, 42, "$os retains startup return status");
}

done_testing();
