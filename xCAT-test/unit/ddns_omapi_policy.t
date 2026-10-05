#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Slurper qw(read_text);
use File::Temp qw(tempfile tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

$ENV{XCATCFG}  ||= 'SQLite:/tmp';
$ENV{XCATROOT} ||= repo_path('xCAT-server');

my $ddns_plugin_path = repo_path('xCAT-server/lib/xcat/plugins/ddns.pm');
require $ddns_plugin_path;

sub omapi_settings {
    my (%overrides) = @_;
    return xCAT::DHCP::OmapiPolicy->settings(
        site_values => {
            dhcpomapialgorithm => undef,
            dhcpomapikeyname   => undef,
            dhcpomshellpath    => undef,
            %overrides,
        },
        fips_mode => 0,
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

my $fips_defaults = xCAT::DHCP::OmapiPolicy->settings(
    site_values => {
        dhcpomapialgorithm => undef,
        dhcpomapikeyname   => undef,
        dhcpomshellpath    => undef,
    },
    fips_mode => 1,
);
{
    no warnings qw(redefine once);
    local *xCAT::Utils::isFIPS = sub { return 1; };
    my $detected_fips = xCAT::DHCP::OmapiPolicy->settings(
        site_values => {
            dhcpomapialgorithm => undef,
            dhcpomapikeyname   => undef,
            dhcpomshellpath    => undef,
        },
    );
    is( $detected_fips->{algorithm}, 'hmac-sha256',
        'runtime FIPS detection selects the SHA-256 default' );
}
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        { omapi_settings => $fips_defaults }
    ),
    'hmac-sha256',
    'FIPS DDNS defaults to the same algorithm as OMAPI'
);
is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $fips_defaults,
            privkey        => 'fips-secret',
        }
    ),
"key \"xcat_key\" {\n\talgorithm hmac-sha256;\n\tsecret \"fips-secret\";\n};\n\n",
    'FIPS DDNS key uses hmac-sha256'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, ' HMAC-SHA512 '
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode aligns an implicit existing key with the OMAPI default'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, 'hmac-md5'
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode replaces an existing MD5 key'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, 'hmac-unknown'
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode replaces an unsupported key algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, undef
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode repairs a key block without an algorithm'
);
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $fips_defaults,
            tsig_algorithm => 'hmac-sha512',
        }
    ),
    'hmac-sha256',
    'FIPS DDNS signs with the algorithm OMAPI uses'
);

my $sha512 = omapi_settings(
    dhcpomapialgorithm => 'hmac-sha512',
    dhcpomapikeyname   => 'provider.key',
);

is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $sha512, 'hmac-sha256'
    ),
    { algorithm => 'hmac-sha512', replace => 1 },
    'an explicit site algorithm replaces a different existing algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $defaults, 'hmac-sha512'
    ),
    { algorithm => 'hmac-sha512', replace => 0 },
    'the existing algorithm is preserved outside FIPS mode'
);

foreach my $case (
    [ $defaults, ' HMAC-SHA512 ', 'hmac-sha512',
        'implicit policy preserves a normalized existing algorithm' ],
    [ $fips_defaults, "\tHMAC-SHA256 ", 'hmac-sha256',
        'FIPS policy does not replace a matching normalized algorithm' ],
    [ $sha512, " HMAC-SHA512\t", 'hmac-sha512',
        'explicit policy does not replace a matching normalized algorithm' ],
) {
    my ( $settings, $current, $algorithm, $description ) = @{$case};
    is_deeply(
        xCAT_plugin::ddns::ddns_reconcile_key_algorithm($settings, $current),
        { algorithm => $algorithm, replace => 0 },
        $description
    );
}

is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $defaults,
            tsig_algorithm => ' HMAC-SHA512 ',
            privkey        => 'legacy-secret',
        }
    ),
"key \"xcat_key\" {\n\talgorithm hmac-sha512;\n\tsecret \"legacy-secret\";\n};\n\n",
    'DDNS renders the normalized existing algorithm outside FIPS mode'
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

subtest 'Net::DNS threshold controls DDNS policy and signing' => sub {
    my $implicit_sha256 = {
        algorithm          => 'hmac-sha256',
        algorithm_explicit => 0,
    };

    foreach my $case (@net_dns_versions) {
        my ( $version, $uses_keyfile ) = @{$case};
        is(
            with_net_dns_version(
                $version,
                sub {
                    xCAT_plugin::ddns::ddns_tsig_algorithm(
                        { omapi_settings => $implicit_sha256 }
                    );
                }
            ),
            'hmac-sha256',
            "Net::DNS $version keeps the algorithm the site table implies"
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

        like(
            $named_contents,
            qr/^\s*algorithm\s+hmac-sha256\s*;/m,
            "Net::DNS $version keeps the named key algorithm"
        );
        is(
            $restartneeded ? 1 : 0,
            0,
            "Net::DNS $version leaves named alone"
        );
    }

    my ( $harvested_key, $harvested_restart ) =
      reconcile_named_key( '1.35', privkey => undef );
    like(
        $harvested_key,
        qr/^\s*algorithm\s+hmac-sha256\s*;/m,
        'a harvested key keeps its algorithm on old Net::DNS'
    );
    ok( !$harvested_restart,
        'harvesting an unchanged key does not restart named' );
};

subtest 'FIPS named key migration and signing agree' => sub {
    foreach my $case (
        ['hmac-md5', 'hmac-sha256', 1, 163],
        ['hmac-sha512', 'hmac-sha256', 1, 163],
    ) {
        my ($current, $expected, $restart, $rr_type) = @{$case};
        foreach my $version ('1.35', '1.47') {
            foreach my $harvest (0, 1) {
                my $key_dir = tempdir(CLEANUP => 1);
                local $xCAT_plugin::ddns::ddns_key_path = "$key_dir/ddns.key";
                my ($named, $restarted, $ctx) = reconcile_named_key(
                    $version, fips_mode => 1, current_algorithm => $current,
                    privkey => $harvest ? undef : 'legacy-secret',
                );
                like($named, qr/^\s*algorithm\s+\Q$expected\E\s*;/m,
                    "FIPS reconciles $current on Net::DNS $version, harvest=$harvest");
                is($restarted ? 1 : 0, $restart,
                    'named restarts only when its algorithm changes');
                is($ctx->{privkey}, 'legacy-secret', 'migration preserves the shared secret');
                my $update = Local::DDNS::Update->new();
                with_net_dns_version($version, sub {
                    xCAT_plugin::ddns::ddns_sign_update($ctx, $update);
                });
                my $arguments = $update->{sign_tsig_calls}->[0];
                if ($version eq '1.35') {
                    is($arguments->[0]->algorithm, $rr_type,
                        'old Net::DNS signs with the reconciled algorithm');
                } else {
                    is_deeply($arguments, ["$key_dir/ddns.key"],
                        'new Net::DNS uses the reconciled key file');
                    like(read_text($arguments->[0]),
                        qr/^\s*algorithm\s+\Q$expected\E\s*;/m,
                        'the signing key file agrees with named and OMAPI');
                }
            }
        }
    }
};

done_testing();

sub with_net_dns_version {
    my ( $version, $code ) = @_;

    local $Net::DNS::VERSION = $version;
    return $code->();
}

sub reconcile_named_key {
    my ( $version, %args ) = @_;
    my $current = $args{current_algorithm} || 'hmac-sha256';
    my $key_dir = tempdir(CLEANUP => 1);
    local $xCAT_plugin::ddns::ddns_key_path =
        $xCAT_plugin::ddns::ddns_key_path eq '/etc/xcat/ddns.key'
        ? "$key_dir/ddns.key" : $xCAT_plugin::ddns::ddns_key_path;

    my ( $named_fh, $named_path ) = tempfile(UNLINK => 1);
    print {$named_fh}
      "options {\n};\n"
      . "key \"xcat_key\" {\n"
      . "\talgorithm $current;\n"
      . "\tsecret \"legacy-secret\";\n"
      . "};\n";
    close($named_fh) or die "Unable to close $named_path: $!";

    my $ctx = {
        omapi_settings => xCAT::DHCP::OmapiPolicy->settings(
            site_values => {
                dhcpomapialgorithm => undef,
                dhcpomapikeyname => undef,
                dhcpomshellpath => undef,
            },
            fips_mode => $args{fips_mode} || 0,
        ),
        privkey        => exists $args{privkey} ? $args{privkey} : 'legacy-secret',
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

    return ( read_text($named_path), $ctx->{restartneeded}, $ctx );
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
