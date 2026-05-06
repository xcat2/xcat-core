# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::TLSPolicy;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(
  MODERN_TLS_VERSION
  LEGACY_TLS_VERSION
  DEFAULT_TLS_POLICY
  resolve_xcatd_tls_settings
  tls_setting_warnings
);

use constant MODERN_TLS_VERSION => 'SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1';
use constant LEGACY_TLS_VERSION => 'SSLv23:!SSLv2:!SSLv3';
use constant DEFAULT_TLS_POLICY => 'modern';

sub _site_value {
    my ($site, $key) = @_;

    return '' unless $site && defined $site->{$key};

    my $value = $site->{$key};
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub _normalize_policy {
    my $policy = shift || '';
    $policy =~ s/^\s+|\s+$//g;
    return lc($policy);
}

sub resolve_xcatd_tls_settings {
    my $site = shift || {};

    my $override = _site_value($site, 'xcatsslversion');
    if ($override ne '') {
        return {
            policy      => 'override',
            ssl_version => $override,
            source      => 'xcatsslversion',
        };
    }

    my $policy_value = _site_value($site, 'xcattlspolicy');
    my $policy = _normalize_policy($policy_value);
    my $source = ($policy ne '') ? 'xcattlspolicy' : 'default';
    $policy = DEFAULT_TLS_POLICY unless $policy ne '';

    if ($policy eq 'legacy') {
        return {
            policy      => 'legacy',
            ssl_version => LEGACY_TLS_VERSION,
            source      => $source,
        };
    }

    return {
        policy      => DEFAULT_TLS_POLICY,
        ssl_version => MODERN_TLS_VERSION,
        source      => ($policy eq DEFAULT_TLS_POLICY) ? $source : 'default',
    };
}

sub _enabled_protocols {
    my $ssl_version = shift || '';
    my %enabled;

    foreach my $token (split /:/, $ssl_version) {
        $token =~ s/^\s+|\s+$//g;
        next if $token eq '';
        next if $token =~ /^!/;
        $enabled{lc($token)} = 1;
    }

    return \%enabled;
}

sub _explicitly_disables {
    my ($ssl_version, $protocol) = @_;

    foreach my $token (split /:/, ($ssl_version || '')) {
        $token =~ s/^\s+|\s+$//g;
        return 1 if lc($token) eq '!' . lc($protocol);
    }

    return 0;
}

sub _deprecated_protocol_enabled {
    my $ssl_version = shift || '';
    my $enabled = _enabled_protocols($ssl_version);

    return 1 if $enabled->{sslv2} || $enabled->{sslv3} || $enabled->{tlsv1} || $enabled->{tlsv1_1} || $enabled->{tlsv11};

    if ($enabled->{sslv23}) {
        return 1 unless _explicitly_disables($ssl_version, 'SSLv2');
        return 1 unless _explicitly_disables($ssl_version, 'SSLv3');
        return 1 unless _explicitly_disables($ssl_version, 'TLSv1');
        return 1 unless _explicitly_disables($ssl_version, 'TLSv1_1') || _explicitly_disables($ssl_version, 'TLSv11');
    }

    return 0;
}

sub _deprecated_cipher_enabled {
    my $ciphers = shift || '';

    foreach my $token (split /:/, $ciphers) {
        $token =~ s/^\s+|\s+$//g;
        next if $token eq '' || $token =~ /^!/;
        return 1 if $token =~ /(?:^|[+_-])(?:3DES|DES-CBC3|RC4)(?:$|[+_-])/i;
        return 1 if $token =~ /^(?:LOW|EXP|EXPORT)$/i;
    }

    return 0;
}

sub tls_setting_warnings {
    my $site = shift || {};
    my @warnings;

    my $policy = _normalize_policy(_site_value($site, 'xcattlspolicy'));
    if ($policy ne '' && $policy ne 'modern' && $policy ne 'legacy') {
        push @warnings, "Unsupported site.xcattlspolicy '$policy'; xcatd will use the modern TLS policy.";
    }

    my $ssl_version = _site_value($site, 'xcatsslversion');
    if ($ssl_version ne '' && _deprecated_protocol_enabled($ssl_version)) {
        push @warnings, "site.xcatsslversion enables deprecated protocols; clear it or use site.xcattlspolicy=modern for TLS 1.2 or newer.";
    }

    my $ciphers = _site_value($site, 'xcatsslciphers');
    if (_deprecated_cipher_enabled($ciphers)) {
        push @warnings, "site.xcatsslciphers contains legacy cipher selectors; clear it unless a legacy estate explicitly requires it.";
    }

    return @warnings;
}

1;
