#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use MIME::Base64 qw(encode_base64);
use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

{
    package Local::PasswdTable;

    sub new
    {
        my ( $class, $password_entry ) = @_;
        return bless {
            password_entry => $password_entry,
            get_calls      => [],
            set_calls      => [],
        }, $class;
    }

    sub getAttribs
    {
        my ( $self, $selector, @attributes ) = @_;
        push @{ $self->{get_calls} }, [ { %{$selector} }, @attributes ];
        return $self->{password_entry};
    }

    sub setAttribs
    {
        my ( $self, $selector, $values ) = @_;
        push @{ $self->{set_calls} },
          [ { %{$selector} }, { %{$values} } ];
        $self->{password_entry} = { password => $values->{password} };
        return;
    }
}

sub expected_config
{
    my (%args) = @_;
    return join '',
      $args{prefix} // '',
      "omapi-port $args{port};\n",
      "key $args{key_name} {\n",
      "  algorithm $args{algorithm};\n",
      "  secret \"$args{secret}\";\n",
      "};\n",
      "omapi-key $args{key_name};\n";
}

{
    no warnings qw(once redefine);

    my $table = Local::PasswdTable->new(
        { password => 'stored-secret==' }
    );
    my @config = ("before\n");
    my @messages;
    my @requested_lengths;
    my $table_new_calls = 0;
    local *xCAT::Table::new = sub {
        $table_new_calls++;
        return $table;
    };
    local *xCAT_plugin::dhcp::genpassword = sub {
        my ($length) = @_;
        push @requested_lengths, $length;
        return 'unused-generated-password-value';
    };

    xCAT_plugin::dhcp::_append_omapi_key_config(
        \@config,
        {
            key_name  => 'site-key',
            algorithm => 'hmac-sha256',
        },
        7911,
        sub { push @messages, shift },
        $table,
    );

    is(
        join( '', @config ),
        expected_config(
            prefix    => "before\n",
            port      => 7911,
            key_name  => 'site-key',
            algorithm => 'hmac-sha256',
            secret    => 'stored-secret==',
        ),
        'IPv4 OMAPI configuration reuses the stored secret'
    );
    is_deeply(
        $table->{get_calls},
        [ [ { key => 'omapi', username => 'site-key' }, 'password' ] ],
        'stored secret is read using the existing passwd-table selector'
    );
    is_deeply( $table->{set_calls}, [],
        'stored secret is not written again' );
    is_deeply( \@messages, [],
        'stored secret does not request a DHCP restart' );
    is_deeply( \@requested_lengths, [32],
        'stored-secret path retains the existing eager password generation' );
    is( $table_new_calls, 0,
        'caller-supplied passwd table is reused without opening another' );
}

{
    no warnings qw(once redefine);

    my $table = Local::PasswdTable->new(undef);
    my @table_new_calls;
    my @messages;
    my @requested_lengths;
    my $generated_password = 'x' x 32;
    my $generated_secret = encode_base64($generated_password);
    chomp $generated_secret;

    local *xCAT::Table::new = sub {
        push @table_new_calls, [@_];
        return $table;
    };
    local *xCAT_plugin::dhcp::genpassword = sub {
        my ($length) = @_;
        push @requested_lengths, $length;
        return $generated_password;
    };

    my @ipv6_config;
    xCAT_plugin::dhcp::_append_omapi_key_config(
        \@ipv6_config,
        {
            key_name  => 'cluster-key',
            algorithm => 'hmac-sha512',
        },
        7912,
        sub { push @messages, shift },
    );

    is(
        join( '', @ipv6_config ),
        expected_config(
            port      => 7912,
            key_name  => 'cluster-key',
            algorithm => 'hmac-sha512',
            secret    => $generated_secret,
        ),
        'IPv6 OMAPI configuration renders and stores a generated secret'
    );
    is_deeply(
        $table_new_calls[0],
        [ 'xCAT::Table', 'passwd', '-create', 1 ],
        'IPv6 path opens the passwd table with the existing arguments'
    );
    is_deeply(
        $table->{set_calls},
        [
            [
                { key => 'omapi', username => 'cluster-key' },
                { username => 'cluster-key', password => $generated_secret }
            ]
        ],
        'generated secret is stored under the configured OMAPI key name'
    );
    is_deeply(
        \@messages,
        [
            {
                data =>
                  ['The dhcp server must be restarted for OMAPI function to work']
            }
        ],
        'generating the secret retains the existing restart notice'
    );

    my @ipv4_config;
    xCAT_plugin::dhcp::_append_omapi_key_config(
        \@ipv4_config,
        {
            key_name  => 'cluster-key',
            algorithm => 'hmac-sha512',
        },
        7911,
        sub { push @messages, shift },
        $table,
    );

    is(
        join( '', @ipv4_config ),
        expected_config(
            port      => 7911,
            key_name  => 'cluster-key',
            algorithm => 'hmac-sha512',
            secret    => $generated_secret,
        ),
        'the other address family reuses the secret created by the first'
    );
    is( scalar @{ $table->{set_calls} }, 1,
        'the shared secret is created only once' );
    is( scalar @messages, 1,
        'the restart notice is emitted only for the created secret' );
    is( scalar @table_new_calls, 1,
        'caller-supplied table prevents a second passwd-table open' );
    is_deeply( \@requested_lengths, [ 32, 32 ],
        'both address-family paths retain 32-character eager generation' );
}

{
    no warnings qw(once redefine);

    my $table = Local::PasswdTable->new( { password => '' } );
    my @config;
    my @messages;
    my $table_new_calls = 0;
    my $generated_password = 'y' x 32;
    my $generated_secret = encode_base64($generated_password);
    chomp $generated_secret;

    local *xCAT::Table::new = sub {
        $table_new_calls++;
        return $table;
    };
    local *xCAT_plugin::dhcp::genpassword = sub {
        return $generated_password;
    };

    xCAT_plugin::dhcp::_append_omapi_key_config(
        \@config,
        {
            key_name  => 'empty-key',
            algorithm => 'hmac-md5',
        },
        7911,
        sub { push @messages, shift },
        $table,
    );

    is(
        join( '', @config ),
        expected_config(
            port      => 7911,
            key_name  => 'empty-key',
            algorithm => 'hmac-md5',
            secret    => $generated_secret,
        ),
        'empty stored password is replaced with a generated secret'
    );
    is_deeply(
        $table->{set_calls},
        [
            [
                { key => 'omapi', username => 'empty-key' },
                { username => 'empty-key', password => $generated_secret }
            ]
        ],
        'replacement secret is persisted for an empty password row'
    );
    is_deeply(
        \@messages,
        [
            {
                data =>
                  ['The dhcp server must be restarted for OMAPI function to work']
            }
        ],
        'empty password retains the existing restart notice'
    );
    is( $table_new_calls, 0,
        'empty-password path retains the caller-supplied table' );
}

{
    no warnings qw(once redefine);

    our %XCATSITEVALS;
    local %XCATSITEVALS = ( externaldhcpservers => '' );

    my $settings = {
        key_name  => 'wired-key',
        algorithm => 'hmac-sha256',
    };
    my $preopened_table = bless {}, 'Local::PreopenedPasswdTable';
    my @table_new_calls;
    my @renderer_calls;

    local *xCAT_plugin::dhcp::_omapi_settings = sub {
        return $settings;
    };
    local *xCAT::Table::new = sub {
        push @table_new_calls, [@_];
        return $preopened_table;
    };
    local *xCAT_plugin::dhcp::_append_omapi_key_config = sub {
        my ( $config, $actual_settings, $port, $cb, @remaining ) = @_;
        push @renderer_calls,
          {
            config     => [ @{$config} ],
            settings   => $actual_settings,
            port       => $port,
            callback   => $cb,
            table      => $remaining[0],
            argument_count => scalar @_,
          };
        return;
    };

    xCAT_plugin::dhcp::newconfig();
    xCAT_plugin::dhcp::newconfig6();

    is( scalar @renderer_calls, 2,
        'IPv4 and IPv6 configuration each invoke the shared renderer' );
    is( $renderer_calls[0]->{port}, 7911,
        'IPv4 configuration wires OMAPI port 7911' );
    is( $renderer_calls[1]->{port}, 7912,
        'IPv6 configuration wires OMAPI port 7912' );
    is( $renderer_calls[0]->{argument_count}, 5,
        'IPv4 configuration forwards its preopened passwd table' );
    is( $renderer_calls[0]->{table}, $preopened_table,
        'IPv4 renderer receives the table opened by its caller' );
    is( $renderer_calls[1]->{argument_count}, 4,
        'IPv6 configuration lets the renderer open the passwd table' );
    is_deeply(
        \@table_new_calls,
        [ [ 'xCAT::Table', 'passwd', '-create', 1 ] ],
        'only IPv4 opens the passwd table before invoking the renderer'
    );
    ok(
        grep( { $_ eq "option conf-file code 209 = text;\n" }
              @{ $renderer_calls[0]->{config} } ),
        'IPv4 renderer receives the IPv4 configuration target'
    );
    is_deeply(
        $renderer_calls[1]->{config},
        [
            "#xCAT generated dhcp configuration\n",
            "\n",
            "ddns-update-style interim;\n",
            "ignore client-updates;\n",
        ],
        'IPv6 renderer receives the IPv6 configuration target'
    );
}

done_testing();
