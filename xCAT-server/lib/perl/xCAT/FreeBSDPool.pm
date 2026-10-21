package xCAT::FreeBSDPool;

use strict;
use warnings;
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use JSON;
use xCAT::NetworkUtils;
use xCAT::Table;
use xCAT::TableUtils;

my $json = JSON->new->canonical->max_depth(12);

sub _fail { croak "FreeBSD service-node pool: $_[0]"; }

sub address {
    my $name = shift;
    _fail('One server hostname or IPv4 address is required') if !defined($name) || ref($name)
      || $name !~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/x;
    my $ip = xCAT::NetworkUtils->getipaddr($name, OnlyV4 => 1);
    _fail('Cannot resolve server to IPv4') if !defined($ip) || ref($ip)
      || $ip !~ /\A(?:[0-9]{1,3}[.]){3}[0-9]{1,3}\z/x;
    _fail('Invalid server IPv4 address') if grep { $_ > 255 || (length($_) > 1 && /^0/x) } split(/[.]/x, $ip);
    return $ip;
}

sub topology {
    my $resource = shift;
    _fail('Invalid node resources') unless ref($resource) eq 'HASH';
    return if length($resource->{xcatmaster} || '') || !length($resource->{servicenode} || '');
    my @names = split(/,/x, $resource->{servicenode}, -1);
    _fail('A service-node pool requires 1 to 32 servers') if !@names || @names > 32;
    my (@servers, %seen);
    for my $name (@names) {
        my $ip = address($name);
        _fail('Repeated service-node pool member') if $seen{$ip}++;
        push @servers, $ip;
    }
    my ($master) = xCAT::TableUtils->get_site_attribute('master');
    return {coordinator => address($master), servers => \@servers};
}

sub node_topology {
    my $node = shift;
    my $table = xCAT::Table->new('noderes', -create => 0) or _fail('Cannot open node resources');
    my $row = $table->getNodeAttribs($node, [qw(xcatmaster servicenode)]);
    $table->close();
    return topology($row || {});
}

sub _records {
    my @pending = (shift);
    my @records;
    my $count = 0;
    while (@pending) {
        my $response = shift @pending;
        _fail('Invalid pool coordinator response') if ++$count > 128 || ref($response) ne 'HASH';
        for my $field (qw(error errorcode)) {
            next unless exists($response->{$field});
            my @values = ref($response->{$field}) eq 'ARRAY' ? @{$response->{$field}} : ($response->{$field});
            for my $value (@values) {
                next if !defined($value) || (!ref($value) && ($value eq '' || $value eq '0'));
                _fail('Pool coordinator rejected the operation: ' . (ref($value) ? 'invalid result' : substr($value, 0, 1024)));
            }
        }
        for my $field (qw(node xcatresponse)) {
            next unless exists($response->{$field});
            _fail('Invalid nested coordinator response') unless ref($response->{$field}) eq 'ARRAY';
            push @pending, @{$response->{$field}};
        }
        if (exists($response->{data})) {
            _fail('Invalid coordinator result') unless ref($response->{data}) eq 'ARRAY';
            push @records, @{$response->{data}};
        }
    }
    return \@records;
}

sub request {
    my ($node, $operation, $input, $dispatch, $topology) = @_;
    _fail('Missing authenticated command dispatcher') unless ref($dispatch) eq 'CODE';
    $topology ||= node_topology($node);
    _fail('Node is not assigned to a service-node pool') unless $topology;
    my $wire = $json->encode($input);
    _fail('Pool request exceeds its size limit') if length($wire) > 65536;
    my $request = {command => ['freebsdpool'], node => [$node], arg => [$operation, $wire],
        _xcatpreprocessed => [1]};
    $request->{_xcatdest} = $topology->{coordinator}
      if xCAT::NetworkUtils->thishostisnot($topology->{coordinator});
    my $records = _records($dispatch->($request));
    _fail('Missing or ambiguous coordinator acknowledgement') if @$records != 1
      || !defined($records->[0]) || ref($records->[0]) || length($records->[0]) > 65536;
    my $result = eval { $json->decode($records->[0]); };
    _fail('Invalid coordinator acknowledgement') unless ref($result) eq 'HASH'
      && ($result->{format} || '') eq 'xcat-freebsd-pool-1' && ($result->{node} || '') eq $node
      && ($result->{operation} || '') eq $operation && ref($result->{result}) eq 'HASH';
    return $result->{result};
}

sub preparation {
    my ($node, $action, $dispatch, $topology) = @_;
    if ($action eq 'offline') {
        request($node, 'cancel', {}, $dispatch, $topology);
        return;
    }
    return if $action eq 'boot';
    _private_tftp();
    my $result = $action eq 'enact'
      ? request($node, 'inspect', {}, $dispatch, $topology)
      : request($node, 'prepare', {servers => $topology->{servers},
          fingerprint => sha256_hex($json->encode([$node, $action, $topology]))}, $dispatch, $topology);
    my %unprepared = map { $_ => 1 } qw(absent installing completing installed booted failed cancelled);
    return if $action eq 'enact' && $unprepared{$result->{phase} || ''};
    _fail('Pool installation is not prepared') unless ($result->{phase} || '') eq 'prepared'
      && ($result->{epoch} || '') =~ /\A[0-9a-f]{32}\z/x;
    return {epoch => $result->{epoch}, coordinator => $topology->{coordinator}};
}

sub _private_tftp {
    my ($shared) = xCAT::TableUtils->get_site_attribute('sharedtftp');
    _fail('Service-node pools require site.sharedtftp=0 and independent TFTP directories')
      unless defined($shared) && !ref($shared) && $shared =~ /\A(?:0|no)\z/ix;
    return;
}

sub local_preparation {
    my ($node, $wire, $topology) = @_;
    _private_tftp();
    _fail('Pool preparation metadata is required; run nodeset or set an explicit xcatmaster') if ref($wire) ne 'ARRAY'
      || @$wire != 1 || !defined($wire->[0]) || ref($wire->[0]) || length($wire->[0]) > 1048576;
    my $nodes = $json->decode($wire->[0]);
    _fail('Pool metadata does not contain this node') unless ref($nodes) eq 'HASH' && exists($nodes->{$node});
    my $metadata = $nodes->{$node};
    _fail('Invalid pool preparation server') if ref($metadata) ne 'HASH'
      || !defined($metadata->{server}) || ref($metadata->{server});
    _fail('Invalid pool preparation metadata') unless ref($metadata) eq 'HASH' && keys(%$metadata) == 3
      && ($metadata->{epoch} || '') =~ /\A[0-9a-f]{32}\z/x
      && ($metadata->{coordinator} || '') eq $topology->{coordinator};
    _fail('Preparation was sent to the wrong service node') if
      xCAT::NetworkUtils->thishostisnot($metadata->{server})
      || !grep { $_ eq $metadata->{server} } @{$topology->{servers}};
    return $metadata;
}

sub event {
    my ($node, $state, $attempt, $phase, $dispatch, $members) = @_;
    my $metadata = $state->{service_pool};
    my $topology = node_topology($node);
    _fail('Service-node pool configuration changed') if !$topology
      || $metadata->{coordinator} ne $topology->{coordinator}
      || xCAT::NetworkUtils->thishostisnot($metadata->{server});
    my $result = request($node, 'event', {epoch => $metadata->{epoch}, server => $metadata->{server},
        generation => $state->{generation}, attempt => $attempt, phase => $phase,
        defined($members) ? (members => $members) : ()}, $dispatch, $topology);
    _fail('Pool acknowledgement has a different generation') unless ($result->{epoch} || '') eq $metadata->{epoch};
    return if $phase eq 'failed' && ($result->{phase} || '') eq 'prepared' && !exists($result->{owner});
    my %expected = (begin => qr/\Ainstalling\z/x, complete => qr/\A(?:installed|booted)\z/x,
        completing => qr/\A(?:completing|installed|booted)\z/x,
        booted => qr/\Abooted\z/x, failed => qr/\Afailed\z/x);
    _fail('Pool acknowledgement does not authorize this installation') unless
      ($result->{owner} || '') eq $metadata->{server} && ($result->{phase} || '') =~ $expected{$phase};
    return;
}

sub refresh_boot {
    my ($node, $metadata, $dispatch) = @_;
    require xCAT::FreeBSDPkg;
    my %environment = map { $_ => $ENV{$_} } grep { defined($ENV{$_}) } keys %ENV;
    my $result = eval {
        xCAT::FreeBSDPkg::run_in_child(sub {
            _records($dispatch->({command => ['freebsdpool'], node => [$node],
                arg => ['refresh', $json->encode({epoch => $metadata->{epoch}, owner => $metadata->{server}})]}));
            return 0;
        }, timeout => 10, environment => \%environment, stdout_limit => 8192, stderr_limit => 8192);
    };
    return 1 if $result && $result->{callback_complete} && !$result->{callback_status}
        && $result->{streams_complete} && !$result->{failure};
    warn "FreeBSD service-node pool: standby boot refresh failed for $node; run nodeset $node enact after server recovery\n";
    return 0;
}

1;
