#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use XCAT::Test::File qw(repo_path);
use xCAT::TableUtils;

$ENV{XCATROOT} = repo_path('xCAT-server');
my $tftpdir = tempdir(CLEANUP => 1);
my $plugin = repo_path('xCAT-server/lib/xcat/plugins/xnba.pm');
{
    no warnings 'redefine';
    local *xCAT::TableUtils::getTftpDir = sub { return $tftpdir; };
    require $plugin;
}

sub request_without_local_nodes {
    my ($disjoint, $disparate, $owners, $resolved) = @_;
    my @responses;
    {
        local @ARGV;
        no warnings 'redefine';
        local *xCAT::Table::new = sub {
            my ($class, $name) = @_;
            die "Unexpected table $name" unless $name eq 'noderes';
            return bless { owners => $owners }, 'Local::NodeResources';
        };
        local *xCAT::TableUtils::get_site_Master = sub { return 'mn.example'; };
        local *xCAT::NetworkUtils::determinehostname = sub { return ('192.0.2.1', 'mn.example'); };
        local *xCAT::NetworkUtils::checkNodeIPaddress = sub {
            return $resolved ? { ip => '192.0.2.101' } : { error => 'No address' };
        };
        local *xCAT::NetworkUtils::nodeonmynet = sub { return 0; };
        local *xCAT::MsgUtils::trace = sub {};
        local *xCAT::MsgUtils::message = sub {};
        xCAT_plugin::xnba::process_request({
            command => ['nodeset'], arg => ['osimage'], node => [sort keys %$owners],
            _disparatetftp => [$disparate], _disjointmode => [$disjoint],
        }, sub { push @responses, @_ }, sub { die 'Unexpected subrequest'; });
    }
    return \@responses;
}

for my $disjoint (0, 1) {
    subtest "disjointdhcps=$disjoint" => sub {
        for my $resolved (0, 1) {
            my $responses = request_without_local_nodes($disjoint, 1,
                { cn1 => 'sn1.example', cn2 => 'sn2.example' }, $resolved);
            is_deeply($responses, [],
                "a nonowner succeeds with no local nodes (resolved=$resolved)");
        }

        for my $owner ('mn.example', '192.0.2.1', 'sn1.example,mn.example', '') {
            for my $resolved (0, 1) {
                my $responses = request_without_local_nodes($disjoint, 1,
                    { cn1 => $owner, cn2 => 'sn2.example' }, $resolved);
                is_deeply($responses, [{ errorcode => [1], error => [
                    'Failed to generate xnba configurations for some node(s) on mn.example. Check xCAT log file for more details.'
                ] }], "an owner reports unhandled nodes (owner='$owner', resolved=$resolved)");
            }
        }

        my $responses = request_without_local_nodes($disjoint, 0,
            { cn1 => 'sn1.example', cn2 => 'sn2.example' }, 0);
        is_deeply($responses, [{ errorcode => [1], error => [
            'Failed to generate xnba configurations for some node(s) on mn.example. Check xCAT log file for more details.'
        ] }], 'shared TFTP still reports unresolved nodes on a nonowner');
    };
}

done_testing();

package Local::NodeResources;

sub getNodesAttribs {
    my ($self, $nodes, $attrs) = @_;
    die 'Unexpected noderes attributes' unless @$attrs == 1 && $attrs->[0] eq 'servicenode';
    return { map { $_ => [{ servicenode => $self->{owners}{$_} }] } @$nodes };
}

sub close {}
