#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::TLSPolicy qw(
  MODERN_TLS_VERSION
  LEGACY_TLS_VERSION
  DEFAULT_TLS_POLICY
  resolve_xcatd_tls_settings
  tls_setting_warnings
);

is(DEFAULT_TLS_POLICY, 'modern', 'modern TLS policy is the default');
is(MODERN_TLS_VERSION, 'SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1', 'modern policy allows TLS 1.2 or newer');
unlike(MODERN_TLS_VERSION, qr/!TLSv1_?3/i, 'modern policy leaves TLS 1.3 available when supported');
is(LEGACY_TLS_VERSION, 'SSLv23:!SSLv2:!SSLv3', 'legacy policy preserves TLS 1.0 era compatibility without SSLv2 or SSLv3');

my $default = resolve_xcatd_tls_settings({});
is($default->{policy}, 'modern', 'empty site settings use modern policy');
is($default->{ssl_version}, MODERN_TLS_VERSION, 'empty site settings resolve to modern SSL_version syntax');
is($default->{source}, 'default', 'empty site settings are reported as default policy source');

my $modern = resolve_xcatd_tls_settings({ xcattlspolicy => ' Modern ' });
is($modern->{policy}, 'modern', 'modern policy is case and whitespace tolerant');
is($modern->{ssl_version}, MODERN_TLS_VERSION, 'explicit modern policy resolves to TLS 1.2 or newer');
is($modern->{source}, 'xcattlspolicy', 'explicit modern policy is reported as site policy source');

my $legacy = resolve_xcatd_tls_settings({ xcattlspolicy => 'legacy' });
is($legacy->{policy}, 'legacy', 'legacy policy is accepted');
is($legacy->{ssl_version}, LEGACY_TLS_VERSION, 'legacy policy resolves to TLS 1.0 era compatibility');

my $override = resolve_xcatd_tls_settings({ xcattlspolicy => 'modern', xcatsslversion => ' TLSv12 ' });
is($override->{policy}, 'override', 'xcatsslversion remains an administrator override');
is($override->{ssl_version}, 'TLSv12', 'xcatsslversion override is trimmed and preserved');

my $invalid = resolve_xcatd_tls_settings({ xcattlspolicy => 'bogus' });
is($invalid->{policy}, 'modern', 'invalid policy falls back to modern');
is($invalid->{ssl_version}, MODERN_TLS_VERSION, 'invalid policy does not weaken TLS defaults');

my @bad_policy = tls_setting_warnings({ xcattlspolicy => 'bogus' });
like($bad_policy[0], qr/Unsupported site\.xcattlspolicy/, 'invalid policy produces a warning');

my @old_protocol = tls_setting_warnings({ xcatsslversion => 'TLSv1' });
like($old_protocol[0], qr/deprecated protocols/, 'explicit TLSv1 override produces a warning');

my @flexible_legacy = tls_setting_warnings({ xcatsslversion => 'SSLv23:!SSLv2:!SSLv3' });
like($flexible_legacy[0], qr/deprecated protocols/, 'flexible override that allows TLSv1 produces a warning');

my @flexible_ssl = tls_setting_warnings({ xcatsslversion => 'SSLv23:!TLSv1:!TLSv1_1' });
like($flexible_ssl[0], qr/deprecated protocols/, 'flexible override that allows SSLv2 or SSLv3 produces a warning');

my @modern_override = tls_setting_warnings({ xcatsslversion => 'SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1' });
is(scalar @modern_override, 0, 'modern explicit override does not warn');

my @modern_override_tlsv11 = tls_setting_warnings({ xcatsslversion => 'SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv11' });
is(scalar @modern_override_tlsv11, 0, 'modern explicit override accepts TLSv11 spelling');

my @old_cipher = tls_setting_warnings({ xcatsslciphers => '3DES' });
like($old_cipher[0], qr/legacy cipher/, 'legacy cipher selector produces a warning');

my @compound_old_cipher = tls_setting_warnings({ xcatsslciphers => 'ALL:!ADH:RC4+RSA:+HIGH' });
like($compound_old_cipher[0], qr/legacy cipher/, 'compound legacy cipher selector produces a warning');

my @openssl_3des_cipher = tls_setting_warnings({ xcatsslciphers => 'ECDHE-RSA-DES-CBC3-SHA' });
like($openssl_3des_cipher[0], qr/legacy cipher/, 'OpenSSL 3DES cipher name produces a warning');

my @disabled_old_cipher = tls_setting_warnings({ xcatsslciphers => 'HIGH:!RC4:!3DES:!LOW:!EXP:!EXPORT' });
is(scalar @disabled_old_cipher, 0, 'disabled legacy cipher selectors do not warn');

done_testing();
