#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT";
use File::Path    qw(make_path);
use File::Slurper qw(write_binary);
use File::Temp    qw(tempdir);
use JSON::PP      qw(decode_json);
use Test::More;
use XCAT::Test::File    qw(repo_path);
use XCAT::Test::Process qw(run_command);

require(repo_path('xCAT-server/lib/xcat/plugins/hostbasedauth.pm'));
is_deeply(xCAT_plugin::hostbasedauth::handled_commands(), { 'mkhostbased-auth' => 'hostbasedauth' }, 'dispatches through xcatd');

my @nodes = qw(compute01 compute02);
my $pins = "# verified independently\ncompute01 ssh-ed25519 AQ== note\ncompute02\tssh-rsa\tAg==\n";
is_deeply(xCAT_plugin::hostbasedauth::parse_pins(\@nodes, $pins), {
        compute01 => ['ssh-ed25519 AQ=='], compute02 => ['ssh-rsa Ag=='],
}, 'parses exact node names and the key identities');
for my $bad (
    [ 'compute01 ssh-ed25519 AQ==', qr/Missing verified host key for 'compute02'/ ],
    [ "$pins*.example ssh-ed25519 AA==\n",    qr/Unexpected host key entry/ ],
    [ "$pins" . 'compute02 ssh-ed25519 AQ==', qr/have the same host key/ ],
    [ "$pins" . 'compute01 @cert-authority AQ==', qr/Expected an exact node name/ ],
) {
    eval { xCAT_plugin::hostbasedauth::parse_pins(\@nodes, $bad->[0]) };
    like($@, $bad->[1], 'invalid pin inventory is rejected');
}

{
    no warnings qw(redefine once);
    local *xCAT::Utils::isMN    = sub { 1 };
    local *xCAT::Utils::runcmd3 = sub {
        my %args = @_;
        my @argv = @{ $args{command} };
        is($argv[0], '/usr/bin/ssh', 'connects through OpenSSH');
        ok(grep($_ eq 'StrictHostKeyChecking=yes', @argv), 'does not accept an unpinned node');
        ok(grep($_ eq 'GlobalKnownHostsFile=/dev/null', @argv), 'does not use system trust for bootstrap');
        ok(grep($_ eq 'HostbasedAuthentication=no', @argv), 'does not depend on the peer trust it is about to change');
        my ($literal) = $args{input} =~ /\Ahelper\nmain\(("[^\n]+")\)\n\z/;
        my $payload = eval { decode_json(decode_json($literal)) };
        is_deeply($payload, { operation => 'check' }, 'transmits the fixed helper and the JSON request');
        return { exitcode => 0, output => '{"result":"ok"}' };
    };
    is_deeply(xCAT_plugin::hostbasedauth::remote('helper', '/test/pins', 'compute01', { operation => 'check' }),
        { result => 'ok' }, 'parses the remote response');
    my @response;
    xCAT_plugin::hostbasedauth::process_request({
            node => \@nodes, arg => [ '--user', 'hpc' ], _xcat_authname => ['operator'], stdin => [$pins],
    }, sub { push @response, shift });
    like($response[0]->{error}->[0], qr/Run this command as root/, 'restricted to the management root identity');
}

{
    no warnings qw(redefine once);
    local *xCAT_plugin::hostbasedauth::remote = sub {
        my (undef, undef, $node, $request) = @_;
        die "$node: Connection refused\n" if $node eq 'compute02';
        return { result => $request->{operation} };
    };
    my @completed;
    eval {
        xCAT_plugin::hostbasedauth::remote_batch(\@nodes, 'helper', '/test/pins', sub { { operation => 'apply' } },
            sub { push @completed, shift });
    };
    like($@, qr/compute02: Connection refused/, 'reports a worker failure with the node name');
    is_deeply(\@completed, ['compute01'], 'reports the completed node when another node fails');
}

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/lib/perl/xCAT");
write_binary("$fixture/lib/perl/xCAT/Client.pm", <<'CLIENT');
package xCAT::Client;
use JSON::PP qw(encode_json);
our $EXITCODE = 0;
sub submit_request { print encode_json($_[0]); }
sub handle_response {}
1;
CLIENT
write_binary("$fixture/pins", $pins);

{
    local $ENV{XCATROOT} = $fixture;
    local $ENV{TERM}     = 'xterm';
    local $ENV{SHELL}    = '/bin/bash';
    open(my $saved_stdin, '<&', \*STDIN)         or die $!;
    open(STDIN,           '<',  "$fixture/pins") or die $!;
    my ($status, $output) = run_command($^X, repo_path('xCAT-client/bin/xcatclient'),
        'mkhostbased-auth', 'compute[01-02]', '--user', 'hpc');
    open(STDIN, '<&', $saved_stdin)                   or die $!;
    is($status, 0, 'xcatclient forwards the request') or diag($output);
    my $request = eval { decode_json($output) };
    diag($@, $output) if $@;
    is_deeply($request->{stdin}, [$pins], 'native CLI forwards redirected pins from a regular file');
    is_deeply($request->{noderange}, ['compute[01-02]'], 'native CLI keeps the noderange');
}

SKIP: {
    my $python = '/usr/bin/python3';
    skip 'python3 is not installed', 1 unless -x $python;
    my ($status, $output) = run_command($python, '-I', repo_path('xCAT-test/unit/mkhostbased_auth_node.py'),
        repo_path('xCAT-server/share/xcat/scripts/xcat-hostbased-auth.py'));
    is($status, 0, 'node configuration fixtures pass') or diag($output);
}
done_testing();
