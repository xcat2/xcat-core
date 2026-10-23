#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $work = tempdir(CLEANUP => 1);
make_path("$work/db");
local $ENV{XCATROOT} = $work;
local $ENV{XCATCFG} = "SQLite:$work/db";
for my $mapping (
    [ xCAT_plugin => 'xCAT-server/lib/xcat/plugins' ],
    [ xCAT_monitoring => 'xCAT-server/lib/xcat/monitoring' ],
) {
    symlink(repo_path($mapping->[1]), "$work/$mapping->[0]") or die $!;
}
unshift @INC, $work;
require xCAT_plugin::syncfiles;
require xCAT_plugin::xdsh;
require xCAT_plugin::updatenode;

my $source = "$work/payload";
my $list = "$work/synclist";
write_text($source, "identity fixture\n");
write_text($list, "$source -> /tmp/syncfiles-identity/payload\n");

sub exercise {
    my ($producer, $case) = @_;
    local %ENV = %ENV;
    delete @ENV{grep { /\A(?:DSH_|DCP_|RSYNC)/ } keys %ENV};
    @ENV{keys %{$case->{inherited}}} = values %{$case->{inherited}};
    no warnings qw(once redefine);
    local $::RCP;
    local $::USER;
    local $::fanout;
    local $::timeout;
    local $::REPORTSTATUS = 'N';
    local @::SUCCESSFULLNODES;
    local @::FAILEDNODES;
    local @ARGV;
    local *xCAT::Utils::isServiceNode = sub { return 0; };
    local *xCAT::Utils::isMN = sub { return 0; };
    local *xCAT::TableUtils::get_site_attribute = sub { return; };
    local *xCAT::SvrUtils::getsynclistfile = sub { return {node1 => $list}; };
    local *xCAT_plugin::syncfiles::noderange = sub { return 'node1'; };
    my (@executions, @responses, @requests);
    local *xCAT::DSHCLI::execute_dcp = sub {
        my ($class, $options) = @_;
        push @executions, {
            options => dclone($options),
            from => $ENV{DSH_FROM_USERID},
            to => $ENV{DSH_TO_USERID},
        };
        return 0;
    };
    my $callback = sub { push @responses, dclone($_[0]); };
    my $dispatch = sub {
        my ($request, $response) = @_;
        push @requests, dclone($request);
        xCAT_plugin::xdsh::process_request($request, $response, sub { die 'Unexpected nested request'; });
    };
    my $request = {
        command => [$producer], node => ['node1'], arg => [],
        username => ['operator'], _xcat_clienthost => ['node1.example.test'],
        environment => $case->{environment} || [],
        SNFileSyncing => ['no'], FileSyncing => ['yes'],
    };
    if ($producer eq 'syncfiles') {
        xCAT_plugin::syncfiles::process_request($request, $callback, $dispatch);
    } else {
        xCAT_plugin::updatenode::updatenodesyncfiles($request, $dispatch, $callback);
    }
    is(scalar @executions, 1, 'one parsed copy reaches the execution boundary');
    is(scalar @requests, 1, 'one producer request reaches the real xdsh plugin');
    my $copy = $executions[0] || {options => {}};
    is($copy->{from}, $case->{from}, 'consumer preserves the expected sending identity');
    is($copy->{to}, $case->{to}, 'consumer preserves the expected receiving identity');
    is($copy->{options}->{user}, $case->{from}, 'xdcp selects the sending identity for its copy user');
    is($copy->{options}->{nodes}, 'node1', 'copy targets the resolved node');
    is_deeply(
        $copy->{options}->{destDir_srcFile},
        {node1 => {'/tmp/syncfiles-identity' => {same_dest_name => [$source]}}},
        'the real synclist parser supplies the payload and destination',
    );
    is_deeply($requests[0]->{username}, [$producer eq 'syncfiles' ? 'root' : 'operator'],
        'the producer retains its request identity contract');
    my @errors = grep {
        $_->{error} || grep { $_ } ref($_->{errorcode}) eq 'ARRAY'
          ? @{$_->{errorcode}} : ($_->{errorcode} || 0)
    } @responses;
    is_deeply(\@errors, [], 'the request has no consumer error');
    return;
}

for my $case (
    {name => 'unset', inherited => {}, from => 'root', to => 'root'},
    {name => 'empty', inherited => {DSH_FROM_USERID => '', DSH_TO_USERID => ''}, from => 'root', to => 'root'},
    {name => 'sending identity only', inherited => {DSH_FROM_USERID => 'sender'}, from => 'sender', to => 'root'},
    {name => 'receiving identity only', inherited => {DSH_TO_USERID => 'receiver'}, from => 'root', to => 'receiver'},
    {name => 'both inherited', inherited => {DSH_FROM_USERID => 'sender', DSH_TO_USERID => 'receiver'}, from => 'sender', to => 'receiver'},
) {
    subtest "syncfiles: $case->{name}" => sub { exercise('syncfiles', $case); };
}

for my $case (
    {name => 'certificate identity', inherited => {}, from => 'operator', to => 'operator'},
    {name => 'certificate overrides inherited sender', inherited => {DSH_FROM_USERID => 'sender', DSH_TO_USERID => 'receiver'}, from => 'operator', to => 'receiver'},
    {name => 'explicit sending identity', inherited => {}, environment => ['DSH_FROM_USERID=sender'], from => 'sender', to => 'operator'},
    {name => 'first explicit sender wins', inherited => {}, environment => ['DSH_FROM_USERID=sender', 'DSH_FROM_USERID=other'], from => 'sender', to => 'operator'},
    {name => 'empty explicit sender falls back at consumer', inherited => {DSH_FROM_USERID => 'sender'}, environment => ['DSH_FROM_USERID='], from => 'operator', to => 'operator'},
) {
    subtest "updatenode: $case->{name}" => sub { exercise('updatenode', $case); };
}

done_testing();
