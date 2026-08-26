#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Slurper qw(read_text);
use File::Temp qw(tempfile);
use Test::More;
use XCAT::Test::File qw(repo_path slurp_repo_file);

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
    ok( $detected_fips->{algorithm_enforced},
        'runtime FIPS detection enforces the selected algorithm' );
}
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        { omapi_settings => $fips_defaults },
        '1.35'
    ),
    'hmac-sha256',
    'FIPS DDNS does not fall back to hmac-md5 on old Net::DNS'
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
        $fips_defaults, ' HMAC-SHA512 ', '1.35'
    ),
    { algorithm => 'hmac-sha512', replace => 0 },
    'FIPS mode preserves an existing supported non-MD5 algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, 'hmac-md5', '1.36'
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode replaces an existing MD5 key'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, 'hmac-unknown', '1.36'
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode replaces an unsupported key algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, undef, '1.36'
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode repairs a key block without an algorithm'
);
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $fips_defaults,
            tsig_algorithm => 'hmac-sha512',
        },
        '1.35'
    ),
    'hmac-sha512',
    'FIPS DDNS signs with the preserved algorithm'
);

my $sha512 = omapi_settings(
    dhcpomapialgorithm => 'hmac-sha512',
    dhcpomapikeyname   => 'provider.key',
);

is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $sha512, 'hmac-sha256', '1.35'
    ),
    { algorithm => 'hmac-sha512', replace => 1 },
    'an explicit site algorithm replaces a different existing algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $defaults, 'hmac-sha512', '1.35'
    ),
    { algorithm => 'hmac-md5', replace => 1 },
    'old Net::DNS retains the legacy MD5 fallback outside FIPS mode'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $defaults, 'hmac-sha512', '1.36'
    ),
    { algorithm => 'hmac-sha512', replace => 0 },
    'new Net::DNS preserves the existing algorithm outside FIPS mode'
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
    my $source = slurp_repo_file('xCAT-server/lib/xcat/plugins/ddns.pm');

    my @raw_comparisons =
      ( $source =~ /^(?!\s*#)[^\n]*(?:<|>=)\s*1\.36\b/gm );
    is( scalar(@raw_comparisons), 0,
        'no Net::DNS threshold uses Perl numeric comparison' );

    my @policy_calls = ( $source =~ /net_dns_uses_keyfile\(/g );
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

subtest 'DDNS updates retain retry and failure propagation' => sub {
    my $ctx = {
        omapi_settings => $defaults,
        privkey        => 'legacy-secret',
    };
    my $update = Local::DDNS::Update->new();
    my $resolver = Local::DDNS::Resolver->new(qw(NOTAUTH NOERROR));

    is(
        xCAT_plugin::ddns::send_ddns_update(
            $ctx, $resolver, $update, 'example.com', 'node1'
        ),
        0,
        'a transient NOTAUTH response is retried successfully'
    );
    is( $resolver->{send_count}, 2, 'the update is sent again after NOTAUTH' );
    is( scalar @{ $update->{sign_tsig_calls} },
        2, 'the update is signed again before each send' );

    $update   = Local::DDNS::Update->new();
    $resolver = Local::DDNS::Resolver->new(qw(NOTAUTH NOTAUTH NOTAUTH));
    my @messages;
    no warnings qw(redefine once);
    local *xCAT::SvrUtils::sendmsg = sub { push @messages, $_[0]; };

    is(
        xCAT_plugin::ddns::send_ddns_update(
            $ctx, $resolver, $update, 'example.com', 'node1'
        ),
        1,
        'a persistent rejection is returned as a failure'
    );
    is( $resolver->{send_count}, 3, 'persistent NOTAUTH is attempted three times' );
    like(
        $messages[-1]->[1],
        qr/error was NOTAUTH/,
        'the persistent rejection is reported to the caller'
    );
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

    my ( $harvested_key, $harvested_restart ) =
      reconcile_named_key( '1.35', privkey => undef );
    like(
        $harvested_key,
        qr/^\s*algorithm\s+hmac-md5\s*;/m,
        'an existing key secret is reconciled for old Net::DNS'
    );
    ok( $harvested_restart,
        'reconciling a harvested key secret records the named restart' );
};

done_testing();

sub with_net_dns_version {
    my ( $version, $code ) = @_;

    local $Net::DNS::VERSION = $version;
    return $code->();
}

sub reconcile_named_key {
    my ( $version, %args ) = @_;

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

    return ( read_text($named_path), $ctx->{restartneeded} );
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
    package Local::DDNS::Resolver;

    sub new {
        my ( $class, @rcodes ) = @_;
        return bless { rcodes => \@rcodes, send_count => 0 }, $class;
    }

    sub send {
        my ($self) = @_;
        $self->{send_count}++;
        my $rcode = shift @{ $self->{rcodes} };
        return bless { rcode => $rcode }, 'Local::DDNS::Reply';
    }
}

{
    package Local::DDNS::Reply;

    sub header {
        return bless { rcode => $_[0]->{rcode} }, 'Local::DDNS::Header';
    }
}

{
    package Local::DDNS::Header;

    sub rcode {
        return $_[0]->{rcode};
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
