package xCAT::FreeBSDUpdate;

use strict;
use warnings;
use File::Basename qw(dirname);
use Getopt::Long ();
use Storable qw(dclone);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC sleep);
use xCAT::Table;
use xCAT::TableUtils;
use xCAT::Utils;

sub _fail { die "FreeBSD updatenode: $_[0]\n"; }

sub _native_type {
    my ($row, $cache) = @_;
    return 1 if ($row->{os} || '') =~ /\Afreebsd/ix;
    my $name = $row->{provmethod};
    return 0 unless defined($name) && length($name);
    return 0 if $name =~ /\A(?:install|netboot|statelite)\z/x;
    unless (exists($cache->{$name})) {
        my $table = xCAT::Table->new('osimage', -create => 0, -autocommit => 1)
          or _fail('Cannot read node image');
        my $image = eval { $table->getAttribs({ imagename => $name }, [qw(imagetype osname osvers osarch provmethod)]) };
        my $error = $@;
        $table->close();
        _fail('Cannot read node image') if $error;
        $cache->{$name} = defined(xCAT::Utils->freebsd_image_error($image)) ? 1 : 0;
    }
    return $cache->{$name};
}

sub _split {
    my $request = shift;
    return ($request, undef) unless @{$request->{node} || []};
    my $table = xCAT::Table->new('nodetype', -create => 0, -autocommit => 1)
      or _fail('Cannot read node types');
    my $rows = eval { $table->getNodesAttribs($request->{node}, [qw(os provmethod)]) };
    my $error = $@;
    $table->close();
    _fail('Cannot read node types') if $error || ref($rows) ne 'HASH';
    my (@native, @legacy, %seen, %images);
    for my $node (@{$request->{node}}) {
        my $row = $rows->{$node} && $rows->{$node}[0] ? $rows->{$node}[0] : {};
        if (_native_type($row, \%images)) {
            push @native, $node unless $seen{$node}++;
        } else {
            push @legacy, $node;
        }
    }
    return ($request, undef) unless @native;
    my $native = dclone($request);
    $native->{node} = \@native;
    my $legacy;
    if (@legacy) {
        $legacy = dclone($request);
        $legacy->{node} = \@legacy;
    }
    return ($legacy, $native);
}

sub _validate_selection {
    my ($request, $options) = @_;
    if (defined($options->{run})) {
        _fail('A retained run requires one FreeBSD node') unless @{$request->{node}} == 1;
        _fail('Invalid retained run identity') unless $options->{run} =~ /\A[0-9a-f]{32}\z/x;
        _fail('A retained run cannot select new scripts') if defined($options->{scripts});
        _fail('A retained run cannot synchronize files again') if $options->{syncfiles};
        _fail('A retained run cannot select another software update') if $options->{software};
    } else {
        _fail('Explicit release requires --freebsd-run') if $options->{release};
        _fail('An update requires -F, -S, -P or a script list')
          unless $options->{syncfiles} || $options->{software} || defined($options->{scripts});
    }
    return;
}

sub _options {
    my $request = shift;
    my @arguments = @{$request->{arg} || []};
    my %options;
    my $parser = Getopt::Long::Parser->new(config => [qw(bundling no_ignore_case no_auto_abbrev no_pass_through)]);
    my $parsed = $parser->getoptionsfromarray(\@arguments,
        'P|scripts:s' => \$options{scripts}, 'F|sync' => \$options{syncfiles},
        'S|sw' => \$options{software},
        'freebsd-run=s' => \$options{run},
        'freebsd-release' => \$options{release}, 't|timetout|timeout=i' => \$options{timeout},
        'V|verbose' => \$options{verbose}, 'h|help' => \$options{help}, 'v|version' => \$options{version});
    _fail('Unsupported options for this FreeBSD update operation') unless $parsed;
    if (@arguments == 1 && !defined($options{scripts}) && !defined($options{run})
        && index($arguments[0], '=') < 0) {
        $options{scripts} = shift @arguments;
    }
    _fail('Unexpected FreeBSD update operands') if @arguments;
    return \%options if $options{help} || $options{version};
    _validate_selection($request, \%options);
    $options{timeout} = 3600 unless defined($options{timeout});
    _fail('Invalid FreeBSD update timeout') if $options{timeout} < 1 || $options{timeout} > 7200;
    return \%options;
}

sub _informational {
    my ($options, $callback) = @_;
    if ($options->{help}) {
        $callback->({ data => ['updatenode <nodes> [-F] [-S] [-P [scripts]]',
            'updatenode <node> --freebsd-run <run> [--freebsd-release] [-t seconds]'] });
        return 1;
    }
    if ($options->{version}) {
        $callback->({ data => [xCAT::Utils->Version()] });
        return 1;
    }
    return 0;
}

sub _route {
    my ($request, $callback, $dispatch) = @_;
    require xCAT::InstUtils;
    require xCAT::NetworkUtils;
    require xCAT::FreeBSDPool;
    my (@fixed, %pool_owners);
    for my $pool_node (@{$request->{node}}) {
        my $pool = xCAT::FreeBSDPool::node_topology($pool_node);
        if ($pool) {
            my $state = xCAT::FreeBSDPool::request($pool_node, 'inspect', {}, $dispatch, $pool);
            _fail('Service-node pool has no installed owner') if ($state->{phase} || '') !~ /\A(?:installed|booted)\z/x
              || !defined($state->{owner}) || ref($state->{owner})
              || !grep { $_ eq $state->{owner} } @{$pool->{servers}};
            push @{$pool_owners{$state->{owner}}}, $pool_node;
        } else {
            push @fixed, $pool_node;
        }
    }
    my $owners = @fixed ? xCAT::InstUtils->get_server_nodes($callback, \@fixed, 0) : {};
    _fail('Cannot determine management-node owners') unless ref($owners) eq 'HASH';
    push @{$owners->{$_}}, @{$pool_owners{$_}} for keys %pool_owners;
    my %expected = map { $_ => 1 } @{$request->{node}};
    my (@requests, %seen);
    for my $owner (sort keys %$owners) {
        _fail('FreeBSD owner must resolve to IPv4') unless $owner =~ /\A(?:[0-9]{1,3}[.]){3}[0-9]{1,3}\z/x;
        for my $node (@{$owners->{$owner}}) {
            _fail('Ambiguous FreeBSD update owner') if !$expected{$node} || $seen{$node}++;
        }
        my $scoped = dclone($request);
        $scoped->{node} = $owners->{$owner};
        $scoped->{_xcatpreprocessed} = [1];
        delete $scoped->{_xcatdest};
        $scoped->{_xcatdest} = $owner if xCAT::NetworkUtils->thishostisnot($owner);
        push @requests, $scoped;
    }
    _fail('Missing FreeBSD update owner') unless keys(%seen) == keys(%expected);
    return \@requests;
}

sub preprocess {
    my ($request, $callback, $subrequest, $legacy_handler) = @_;
    my $result;
    my $ok = eval {
        my ($legacy, $native) = _split($request);
        if (!$native) {
            $result = $legacy_handler->($request, $callback, $subrequest);
        } else {
            my $options = _options($native);
            _fail('A retained run cannot include other operating systems') if $legacy && defined($options->{run});
            if (_informational($options, $callback)) {
                $result = [];
            } else {
                $result = _route($native, $callback, $subrequest);
                if ($legacy) {
                    my $requests = $legacy_handler->($legacy, $callback, $subrequest);
                    push @$result, @$requests if $requests;
                }
            }
        }
        1;
    };
    unless ($ok) {
        $callback->({ error => [$@ || 'Cannot preprocess FreeBSD update'], errorcode => [1] });
        return;
    }
    return $result;
}

sub _report {
    my ($node, $run, $report, $callback) = @_;
    if ($report->{package_recovery}) {
        $callback->({ data => ["$node: Package provenance recovered; the interrupted execution remains uncertain."] });
    }
    if ($report->{package_preservation}) {
        $callback->({ data => ["$node: Package application did not start; previous package provenance retained."] });
    }
    if (my $logs = $report->{framework_logs}) {
        for my $name (sort keys %$logs) {
            $callback->({ data => ["$node: Framework diagnostic: $logs->{$name}{path}"] });
        }
    }
    if (my $prerequisite = $report->{prerequisite}) {
        $callback->({ data => ["$node: Package prerequisite failed during $prerequisite->{phase}; diagnostic: $prerequisite->{stderr}{path}"] });
    }
    if (my $logs = $report->{prerequisite_logs}) {
        for my $stream (qw(stdout stderr)) {
            next unless $logs->{$stream};
            $callback->({ data => ["$node: Package prerequisite $stream: $logs->{$stream}{path}"] });
        }
    }
    for my $entry (@{$report->{entries}}) {
        my $status = defined($entry->{status}) ? "exit $entry->{status}" : $entry->{state};
        for my $stream (qw(stdout stderr)) {
            next unless $entry->{$stream};
            $status .= "; $stream truncated at $entry->{$stream}{limit} bytes" if $entry->{$stream}{truncated};
            $status .= "; $stream remained open after command exit" if $entry->{$stream}{open_after_exit};
        }
        $callback->({ data => ["$node: $entry->{phase} $entry->{script}: $status"] });
    }
    $callback->({ data => ["$node: FreeBSD postscript run $run: $report->{receipt}{outcome}"] });
    my $path = dirname($report->{archive}{path}) . '/report.json';
    $callback->({ data => ["$node: FreeBSD postscript report: $path"] });
    return;
}

sub _sync {
    my ($node, $options, $callback, $subrequest, @transport) = @_;
    require xCAT::FreeBSDInstall;
    my $state = xCAT::FreeBSDInstall::state($node);
    _fail('File synchronization requires an installed FreeBSD node') unless $state
      && $state->{phase} =~ /\A(?:installed|booted)\z/x;
    xCAT::TableUtils->setUpdateStatus([$node], 'syncing');
    my $synced = eval {
        xCAT::FreeBSDPostscript::sync_files($node, $subrequest, $options->{timeout}, @transport);
    };
    my $error = $@;
    xCAT::TableUtils->setUpdateStatus([$node], $synced ? 'synced' : 'failed');
    _fail($error || 'File synchronization did not complete') unless $synced;
    $callback->({ data => ["$node: File synchronization completed ($synced->{lists} lists); evidence: $synced->{directory}"] });
    return;
}

sub _run {
    my ($node, $request, $options, $callback, $subrequest) = @_;
    require xCAT::FreeBSDPostscript;
    my @exports;
    if (defined($options->{run})) {
        push @exports, xCAT::FreeBSDPostscript::read_export($options->{run});
    } else {
        push @exports, xCAT::FreeBSDPostscript::prepare_update($node, 'ospkgs,otherpkgs', require_packages => 1)
          if $options->{software};
        push @exports, xCAT::FreeBSDPostscript::prepare_update($node, $options->{scripts}) if defined($options->{scripts});
    }
    _fail('Retained run belongs to another node') if grep { $_->{node} ne $node } @exports;
    my @transport = exists($request->{username}) ? (username => $request->{username}) : ();
    _sync($node, $options, $callback, $subrequest, @transport) if $options->{syncfiles};
    for my $export (@exports) {
        return 1 if _execute_export($export, $options, $callback, $subrequest, @transport);
    }
    return 0;
}

sub _execute_export {
    my ($export, $options, $callback, $subrequest, @transport) = @_;
    my $node = $export->{node};
    my $run = $export->{binding}{run};
    $callback->({ data => ["$node: FreeBSD postscript run $run"] });
    xCAT::TableUtils->setUpdateStatus([$node], 'syncing');
    my $result = eval {
        xCAT::FreeBSDPostscript::release_execution($run, $subrequest, @transport) if $options->{release};
        _observe_export($export, $options, $callback, $subrequest, @transport);
    };
    my $error = $@;
    if (length($error)) {
        xCAT::TableUtils->setUpdateStatus([$node], 'failed');
        _fail($error);
    }
    return $result;
}

sub _observe_export {
    my ($export, $options, $callback, $subrequest, @transport) = @_;
    my $node = $export->{node};
    my $run = $export->{binding}{run};
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + $options->{timeout};
    my $busy_reported = 0;
    while (1) {
        my $receipt = xCAT::FreeBSDPostscript::deliver_execution($run, $subrequest, @transport);
        if ($receipt->{outcome} eq 'busy' && !$busy_reported++) {
            $callback->({ data => ["$node: Node is busy; waiting to start FreeBSD postscript run $run."] });
        }
        if ($receipt->{complete} eq 'yes' || $receipt->{outcome} eq 'uncertain') {
            if ($receipt->{outcome} eq 'uncertain') {
                $callback->({ data => ["$node: Run $run has uncertain execution. Node diagnostics: /var/db/xcat/postscripts/runs/$run. "
                    . "To release after verified command completion or a reboot: updatenode $node --freebsd-run $run --freebsd-release"] });
            }
            my $report = xCAT::FreeBSDPostscript::collect_execution($run, $subrequest, @transport);
            _report($node, $run, $report, $callback);
            my $success = $report->{receipt}{complete} eq 'yes' && $report->{receipt}{outcome} eq 'success';
            xCAT::TableUtils->setUpdateStatus([$node], $success ? 'synced' : 'failed');
            return $success ? 0 : 1;
        }
        if (clock_gettime(CLOCK_MONOTONIC) >= $deadline) {
            $callback->({ error => ["$node: Run $run is still $receipt->{outcome}; use --freebsd-run $run to resume observation"],
                errorcode => [1] });
            return 1;
        }
        sleep(1);
    }
    return;
}

sub process {
    my ($request, $callback, $subrequest, $legacy_handler) = @_;
    my ($legacy, $native, $options);
    my $valid = eval {
        ($legacy, $native) = _split($request);
        $options = _options($native) if $native;
        _fail('A retained run cannot include other operating systems') if $legacy && $options && defined($options->{run});
        1;
    };
    unless ($valid) {
        $callback->({ error => [$@], errorcode => [1] });
        return 1;
    }
    return $legacy_handler->($request, $callback, $subrequest) unless $native;
    return 0 if _informational($options, $callback);
    my $failed = 0;
    for my $node (@{$native->{node}}) {
        my $result = eval { _run($node, $native, $options, $callback, $subrequest) };
        if ($@) {
            $callback->({ error => ["$node: $@"], errorcode => [1] });
            $failed = 1;
        } elsif ($result) {
            $callback->({ error => ["$node: FreeBSD postscript update did not complete successfully"], errorcode => [1] });
            $failed = 1;
        }
    }
    $failed = 1 if $legacy && $legacy_handler->($legacy, $callback, $subrequest);
    return $failed;
}

1;
