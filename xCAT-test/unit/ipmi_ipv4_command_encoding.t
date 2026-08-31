#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)

BEGIN {
    *CORE::GLOBAL::chmod = sub { return 1; };

    my @stub_modules = qw(
      xCAT::GlobalDef
      xCAT_monitoring::monitorctrl
      xCAT::SPD
      xCAT::IPMI
      xCAT::BMCUtils
      xCAT::PasswordUtils
      xCAT::Utils
      xCAT::TableUtils
      xCAT::IMMUtils
      xCAT::ServiceNodeUtils
      xCAT::SvrUtils
      xCAT::NetworkUtils
      xCAT::Usage
      xCAT::data::ibmhwtypes
      xCAT::data::ibmleds
      xCAT::data::ipmigenericevents
      xCAT::data::ipmisensorevents
    );

    foreach my $module (@stub_modules) {
        ( my $module_file = $module ) =~ s{::}{/}g;
        $INC{"$module_file.pm"} = __FILE__;
        no strict 'refs';
        *{"${module}::import"} = sub { };
    }

    no strict 'refs';
    *{'xCAT::BMCUtils::rspconfig_bmc_setting'} = sub { return {}; };

    package File::Path;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::mkpath"} = sub { return 1; };
    }
    $INC{'File/Path.pm'} = __FILE__;
}

package Local::IPMISession;

sub new {
    my ( $class, $channel ) = @_;
    return bless { currentchannel => $channel, calls => [] }, $class;
}

sub subcmd {
    my ( $self, %args ) = @_;
    push @{ $self->{calls} }, \%args;
    return;
}

package Local::IPMIFlowSession;

sub new {
    my ( $class, $channel ) = @_;
    return bless { currentchannel => $channel, calls => [] }, $class;
}

sub subcmd {
    my ( $self, %args ) = @_;
    push @{ $self->{calls} }, \%args;

    # Answer LAN configuration writes so the transaction chain advances;
    # leave the final read-back request unanswered to end the exchange.
    if ( $args{command} == 0x01 ) {
        $args{callback}->( {}, $args{callback_args} );
    }
    return;
}

package main;

no warnings qw(once redefine);
use FindBin;
use File::Spec;
use Test::More;

my $repo_root = $ENV{XCAT_IPMI_PLUGIN_ROOT}
  || File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'ipmi.pm' );
require $plugin;

my $system_inet_aton = \&xCAT_plugin::ipmi::inet_aton;
my @messages;
*xCAT::SvrUtils::sendmsg = sub {
    push @messages, [@_];
    return;
};

sub run_setting {
    my ($setting) = @_;
    my $session = Local::IPMISession->new( 2 );
    my $session_data = {
        bmcnum               => 1,
        ipmisession          => $session,
        netinfo_setinprogress => 1,
        node                 => 'node01',
        set_ipsrc_static     => 1,
        subcommand           => $setting,
    };

    @messages = ();
    my $ok = eval {
        xCAT_plugin::ipmi::setnetinfo($session_data);
        1;
    };

    return {
        calls        => $session->{calls},
        error        => $@,
        messages     => [@messages],
        session_data => $session_data,
        succeeded    => $ok,
    };
}

subtest 'IPv4 settings preserve their wire command bytes' => sub {
    my @cases = (
        {
            setting => 'ip=192.168.1.10',
            data    => [ 2, 0x03, 192, 168, 1, 10 ],
            value   => '192.168.1.10',
        },
        {
            setting => 'ip=0.0.0.0',
            data    => [ 2, 0x03, 0, 0, 0, 0 ],
            value   => '0.0.0.0',
        },
        {
            setting => 'gateway=10.20.30.1',
            data    => [ 2, 0x0c, 10, 20, 30, 1 ],
            value   => '10.20.30.1',
        },
        {
            setting => 'backupgateway=10.20.30.2',
            data    => [ 2, 0x0e, 10, 20, 30, 2 ],
            value   => '10.20.30.2',
        },
        {
            setting  => 'snmpdest2=bmc.example.test',
            hostname => 1,
            data    => [
                2, 0x13, 2, 0, 0, 203, 0, 113, 7,
                0, 0,    0, 0, 0, 0,
            ],
        },
    );

    foreach my $case (@cases) {
        my $result;
        if ( $case->{hostname} ) {
            local *xCAT_plugin::ipmi::inet_aton = sub {
                return pack( 'C4', 203, 0, 113, 7 )
                  if $_[0] eq 'bmc.example.test';
                return $system_inet_aton->(@_);
            };
            $result = run_setting( $case->{setting} );
        } else {
            $result = run_setting( $case->{setting} );
        }
        ok( $result->{succeeded}, "$case->{setting} is encoded" )
          or diag $result->{error};
        is( scalar( @{ $result->{calls} } ), 1,
            "$case->{setting} sends one command" );
        my $call = $result->{calls}->[0];
        is( $call->{netfn}, 0x0c, "$case->{setting} uses the transport netfn" );
        is( $call->{command}, 0x01,
            "$case->{setting} uses the LAN configuration command" );
        is_deeply( $call->{data}, $case->{data},
            "$case->{setting} preserves the command data" );
        is_deeply( $result->{messages}, [],
            "$case->{setting} reports no error" );
        if ( exists $case->{value} ) {
            is( $result->{session_data}->{setnetinfo_value}, $case->{value},
                "$case->{setting} preserves the canonical readback value" );
        }
    }
};

subtest 'IPv4 resolver contract' => sub {
    plan skip_all => 'shared IPv4 resolver is not present on the base revision'
      unless xCAT_plugin::ipmi->can('_resolve_ipv4_octets');

    my ( $canonical, @octets ) =
      xCAT_plugin::ipmi::_resolve_ipv4_octets('192.168.1.10');
    is( $canonical, '192.168.1.10', 'a literal is canonicalized' );
    is_deeply( \@octets, [ 192, 168, 1, 10 ],
        'a literal produces exactly four octets' );

    {
        local *xCAT_plugin::ipmi::inet_aton = sub {
            return pack( 'C4', 203, 0, 113, 7 )
              if $_[0] eq 'bmc.example.test';
            return $system_inet_aton->(@_);
        };
        ( $canonical, @octets ) =
          xCAT_plugin::ipmi::_resolve_ipv4_octets('bmc.example.test');
    }
    is( $canonical, '203.0.113.7', 'a resolvable hostname remains supported' );
    is_deeply( \@octets, [ 203, 0, 113, 7 ],
        'a hostname produces the resolved octets' );

    my @invalid =
      xCAT_plugin::ipmi::_resolve_ipv4_octets('999.999.999.999');
    is_deeply( \@invalid, [], 'an invalid address produces no result' );
};

subtest 'ambiguous IPv4 literals are rejected' => sub {
    plan skip_all => 'the shared IPv4 resolver is not present on the base revision'
      unless xCAT_plugin::ipmi->can('_resolve_ipv4_octets');

    my @ambiguous = (
        [ '192.168.001.010', 'leading-zero octets are octal to some resolvers' ],
        [ '192.168.257',     'out-of-range octets overflow into neighbours' ],
        [ '3232235786',      'single-number form' ],
        [ '192.168.1',       'partial three-part form' ],
        [ '192.168.1.10.5',  'five-part form' ],
        [ '256.1.1.1',       'octet above 255' ],
        [ '192.168..1',      'empty octet' ],
        [ '0xc0a8010a',      'single hexadecimal form' ],
        [ '0xc0.0xa8.0x01.0x0a', 'dotted hexadecimal form' ],
        [ '0X0A141E02',      'uppercase hexadecimal form' ],
        [ '127.0x0.0.1',     'mixed decimal and hexadecimal form' ],
    );
    foreach my $case (@ambiguous) {
        my ( $value, $reason ) = @{$case};
        is_deeply( [ xCAT_plugin::ipmi::_resolve_ipv4_octets($value) ],
            [], "'$value' is rejected: $reason" );
    }

    is_deeply(
        [ xCAT_plugin::ipmi::_resolve_ipv4_octets('0.0.0.0') ],
        [ '0.0.0.0', 0, 0, 0, 0 ],
        'the all-zero address used to clear settings stays accepted'
    );
    is_deeply(
        [ xCAT_plugin::ipmi::_resolve_ipv4_octets('255.255.255.255') ],
        [ '255.255.255.255', 255, 255, 255, 255 ],
        'the top of the address range stays accepted'
    );

    {
        local *xCAT_plugin::ipmi::inet_aton = sub {
            return pack( 'C4', 203, 0, 113, 8 ) if $_[0] eq 'beef.face';
            return $system_inet_aton->(@_);
        };
        is_deeply(
            [ xCAT_plugin::ipmi::_resolve_ipv4_octets('beef.face') ],
            [ '203.0.113.8', 203, 0, 113, 8 ],
            'a hostname made of hexadecimal characters still resolves'
        );
    }

    foreach my $setting (
        'ip=192.168.001.010',       'gateway=192.168.257',
        'ip=0xc0a8010a',            'gateway=0xc0.0xa8.0x01.0x0a',
        'backupgateway=0X0A141E02', 'snmpdest1=0xcb007107',
      ) {
        my ( undef, $value ) = split /=/, $setting;
        my $result = run_setting($setting);
        ok( $result->{succeeded}, "$setting does not raise a Perl exception" )
          or diag $result->{error};
        is_deeply( $result->{calls}, [], "$setting sends no IPMI command" );
        is_deeply(
            $result->{messages}->[0]->[0],
            [ 1, "Unable to resolve '$value' to an IPv4 address" ],
            "$setting reports the rejection"
        );
    }
};

subtest 'IPv4 settings resolve once per transaction' => sub {
    plan skip_all => 'the shared IPv4 resolver is not present on the base revision'
      unless xCAT_plugin::ipmi->can('_resolve_ipv4_octets');

    my @cases = (
        {
            setting  => 'gateway=bmc.flaky.test',
            sequence => [
                [ 2, 0x00, 0x01 ],
                [ 2, 0x0c, 10, 20, 30, 40 ],
                [ 2, 0x00, 0x00 ],
            ],
        },
        {
            setting  => 'ip=bmc.flaky.test',
            sequence => [
                [ 2, 0x00, 0x01 ],
                [ 2, 0x04, 0x01 ],
                [ 2, 0x03, 10, 20, 30, 40 ],
                [ 2, 0x00, 0x00 ],
            ],
        },
    );

    foreach my $case (@cases) {
        my $lookups = 0;
        my $session;
        my $session_data;
        {
            # The lookup succeeds once and then fails, like transient DNS.
            local *xCAT_plugin::ipmi::inet_aton = sub {
                return pack( 'C4', 10, 20, 30, 40 ) if ++$lookups == 1;
                return;
            };
            $session      = Local::IPMIFlowSession->new( 2 );
            $session_data = {
                bmcnum      => 1,
                ipmisession => $session,
                node        => 'node01',
                subcommand  => $case->{setting},
            };
            @messages = ();
            my $ok = eval { xCAT_plugin::ipmi::setnetinfo($session_data); 1 };
            ok( $ok, "$case->{setting} completes the transaction" ) or diag $@;
        }
        is( $lookups, 1, "$case->{setting} resolves exactly once" );
        my @writes = grep { $_->{command} == 0x01 } @{ $session->{calls} };
        is_deeply(
            [ map { $_->{data} } @writes ],
            $case->{sequence},
            "$case->{setting} opens, writes, and closes the transaction"
        );
        # netinfo_set issues the read-back twice (it schedules Set Complete
        # and falls through); require only that the chain reaches it.
        cmp_ok( scalar( grep { $_->{command} == 0x02 } @{ $session->{calls} } ),
            '>=', 1, "$case->{setting} reaches the read-back request" );
        is_deeply( [@messages], [], "$case->{setting} reports no error" );
        is( $session_data->{setnetinfo_value}, '10.20.30.40',
            "$case->{setting} keeps the resolved readback value" );
    }
};

subtest 'invalid IPv4 settings report an xCAT error' => sub {
    plan skip_all => 'invalid setting handling is not present on the base revision'
      unless xCAT_plugin::ipmi->can('_resolve_ipv4_octets');

    foreach my $name (qw(ip gateway backupgateway snmpdest1)) {
        my $result = run_setting("$name=999.999.999.999");
        ok( $result->{succeeded}, "$name does not raise a Perl exception" )
          or diag $result->{error};
        is_deeply( $result->{calls}, [], "$name sends no IPMI command" );
        is( scalar( @{ $result->{messages} } ), 1,
            "$name reports one error" );
        is_deeply(
            $result->{messages}->[0]->[0],
            [ 1, "Unable to resolve '999.999.999.999' to an IPv4 address" ],
            "$name explains the invalid value",
        );
    }
};

done_testing();
