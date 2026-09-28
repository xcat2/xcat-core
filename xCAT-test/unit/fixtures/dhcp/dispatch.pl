package main;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../../lib";
use lib "$FindBin::Bin/../../../../perl-xCAT";
use File::Temp qw(tempdir);
use JSON qw(decode_json encode_json);
use XCAT::Test::File qw(repo_path);

my $fixture = decode_json(shift @ARGV);
my @messages;
my @errors;

BEGIN {
    package xCAT::Table;
    sub new {
        my ( $class, $table ) = @_;
        die "Unexpected table $table" unless $table eq 'networks' || $table eq 'noderes';
        return bless { table => $table }, $class;
    }
    sub getAllEntries {
        my ($self) = @_;
        die 'Expected networks table' unless $self->{table} eq 'networks';
        return $fixture->{networks} || [];
    }
    sub getNodesAttribs {
        my ( $self, $nodes, $attributes ) = @_;
        die 'Expected noderes table' unless $self->{table} eq 'noderes';
        my %result;
        for my $node (@$nodes) {
            my $row = $fixture->{noderes}->{$node};
            $result{$node} = defined($row)
              ? [ { map { $_ => $row->{$_} } @$attributes } ]
              : [undef];
        }
        return \%result;
    }
    sub close { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub getTftpDir { return '/tftpboot'; }
    sub get_site_Master { return $fixture->{site_master}; }
    sub get_site_attribute {
        my ( $class, $attribute ) = @_;
        return ($fixture->{site_master}) if $attribute eq 'master';
        return (0) if $attribute eq 'disjointdhcps';
        die "Unexpected site attribute $attribute";
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    use Exporter qw(import);
    our @EXPORT_OK = qw(getipaddr);
    sub getipaddr { die 'Unexpected address lookup'; }
    sub determinehostname { return @{ $fixture->{local_names} || ['mn'] }; }
    sub nodeonmynet { return 1; }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::Utils;
    sub osver { return 'rhels9'; }
    sub isServiceNode { return $fixture->{is_service_node} || 0; }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::SvrUtils;
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    $INC{'xCAT/NodeRange.pm'} = __FILE__;

    package xCAT::MsgUtils;
    sub trace { return; }
    sub message {
        my ( $class, $level, $message ) = @_;
        push @messages, [ $level, $message ];
        return;
    }
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;
}

$ENV{XCATROOT} = tempdir( CLEANUP => 1 );
require xCAT::ServiceNodeUtils;
{
    no warnings qw(once redefine);
    *xCAT::ServiceNodeUtils::getSNList = sub {
        my ( $class, $service ) = @_;
        die 'Expected DHCP service inventory' unless $service eq 'dhcpserver';
        return @{ $fixture->{service_nodes} };
    };
}

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm');
require $plugin;
my $requests = xCAT_plugin::dhcp::preprocess_request(
    $fixture->{request}, sub { push @errors, $_[0]; }
);
print encode_json({ requests => $requests, errors => \@errors, messages => \@messages })
  or die "Unable to report dispatch result: $!";
