#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::More;
use XCAT::Test::File qw(repo_path);

my %rows;
my %resolved_nodes;

BEGIN {
    package xCAT::Table;
    sub new {
        my ( $class, $table ) = @_;
        die "Unexpected table $table" unless $table eq 'chain';
        return bless {}, $class;
    }
    sub getNodesAttribs {
        my ( $self, $nodes, @attributes ) = @_;
        @attributes = @{ $attributes[0] } if ref($attributes[0]) eq 'ARRAY';
        my %result;
        for my $node (@$nodes) {
            $result{$node} = exists($rows{$node})
              ? [ { map { $_ => $rows{$node}->{$_} } @attributes } ]
              : [undef];
        }
        return \%result;
    }
    sub setNodeAttribs {
        my ( $self, $node, $attributes ) = @_;
        my $copy = Storable::dclone($attributes);
        @{$rows{$node}}{keys %$copy} = values %$copy;
        return 0;
    }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::NodeRange;
    use Exporter qw(import);
    our @EXPORT = qw(noderange);
    sub noderange { return @{ $resolved_nodes{$_[0]} || [] }; }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;

    package xCAT::Utils;
    sub isMN { return 0; }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub get_site_attribute {
        my ( $class, $attribute ) = @_;
        die "Unexpected site attribute $attribute" unless $attribute eq 'nodestatus';
        return (1);
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    sub trace { return; }
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT_monitoring::monitorctrl;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
}

local $ENV{XCATROOT} = tempdir( CLEANUP => 1 );
my $plugin = repo_path('xCAT-server/lib/xcat/plugins/destiny.pm');
require $plugin;

sub capture_chain_handoffs {
    my ($request) = @_;
    my ( @handoffs, @subrequests, @errors, @logs );
    no warnings qw(once redefine);
    local %::XCATSITEVALS = ();
    local *xCAT_plugin::destiny::setdestiny = sub {
        my ( $outgoing, $flag ) = @_;
        push @handoffs, {
            request          => dclone($outgoing),
            flag             => $flag,
            chain_at_handoff => dclone($rows{$outgoing->{node}->[0]}),
        };
        return;
    };
    local *xCAT_plugin::destiny::syslog = sub {
        push @logs, [@_];
        return;
    };
    xCAT_plugin::destiny::process_request(
        $request,
        sub { push @errors, dclone($_[0]); },
        sub {
            push @subrequests, { request => dclone($_[0]), chain_at_dispatch => dclone(\%rows) };
        },
    );
    return { handoffs => \@handoffs, subrequests => \@subrequests, errors => \@errors, logs => \@logs };
}

my $image = 'osimage=rhels9-x86_64-install-compute';
my @cases = (
    {
        name => 'repeated advances from boot preserve the state without enacting again',
        rows => { node1 => { currstate => 'boot', currchain => 'boot', chain => $image } },
        steps => [
            { transitions => [ [ 'node1', 'boot', 'boot' ] ] },
            { transitions => [ [ 'node1', 'boot', 'boot' ] ] },
            { transitions => [ [ 'node1', 'boot', 'boot' ] ] },
        ],
    },
    {
        name => 'an exhausted installation chain advances to standby',
        rows => { node1 => { currstate => $image, currchain => $image, chain => $image } },
        steps => [ { transitions => [ [ 'node1', 'standby', 'standby' ] ] } ],
    },
    {
        name => 'remaining steps reach boot before repeated advances stop enacting',
        rows => { node1 => { currstate => $image, currchain => "$image,boot", chain => "$image,boot" } },
        steps => [
            { transitions => [ [ 'node1', $image, 'boot' ] ], enact => ['node1'] },
            { transitions => [ [ 'node1', 'boot', 'boot' ] ], enact => ['node1'] },
            { transitions => [ [ 'node1', 'boot', 'boot' ] ] },
        ],
    },
    {
        name => 'an empty current chain starts from the default chain',
        rows => { node1 => { currstate => '', currchain => '', chain => "$image,boot" } },
        steps => [ { transitions => [ [ 'node1', $image, 'boot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'an unset current chain can start a single boot step',
        rows => { node1 => { currstate => undef, currchain => undef, chain => 'boot' } },
        steps => [ { transitions => [ [ 'node1', 'boot', 'boot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'a current chain takes precedence over the default chain',
        rows => { node1 => { currstate => 'boot', currchain => 'shutdown,boot', chain => $image } },
        steps => [ { transitions => [ [ 'node1', 'shutdown', 'boot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'semicolon-separated steps advance and retain the remaining chain',
        rows => { node1 => { currstate => 'offline', currchain => 'boot;shutdown;boot', chain => $image } },
        steps => [ { transitions => [ [ 'node1', 'boot', 'shutdown,boot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'a new single boot step is enacted when the previous state differs',
        rows => { node1 => { currstate => 'offline', currchain => 'boot', chain => $image } },
        steps => [ { transitions => [ [ 'node1', 'boot', 'boot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'the initrd option reaches both the destiny handoff and nodeset',
        rows => { node1 => { currstate => 'boot', currchain => "$image:--noupdateinitrd,boot", chain => $image } },
        steps => [ {
            transitions => [ [ 'node1', "$image:--noupdateinitrd", 'boot', [ $image, '--noupdateinitrd' ] ] ],
            enact => ['node1'], enact_args => [ 'enact', '--noupdateinitrd' ],
        } ],
    },
    {
        name => 'each requested node is updated before one aggregate nodeset request',
        request => { command => ['nextdestiny'], node => [qw(node2 node1)] },
        rows => {
            node1 => { currstate => 'offline', currchain => 'boot', chain => $image },
            node2 => { currstate => 'boot', currchain => 'shutdown,boot', chain => $image },
        },
        steps => [ {
            transitions => [ [ 'node2', 'shutdown', 'boot' ], [ 'node1', 'boot', 'boot' ] ],
            enact => [qw(node2 node1)],
        } ],
    },
    {
        name => 'an initrd option on one node reaches the aggregate nodeset request',
        request => { command => ['nextdestiny'], node => [qw(node1 node2)] },
        rows => {
            node1 => { currstate => 'offline', currchain => 'boot', chain => $image },
            node2 => { currstate => 'boot', currchain => "$image:--noupdateinitrd,boot", chain => $image },
        },
        steps => [ {
            transitions => [ [ 'node1', 'boot', 'boot' ], [ 'node2', "$image:--noupdateinitrd", 'boot', [ $image, '--noupdateinitrd' ] ] ],
            enact => [qw(node1 node2)], enact_args => [ 'enact', '--noupdateinitrd' ],
        } ],
    },
    {
        name => 'a scalar node request reaches the same chain handler',
        request => { command => ['nextdestiny'], node => 'node1' },
        rows => { node1 => { currstate => 'boot', currchain => 'boot', chain => $image } },
        steps => [ { transitions => [ [ 'node1', 'boot', 'boot' ] ] } ],
    },
    {
        name => 'a client request advances the resolved node',
        request => { command => ['nextdestiny'], _xcat_clienthost => ['client'] },
        resolved => { client => ['node1'] },
        rows => { node1 => { currstate => 'boot', currchain => 'boot', chain => $image } },
        steps => [ { transitions => [ [ 'node1', 'boot', 'boot' ] ] } ],
    },
    {
        name => 'an unresolved client does not update or enact a chain',
        request => { command => ['nextdestiny'], _xcat_clienthost => ['unknown'] },
        rows => { node1 => { currstate => 'boot', currchain => 'boot', chain => $image } },
        steps => [ { transitions => [] } ],
    },
    {
        name => 'a missing chain row reports an error without dispatching',
        rows => {},
        steps => [ {
            transitions => [],
            logs => [ [ 'local4|err', 'ERROR: node requested destiny update, no path in chain.currchain' ] ],
        } ],
    },
);

for my $case (@cases) {
    subtest $case->{name} => sub {
        %rows = %{ dclone($case->{rows}) };
        $rows{unrelated} = { currstate => 'offline', currchain => 'boot', chain => 'boot' };
        %resolved_nodes = %{ $case->{resolved} || {} };
        my $expected_rows = dclone(\%rows);
        for my $step (@{ $case->{steps} }) {
            my @expected_handoffs;
            for my $transition (@{ $step->{transitions} }) {
                my ( $node, $state, $remaining, $args ) = @$transition;
                $expected_rows->{$node}->{currstate} = $state;
                $expected_rows->{$node}->{currchain} = $remaining;
                push @expected_handoffs, {
                    request => { node => [$node], arg => $args || [$state] },
                    flag => 1,
                    chain_at_handoff => dclone($expected_rows->{$node}),
                };
            }
            my $request = dclone($case->{request} || { command => ['nextdestiny'], node => ['node1'] });
            my $original = dclone($request);
            my $result = capture_chain_handoffs($request);
            my $expected_subrequests = $step->{enact}
              ? [ {
                    request => { command => ['nodeset'], node => $step->{enact}, arg => $step->{enact_args} || ['enact'] },
                    chain_at_dispatch => dclone($expected_rows),
                } ]
              : [];
            is_deeply( \%rows, $expected_rows, 'nextdestiny writes the expected chain state without touching other rows' );
            is_deeply( $result->{handoffs}, \@expected_handoffs, 'destiny handoffs carry the flag and follow their chain updates' );
            is_deeply( $result->{subrequests}, $expected_subrequests, 'nodeset requests follow all chain updates' );
            is_deeply( $result->{errors}, [], 'no callback error is emitted' );
            is_deeply( $result->{logs}, $step->{logs} || [], 'syslog messages match' );
            is_deeply( $request, $original, 'the caller request is preserved' );
        }
    };
}

done_testing();
