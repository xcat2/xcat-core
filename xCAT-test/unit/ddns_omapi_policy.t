#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir tempfile);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $tmp = tempdir(CLEANUP => 1);
local $ENV{XCATCFG} = "SQLite:$tmp";
local $ENV{XCATROOT} = repo_path('xCAT-server');

our $key_file = "$tmp/ddns.key";
BEGIN {
    # Redirect the fixed key path without replacing the production read/write decisions.
    *CORE::GLOBAL::open = sub (*;$@) {
        return CORE::open($_[0], $_[1], $key_file)
          if @_ == 3 && !ref($_[2]) && $_[2] eq '/etc/xcat/ddns.key';
        die 'Unexpected key-file open form'
          if @_ == 2 && index($_[1], '/etc/xcat/ddns.key') >= 0;
        return CORE::open($_[0], $_[1]) if @_ == 2;
        return CORE::open($_[0], $_[1], @_[2 .. $#_]);
    };
}

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
my $provider_key =
  "key \"provider.key\" {\n\talgorithm hmac-sha512;\n\tsecret \"provider-secret\";\n};\n\n";

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
    $provider_key,
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

        unlink $key_file if -e $key_file;
        my $key_context = {
            omapi_settings => $sha512,
            privkey        => 'provider-secret',
        };
        with_net_dns_version(
            $version,
            sub {
                xCAT_plugin::ddns::ensure_ddns_key_file($key_context);
            }
        );
        is(
            -f $key_file ? read_text($key_file) : undef,
            $uses_keyfile ? $provider_key : undef,
            "Net::DNS $version creates a key file only when required"
        );

        write_text($key_file, "previous key\n");
        with_net_dns_version(
            $version,
            sub { xCAT_plugin::ddns::ensure_ddns_key_file($key_context); }
        );
        is(
            read_text($key_file),
            $uses_keyfile ? $provider_key : "previous key\n",
            "Net::DNS $version refreshes an existing key only when required"
        );

        for my $secret (undef, '') {
            $key_context->{privkey} = $secret;
            unlink $key_file or die "Unable to remove $key_file: $!";
            with_net_dns_version(
                $version,
                sub { xCAT_plugin::ddns::ensure_ddns_key_file($key_context); }
            );
            ok(!-e $key_file,
                "Net::DNS $version does not create a key without a secret");

            write_text($key_file, "previous key\n");
            with_net_dns_version(
                $version,
                sub { xCAT_plugin::ddns::ensure_ddns_key_file($key_context); }
            );
            is(read_text($key_file), "previous key\n",
                "Net::DNS $version preserves an existing key without a secret");
        }
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
        is(
            -f $key_file ? read_text($key_file) : undef,
            $uses_keyfile
              ? "key \"xcat_key\" {\n\talgorithm hmac-sha256;\n\tsecret \"legacy-secret\";\n};\n\n"
              : undef,
            "Net::DNS $version writes the named algorithm to the key file when required"
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

    unlink $key_file if -e $key_file;
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
