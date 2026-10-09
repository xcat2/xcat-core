#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use HTTP::Response;
use JSON;
use Test::More;

our ($now, @login_children);
BEGIN {
    no warnings 'once';
    if (@ARGV && $ARGV[0] eq '--fixture') {
        $now = 0;
        *CORE::GLOBAL::time = sub () { return $now; };
        *CORE::GLOBAL::waitpid = sub ($$) {
            $? = 0;
            return @login_children ? shift @login_children : -1;
        };
    }
}

{
    package RetryTable;

    sub getAttribs { return { username => 'test-user', password => 'test-password' }; }

    sub getNodesAttribs {
        my ($self, $nodes) = @_;
        return { map { $_ => [{ bmc => "$_.example" }] } @$nodes };
    }
}

{
    package RetryHTTP;

    sub add_with_opts { return $_[0]{send}->($_[1]); }
    sub wait_for_next_response { return $_[0]{receive}->(); }
}

sub run_fixture {
    my ($replies) = @_;
    my (@requests, @messages, @responses, @warnings);
    local $SIG{__WARN__} = sub { push @warnings, @_; };
    my $config = tempdir(CLEANUP => 1);
    $ENV{XCATCFG} = "SQLite:$config";
    my $source = File::Spec->rel2abs("$FindBin::Bin/../../xCAT-server");
    my $plugin = "$source/lib/xcat/plugins/openbmc.pm";
    if (-d "$FindBin::Bin/../../perl-xCAT") {
        $ENV{XCATROOT} = $source;
        unshift @INC, "$source/lib/perl", "$source/lib",
            "$FindBin::Bin/../../perl-xCAT";
    } else {
        my $root = $ENV{XCATROOT} || '/opt/xcat';
        $root = '/opt/xcat' unless -f "$root/lib/perl/xCAT_plugin/openbmc.pm";
        $ENV{XCATROOT} = $root;
        unshift @INC, "$root/lib/perl";
        $plugin = "$root/lib/perl/xCAT_plugin/openbmc.pm";
    }

    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
    require File::Path;
    {
        no warnings 'redefine';
        # Loading the plugin must not create its system log directories.
        local *File::Path::mkpath = sub { return; };
        require $plugin;
    }

    my $handle = 0;
    my $pid = 1000;
    $now = 0;
    no warnings 'redefine';
    no warnings 'once';
    local *xCAT::Table::new = sub {
        my ($class, $name) = @_;
        die "Unexpected table: $name" unless $name eq 'passwd' || $name eq 'openbmc';
        return bless {}, 'RetryTable';
    };
    local *xCAT::NetworkUtils::getNodeIPaddress = sub { return '192.0.2.1'; };
    local *xCAT::Utils::xfork = sub {
        push @login_children, ++$pid;
        return $pid;
    };
    local *LWP::UserAgent::request = sub { die 'Unexpected synchronous HTTP request'; };
    my $send = sub {
        my ($request) = @_;
        my $node = $request->uri->host;
        $node =~ s/\.example$//;
        die "Unexpected BMC: $node" unless exists $replies->{$node};
        my $login = $request->uri->path eq '/login';
        my $code = $login ? 200 : shift @{$replies->{$node}};
        die "Unexpected extra request for $node" unless defined $code;
        push @requests, {
            node => $node, time => $now, method => $request->method,
            path => $request->uri->path, content => $request->content,
            authorization => scalar $request->header('Authorization'),
        };
        my $response = HTTP::Response->new($code);
        $response->content($code == 503 ? 'Service Unavailable' : encode_json({ data => {
            '/xyz/openbmc_project/state/chassis0' => {
                CurrentPowerState => 'xyz.openbmc_project.State.Chassis.PowerState.Off',
                RequestedPowerTransition => 'xyz.openbmc_project.State.Chassis.Transition.Off',
            },
            description => 'BMC request failed',
        } }));
        push @responses, [$response, ++$handle];
        return $handle;
    };
    my $receive = sub {
        return @{shift @responses} if @responses;
        die "Request did not complete" if ++$now > 30;
        return;
    };
    local *HTTP::Async::new = sub {
        return bless { send => $send, receive => $receive }, 'RetryHTTP';
    };
    local $SIG{ALRM} = sub { die "Request timed out\n"; };
    alarm 10;
    xCAT_plugin::openbmc::process_request({
        command => ['rpower'], arg => ['stat'], node => [sort keys %$replies],
    }, sub { push @messages, $_[0]; });
    alarm 0;
    return { requests => \@requests, messages => \@messages, warnings => \@warnings,
        pending => scalar @responses, remaining => $replies };
}

if (@ARGV && $ARGV[0] eq '--fixture') {
    print encode_json(run_fixture(decode_json($ARGV[1])));
    exit 0;
}

sub check_request {
    my ($replies, $expected) = @_;
    # A fresh interpreter gives each request its own plugin state.
    open(my $child, '-|', $^X, File::Spec->rel2abs(__FILE__), '--fixture',
        encode_json($replies)) or die "Cannot start fixture: $!";
    my $output = do { local $/; <$child> };
    close $child;
    is($?, 0, 'request completes without a fixture error');
    my $result = eval { decode_json($output) };
    my $decode_error = $@;
    ok(ref($result) eq 'HASH', 'fixture returns request results') or do {
        diag($decode_error || $output || 'No fixture output');
        return;
    };
    is_deeply($result->{warnings}, [], 'no runtime warnings');
    is($result->{pending}, 0, 'all HTTP responses are consumed');
    is(scalar @{$result->{messages}}, scalar keys %$replies,
        'only the requested nodes produce results');
    for my $node (sort keys %$replies) {
        my @login = grep { $_->{node} eq $node && $_->{path} eq '/login' }
            @{$result->{requests}};
        is(scalar @login, 1, "$node logs in once");
        is($login[0]{method}, 'POST', "$node sends the login request");
        my @sent = grep { $_->{node} eq $node && $_->{path} ne '/login' }
            @{$result->{requests}};
        is_deeply([map { $_->{time} } @sent], $expected->{$node}{times},
            "$node retries at three-second intervals, then stops");
        is_deeply([map { [@{$_}{qw(method path content authorization)}] } @sent],
            [map { ['GET', '/xyz/openbmc_project/state/enumerate', '',
                'Basic dGVzdC11c2VyOnRlc3QtcGFzc3dvcmQ='] } @{$expected->{$node}{times}}],
            "$node preserves the request and credentials on each attempt");
        my $message = { name => [$node] };
        if (exists $expected->{$node}{error}) {
            $message->{errorcode} = [1];
            $message->{error} = [$expected->{$node}{error}];
        } else {
            $message->{data} = [{ contents => [$expected->{$node}{result}] }];
        }
        is_deeply([grep { $_->{node}[0]{name}[0] eq $node } @{$result->{messages}}],
            [{ node => [$message] }],
            "$node reports exactly one final result");
        is_deeply($result->{remaining}{$node}, [], "$node consumes the expected replies");
    }
}

for my $failures (0 .. 3) {
    subtest "success after $failures service-unavailable responses" => sub {
        check_request({ node01 => [(503) x $failures, 200] }, {
            node01 => { times => [map { 3 * $_ } 0 .. $failures], result => 'off' },
        });
    };
}

subtest 'the fourth 503 ends the request' => sub {
    check_request({ node01 => [(503) x 4] }, {
        node01 => { times => [0, 3, 6, 9], error => '503 Service Unavailable' },
    });
};

subtest 'other errors are not retried' => sub {
    check_request({ node01 => [502] }, {
        node01 => { times => [0], error => '[502] BMC request failed' },
    });
};

subtest 'one exhausted node does not stop or spend another node retry budget' => sub {
    check_request({ node01 => [(503) x 4], node02 => [503, 503, 503, 200], node03 => [200] }, {
        node01 => { times => [0, 3, 6, 9], error => '503 Service Unavailable' },
        node02 => { times => [0, 3, 6, 9], result => 'off' },
        node03 => { times => [0], result => 'off' },
    });
};

done_testing();
