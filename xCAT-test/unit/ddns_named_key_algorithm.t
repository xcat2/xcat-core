#!/usr/bin/env perl

# makedns must sign every update with the algorithm the named.conf key stanza declares.
# named matches a TSIG key by name AND algorithm, so a stanza that does not agree with the
# signature makes named reject every update and makedns exit 1.
#
# Run this test with XCATROOT set to the tree under test. xCAT::Table does
# "use lib $::XCATROOT/lib/perl", so an installed /opt/xcat shadows the modules under test:
#   XCATROOT=$PWD/xCAT-server prove xCAT-test/unit/ddns_named_key_algorithm.t

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempfile);
use Test::More;

$ENV{XCATCFG}  ||= 'SQLite:/tmp';
$ENV{XCATROOT} ||= "$FindBin::Bin/../../xCAT-server";

my $ddns_plugin_path =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/ddns.pm";
if ( -f $ddns_plugin_path ) {
    require $ddns_plugin_path;
}
else {
    require xCAT_plugin::ddns;
}

# KEY RR algorithm numbers, as ddns_sign_update writes them for old Net::DNS.
my %ALGORITHM_OF_RR_TYPE = (
    157 => 'hmac-md5',
    161 => 'hmac-sha1',
    162 => 'hmac-sha224',
    163 => 'hmac-sha256',
    164 => 'hmac-sha384',
    165 => 'hmac-sha512',
);

my $SECRET = 'c2VjcmV0LXNlY3JldC1zZWNyZXQtc2VjcmV0LXNlY3I=';

my $with_key = <<"NAMED";
options {
};
key "xcat_key" {
\talgorithm hmac-sha256;
\tsecret "$SECRET";
};
NAMED

my $without_key = "options {\n};\n";

subtest 'old Net::DNS keeps the configured algorithm in named.conf' => sub {
    my $result = run_makedns(
        named_conf     => $with_key,
        site_algorithm => 'hmac-sha256',
        net_dns        => '1.25',
    );

    is( $result->{named_algorithm}, 'hmac-sha256',
        'named.conf keeps the algorithm the key was generated with' );
    is( $result->{signing_algorithm}, 'hmac-sha256',
        'the update is signed with that algorithm' );
    is( $result->{restartneeded}, 0, 'named is not restarted' );
};

subtest 'old Net::DNS does not downgrade an unconfigured site' => sub {
    my $result = run_makedns(
        named_conf     => $with_key,
        site_algorithm => undef,
        net_dns        => '1.25',
    );

    is( $result->{named_algorithm}, 'hmac-sha256',
        'named.conf keeps hmac-sha256 when the site table names no algorithm' );
    is( $result->{signing_algorithm}, 'hmac-sha256',
        'the update is signed with hmac-sha256' );
    is( $result->{restartneeded}, 0, 'named is not restarted' );
};

subtest 'new Net::DNS signs through the key file' => sub {
    my $result = run_makedns(
        named_conf     => $with_key,
        site_algorithm => 'hmac-sha256',
        net_dns        => '1.47',
    );

    is( $result->{named_algorithm}, 'hmac-sha256',
        'named.conf keeps hmac-sha256' );
    is( $result->{signing_algorithm}, 'keyfile',
        'the update is signed with /etc/xcat/ddns.key' );
};

subtest 'an explicit site algorithm replaces the stanza' => sub {
    my $result = run_makedns(
        named_conf     => $with_key,
        site_algorithm => 'hmac-sha512',
        net_dns        => '1.25',
    );

    is( $result->{named_algorithm}, 'hmac-sha512',
        'named.conf takes the algorithm the administrator selected' );
    is( $result->{signing_algorithm}, 'hmac-sha512',
        'the update is signed with the selected algorithm' );
    is( $result->{restartneeded}, 1, 'named is restarted for the new stanza' );
};

subtest 'a generated key stays on hmac-md5 for old Net::DNS' => sub {
    my $result = run_makedns(
        named_conf     => $without_key,
        site_algorithm => undef,
        net_dns        => '1.25',
    );

    is( $result->{named_algorithm}, 'hmac-md5',
        'a key created for old Net::DNS uses hmac-md5' );
    is( $result->{signing_algorithm}, 'hmac-md5',
        'the update is signed with hmac-md5' );
};

done_testing();

#---------------------------------------------------------------------------

=head3 run_makedns

    Description: Run update_namedconf over a scratch named.conf, then sign one update
                 with the context that run produced.
    Arguments:   named_conf (the file content), site_algorithm (undef for none),
                 net_dns (the Net::DNS version to report)
    Returns:     hash reference with named_algorithm, signing_algorithm, restartneeded

=cut

#---------------------------------------------------------------------------
sub run_makedns {
    my (%args) = @_;

    my ( $named_fh, $named_path ) = tempfile( UNLINK => 1 );
    print {$named_fh} $args{named_conf};
    close($named_fh) or die "Unable to close $named_path: $!";

    my $settings = xCAT::DHCP::OmapiPolicy->settings(
        site_values => {
            dhcpomapialgorithm => $args{site_algorithm},
            dhcpomapikeyname   => undef,
            dhcpomshellpath    => undef,
        }
    );
    die "Unusable OMAPI settings: $settings->{error}" if $settings->{error};

    my $ctx = {
        omapi_settings => $settings,
        privkey        => $SECRET,
        zonesdir       => '/tmp',
        dbdir          => '/tmp',
        zonestotouch   => {},
        adzones        => {},
        dnsupdaters    => [],
        adservers      => [],
        restartneeded  => 0,
    };

    no warnings qw(redefine once);
    local *xCAT_plugin::ddns::get_conf             = sub { return $named_path; };
    local *xCAT_plugin::ddns::ensure_ddns_key_file = sub { return; };
    local *xCAT::TableUtils::get_site_attribute    = sub { return; };
    local *xCAT::Utils::runcmd                     = sub { return (); };
    local *xCAT::Utils::isAIX                      = sub { return 0; };
    local *xCAT::Utils::isLinux                    = sub { return 1; };
    local *xCAT::Table::new = sub { return bless {}, 'Local::DDNS::PasswdTable'; };

    my $update = Local::DDNS::Update->new();
    {
        local $Net::DNS::VERSION = $args{net_dns};
        xCAT_plugin::ddns::update_namedconf( $ctx, 0 );
        xCAT_plugin::ddns::ddns_sign_update( $ctx, $update );
    }

    open( my $result_fh, '<', $named_path )
      or die "Unable to read $named_path: $!";
    local $/;
    my $contents = <$result_fh>;
    close($result_fh) or die "Unable to close $named_path: $!";

    my ($named_algorithm) =
      ( $contents =~ /key\s+"?xcat_key"?[^{]*\{[^}]*?algorithm\s+([^;\s]+)\s*;/s );

    return {
        named_algorithm   => defined($named_algorithm) ? lc($named_algorithm) : undef,
        signing_algorithm => signing_algorithm($update),
        restartneeded     => $ctx->{restartneeded} ? 1 : 0,
    };
}

#---------------------------------------------------------------------------

=head3 signing_algorithm

    Description: Name the TSIG algorithm one recorded sign_tsig call selects.
    Arguments:   the recording update object
    Returns:     the algorithm name, or "keyfile" for the key-file interface

=cut

#---------------------------------------------------------------------------
sub signing_algorithm {
    my ($update) = @_;

    my $calls = $update->{sign_tsig_calls};
    is( scalar( @{$calls} ), 1, 'the update is signed once' );
    my $args = $calls->[0];

    if ( @{$args} == 1 && !ref( $args->[0] ) ) {
        return 'keyfile';
    }
    if ( @{$args} == 2 ) {
        return 'hmac-md5';
    }

    my $rr_type = $args->[0]->algorithm;
    return $ALGORITHM_OF_RR_TYPE{$rr_type} || "KEY RR algorithm $rr_type";
}

{

    package Local::DDNS::Update;

    sub new {
        return bless { sign_tsig_calls => [] }, shift;
    }

    sub sign_tsig {
        my ( $self, @args ) = @_;
        push @{ $self->{sign_tsig_calls} }, \@args;
        return;
    }
}

{

    package Local::DDNS::PasswdTable;

    sub setAttribs {
        return 1;
    }
}
