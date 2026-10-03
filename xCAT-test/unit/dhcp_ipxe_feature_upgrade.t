#!/usr/bin/env perl
# A package upgrade keeps the DHCP configuration that an older makedhcp -n wrote, without the iPXE
# feature options. makedhcp without -n must add them before dhcpd or Kea gets a rule that tests them:
# dhcpd rejects such a rule, and Kea never finds a sub-option of option 175 without its definition.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use B ();
use File::Temp qw(tempdir);
use JSON ();
use Test::More;

use xCAT::DHCP::Backend::Kea;
use xCAT::DHCP::BootPolicy;

$ENV{XCATCFG} ||= 'SQLite:/tmp';
my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

my @features = @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() };
my $kea_defs = xCAT::DHCP::BootPolicy->kea_ipxe_option_defs();

# JSON::XS, and JSON::PP before Perl 5.36, write a number that Perl has used as a string as a JSON
# string, and Kea rejects an option code that is a string.
sub string_codes { return grep { B::svref_2object( \$_->{code} )->FLAGS & B::SVp_POK } @{ $_[0] }; }

# The header of an ISC configuration that makedhcp -n wrote before the iPXE feature options.
my @old_header = (
    "#xCAT generated dhcp configuration\n",
    "\n",
    "option conf-file code 209 = text;\n",
    "option space gpxe;\n",
    "option gpxe-encap-opts code 175 = encapsulate gpxe;\n",
    "option gpxe.bus-id code 177 = string;\n",
    "option user-class-identifier code 77 = string;\n",
    "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
    "} # 192.0.2.0/255.255.255.0 subnet_end\n",
);

{
    my @conf = @old_header;
    is_deeply( [ xCAT::DHCP::BootPolicy->isc_declare_ipxe_features( \@conf ) ], [ scalar @features, undef ],
        'ISC: an old configuration gets every iPXE feature option' );
    is_deeply( \@conf, [ @old_header[ 0 .. 3 ], @features, @old_header[ 4 .. $#old_header ] ],
        'ISC: after the gpxe option space, with the other lines unchanged' );

    my @again = @conf;
    is_deeply( [ xCAT::DHCP::BootPolicy->isc_declare_ipxe_features( \@again ) ], [ 0, undef ], 'ISC: a second run adds nothing' );
    is_deeply( \@again, \@conf, 'ISC: and leaves the configuration unchanged' );

    my ($http) = grep { /^option gpxe\.http / } @features;
    my @partial = ( @old_header[ 0 .. 3 ], $http, @old_header[ 4 .. $#old_header ] );
    is_deeply( [ xCAT::DHCP::BootPolicy->isc_declare_ipxe_features( \@partial ) ], [ @features - 1, undef ],
        'ISC: a configuration that declares one option gets the others' );
    is( scalar( grep { $_ eq $http } @partial ), 1, 'ISC: and keeps a single declaration of it' );

    # dhcpd reads declarations that start with blanks or have more than one blank between the words.
    my @indented = map { /^option / ? "  $_" : $_ } @old_header;
    s/^  option space gpxe;/\toption  space   gpxe ;/ for @indented;
    ( my $spaced_http = $http ) =~ s/^option (\S+) code/  option \t$1  code/;
    my @spaced = ( @indented[ 0 .. 3 ], $spaced_http, @indented[ 4 .. $#indented ] );
    is_deeply( [ xCAT::DHCP::BootPolicy->isc_declare_ipxe_features( \@spaced ) ], [ @features - 1, undef ],
        'ISC: a configuration with indented declarations gets the missing ones' );
    is_deeply( [ @spaced[ 0 .. 3 ] ], [ @indented[ 0 .. 3 ] ], 'ISC: after its gpxe option space' );
    is( scalar( grep { /gpxe\.http/ } @spaced ), 1, 'ISC: and keeps its own declaration of an option' );

    my @no_space = grep { !/gpxe/ } @old_header;
    my @unchanged = @no_space;
    is_deeply( [ xCAT::DHCP::BootPolicy->isc_declare_ipxe_features( \@no_space ) ], [ 0, 'it declares no gpxe option space' ],
        'ISC: a configuration without the gpxe option space gets an error' );
    is_deeply( \@no_space, \@unchanged, 'ISC: and stays unchanged' );
}

{
    my @old_defs = ( { name => 'conf-file', code => 209, type => 'string', space => 'dhcp4' } );
    my $dhcp4 = JSON::decode_json( JSON::encode_json( { 'option-def' => \@old_defs } ) );
    is_deeply( [ xCAT::DHCP::BootPolicy->kea_declare_ipxe_features($dhcp4) ], [ scalar @$kea_defs, undef ],
        'Kea: old option definitions get option 175 and every iPXE feature option' );
    is_deeply( $dhcp4->{'option-def'}, [ @old_defs, @$kea_defs ], 'Kea: after the definitions it had' );
    is_deeply( [ string_codes( $dhcp4->{'option-def'} ) ], [], 'Kea: and every option code stays a number' );

    is_deeply( [ xCAT::DHCP::BootPolicy->kea_declare_ipxe_features($dhcp4) ], [ 0, undef ], 'Kea: a second run adds nothing' );
    is( scalar @{ $dhcp4->{'option-def'} }, @old_defs + @$kea_defs, 'Kea: and duplicates no definition' );

    my $empty = {};
    is_deeply( [ xCAT::DHCP::BootPolicy->kea_declare_ipxe_features($empty) ], [ scalar @$kea_defs, undef ],
        'Kea: a configuration without option definitions gets them' );
    is_deeply( $empty->{'option-def'}, $kea_defs, 'Kea: in a new option-def list' );

    my $encapsulating = { name => 'site-175', code => 175, type => 'empty', space => 'dhcp4', encapsulate => 'gpxe' };
    my $custom = { 'option-def' => [$encapsulating] };
    is_deeply( [ xCAT::DHCP::BootPolicy->kea_declare_ipxe_features($custom) ], [ @$kea_defs - 1, undef ],
        'Kea: a configuration whose option 175 encapsulates the gpxe space gets only the feature options' );
    is_deeply( $custom->{'option-def'}, [ $encapsulating, @{$kea_defs}[ 1 .. $#$kea_defs ] ], 'Kea: and keeps its option 175' );

    my @binary = ( @old_defs, { name => 'site-175', code => 175, type => 'binary', space => 'dhcp4' } );
    my $opaque = { 'option-def' => [@binary] };
    my ( $added, $error ) = xCAT::DHCP::BootPolicy->kea_declare_ipxe_features($opaque);
    is( $added, 0, 'Kea: a configuration whose option 175 encapsulates nothing gets no definition' );
    like( $error, qr/\bsite-175 gives option 175 no gpxe encapsulation.*Run makedhcp -n/, 'Kea: but an error that names it and the fix' );
    is_deeply( $opaque->{'option-def'}, \@binary, 'Kea: and keeps its definitions, which option data can name' );
}

# makedhcp writes the ISC configuration and restarts dhcpd at once, because OMAPI gives the running
# dhcpd host statements before the end of the command.
{
    my $dir = tempdir( CLEANUP => 1 );
    my @restarts;
    no warnings 'redefine';
    local *xCAT::Utils::restartservice = sub { shift if $_[0] && $_[0] eq 'xCAT::Utils'; push @restarts, $_[0]; return 0; };

    my @conf = @old_header;
    my $path = "$dir/dhcpd.conf";
    is( xCAT_plugin::dhcp::_isc_declare_ipxe_features( \@conf, $path ), undef, 'ISC: makedhcp adds the options without error' );
    my $written = do { local ( @ARGV, $/ ) = ($path); <> };
    is( $written, join( '', @conf ), 'ISC: makedhcp writes the configuration with the options' );
    like( $written, qr/^option gpxe\.http code 19 = unsigned integer 8;$/m, 'ISC: which declares the HTTP feature' );
    is_deeply( \@restarts, ['dhcp'], 'ISC: makedhcp restarts dhcpd once' );
    ok( !-e "$path.ipxe-restart", 'ISC: and removes the restart marker once dhcpd has restarted' );

    @restarts = ();
    my $current = "$dir/current.conf";
    is( xCAT_plugin::dhcp::_isc_declare_ipxe_features( [@conf], $current ), undef, 'ISC: a current configuration gives no error' );
    ok( !-e $current, 'ISC: makedhcp does not write a current configuration' );
    is_deeply( \@restarts, [], 'ISC: and does not restart dhcpd' );

    my $unwritable = "$dir/conf.d";
    mkdir $unwritable or die "Cannot create $unwritable: $!";
    like( xCAT_plugin::dhcp::_isc_declare_ipxe_features( [@old_header], $unwritable ), qr/^Unable to add the iPXE feature options to \Q$unwritable\E: /,
        'ISC: makedhcp reports a configuration it cannot write' );
    is_deeply( \@restarts, [], 'ISC: and does not restart dhcpd' );
    ok( -e "$unwritable.ipxe-restart", 'ISC: but marks the restart before it writes the configuration' );

    my $bare = "$dir/bare.conf";
    like( xCAT_plugin::dhcp::_isc_declare_ipxe_features( [ grep { !/gpxe/ } @old_header ], $bare ),
        qr/^Unable to add the iPXE feature options to \Q$bare\E: it declares no gpxe option space\. Run makedhcp -n\.$/,
        'ISC: makedhcp reports a configuration without the gpxe option space' );
    ok( !-e $bare && !@restarts, 'ISC: and neither writes it nor restarts dhcpd' );

    # A run whose restart fails leaves the options in the file and the running dhcpd without them.
    my $failed = "$dir/failed.conf";
    {
        local *xCAT::Utils::restartservice = sub { return 1; };
        like( xCAT_plugin::dhcp::_isc_declare_ipxe_features( [@old_header], $failed ),
            qr/^Unable to restart the DHCP server after adding the iPXE feature options/, 'ISC: makedhcp reports a restart that fails' );
    }
    ok( -e "$failed.ipxe-restart", 'ISC: and keeps the restart marker' );
    open( my $fh, '<', $failed ) or die "Cannot read $failed: $!";
    my @retry = <$fh>;
    close($fh);
    @restarts = ();
    is( xCAT_plugin::dhcp::_isc_declare_ipxe_features( \@retry, $failed ), undef,
        'ISC: the next run, with the options already in the file, gives no error' );
    is_deeply( \@restarts, ['dhcp'], 'ISC: and restarts dhcpd before it changes a host' );
    ok( !-e "$failed.ipxe-restart", 'ISC: and then removes the marker' );
}

# makedhcp stops before it changes a subnet or a host when dhcpd has not loaded the options: OMAPI
# removes a host before it adds it again. process_request also sets the callback of the Kea path.
my @responses;
{
    package DHCPUpgradeISCBackend;
    sub name { return 'isc'; }

    package DHCPUpgradeTable;
    sub getNodeAttribs { return; }
    sub getNodesAttribs { return {}; }
    sub getAllAttribs { return; }
    sub getAttribs { return { username => 'xcat_key', password => 'dGVzdA==' }; }
    sub close { return; }

    package main;

    my $dir = tempdir( CLEANUP => 1 );
    my ( @restarts, @reached );
    no warnings 'redefine';
    local *xCAT::DHCP::Backend::new_backend = sub { return bless {}, 'DHCPUpgradeISCBackend'; };
    local *xCAT::Utils::isServiceNode = sub { return 0; };
    local *xCAT::Utils::isLinux = sub { return 1; };
    local *xCAT::Utils::checkservicestatus = sub { return 0; };
    local *xCAT::Table::new = sub { return bless {}, 'DHCPUpgradeTable'; };
    local *xCAT::NetworkUtils::determinehostname = sub { return ('mn'); };
    local *xCAT::TableUtils::get_site_attribute = sub { return; };
    local *xCAT::MsgUtils::trace = sub { return; };
    local *xCAT_plugin::dhcp::addnic = sub { push @reached, 'addnic'; };
    local *xCAT_plugin::dhcp::addnet = sub { push @reached, 'addnet'; };
    local *xCAT_plugin::dhcp::addnet6 = sub { return; };
    my $writeout = \&xCAT_plugin::dhcp::writeout;
    local *xCAT_plugin::dhcp::writeout = sub { push @reached, 'writeout'; };
    local *xCAT_plugin::dhcp::_open_omshell_writer = sub { push @reached, 'omshell'; return; };
    local $::XCATSITEVALS{externaldhcpservers};
    local $xCAT_plugin::dhcp::dhcpconffile = "$dir/dhcpd.conf";
    local $xCAT_plugin::dhcp::distro = 'rhels9.4';

    my $makedhcp = sub {
        my ($restart) = @_;
        local *xCAT::Utils::restartservice = sub { push @restarts, 'dhcp'; return $restart; };
        @responses = @reached = @restarts = ();
        my $umask = umask;
        # process_request prints after it restarts dhcpd, and that text would break the TAP output.
        open( my $printed, '>', \my $text ) or die "Cannot open an output buffer: $!";
        my $selected = select($printed);
        eval {
            xCAT_plugin::dhcp::process_request( { _xcatpreprocessed => [1], node => ['cn1'], arg => [] }, sub { push @responses, @_; } );
            1;
        } or push @reached, "died: $@";
        select($selected);
        umask $umask;
        return join ' ', map { @{ $_->{error} || [] } } @responses;
    };
    my $write = sub {
        my ( $read_only, @lines ) = @_;
        @lines = @old_header unless @lines;
        my $conf = $xCAT_plugin::dhcp::dhcpconffile;
        chmod 0600, $conf;
        open( my $fh, '>', $conf ) or die "Cannot create $conf: $!";
        print {$fh} @lines;
        close($fh) or die "Cannot close $conf: $!";
        chmod 0400, $conf if $read_only;
    };

    $write->(0);
    like( $makedhcp->(1), qr/Unable to restart the DHCP server after adding the iPXE feature options/,
        'ISC: makedhcp reports a dhcpd that does not restart with the options' );
    is_deeply( \@reached, [], 'ISC: and changes no subnet or host' );

    $write->( 0, grep { !/gpxe/ } @old_header );
    like( $makedhcp->(0), qr/: it declares no gpxe option space\. Run makedhcp -n\./,
        'ISC: makedhcp reports a configuration without the gpxe option space' );
    is_deeply( [ \@restarts, \@reached ], [ [], [] ], 'ISC: and neither restarts dhcpd nor changes a subnet or host' );

    # makedhcp -a before makedhcp -n writes a new configuration, which declares the options. dhcpd can
    # still run an older one, so it loads the new one before OMAPI replaces a host.
    my $newconfig = \&xCAT_plugin::dhcp::newconfig;
    for my $case ( [ 'no dhcpd.conf' ], [ 'a dhcpd.conf that xCAT did not write', "ddns-update-style none;\n" ] ) {
        my ( $label, @lines ) = @$case;
        my $conf = $xCAT_plugin::dhcp::dhcpconffile;
        my $loaded;
        local *xCAT_plugin::dhcp::newconfig = sub { push @reached, 'newconfig'; return $newconfig->(@_); };
        local *xCAT_plugin::dhcp::writeout = sub { push @reached, 'writeout'; return $writeout->(@_); };
        local *xCAT_plugin::dhcp::_open_omshell_writer = sub {
            $loaded = "@restarts";
            push @reached, 'omshell';
            open( my $fh, '>', \my $commands ) or die "Cannot open an omshell buffer: $!";
            return $fh;
        };
        local *xCAT_plugin::dhcp::_close_omshell_writer = sub { return; };
        local *xCAT_plugin::dhcp::addnode = sub { push @reached, 'addnode'; };
        local *xCAT::DBobjUtils::getnodetype = sub { return {}; };
        local *xCAT::NetworkUtils::getipaddr = sub { return; };
        unlink $conf, "$conf.ipxe-restart";
        $write->( 0, @lines ) if @lines;
        unlike( $makedhcp->(0), qr/iPXE feature options|gpxe/, "ISC: makedhcp with $label gives no iPXE option error" );
        is_deeply( [ grep { /^(?:newconfig|writeout|omshell|addnode)$/ } @reached ],
            [qw(newconfig writeout omshell addnode writeout)],
            'ISC: and writes a new configuration before OMAPI changes a host' ) or diag("reached: @reached");
        is( $loaded, 'dhcp', 'ISC: and restarts dhcpd with it first' );
        open( my $fh, '<', $conf ) or die "Cannot read $conf: $!";
        my $final = do { local $/; <$fh> };
        close($fh);
        ok( ( grep { index( $final, $_ ) >= 0 } @features ) == @features && $final =~ /^omapi-port 7911;$/m,
            'ISC: and the configuration it writes last keeps the iPXE options and the OMAPI port' );
        ok( !-e "$conf.ipxe-restart", 'ISC: and leaves no restart marker' );

        unlink $conf, "$conf.ipxe-restart";
        $write->( 0, @lines ) if @lines;
        like( $makedhcp->(1), qr/Unable to restart the DHCP server with the new configuration/,
            "ISC: makedhcp with $label reports a dhcpd that does not restart with the new configuration" );
        ok( !grep( { $_ eq 'omshell' } @reached ), 'ISC: and changes no host' ) or diag("reached: @reached");

        # The configuration is on disk once a run stops before dhcpd restarts, so the next run takes the
        # path of an upgraded configuration that already declares the options.
        unlink $conf, "$conf.ipxe-restart";
        $write->( 0, @lines ) if @lines;
        {
            local *xCAT_plugin::dhcp::restart_dhcpd = sub { die "stopped\n"; };
            $makedhcp->(0);
        }
        $loaded = undef;
        unlike( $makedhcp->(0), qr/iPXE feature options|Unable to restart/,
            "ISC: makedhcp after a run with $label that stopped before the restart gives no restart error" );
        ok( !grep( { $_ eq 'newconfig' } @reached ), 'ISC: and keeps the configuration of that run' ) or diag("reached: @reached");
        is( $loaded, 'dhcp', 'ISC: and restarts dhcpd before OMAPI changes a host' );
        ok( !-e "$conf.ipxe-restart", 'ISC: and then removes the marker' );
    }

  SKIP: {
        skip 'root writes a read-only file', 3 if $> == 0;
        $write->(1);
        like( $makedhcp->(0), qr/Unable to add the iPXE feature options/, 'ISC: makedhcp reports a configuration it cannot write' );
        is_deeply( \@restarts, [], 'ISC: and does not restart dhcpd' );
        is_deeply( \@reached, [], 'ISC: and changes no subnet or host' );
    }
}

# Kea applies the host reservations through the Control Agent, but reads option definitions only
# from its configuration file. makedhcp loads that file and writes it back as JSON.
{
    package DHCPUpgradeKeaBackend;
    our @ISA = ('xCAT::DHCP::Backend::Kea');
    sub load_dhcp4_config { my ($self) = @_; return $self->SUPER::load_dhcp4_config( $self->{path} ); }
    sub upsert_reservations { return; }
    sub encode_config { my ( $self, $config ) = @_; $self->{encoded} = $config; return $self->SUPER::encode_config($config); }
    sub write_dhcp4_json { $_[0]->{written} = $_[1]; return {}; }
    sub live_upsert_reservations { return { ok => 1 }; }
    sub restart_services { $_[0]->{restarts}++; return {}; }

    package main;

    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_build_dhcp4_intent = sub { return { subnets => [] }; };
    local *xCAT_plugin::dhcp::kea_build_dhcp6_intent = sub { return { subnets => [] }; };
    local *xCAT_plugin::dhcp::kea_build_ddns_intent = sub { return; };
    local *xCAT_plugin::dhcp::kea_expand_request_nodes = sub { return ['cn1']; };
    local *xCAT_plugin::dhcp::kea_build_node_reservations = sub { return []; };
    local *xCAT_plugin::dhcp::kea_sync_xnba_client_classes = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 1; };
    local *xCAT_plugin::dhcp::kea_control_agent_live_enabled = sub { return 1; };
    local $::XCATSITEVALS{externaldhcpservers};

    my $dir = tempdir( CLEANUP => 1 );
    my $makedhcp = sub {
        my (@defs) = @_;
        my $backend = DHCPUpgradeKeaBackend->new();
        $backend->{path} = "$dir/kea-dhcp4.conf";
        open( my $fh, '>', $backend->{path} ) or die "Cannot create $backend->{path}: $!";
        print {$fh} JSON::encode_json( { Dhcp4 => { subnet4 => [ { id => 1, subnet => '192.0.2.0/24' } ], 'option-def' => \@defs } } );
        close($fh) or die "Cannot close $backend->{path}: $!";
        xCAT_plugin::dhcp::kea_process_request( $backend, { node => ['cn1'] }, {}, {}, 0 );
        return $backend;
    };

    my @old_defs = ( { name => 'conf-file', code => 209, type => 'string', space => 'dhcp4' } );
    my $old = $makedhcp->(@old_defs);
    is_deeply( JSON::decode_json( $old->{written} )->{Dhcp4}{'option-def'}, [ @old_defs, @$kea_defs ],
        'Kea: makedhcp adds the iPXE feature options to an old configuration' );
    is_deeply( [ string_codes( $old->{encoded}{Dhcp4}{'option-def'} ) ], [], 'Kea: and writes every option code as a number' );
    is( $old->{restarts}, 1, 'Kea: and restarts Kea to load them' );

    @responses = ();
    my $opaque = $makedhcp->( @old_defs, { name => 'site-175', code => 175, type => 'binary', space => 'dhcp4' } );
    like( join( ' ', map { @{ $_->{error} || [] } } @responses ), qr/\bsite-175 gives option 175 no gpxe encapsulation/,
        'Kea: makedhcp reports an option 175 without the gpxe encapsulation' );
    ok( !defined $opaque->{written} && !$opaque->{restarts}, 'Kea: and changes nothing' );

    my $current = $makedhcp->( @old_defs, @$kea_defs );
    is( scalar @{ JSON::decode_json( $current->{written} )->{Dhcp4}{'option-def'} }, @old_defs + @$kea_defs,
        'Kea: a current configuration keeps its definitions' );
    is_deeply( [ string_codes( $current->{encoded}{Dhcp4}{'option-def'} ) ], [], 'Kea: and writes every option code as a number' );
    ok( !$current->{restarts}, 'Kea: and makedhcp updates its hosts without a restart' );
}

done_testing();
