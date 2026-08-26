#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use xCAT::xcatd;
use xCAT::CmdLog;

ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['getcredentials'], arg => [] }, ''),
    'getcredentials is a sensitive-response command');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['lsvm'], arg => [] }, 0),
    'lsvm returns the directory entry with its passwords, so it is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['gettab'], arg => ['key=xcat', 'passwd.password'] }, ''),
    'gettab of a passwd column is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['tabdump'], arg => ['passwd'] }, ''),
    'tabdump passwd is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['rspconfig'], arg => [] }, 1),
    'a redacted request is sensitive');
ok(!xCAT::CmdLog::response_is_sensitive(
        { command => ['rpower'], arg => ['n1', 'stat'] }, 0),
    'a benign request is not sensitive');

# A secret attribute with no "passw" in its name must classify through the
# shared secret set, not the text heuristic.
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['gettab'], arg => ['node=pdu01', 'pdu.authkey'] }, 0),
    'gettab of an authentication key is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['gettab'], arg => ['node=pdu01', 'pdu.privkey'] }, 0),
    'gettab of a privacy key is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['gettab'], arg => ['key=snmpc', 'site.value'] }, 0),
    'gettab of the snmpc site value is sensitive');
ok(!xCAT::CmdLog::response_is_sensitive(
        { command => ['gettab'], arg => ['key=domain', 'site.value'] }, 0),
    'gettab of a plain site value is not sensitive');

# A dump of a whole table that owns a secret column returns the bare values.
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['tabdump'], arg => ['token'] }, 0),
    'tabdump of the token table is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['tabdump'], arg => ['prodkey'] }, 0),
    'tabdump of the prodkey table is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['tabdump'], arg => ['site'] }, 0),
    'tabdump of the site table is sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['tabdump'], arg => ['-w', 'key==snmpc', 'site'] }, 0),
    'a filtered site dump is sensitive');
ok(!xCAT::CmdLog::response_is_sensitive(
        { command => ['tabdump'], arg => ['networks'] }, 0),
    'tabdump of the networks table is not sensitive');
ok(xCAT::CmdLog::response_is_sensitive(
        { command => ['nodels'], noderange => ['node01'], arg => ['prodkey'] }, 0),
    'nodels of a whole secret table is sensitive');
ok(!xCAT::CmdLog::response_is_sensitive(
        { command => ['nodels'], noderange => ['switches'], arg => [] }, 0),
    'a group named like a secret table is not sensitive');
ok(!xCAT::CmdLog::response_is_sensitive(
        { command => ['nodels'], noderange => ['node01'], arg => ['nodetype'] }, 0),
    'nodels of a benign table is not sensitive');

sub run {
    my ($sensitive, @responses) = @_;
    my $buffer = '';
    $buffer .= xCAT::CmdLog::format_response(
        { xcatresponse => [ { data => [$_] } ] },
        '',
    ) for @responses;
    return xCAT::CmdLog::finalize_response($buffer, $sensitive);
}

my $bare = run(1, 'S3cr3tPW');
unlike($bare, qr/S3cr3tPW/, 'a bare passwd value is not logged');
like($bare, qr/\*REDACTED\*/, 'a sensitive response is redacted');

unlike(run(0, 'password', 'S3cr3tPW'), qr/S3cr3tPW/,
    'multi-callback, passw first: the secret fragment is not logged');
unlike(run(0, 'S3cr3tPW', 'password'), qr/S3cr3tPW/,
    'multi-callback, secret first: the earlier fragment is redacted too');
like(run(0, 'invalid password for node'), qr/\*REDACTED\*/,
    'a response mentioning a password is redacted by the fallback');

my $benign = run(0, 'node01: on');
like($benign, qr/node01: on/, 'a benign response is logged verbatim');
unlike($benign, qr/\*REDACTED\*/, 'a benign response is not redacted');

my $lsdef = run(0, 'Object name: pdu01', '    authkey=AUTH_SECRET', '    privkey=PRIV_SECRET');
unlike($lsdef, qr/AUTH_SECRET|PRIV_SECRET/, 'implicit lsdef secrets are not logged');
like($lsdef, qr/\*REDACTED\*/, 'lsdef response containing secret attributes is redacted');
my $colon = run(0, 'node01: prodkey.key: AAAAA-BBBBB');
unlike($colon, qr/AAAAA/, 'a colon separated secret column is redacted');
my $plain = run(0, 'Object name: node01', '    groups=compute', '    mgt=ipmi');
unlike($plain, qr/\*REDACTED\*/, 'a benign object listing is not redacted');

my $first = run(1, 'SECRET_N');
my $second = run(0, 'benign_np1');
like($first, qr/\*REDACTED\*/, 'a sensitive response is preserved as redacted');
unlike($first, qr/SECRET_N/, 'the sensitive response does not leak');
like($second, qr/benign_np1/, 'the next benign response is not over-redacted');

is(
    xCAT::CmdLog::format_response(
        { xcatresponse => [ { serverdone => [1] } ] },
        'management',
    ),
    '',
    'a terminal serverdone response does not add log text',
);

is(
    xCAT::CmdLog::format_response(
        {
            xcatresponse => [ {
                xcatdsource => ['service'],
                error       => ['failed'],
                warning     => ['careful'],
                info        => ['working'],
                sinfo       => ['progress'],
                node        => [ {
                    name => ['node01'],
                    data => ['on'],
                } ],
            } ],
        },
        'management',
    ),
    "Error: [service]: failed\n"
      . "Warning: [service]: careful\n"
      . "[service]: working\n"
      . "progress node01: [service]: on\n",
    'response formatting preserves source, severity, progress, and node data',
);

done_testing();
