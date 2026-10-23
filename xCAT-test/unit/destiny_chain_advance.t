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
        die "Unexpected table $table" unless $table eq 'chain' || $table eq 'bootparams';
        return bless { table => $table }, $class;
    }
    sub getNodesAttribs {
        my ( $self, $nodes, @attributes ) = @_;
        return {} if $self->{table} eq 'bootparams';
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
    sub setNodesAttribs {
        my ( $self, $updates ) = @_;
        for my $node (keys %$updates) {
            $self->setNodeAttribs($node, $updates->{$node});
        }
        return 0;
    }
    sub close { return; }
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
        name => 'boot does not complete a new iSCSI boot step',
        rows => { node1 => { currstate => 'boot', currchain => 'iscsiboot', chain => 'iscsiboot' } },
        steps => [ { transitions => [ [ 'node1', 'iscsiboot', 'iscsiboot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'iSCSI boot does not complete a new local boot step',
        rows => { node1 => { currstate => 'iscsiboot', currchain => 'boot', chain => 'boot' } },
        steps => [ { transitions => [ [ 'node1', 'boot', 'boot' ] ], enact => ['node1'] } ],
    },
    {
        name => 'an exactly completed iSCSI boot step retains the standby policy',
        rows => { node1 => { currstate => 'iscsiboot', currchain => 'iscsiboot', chain => 'iscsiboot' } },
        steps => [ { transitions => [ [ 'node1', 'standby', 'standby' ] ] } ],
    },
    {
        name => 'an image-name prefix does not complete a different image',
        rows => { node1 => { currstate => $image, currchain => "$image-extra", chain => "$image-extra" } },
        steps => [ { transitions => [ [ 'node1', "$image-extra", "$image-extra" ] ], enact => ['node1'] } ],
    },
    {
        name => 'dots in image names are literal',
        rows => { node1 => { currstate => 'osimage=rhels9.6-compute',
                            currchain => 'osimage=rhels9x6-compute', chain => 'osimage=rhels9x6-compute' } },
        steps => [ { transitions => [ [ 'node1', 'osimage=rhels9x6-compute', 'osimage=rhels9x6-compute' ] ], enact => ['node1'] } ],
    },
    {
        name => 'an exactly completed dotted image retains the standby policy',
        rows => { node1 => { currstate => 'osimage=rhels9.6-compute',
                            currchain => 'osimage=rhels9.6-compute', chain => 'osimage=rhels9.6-compute' } },
        steps => [ { transitions => [ [ 'node1', 'standby', 'standby' ] ] } ],
    },
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

for my $order ([qw(node1 node2)], [qw(node2 node1)]) {
    for my $option (0, 1) {
        my $state = $option ? "$image:--noupdateinitrd" : 'shutdown';
        my %transitions = (
            node1 => ['node1', 'boot', 'boot'],
            node2 => ['node2', $state, 'boot', $option ? [$image, '--noupdateinitrd'] : ['shutdown']],
        );
        push @cases, {
            name => "completed and active nodes in order @$order, initrd option=$option",
            request => {command => ['nextdestiny'], node => $order},
            rows => {
                node1 => {currstate => 'boot', currchain => 'boot', chain => 'boot'},
                node2 => {currstate => 'boot', currchain => "$state,boot", chain => "$state,boot"},
            },
            steps => [{
                transitions => [map { $transitions{$_} } @$order],
                enact => ['node2'], enact_args => $option ? ['enact', '--noupdateinitrd'] : ['enact'],
            }],
        };
    }
}
push @cases, {
    name => 'a completed middle node does not suppress either active neighbor',
    request => {command => ['nextdestiny'], node => [qw(node3 node2 node1)]},
    rows => {
        node1 => {currstate => 'offline', currchain => 'boot', chain => 'boot'},
        node2 => {currstate => 'boot', currchain => 'boot', chain => 'boot'},
        node3 => {currstate => 'boot', currchain => 'shutdown,boot', chain => 'shutdown,boot'},
    },
    steps => [{
        transitions => [['node3', 'shutdown', 'boot'], ['node2', 'boot', 'boot'], ['node1', 'boot', 'boot']],
        enact => [qw(node3 node1)],
    }],
}, {
    name => 'a request containing only completed nodes does not enact',
    request => {command => ['nextdestiny'], node => [qw(node1 node2)]},
    rows => {
        node1 => {currstate => 'boot', currchain => 'boot', chain => 'boot'},
        node2 => {currstate => $image, currchain => $image, chain => $image},
    },
    steps => [{transitions => [['node1', 'boot', 'boot'], ['node2', 'standby', 'standby']]}],
};

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

subtest 'a final discovery step completes using the state recorded by setdestiny' => sub {
    my $discovery = 'ondiscover=makegocons|rspconfig:sshcfg';
    %rows = (node1 => {currstate => 'boot', currchain => $discovery, chain => $discovery});
    my (@commands, @errors);
    {
        no warnings qw(once redefine);
        local *xCAT::Utils::runcmd = sub {
            push @commands, [@_];
            return;
        };
        local *xCAT_plugin::destiny::getdestiny = sub { return; };
        xCAT_plugin::destiny::process_request(
            {command => ['setdestiny'], node => ['node1'], arg => [$discovery]},
            sub { push @errors, dclone($_[0]); },
            sub { die 'Unexpected subrequest while applying discovery'; },
        );
    }
    is_deeply(\@commands, [
        ['xCAT::Utils', 'makegocons node1 ', 0],
        ['xCAT::Utils', 'rspconfig node1 sshcfg', 0],
    ], 'the real applicator runs both discovery commands once');
    is_deeply(\@errors, [], 'applying discovery emits no errors');
    is($rows{node1}->{currstate}, 'ondiscover', 'the real applicator records the bare discovery state');
    is($rows{node1}->{currchain}, $discovery, 'the chain retains its command arguments');

    my $result = capture_chain_handoffs({command => ['nextdestiny'], node => ['node1']});
    is_deeply($rows{node1}, {currstate => 'standby', currchain => 'standby', chain => $discovery},
        'the recorded state completes the final discovery step');
    is_deeply($result->{handoffs}, [{
        request => {node => ['node1'], arg => ['standby']}, flag => 1,
        chain_at_handoff => dclone($rows{node1}),
    }], 'completion hands off standby instead of repeating discovery');
    is_deeply($result->{subrequests}, [], 'completed discovery does not enact again');
    is_deeply($result->{errors}, [], 'completion emits no callback error');
    is_deeply($result->{logs}, [], 'completion emits no syslog error');
};

done_testing();
