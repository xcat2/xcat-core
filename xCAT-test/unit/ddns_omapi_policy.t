#!/usr/bin/env perl
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
    $ddns_plugin_path = $INC{'xCAT_plugin/ddns.pm'};
}

sub omapi_settings {
    my (%overrides) = @_;
    return xCAT::DHCP::OmapiPolicy->settings(
        site_values => {
            dhcpomapialgorithm => undef,
            dhcpomapikeyname   => undef,
            dhcpomshellpath    => undef,
            %overrides,
        }
    );
}

# Model a populated xCAT site and require each fixture to override it fully.
our %XCATSITEVALS;
local %XCATSITEVALS = (
    dhcpomapialgorithm => 'hmac-sha256',
    dhcpomapikeyname   => 'site-key',
    dhcpomshellpath    => '/opt/site/bin/omshell',
);

my @net_dns_versions = (
    [ '1.09',  0 ],
    [ '1.35',  0 ],
    [ '1.36',  1 ],
    [ '1.40',  1 ],
    [ '1.100', 1 ],
    [ '2.0',   1 ],
);

my $defaults = omapi_settings();
is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $defaults,
            privkey        => 'legacy-secret',
        }
    ),
"key \"xcat_key\" {\n\talgorithm hmac-md5;\n\tsecret \"legacy-secret\";\n};\n\n",
    'default DDNS key remains xcat_key with hmac-md5'
);

my $sha512 = omapi_settings(
    dhcpomapialgorithm => 'hmac-sha512',
    dhcpomapikeyname   => 'provider.key',
);

is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $sha512,
        }
    ),
    'hmac-sha512',
    'explicit non-MD5 DDNS algorithm is honored'
);

is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $sha512,
            privkey        => 'provider-secret',
        }
    ),
"key \"provider.key\" {\n\talgorithm hmac-sha512;\n\tsecret \"provider-secret\";\n};\n\n",
    'custom DDNS key name and algorithm are rendered'
);

subtest 'all Net::DNS thresholds share the dotted version policy' => sub {
    open( my $source_fh, '<', $ddns_plugin_path )
      or die "Unable to read $ddns_plugin_path: $!";
    local $/;
    my $source = <$source_fh>;
    close($source_fh)
      or die "Unable to close $ddns_plugin_path: $!";

    my @raw_comparisons =
      ( $source =~ /^(?!\s*#)[^\n]*(?:<|>=)\s*1\.36\b/gm );
    is( scalar(@raw_comparisons), 0,
        'no Net::DNS threshold uses Perl numeric comparison' );

    my @policy_calls = ( $source =~ /net_dns_uses_keyfile\(\)/g );
    is( scalar(@policy_calls), 4,
        'all four Net::DNS threshold sites use the shared policy' );
};

subtest 'Net::DNS threshold controls DDNS policy and signing' => sub {
    my $implicit_sha256 = {
        algorithm          => 'hmac-sha256',
        algorithm_explicit => 0,
    };

    foreach my $case (@net_dns_versions) {
        my ( $version, $uses_keyfile ) = @{$case};
        my $expected_algorithm = $uses_keyfile ? 'hmac-sha256' : 'hmac-md5';
        is(
            with_net_dns_version(
                $version,
                sub {
                    xCAT_plugin::ddns::ddns_tsig_algorithm(
                        { omapi_settings => $implicit_sha256 }
                    );
                }
            ),
            $expected_algorithm,
            "Net::DNS $version selects the expected implicit algorithm"
        );

        my $update = Local::DDNS::Update->new();
        with_net_dns_version(
            $version,
            sub {
                xCAT_plugin::ddns::ddns_sign_update(
                    {
                        omapi_settings => $defaults,
                        privkey        => 'legacy-secret',
                    },
                    $update
                );
            }
        );
        my $expected_call = $uses_keyfile
          ? [ '/etc/xcat/ddns.key' ]
          : [ 'xcat_key', 'legacy-secret' ];
        is_deeply(
            $update->{sign_tsig_calls},
            [$expected_call],
            "Net::DNS $version signs through the expected interface"
        );

        my $tracker = tie my %key_context, 'Local::DDNS::TrackingHash';
        with_net_dns_version(
            $version,
            sub {
                xCAT_plugin::ddns::ensure_ddns_key_file(\%key_context);
            }
        );
        is_deeply(
            $tracker->{fetches},
            $uses_keyfile ? ['privkey'] : [],
            "Net::DNS $version applies the expected keyfile write gate"
        );
    }
};

subtest 'Net::DNS threshold controls named key reconciliation' => sub {
    foreach my $case (@net_dns_versions) {
        my ( $version, $uses_keyfile ) = @{$case};
        my ( $named_contents, $restartneeded ) =
          reconcile_named_key($version);
        my $expected_algorithm = $uses_keyfile ? 'hmac-sha256' : 'hmac-md5';

        like(
            $named_contents,
            qr/^\s*algorithm\s+\Q$expected_algorithm\E\s*;/m,
            "Net::DNS $version keeps the expected named key algorithm"
        );
        is(
            $restartneeded ? 1 : 0,
            $uses_keyfile ? 0 : 1,
            "Net::DNS $version records the expected named restart state"
        );
    }
};

done_testing();

sub with_net_dns_version {
    my ( $version, $code ) = @_;

    local $Net::DNS::VERSION = $version;
    return $code->();
}

sub reconcile_named_key {
    my ($version) = @_;

    my ( $named_fh, $named_path ) = tempfile(UNLINK => 1);
    print {$named_fh}
      "options {\n};\n"
      . "key \"xcat_key\" {\n"
      . "\talgorithm hmac-sha256;\n"
      . "\tsecret \"legacy-secret\";\n"
      . "};\n";
    close($named_fh) or die "Unable to close $named_path: $!";

    my $ctx = {
        omapi_settings => omapi_settings(),
        privkey        => 'legacy-secret',
        zonesdir       => '/tmp',
        dbdir          => '/tmp',
        zonestotouch   => {},
        adzones        => {},
        dnsupdaters    => [],
        adservers      => [],
        restartneeded  => 0,
    };

    no warnings qw(redefine once);
    local *xCAT_plugin::ddns::get_conf = sub { return $named_path; };
    local *xCAT_plugin::ddns::ensure_ddns_key_file = sub { return; };
    local *xCAT::TableUtils::get_site_attribute = sub { return; };
    local *xCAT::Utils::runcmd = sub { return (); };
    local *xCAT::Utils::isAIX = sub { return 0; };
    local *xCAT::Utils::isLinux = sub { return 1; };
    local *xCAT::Table::new = sub {
        return bless {}, 'Local::DDNS::PasswdTable';
    };

    with_net_dns_version(
        $version,
        sub { xCAT_plugin::ddns::update_namedconf( $ctx, 0 ); }
    );

    open( my $result_fh, '<', $named_path )
      or die "Unable to read $named_path: $!";
    local $/;
    my $contents = <$result_fh>;
    close($result_fh) or die "Unable to close $named_path: $!";

    return ( $contents, $ctx->{restartneeded} );
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

{
    package Local::DDNS::TrackingHash;

    sub TIEHASH {
        return bless { fetches => [] }, shift;
    }

    sub FETCH {
        my ( $self, $key ) = @_;
        push @{ $self->{fetches} }, $key;
        return;
    }
}
