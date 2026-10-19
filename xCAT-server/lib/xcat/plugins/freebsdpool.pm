package xCAT_plugin::freebsdpool;

use strict;
use warnings;
use Carp qw(croak);
use JSON;
use xCAT::FreeBSDInstall;
use xCAT::FreeBSDPool;

sub handled_commands { return {freebsdpool => 'freebsdpool'}; }

sub _request {
    my $request = shift;
    croak 'One node and one pool operation are required' unless ref($request->{node}) eq 'ARRAY'
      && @{$request->{node}} == 1 && ref($request->{arg}) eq 'ARRAY' && @{$request->{arg}} == 2;
    my $node = $request->{node}[0];
    my ($operation, $wire) = @{$request->{arg}};
    croak 'Invalid pool node or operation' if !defined($node) || ref($node)
      || $node !~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/x || !defined($operation) || ref($operation)
      || $operation !~ /\A(?:prepare|register|event|inspect|cancel|refresh|boot)\z/x;
    croak 'Invalid pool operation payload' if !defined($wire) || ref($wire) || length($wire) > 8192;
    return ($node, $operation, $wire);
}

sub preprocess_request {
    my ($request, $callback) = @_;
    my $requests = eval {
        my ($node, $operation, $wire) = _request($request);
        return [$request] if $operation ne 'refresh';
        my $input = JSON->new->max_depth(12)->decode($wire);
        croak 'Invalid standby refresh request' unless ref($input) eq 'HASH' && keys(%$input) == 2
            && defined($input->{epoch}) && ref($input->{epoch}) eq '' && $input->{epoch} =~ /\A[0-9a-f]{32}\z/x
            && defined($input->{owner}) && ref($input->{owner}) eq '' && $input->{owner} =~ /\A[0-9.]+\z/x;
        my $topology = xCAT::FreeBSDPool::node_topology($node);
        croak 'Standby refresh was sent to another server' if xCAT::NetworkUtils->thishostisnot($input->{owner});
        croak 'Standby refresh requires the local pool owner' unless $topology
            && grep { $_ eq $input->{owner} } @{$topology->{servers}};
        return [map { {command => ['freebsdpool'], node => [$node], _xcatpreprocessed => [1],
            _xcatdest => $_, arg => ['boot', JSON->new->encode({epoch => $input->{epoch}, server => $_})]} }
            grep { $_ ne $input->{owner} } @{$topology->{servers}}];
    };
    $callback->({error => [$@ || 'Cannot scope standby boot refresh'], errorcode => [1]}) if $@;
    return $requests;
}

sub process_request {
    my ($request, $callback, $dispatch) = @_;
    my $ok = eval {
        my ($node, $operation, $wire) = _request($request);
        my $json = JSON->new->canonical->max_depth(12);
        my $input = $json->decode($wire);
        croak 'Invalid pool operation payload' unless ref($input) eq 'HASH';
        if ($operation eq 'boot') {
            my $result = xCAT::FreeBSDInstall::pool_boot($node, $input, $dispatch);
            $callback->({data => [$json->encode({format => 'xcat-freebsd-pool-1', node => $node,
                operation => $operation, result => $result})]});
            return 1;
        }
        my $topology = xCAT::FreeBSDPool::node_topology($node);
        croak 'The management node must coordinate this service-node pool' if !$topology
          || xCAT::NetworkUtils->thishostisnot($topology->{coordinator});
        if ($operation eq 'prepare') {
            croak 'Pool membership changed during preparation' unless ref($input->{servers}) eq 'ARRAY'
              && $json->encode($input->{servers}) eq $json->encode($topology->{servers});
        } elsif (exists($input->{server})) {
            croak 'Invalid pool server' if !defined($input->{server}) || ref($input->{server});
            croak 'Server no longer belongs to this pool' unless
              grep { $_ eq $input->{server} } @{$topology->{servers}};
        }
        my $result = xCAT::FreeBSDInstall::pool_request($node, $operation, $input);
        $callback->({data => [$json->encode({format => 'xcat-freebsd-pool-1', node => $node,
            operation => $operation, result => $result})]});
        1;
    };
    $callback->({error => [$@ || 'Service-node pool operation failed'], errorcode => [1]}) unless $ok;
    return;
}

1;
