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
use DBI;

my $bindir = $ENV{XCAT_TEST_PG_BINDIR};
plan skip_all => 'Set XCAT_TEST_PG_BINDIR to native PostgreSQL binaries' unless $bindir;
BAIL_OUT('The private PostgreSQL fixture must run without root privileges') if $< == 0;
for my $command (qw(initdb pg_ctl postgres psql createdb)) {
    BAIL_OUT("Missing native PostgreSQL program $command") unless -x "$bindir/$command";
}
BEGIN {
    *CORE::GLOBAL::exit = sub { die bless { status => $_[0] || 0 }, 'PgSchemaTestExit' };
}
my $tmp = tempdir('xcat-pg-schema-XXXXXX', TMPDIR => 1, CLEANUP => 1);
make_path("$tmp/socket", "$tmp/xcatdb");
local $ENV{PGHOST} = "$tmp/socket";
local $ENV{PGPORT} = 55491;
local $ENV{PGUSER} = 'postgres';
local $ENV{PGDATABASE} = 'postgres';
local $ENV{PSQL_HISTORY} = '/dev/null';
local $ENV{XCATROOT} = repo_path('xCAT-server');
local $ENV{XCATCFG} = "SQLite:$tmp/xcatdb";
my $started = 0;
END {
    if ($started) {
        system("$bindir/pg_ctl", '-D', "$tmp/data", '-m', 'immediate', '-w', 'stop');
    }
}
sub quiet_system {
    my (@args) = @_;
    open(my $log, '>>', "$tmp/commands.log") or die $!;
    local *STDOUT = $log;
    local *STDERR = $log;
    return system(@args);
}
my @init = ("$bindir/initdb", '-D', "$tmp/data", '-U', 'postgres', '--auth-local=trust', '--auth-host=reject', '--no-locale');
push @init, ('-L', $ENV{XCAT_TEST_PG_SHAREDIR}) if $ENV{XCAT_TEST_PG_SHAREDIR};
is(quiet_system(@init), 0, 'native initdb creates a private cluster');
my $start = quiet_system("$bindir/pg_ctl", '-D', "$tmp/data", '-l', "$tmp/server.log", '-o', "-k $tmp/socket -h '' -p $ENV{PGPORT}", '-w', 'start');
is($start, 0, 'private PostgreSQL starts with only a private Unix socket');
BAIL_OUT('Unable to start the private PostgreSQL fixture') if $start != 0;
$started = 1;
my $admin = DBI->connect("dbi:Pg:dbname=postgres;host=$ENV{PGHOST};port=$ENV{PGPORT}", 'postgres', '', { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
my ($version) = $admin->selectrow_array('SHOW server_version_num');
cmp_ok($version, '>=', 150000, 'fixture exercises the PostgreSQL 15 schema privilege contract');
my ($listen) = $admin->selectrow_array('SHOW listen_addresses');
is($listen, '', 'fixture does not listen on TCP');

my ($help, $load_error);
{
    local @ARGV = ('--help');
    open(my $out, '>', \$help) or die $!;
    local *STDOUT = $out;
    do($ENV{XCAT_PGSQLSETUP_SOURCE} || repo_path('xCAT-client/bin/pgsqlsetup'));
    $load_error = $@;
}
is(ref($load_error), 'PgSchemaTestExit', 'complete pgsqlsetup loads through its help path');
BAIL_OUT("Unable to load pgsqlsetup: $load_error") unless ref($load_error) eq 'PgSchemaTestExit' && $load_error->{status} == 0;
{
    local $::osname = 'Linux';
    local $::linuxos = 'openeuler24.03sp3';
    local $::dbname = 'xcat_schema_fixture';
    local $::pgcmddir = $bindir;
    local $::adminpassword = 'fixture';
    no warnings 'redefine';
    local *main::runpgcmd_chkoutput = sub { return quiet_system($_[0]) };
    local *main::runpostgrescmd = sub { return quiet_system($_[0]) };
    eval { main::setupxcatdb() };
    is($@, '', 'complete setupxcatdb creates the database and both roles on native PostgreSQL');
}
my $db = DBI->connect("dbi:Pg:dbname=xcat_schema_fixture;host=$ENV{PGHOST};port=$ENV{PGPORT}", 'postgres', '', { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
my ($owner) = $db->selectrow_array("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = current_database()");
is($owner, 'postgres', 'database ownership remains with postgres');
my ($schema_owner) = $db->selectrow_array("SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'public'");
is($schema_owner, 'pg_database_owner', 'public schema retains the native owner');
my ($public_create) = $db->selectrow_array("SELECT count(*) FROM pg_namespace, aclexplode(nspacl) a WHERE nspname='public' AND a.grantee=0 AND a.privilege_type='CREATE'");
is($public_create, 0, 'schema CREATE is not granted to PUBLIC');
for my $role (qw(xcatadm root)) {
    my ($create, $usage) = $db->selectrow_array("SELECT has_schema_privilege(?, 'public', 'CREATE'), has_schema_privilege(?, 'public', 'USAGE')", undef, $role, $role);
    ok($create, "$role can create public schema tables");
    ok($usage, "$role can use the public schema");
    my $user = DBI->connect("dbi:Pg:dbname=xcat_schema_fixture;host=$ENV{PGHOST};port=$ENV{PGPORT}", $role, 'fixture', { RaiseError => 0, PrintError => 0, AutoCommit => 1 });
    ok($user, "$role connects using its configured database identity");
    my $table = 'fixture_' . $role;
    my $created = $user && $user->do("CREATE TABLE $table (id integer primary key, value text)");
    ok($created, "$role creates an actual table");
    my $inserted = $created && $user->do("INSERT INTO $table VALUES (1, 'retained')");
    ok($inserted, "$role inserts a row");
    my ($value) = $inserted ? $user->selectrow_array("SELECT value FROM $table WHERE id = 1") : (undef);
    is($value, 'retained', "$role reads the stored row");
    $user->disconnect if $user;
}
$db->disconnect;
$admin->do('DROP DATABASE xcat_schema_fixture');
$admin->do('DROP ROLE xcatadm');
$admin->do('DROP ROLE root');
{
    local $::osname = 'Linux';
    local $::linuxos = 'openeuler24.03sp3';
    local $::dbname = 'xcat_schema_failure';
    local $::pgcmddir = $bindir;
    local $::adminpassword = 'fixture';
    my ($continued, $failed_command) = (0, undef);
    no warnings 'redefine';
    local *main::runpgcmd_chkoutput = sub { return quiet_system($_[0]) };
    local *main::runpostgrescmd = sub {
        my $failure_db = DBI->connect("dbi:Pg:dbname=xcat_schema_failure;host=$ENV{PGHOST};port=$ENV{PGPORT}", 'postgres', '', { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
        $failure_db->do('DROP SCHEMA public');
        $failure_db->disconnect;
        $failed_command = quiet_system($_[0]);
        return $failed_command;
    };
    eval { main::setupxcatdb(); $continued = 1; };
    my $error = $@;
    ok(defined($failed_command) && $failed_command != 0, 'native psql returns failure when the schema grant cannot run');
    is(ref($error) ? $error->{status} : undef, 1, 'actual native schema grant failure fails the CLI');
    is($continued, 0, 'actual native schema grant failure prevents subsequent setup');
}
$admin->disconnect;
is(quiet_system("$bindir/pg_ctl", '-D', "$tmp/data", '-m', 'fast', '-w', 'stop'), 0, 'private PostgreSQL shuts down cleanly');
$started = 0;
done_testing();
