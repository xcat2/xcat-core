#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(repo_path);

use File::Spec;
use Test::More;

my $plugin_path = repo_path('xCAT-server/lib/xcat/plugins/openbmc.pm');

open my $plugin_fh, '<', $plugin_path
  or die "Could not open $plugin_path: $!\n";
my $plugin_source = do { local $/; <$plugin_fh> };
close $plugin_fh;

sub extract_subroutine {
    my ($name) = @_;
    my ($subroutine) =
      $plugin_source =~ /(^sub \Q$name\E \{.*?^\}\n)(?=\n#-+)/ms;
    die "Could not extract $name from $plugin_path\n"
      if !defined $subroutine;
    return $subroutine;
}

my $retry_after        = extract_subroutine('retry_after');
my $deal_with_response = extract_subroutine('deal_with_response');

{
    package xCAT::SvrUtils;

    our @messages;

    sub sendmsg {
        push @messages, [@_];
    }
}

{
    package OpenBMC503Response;

    sub new {
        return bless {}, shift;
    }

    sub status_line {
        return '503 Service Unavailable';
    }
}

## no critic (BuiltinFunctions::ProhibitStringyEval)
my $loaded = eval <<"HARNESS";
package OpenBMC503Harness;
no strict 'vars';
use warnings;
use JSON;
$retry_after
$deal_with_response
1;
HARNESS
## use critic
die "Could not load the OpenBMC response harness: $@\n" if !$loaded;

$::RESPONSE_OK                  = '200 OK';
$::RESPONSE_SERVICE_UNAVAILABLE = '503 Service Unavailable';
$::UPLOAD_ACTIVATE_STREAM       = 0;
$::UPLOAD_AND_ACTIVATE          = 0;

my $node     = 'node01';
my $response = OpenBMC503Response->new();
my $callback = sub { };

$OpenBMC503Harness::callback       = $callback;
$OpenBMC503Harness::wait_node_num  = 1;
$OpenBMC503Harness::xcatdebugmode  = 0;
$OpenBMC503Harness::next_status{LOGIN_RESPONSE} = 'RPOWER_STATUS_REQUEST';

for my $attempt (1 .. 3) {
    subtest "503 retry attempt $attempt is scheduled" => sub {
        my $handle = "handle-$attempt";
        $OpenBMC503Harness::handle_id_node{$handle} = $node;
        $OpenBMC503Harness::node_info{$node}{cur_status} =
          'RPOWER_STATUS_RESPONSE';
        delete $OpenBMC503Harness::node_wait{$node};

        my @warnings;
        my $before = time();
        {
            local $SIG{__WARN__} = sub { push @warnings, @_ };
            OpenBMC503Harness::deal_with_response($handle, $response);
        }
        my $after = time();

        is(
            $OpenBMC503Harness::node_info{$node}{_503_retries},
            $attempt,
            'retry counter is incremented once'
        );
        is(
            $OpenBMC503Harness::node_info{$node}{cur_status},
            'RPOWER_STATUS_REQUEST',
            'response state returns to its request state'
        );
        cmp_ok(
            $OpenBMC503Harness::node_wait{$node},
            '>=',
            $before + 3,
            'retry deadline is at least three seconds from entry'
        );
        cmp_ok(
            $OpenBMC503Harness::node_wait{$node},
            '<=',
            $after + 3,
            'retry deadline is no more than three seconds from return'
        );
        ok(
            !exists $OpenBMC503Harness::handle_id_node{$handle},
            'completed response handle is removed'
        );
        is(
            $OpenBMC503Harness::wait_node_num,
            1,
            'node remains active while a retry is pending'
        );
        is_deeply(\@xCAT::SvrUtils::messages, [], 'no error is reported');
        is_deeply(\@warnings, [], 'no warning is emitted');
    };
}

subtest 'fourth 503 exhausts retries' => sub {
    my $handle = 'handle-4';
    $OpenBMC503Harness::handle_id_node{$handle} = $node;
    $OpenBMC503Harness::node_info{$node}{cur_status} =
      'RPOWER_STATUS_RESPONSE';
    delete $OpenBMC503Harness::node_wait{$node};

    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        OpenBMC503Harness::deal_with_response($handle, $response);
    }

    is(
        $OpenBMC503Harness::node_info{$node}{_503_retries},
        4,
        'retry counter records the exhausted attempt'
    );
    is(
        $OpenBMC503Harness::node_info{$node}{cur_status},
        'RPOWER_STATUS_RESPONSE',
        'terminal response state is not rescheduled'
    );
    ok(
        !exists $OpenBMC503Harness::node_wait{$node},
        'no retry deadline is set'
    );
    ok(
        !exists $OpenBMC503Harness::handle_id_node{$handle},
        'completed response handle is removed'
    );
    is($OpenBMC503Harness::wait_node_num, 0, 'node is completed');
    is_deeply(
        \@xCAT::SvrUtils::messages,
        [[[1, '503 Service Unavailable'], $callback, $node]],
        'the existing terminal error is reported'
    );
    is_deeply(\@warnings, [], 'no warning is emitted');
};

done_testing();
