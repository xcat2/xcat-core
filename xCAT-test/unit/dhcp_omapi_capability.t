#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Config;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG} = 'SQLite:' . tempdir(CLEANUP => 1);
}

use xCAT::DHCP::OmapiPolicy;
use xCAT::DHCP::OmapiRunner;

my $directory = tempdir(CLEANUP => 1);
my $client = "$directory/custom-omshell";
write_text($client, "#!$Config{perlpath}\n" . <<'PERL');
use strict;
use warnings;
my $input = do { local $/; <STDIN> };
open(my $trace, '>>', $ENV{OMAPI_TRACE}) or die $!;
print {$trace} $input or die $!;
close($trace) or die $!;
if ($input eq "key-algorithm\n") {
    if ($ENV{OMAPI_CLIENT} eq 'legacy') {
        warn "unknown token: key-algorithm\n";
        print '> ';
    } elsif ($ENV{OMAPI_CLIENT} eq 'silent') {
        exit 0;
    } else {
        $| = 1;
        my $command = $ENV{OMAPI_CLIENT} eq 'corrected' ? 'key-algorithm' : 'key-algoritm';
        print "> missing or invalid algorithm name\nusage: $command <algorithm name>\n> ";
        exit 1 if $ENV{OMAPI_CLIENT} eq 'failed';
        if ($ENV{OMAPI_CLIENT} eq 'stalled') {
            $SIG{TERM} = 'IGNORE';
            open(my $pid, '>', $ENV{OMAPI_PID}) or die $!;
            print {$pid} $$;
            close($pid);
            sleep 60;
        }
    }
}
PERL
chmod 0755, $client or die $!;
local $ENV{OMAPI_TRACE} = "$directory/trace";
local $ENV{OMAPI_PID} = "$directory/pid";

{
    package FastCapabilityRunner;
    use parent 'xCAT::DHCP::OmapiRunner';
    sub _completion_delay { die 'a probe has no server state to settle'; }
    sub _poll_interval { return 0.01; }
    sub _completion_attempts { return 500; }
    sub _termination_attempts { return 10; }
}

sub settings {
    my ($algorithm, $fips) = @_;
    return xCAT::DHCP::OmapiPolicy->settings(
        fips_mode => $fips || 0,
        site_values => { dhcpomapialgorithm => $algorithm, dhcpomshellpath => $client }
    );
}

for my $algorithm (undef, 'hmac-md5') {
    local $ENV{OMAPI_CLIENT} = 'legacy';
    unlink $ENV{OMAPI_TRACE};
    is(FastCapabilityRunner->key_algorithm_error(settings($algorithm)), undef,
        'legacy MD5 does not require a SHA-capable client');
    ok(!-e $ENV{OMAPI_TRACE}, 'MD5 does not execute the probe');
}
for my $mode (qw(modern corrected legacy silent failed stalled)) {
    local $ENV{OMAPI_CLIENT} = $mode;
    write_text($ENV{OMAPI_TRACE}, '');
    my $error = FastCapabilityRunner->key_algorithm_error(settings('hmac-sha256'));
    if ($mode eq 'modern' || $mode eq 'corrected') {
        is($error, undef, "$mode omshell supports SHA selection");
    } else {
        like($error, qr/\Q$client\E.*hmac-sha256.*dhcpomshellpath/,
            "$mode omshell is rejected with a remediation message");
    }
    is(read_text($ENV{OMAPI_TRACE}), "key-algorithm\n",
        "$mode probe sends no connection command or secret");
}
my $stalled_pid = read_text($ENV{OMAPI_PID});
ok(!kill(0, $stalled_pid), 'the timed-out probe is reaped');
{
    my $missing = settings('hmac-sha512');
    $missing->{omshell_path} = "$directory/missing";
    like(FastCapabilityRunner->key_algorithm_error($missing), qr/Cannot verify/,
        'a missing custom client fails closed');
}

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm');
require $plugin;
{
    package CapabilityBackend;
    sub name { return $_[0]->{name}; }
    sub check_services { return {error => 'service boundary'}; }
}
{
    no warnings qw(redefine once);
    local *xCAT::Utils::isServiceNode = sub { return 0; };
    local *xCAT::Utils::isLinux = sub { return 1; };
    local *xCAT::Utils::isFIPS = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return 1; };
    local %::XCATSITEVALS = (dhcpomapialgorithm => 'hmac-sha256', dhcpomshellpath => $client);
    for my $site (
        ['rhels8.0', '', 1],
        ['ubuntu20.04', '', 0], ['ubuntu20.04', '192.0.2.1', 1],
        ['ubuntu22.04', '', 0], ['ubuntu22.04', '192.0.2.1', 1]
    ) {
        local $xCAT_plugin::dhcp::distro = $site->[0];
        local $::XCATSITEVALS{externaldhcpservers} = $site->[1];
        for my $backend (qw(isc kea)) {
            local *xCAT::DHCP::Backend::new_backend = sub { return bless {name => $backend}, 'CapabilityBackend'; };
            for my $mode (qw(legacy modern)) {
                local $ENV{OMAPI_CLIENT} = $mode;
                write_text($ENV{OMAPI_TRACE}, '');
                my @messages;
                my $mask = umask;
                xCAT_plugin::dhcp::process_request({arg => ['-q'], node => ['node01']},
                    sub { push @messages, map { @{$_->{error} || []}, @{$_->{data} || []} } @_; });
                umask $mask;
                my $messages = join ' ', @messages;
                my $probe = $backend eq 'isc' && $site->[2];
                my $label = "$site->[0] external=$site->[1] $backend $mode";
                if ($probe && $mode eq 'legacy') {
                    like($messages, qr/Cannot verify key-algorithm/, "$label rejects an unsupported SHA client");
                } else {
                    like($messages, qr/dhcp server is not running|service boundary/,
                        "$label reaches the service check");
                }
                is(read_text($ENV{OMAPI_TRACE}), $probe ? "key-algorithm\n" : '',
                    "$label probes only when the query uses OMAPI");
            }
        }
    }
}

my $root = "$directory/root";
make_path("$root/lib/perl/xCAT/DHCP", "$directory/commands");
write_text("$root/lib/perl/xCAT/DHCP/Backend.pm", <<'PERL');
package xCAT::DHCP::Backend;
sub new_backend { return bless {}, __PACKAGE__; }
sub name { return 'isc'; }
1;
PERL
write_text("$root/lib/perl/xCAT/Table.pm", <<'PERL');
package xCAT::Table;
sub new { return bless {}, __PACKAGE__; }
sub getAttribs { return {password => 'dGVzdA=='}; }
1;
PERL
my $wrapper = "$directory/dhcpop-wrapper";
write_text($wrapper, <<'PERL');
use xCAT::DHCP::OmapiRunner;
use xCAT::Utils;
no warnings 'redefine';
*xCAT::Utils::isFIPS = sub { return $ENV{OMAPI_FIPS}; };
*xCAT::DHCP::OmapiRunner::_completion_delay = sub { return 0; };
*xCAT::DHCP::OmapiRunner::_command_directory = sub { return $ENV{OMAPI_DIRECTORY}; };
our %XCATSITEVALS = (dhcpomapialgorithm => $ENV{OMAPI_ALGORITHM}, dhcpomshellpath => $ENV{OMAPI_PATH});
my $script = shift @ARGV;
do $script;
die $@ if $@;
PERL
for my $case (['hmac-md5', 0, 'legacy', 0], ['hmac-sha256', 0, 'legacy', 1],
    ['hmac-sha256', 0, 'modern', 0], ['', 1, 'legacy', 1]) {
    local @ENV{qw(XCATROOT OMAPI_ALGORITHM OMAPI_FIPS OMAPI_CLIENT OMAPI_DIRECTORY OMAPI_PATH)} =
        ($root, $case->[0], $case->[1], $case->[2], "$directory/commands", $client);
    write_text($ENV{OMAPI_TRACE}, '');
    open(my $child, '-|', $Config{perlpath}, "-I$root/lib/perl",
        '-I' . repo_path('perl-xCAT'), '-I' . repo_path('xCAT-server/lib/perl'),
        '-I' . repo_path('xCAT-test/lib'), $wrapper,
        repo_path('xCAT-server/share/xcat/tools/dhcpop'), '-r', '-n', 'node01') or die $!;
    my $output = do { local $/; <$child> };
    close($child);
    is($? >> 8, $case->[3], "dhcpop: algorithm=$case->[0] FIPS=$case->[1] client=$case->[2]");
    if ($case->[3]) {
        like($output, qr/Cannot verify key-algorithm/, 'dhcpop reports the capability error');
        unlike(read_text($ENV{OMAPI_TRACE}), qr/\bconnect\b|dGVzdA==/,
            'dhcpop stops before sending a secret or changing a lease');
    } else {
        like(read_text($ENV{OMAPI_TRACE}), qr/connect\nnew host/, 'dhcpop continues with the lease operation');
    }
}

done_testing();
