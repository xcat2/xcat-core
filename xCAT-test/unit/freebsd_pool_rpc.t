#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib $ENV{XCAT_FREEBSD_STATE_MODULE_DIR} || "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use File::Temp qw(tempdir);
use JSON;
use Storable qw(dclone);
use Test::More;
use XCAT::Test::PostageFixture qw(fixture);
use xCAT::FreeBSDInstall;
use xCAT::FreeBSDPool;

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsdpool.pm";
my $root = tempdir(CLEANUP => 1);
my $sequence = 0;
my $directory;
my $host = '192.0.2.1';
my $shared_tftp = 0;
my %addresses = (manager => '192.0.2.1', sn1 => '192.0.2.11', sn2 => '192.0.2.12', node1 => '192.0.2.20');
my @requests;
my $pool_request = \&xCAT::FreeBSDInstall::pool_request;
my $pool_boot = \&xCAT::FreeBSDInstall::pool_boot;
{
    no warnings qw(redefine once);
    *xCAT::NetworkUtils::getipaddr = sub { return $addresses{$_[1]} || $_[1]; };
    *xCAT::NetworkUtils::thishostisnot = sub { return $_[1] ne $host; };
    *xCAT::TableUtils::get_site_attribute = sub {
        return 'manager' if $_[1] eq 'master';
        return $shared_tftp if $_[1] eq 'sharedtftp';
        return;
    };
    *xCAT::FreeBSDInstall::pool_request = sub { return $pool_request->(@_, directory => "$directory/coordinator"); };
    *xCAT::FreeBSDInstall::pool_boot = sub { return $pool_boot->(@_, directory => "$directory/$host"); };
}

sub dispatch {
    my $request = shift;
    push @requests, dclone($request);
    if ($request->{command}[0] eq 'nodeset') {
        croak 'Boot request was routed incorrectly' unless $request->{_freebsd_owner}[0] eq $host;
        $xCAT::Table::rows{chain}[0]{currstate} = $request->{arg}[0];
        open(my $record, '>>', "$directory/boot-publications") or croak $!;
        print {$record} "$host\n" or croak $!;
        close($record) or croak $!;
        return {};
    }
    croak 'Unexpected coordinator command' unless $request->{command}[0] eq 'freebsdpool';
    my @responses;
    my $previous = $host;
    if ($request->{arg}[0] eq 'refresh') {
        my $scoped = xCAT_plugin::freebsdpool::preprocess_request($request,
            sub { push @responses, shift; return; });
        for my $part (@{$scoped || []}) {
            push @responses, dispatch($part);
        }
    } else {
        $host = $request->{_xcatdest} || '192.0.2.1';
        xCAT_plugin::freebsdpool::process_request($request, sub { push @responses, shift; return; }, \&dispatch);
    }
    $host = $previous;
    return {xcatresponse => \@responses};
}

sub reset_fixture {
    fixture(1);
    $shared_tftp = 0;
    $xCAT::Table::rows{noderes} = [{node => 'node1', servicenode => 'sn1,sn2'}];
    $directory = "$root/case-" . ++$sequence;
    @requests = ();
    $host = '192.0.2.1';
    my $topology = xCAT::FreeBSDPool::node_topology('node1');
    my $metadata = xCAT::FreeBSDPool::preparation('node1', 'osimage=freebsd', \&dispatch, $topology);
    my %generations;
    for my $server (@{$topology->{servers}}) {
        my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64,
            directory => "$directory/$server", service_pool => {%$metadata, server => $server});
        xCAT::FreeBSDPool::request('node1', 'register', {epoch => $metadata->{epoch}, server => $server,
            generation => $generation, fingerprint => 'b' x 64, master => $server}, \&dispatch, $topology);
        $generations{$server} = $generation;
    }
    return ($metadata, \%generations, $topology);
}

sub status {
    my ($server, $generation, $phase, $dispatcher, $action) = @_;
    $host = $server;
    return xCAT::FreeBSDInstall::transition('node1',
        'freebsd-install-v1 ' . $generation . ' ' . ('c' x 32) . " $phase\n",
        $action || sub { return; }, directory => "$directory/$server", dispatch => $dispatcher || \&dispatch);
}

sub rejected {
    my ($action, $pattern, $label) = @_;
    my $ok = eval { $action->(); 1; };
    ok(!$ok, "$label is rejected");
    like($@, $pattern, "$label explains why");
    return;
}

subtest 'public RPC and local transition bind the same winner' => sub {
    my ($metadata, $generations) = reset_fixture();
    like(status('192.0.2.12', $generations->{'192.0.2.12'}, 'begin'), qr/begin[ ]ok/x, 'second service node begins');
    is($requests[-1]{_xcatdest}, '192.0.2.1', 'service node uses the authenticated MN destination');
    rejected(sub { status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin'); },
        qr/coordinator[ ]rejected/x, 'standby claim');
    is(xCAT::FreeBSDInstall::state('node1', directory => "$directory/192.0.2.11")->{phase},
        'prepared', 'rejected standby does not enter a destructive phase');
    status('192.0.2.12', $generations->{'192.0.2.12'}, 'complete');
    status('192.0.2.12', $generations->{'192.0.2.12'}, 'booted');
    my $state = xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch);
    is($state->{owner}, '192.0.2.12', 'MN retains the selected owner');
    is($state->{phase}, 'booted', 'MN retains disk-boot acknowledgement');
    is(xCAT::FreeBSDPool::preparation('node1', 'enact', \&dispatch,
        xCAT::FreeBSDPool::node_topology('node1')), undef, 'server recovery does not rearm a completed installation');
    is(xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch)->{phase},
        'booted', 'enact leaves the installed ownership record unchanged');
    return;
};

subtest 'a pool epoch retains its registered local generation' => sub {
    my ($metadata, $generations, $topology) = reset_fixture();
    my $server = '192.0.2.11';
    my %options = (directory => "$directory/$server", service_pool => {%$metadata, server => $server});
    my $before = xCAT::FreeBSDInstall::state('node1', directory => "$directory/$server");
    my $publications = 0;
    for my $change ([('d' x 64)], [('a' x 64), postscript_preparations =>
        {firstboot => 'e' x 64, repeat => 'f' x 64}]) {
        rejected(sub { xCAT::FreeBSDInstall::prepare('node1', @$change, %options,
            publish => sub { ++$publications; return; }); }, qr/new[ ]pool[ ]epoch/x,
            'changed preparation within an existing epoch');
        is_deeply(xCAT::FreeBSDInstall::state('node1', directory => "$directory/$server"),
            $before, 'rejected replacement preserves registered local state');
    }
    is($publications, 0, 'changed preparation cannot replace the boot entry');
    is(xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, %options),
        $generations->{$server}, 'unchanged preparation retains the registered generation');
    my $next = xCAT::FreeBSDPool::preparation('node1', 'osimage=freebsd', \&dispatch, $topology);
    my $replacement = xCAT::FreeBSDInstall::prepare('node1', 'd' x 64,
        directory => "$directory/$server", service_pool => {%$next, server => $server});
    isnt($replacement, $generations->{$server}, 'an explicit new epoch accepts changed configuration');
    xCAT::FreeBSDPool::request('node1', 'register', {epoch => $next->{epoch}, server => $server,
        generation => $replacement, fingerprint => 'd' x 64, master => $server}, \&dispatch, $topology);
    like(status($server, $replacement, 'begin'), qr/begin[ ]ok/x, 'new registered generation can begin');
    return;
};

subtest 'missing and lost coordinator replies prevent local authorization' => sub {
    my (undef, $generations) = reset_fixture();
    my $actions = 0;
    my $action = sub { ++$actions; return; };
    rejected(sub { status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin', sub { return {}; }, $action); },
        qr/Missing[ ]or[ ]ambiguous/x, 'missing acknowledgement');
    is($actions, 0, 'missing acknowledgement invokes no installation action');
    is(xCAT::FreeBSDInstall::state('node1', directory => "$directory/192.0.2.11")->{phase},
        'prepared', 'missing acknowledgement leaves local preparation intact');
    rejected(sub { status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin', sub { dispatch(shift); return {}; }, $action); },
        qr/Missing[ ]or[ ]ambiguous/x, 'reply lost after durable claim');
    rejected(sub { status('192.0.2.12', $generations->{'192.0.2.12'}, 'begin'); },
        qr/coordinator[ ]rejected/x, 'standby following lost claim reply');
    status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin', \&dispatch, $action);
    is($actions, 1, 'same owner and attempt can recover the lost acknowledgement');
    return;
};

subtest 'shared TFTP cannot publish or prepare a service-node pool' => sub {
    my ($metadata, undef, $topology) = reset_fixture();
    my $before = xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch);
    for my $shared (undef, '1', 'yes', 'manager') {
        $shared_tftp = $shared;
        @requests = ();
        rejected(sub { xCAT::FreeBSDPool::preparation('node1', 'osimage=freebsd', \&dispatch, $topology); },
            qr/sharedtftp=0/x, 'shared TFTP preparation');
        is_deeply(\@requests, [], 'invalid TFTP policy sends no coordinator mutation');
        $host = '192.0.2.11';
        rejected(sub { xCAT::FreeBSDPool::local_preparation('node1',
            [encode_json({node1 => {%$metadata, server => $host}})], $topology); },
            qr/sharedtftp=0/x, 'forwarded preparation with shared TFTP');
    }
    $shared_tftp = 0;
    is_deeply(xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch), $before,
        'rejected preparations leave the epoch unchanged');
    return;
};

subtest 'disk boot reconciles completion after a management-node outage' => sub {
    my (undef, $generations) = reset_fixture();
    my $server = '192.0.2.11';
    status($server, $generations->{$server}, 'begin');
    my @actions;
    my $outage = sub {
        my $request = shift;
        my $input = decode_json($request->{arg}[1]);
        return {error => ['Management node unavailable']} if ($input->{phase} || '') eq 'complete';
        return dispatch($request);
    };
    rejected(sub { status($server, $generations->{$server}, 'complete', $outage,
        sub { push @actions, shift; return; }); }, qr/unavailable/x, 'completion acknowledgement during outage');
    is(xCAT::FreeBSDInstall::state('node1', directory => "$directory/$server")->{phase},
        'installed', 'disk boot was published and local installation completed');
    is(xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch)->{phase},
        'completing', 'coordinator retains the incomplete acknowledgement');
    my $recovered = eval {
        status($server, $generations->{$server}, 'booted', \&dispatch, sub { push @actions, shift; return; });
    };
    like($recovered, qr/booted[ ]ok/x, 'the recovered owner acknowledges disk boot');
    is(xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch)->{phase},
        'booted', 'disk boot reconciles the coordinator after connectivity returns');
    is_deeply(\@actions, [qw(complete booted)], 'recovery does not repeat installation or boot publication');
    return;
};

subtest 'converting a fixed owner to a pool fences its old preparation' => sub {
    reset_fixture();
    my $stale = "$directory/fixed";
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'e' x 64, directory => $stale);
    my $before = xCAT::FreeBSDInstall::state('node1', directory => $stale);
    my @dispatched;
    rejected(sub { xCAT::FreeBSDInstall::handle_status('node1', '192.0.2.20',
        'freebsd-install-v1 ' . $generation . ' ' . ('c' x 32) . " begin\n",
        sub { push @dispatched, shift; return {}; }, directory => $stale); },
        qr/registered[ ]local[ ]preparation/x, 'stale fixed-owner begin');
    is_deeply(\@dispatched, [], 'old preparation cannot perform any installation action');
    is_deeply(xCAT::FreeBSDInstall::state('node1', directory => $stale), $before,
        'rejection preserves the stale preparation for diagnosis');
    return;
};

subtest 'offline and membership changes fence prepared service nodes' => sub {
    my (undef, $generations, $topology) = reset_fixture();
    xCAT::FreeBSDPool::preparation('node1', 'offline', \&dispatch, $topology);
    for my $server (sort keys %$generations) {
        rejected(sub { status($server, $generations->{$server}, 'begin'); },
            qr/coordinator[ ]rejected/x, 'cancelled prepared service node');
    }
    (undef, $generations) = reset_fixture();
    $xCAT::Table::rows{noderes}[0]{servicenode} = 'sn2';
    rejected(sub { status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin'); },
        qr/coordinator[ ]rejected/x, 'removed pool member');
    return;
};

subtest 'malformed and ambiguous acknowledgements cannot authorize begin' => sub {
    my ($metadata, $generations) = reset_fixture();
    my $valid = {format => 'xcat-freebsd-pool-1', node => 'node1', operation => 'event',
        result => {epoch => $metadata->{epoch}, owner => '192.0.2.11', phase => 'installing'}};
    my @responses = ({data => ['broken']}, {data => [encode_json($valid), encode_json($valid)]},
        {data => [encode_json({%$valid, node => 'node2'})]},
        {data => [encode_json({%$valid, operation => 'inspect'})]},
        {error => ['denied'], data => [encode_json($valid)]},
        {data => [encode_json({%$valid, result => {%{$valid->{result}}, phase => 'prepared'}})]},
        {data => [encode_json({%$valid, result => {%{$valid->{result}}, owner => '192.0.2.12'}})]});
    for my $response (@responses) {
        my $actions = 0;
        my $ok = eval { status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin',
            sub { return $response; }, sub { ++$actions; return; }); 1; };
        ok(!$ok, 'invalid coordinator reply is rejected');
        is($actions, 0, 'invalid reply invokes no installation action');
    }
    return;
};

subtest 'completion does not depend on an unavailable standby' => sub {
    my (undef, $generations) = reset_fixture();
    require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/xnba.pm";
    $xCAT::Table::rows{chain} = [{node => 'node1', currstate => 'install'}];
    $host = '192.0.2.12';
    my @commands;
    my @boot_destinations;
    my $dispatcher = sub {
        my $request = shift;
        return {error => ['Standby is unavailable']} if $request->{command}[0] eq 'freebsdpool'
            && $request->{arg}[0] eq 'refresh';
        return dispatch($request) if $request->{command}[0] eq 'freebsdpool';
        push @commands, dclone($request);
        if ($request->{command}[0] eq 'nodeset') {
            my $scoped = xCAT_plugin::xnba::preprocess_request($request, sub { croak 'Boot scoping failed'; }, \&dispatch);
            for my $part (@{$scoped || []}) {
                my $destination = $part->{_xcatdest} || $host;
                croak 'Standby is unavailable' if $destination ne $host;
                push @boot_destinations, $destination;
                $xCAT::Table::rows{chain}[0]{currstate} = $part->{arg}[0];
            }
        } elsif ($request->{command}[0] eq 'updatenodestat') {
            $xCAT::Table::rows{nodelist}[0]{status} = $request->{arg}[0];
        } else {
            croak 'Unexpected status command';
        }
        return {};
    };
    for my $phase (qw(begin complete booted)) {
        my $reply = eval { xCAT::FreeBSDInstall::handle_status('node1', '192.0.2.20',
            'freebsd-install-v1 ' . $generations->{'192.0.2.12'} . ' ' . ('c' x 32) . " $phase\n",
            $dispatcher, directory => "$directory/192.0.2.12"); };
        like($reply, qr/\Q$phase\E[ ]ok/x, "$phase callback is acknowledged");
    }
    my ($boot) = grep { $_->{command}[0] eq 'nodeset' } @commands;
    is_deeply($boot->{_freebsd_owner}, ['192.0.2.12'], 'completion selects the serving node');
    is_deeply(\@boot_destinations, ['192.0.2.12'], 'the real xNBA scope sends disk boot only to the reachable owner');
    is($xCAT::Table::rows{chain}[0]{currstate}, 'boot', 'node is configured to boot from disk');
    is($xCAT::Table::rows{nodelist}[0]{status}, 'booted', 'disk boot is recorded');
    return;
};

subtest 'failed completion does not report an installed pool owner' => sub {
    my (undef, $generations) = reset_fixture();
    status('192.0.2.11', $generations->{'192.0.2.11'}, 'begin');
    rejected(sub { status('192.0.2.11', $generations->{'192.0.2.11'}, 'complete', \&dispatch,
        sub { croak 'Boot publication failed'; }); }, qr/Boot[ ]publication[ ]failed/x, 'completion action failure');
    my $state = xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch);
    is($state->{phase}, 'completing', 'coordinator retains the unfinished transition');
    status('192.0.2.11', $generations->{'192.0.2.11'}, 'failed');
    $state = xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch);
    is($state->{phase}, 'failed', 'installer can report failure after a failed completion');
    return;
};

subtest 'completed installations refresh standby boot entries through a bounded worker' => sub {
    my ($metadata, $generations) = reset_fixture();
    $xCAT::Table::rows{chain} = [{node => 'node1', currstate => 'install'}];
    status('192.0.2.12', $generations->{'192.0.2.12'}, 'begin');
    status('192.0.2.12', $generations->{'192.0.2.12'}, 'complete');
    ok(xCAT::FreeBSDPool::refresh_boot('node1', {%$metadata, server => '192.0.2.12'}, \&dispatch),
        'the real subprocess and scoped coordinator plugin refresh the standby');
    open(my $record, '<', "$directory/boot-publications") or croak $!;
    is(do { local $/; <$record> }, "192.0.2.11\n", 'only the standby receives disk boot publication');
    close($record) or croak $!;
    is(xCAT::FreeBSDPool::request('node1', 'inspect', {}, \&dispatch)->{phase}, 'installed',
        'standby publication leaves the selected installation intact');
    $host = '192.0.2.11';
    xCAT::FreeBSDPool::request('node1', 'cancel', {}, \&dispatch);
    rejected(sub { xCAT::FreeBSDInstall::pool_boot('node1',
        {epoch => $metadata->{epoch}, server => $host}, \&dispatch); }, qr/not[ ]completed/x,
        'delayed refresh after cancellation');
    my $replacement = xCAT::FreeBSDPool::preparation('node1', 'osimage=freebsd', \&dispatch,
        xCAT::FreeBSDPool::node_topology('node1'));
    xCAT::FreeBSDInstall::cancel('node1', directory => "$directory/$host");
    xCAT::FreeBSDInstall::prepare('node1', 'b' x 64, directory => "$directory/$host",
        service_pool => {%$replacement, server => $host});
    rejected(sub { xCAT::FreeBSDInstall::pool_boot('node1',
        {epoch => $metadata->{epoch}, server => $host}, \&dispatch); }, qr/Stale[ ]standby/x,
        'delayed refresh after local rearm');
};
done_testing();
