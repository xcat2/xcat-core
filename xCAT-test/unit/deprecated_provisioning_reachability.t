#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Temp qw(tempdir);
use Getopt::Long;
use Storable qw(dclone);
use Test::More;
use XCAT::Test::File qw(repo_path);

my ( $root, %images, @effects, @locks );

BEGIN {
    package xCAT::Table;
    sub new {
        my ( $class, $table ) = @_;
        die "Unexpected table $table" unless $table =~ /^(?:chain|bootparams|nodetype|noderes|osimage|linuximage)$/;
        return bless { table => $table }, $class;
    }
    sub getNodesAttribs {
        my ( $self, $nodes, @attributes ) = @_;
        @attributes = @{ $attributes[0] } if ref($attributes[0]) eq 'ARRAY';
        die "Unexpected read from $self->{table}" unless $self->{table} eq 'bootparams';
        return { map { $_ => [ { map { $_ => undef } @attributes } ] } @$nodes };
    }
    sub getNodeAttribs {
        my ( $self, $node, $attributes ) = @_;
        die "Unexpected read from $self->{table}" unless $self->{table} eq 'noderes';
        return { netboot => 'xnba' };
    }
    sub getAttribs {
        my ( $self, $query, @attributes ) = @_;
        @attributes = @{ $attributes[0] } if ref($attributes[0]) eq 'ARRAY';
        die "Unexpected read from $self->{table}" unless exists $images{$self->{table}};
        my $row = $images{$self->{table}}->{$query->{imagename}};
        return unless $row;
        my %result;
        for my $attribute (@attributes) {
            my $value = $row->{$attribute};
            $result{$attribute} = $value if defined($value) && $value ne '';
        }
        return keys(%result) ? \%result : undef;
    }
    sub setNodesAttribs {
        push @effects, 'database update';
        die "Unexpected database update";
    }
    sub close { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::Utils;
    sub isMN { return 0; }
    sub Version { return 'fixture-version'; }
    sub acquire_lock_imageop {
        my ( $class, $directory ) = @_;
        push @locks, $directory;
        return ( 1, 'fixture image lock busy' );
    }
    sub runcmd {
        push @effects, 'external command';
        die "Unexpected external command";
    }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub getInstallDir { return "$root/install"; }
    sub get_site_attribute {
        my ( $class, $attribute ) = @_;
        return (1) if $attribute eq 'nodestatus';
        return ('UTC') if $attribute eq 'timezone';
        die "Unexpected site attribute $attribute";
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    sub trace { return; }
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT::Postage;
    sub create_mypostscript_or_not {
        push @effects, 'postscript generation';
        die "Unexpected postscript generation";
    }
    $INC{'xCAT/Postage.pm'} = __FILE__;

    $INC{'xCAT/NodeRange.pm'} = __FILE__;
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;
    $INC{'xCAT/PasswordUtils.pm'} = __FILE__;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
}

$root = tempdir( CLEANUP => 1 );
local $ENV{XCATROOT} = $root;
# Inherited POSIX parsing rules must not change the request-order fixtures.
local $ENV{POSIXLY_CORRECT};
delete $ENV{POSIXLY_CORRECT};
Getopt::Long::Configure('default');
$INC{"$root/lib/perl/xCAT/Table.pm"} = __FILE__;
%images = (
    osimage => {
        unconfigured => { provmethod => undef, osvers => 'rhels9' },
        empty => { provmethod => undef, osvers => '' },
        'known-image' => { osvers => 'rhels9', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' },
    },
    linuximage => { 'known-image' => { rootimgdir => "$root/image" } },
);

sub run_request {
    my ( $handler, $request ) = @_;
    my @responses;
    @effects = ();
    @locks = ();
    local @ARGV;
    no warnings 'once';
    local %::XCATSITEVALS = ();
    my $status;
    my $completed = eval {
        $status = $handler->(
            dclone($request),
            sub { push @responses, dclone($_[0]); },
            sub {
                push @effects, 'subrequest';
                die "Unexpected subrequest";
            },
        );
        1;
    };
    my $exception = $@;
    is( $completed, 1, 'request completes without an exception' ) or diag($exception);
    is_deeply( \@effects, [], 'no calls reach the write, command or provisioning guards' );
    return ( $status, \@responses, [@locks] );
}

require(repo_path('xCAT-server/lib/xcat/plugins/destiny.pm'));

my $deprecated = 'The options "install", "netboot", and "statelite" have been deprecated, use "osimage=<osimage_name>" instead.';
my @destiny_cases;
for my $state (qw(install netboot statelite)) {
    push @destiny_cases, map {
        { args => $_, response => { error => $deprecated, errorcode => [1], errorabort => [1] } }
    } (
        [$state],
        ["$state=rhels9-x86_64-compute"],
        ["$state=rhels9-x86_64-compute:reboot4deploy"],
        ["$state,boot"],
        [ '--noupdateinitrd', "$state=rhels9-x86_64-compute" ],
    );
}
push @destiny_cases,
  {
    args => ['osimage=missing-image'],
    response => { error => 'Cannot find the OS image missing-image in the osimage table.', errorcode => [1], errorabort => [1] },
  },
  {
    args => ['osimage=unconfigured'],
    response => { error => 'osimage.provmethod for unconfigured must be set.', errorcode => [1], errorabort => [1] },
  },
  {
    args => ['osimage=empty'],
    response => { error => 'Cannot find the OS image empty in the osimage table.', errorcode => [1], errorabort => [1] },
  };

for my $case (@destiny_cases) {
    subtest 'setdestiny ' . join( ' ', @{ $case->{args} } ) => sub {
        my ( undef, $responses, $locks ) = run_request(
            \&xCAT_plugin::destiny::process_request,
            { command => ['setdestiny'], node => [qw(node1 node2)], arg => $case->{args}, bootparams => {} },
        );
        is_deeply( $responses, [ $case->{response} ], 'the handler returns the expected failure and abort status' );
        is_deeply( $locks, [], 'no image operation starts' );
    };
}

# Load packimage after destiny requests because it changes global option parsing.
require(repo_path('xCAT-server/lib/xcat/plugins/packimage.pm'));

my $obsolete = "-o, -p and -a options are obsoleted, please use 'packimage <osimage name>' instead.";
my $missing = "An image name is required, use 'packimage <osimage name>'.";
my @packimage_cases;
for my $option ( [ '-o', '--osver', 'rhels9' ], [ '-p', '--profile', 'compute' ], [ '-a', '--arch', 'x86_64' ] ) {
    my ( $short, $long, $value ) = @$option;
    push @packimage_cases, map {
        { args => $_, error => $obsolete }
    } (
        [ $short, $value ],
        [ $long, $value ],
        [ "$long=$value" ],
        [ $short, $value, 'known-image' ],
        [ 'known-image', $short, $value ],
    );
}
push @packimage_cases,
  { args => [ '-o', 'rhels9', '-p', 'compute', '-a', 'x86_64', 'known-image' ], error => $obsolete },
  map { { args => $_, error => $missing } } (
    [ '-m', 'cpio' ], [ '--method', 'tar' ], [ '--compress=gzip' ], ['--nosyncfiles'],
    [ '-m', 'cpio', '-c', 'xz', '--nosyncfiles' ],
  );
push @packimage_cases, map {
    { args => $_, error => 'fixture image lock busy', locks => ["$root/image/rootimg"] }
} ( ['known-image'], [ '--method', 'cpio', '--compress=gzip', '--nosyncfiles', 'known-image' ] );

for my $case (@packimage_cases) {
    subtest 'packimage ' . join( ' ', @{ $case->{args} } ) => sub {
        my ( $status, $responses, $locks ) = run_request(
            \&xCAT_plugin::packimage::process_request,
            { command => ['packimage'], arg => $case->{args} },
        );
        is( $status, 1, 'the handler returns failure' );
        is_deeply( $responses, [ { error => [ $case->{error} ], errorcode => [1] } ], 'the callback reports the expected error' );
        is_deeply( $locks, $case->{locks} || [], 'only a named image reaches the image lock' );
    };
}

for my $case ( [ [] ], [ ['-h'] ], [ ['--help'] ], [ ['-v'], 'fixture-version' ], [ ['--version'], 'fixture-version' ] ) {
    my ( $args, $version ) = @$case;
    subtest 'packimage information request ' . join( ' ', @$args ) => sub {
        my ( $status, $responses, $locks ) = run_request(
            \&xCAT_plugin::packimage::process_request,
            { command => ['packimage'], arg => $args },
        );
        is( $status, 0, 'the information request succeeds' );
        is( scalar(@$responses), 1, 'one response is returned' );
        is_deeply( [ sort keys %{ $responses->[0] } ], ['info'], 'the response is informational, not an error' );
        if (defined $version) {
            is_deeply( $responses->[0]->{info}, [$version], 'the installed version is returned' );
        } else {
            like( $responses->[0]->{info}->[0], qr/^Usage:\n\s+packimage\b/, 'usage is returned' );
        }
        is_deeply( $locks, [], 'no image operation starts' );
    };
}

done_testing();
