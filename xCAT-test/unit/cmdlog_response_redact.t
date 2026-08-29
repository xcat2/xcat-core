#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);
use xCAT::xcatd;

my $xcatd = repo_path('xCAT-server/sbin/xcatd');
plan skip_all => 'xcatd not found' unless -r $xcatd;

my $cmdlog_module = repo_path('xCAT-server/lib/perl/xCAT/CmdLog.pm');
require xCAT::CmdLog if -r $cmdlog_module;

my $src = slurp_repo_file('xCAT-server/sbin/xcatd');

# Extract the three command-log response subs and load them. xcatd is present,
# so a sub that cannot be extracted is a hard failure, not a skip.
my %sub;
for my $name (qw(cmdlog_response_is_sensitive cmdlog_finalize_response cmdlog_collectlog)) {
    my ($body) = $src =~ /(^sub \Q$name\E\b.*?^\})/ms;
    BAIL_OUT("could not extract $name from xcatd") unless $body;
    $body =~ s/^sub \Q$name\E\(\)/sub $name/m;
    $sub{$name} = $body;
}

our $cmdlog_alllog;
our $cmdlog_response_buffer;
our $cmdlog_response_sensitive;
our $MYXCATSERVER = "";
{
    no strict;
    no warnings;
    eval "$sub{cmdlog_response_is_sensitive}\n$sub{cmdlog_finalize_response}\n$sub{cmdlog_collectlog}";
}
die "eval of command-log subs failed: $@" if $@;

# Classification from the request.
ok(cmdlog_response_is_sensitive({ command => ['getcredentials'], arg => [] }, ''),
    'getcredentials is a sensitive-response command');
ok(cmdlog_response_is_sensitive({ command => ['lsvm'], arg => [] }, 0),
    'lsvm returns the directory entry with its passwords, so it is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['gettab'], arg => ['key=xcat', 'passwd.password'] }, ''),
    'gettab of a passwd column is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['tabdump'], arg => ['passwd'] }, ''),
    'tabdump passwd is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['rspconfig'], arg => [] }, 1),
    'a redacted request is sensitive');
ok(!cmdlog_response_is_sensitive({ command => ['rpower'], arg => ['n1', 'stat'] }, 0),
    'a benign request is not sensitive');

# A secret attribute with no "passw" in its name must classify through the
# shared secret set, not the text heuristic.
ok(cmdlog_response_is_sensitive({ command => ['gettab'], arg => ['node=pdu01', 'pdu.authkey'] }, 0),
    'gettab of an authentication key is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['gettab'], arg => ['node=pdu01', 'pdu.privkey'] }, 0),
    'gettab of a privacy key is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['gettab'], arg => ['key=snmpc', 'site.value'] }, 0),
    'gettab of the snmpc site value is sensitive');
ok(!cmdlog_response_is_sensitive({ command => ['gettab'], arg => ['key=domain', 'site.value'] }, 0),
    'gettab of a plain site value is not sensitive');

# A dump of a whole table that owns a secret column returns the bare values.
ok(cmdlog_response_is_sensitive({ command => ['tabdump'], arg => ['token'] }, 0),
    'tabdump of the token table is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['tabdump'], arg => ['prodkey'] }, 0),
    'tabdump of the prodkey table is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['tabdump'], arg => ['site'] }, 0),
    'tabdump of the site table is sensitive');
ok(cmdlog_response_is_sensitive({ command => ['tabdump'], arg => ['-w', 'key==snmpc', 'site'] }, 0),
    'a filtered site dump is sensitive');
ok(!cmdlog_response_is_sensitive({ command => ['tabdump'], arg => ['networks'] }, 0),
    'tabdump of the networks table is not sensitive');
ok(cmdlog_response_is_sensitive({ command => ['nodels'], noderange => ['node01'], arg => ['prodkey'] }, 0),
    'nodels of a whole secret table is sensitive');
ok(!cmdlog_response_is_sensitive({ command => ['nodels'], noderange => ['switches'], arg => [] }, 0),
    'a group named like a secret table is not sensitive');
ok(!cmdlog_response_is_sensitive({ command => ['nodels'], noderange => ['node01'], arg => ['nodetype'] }, 0),
    'nodels of a benign table is not sensitive');

# Drive collect(s) then finalize, returning what was appended to the log.
sub run {
    my ($sensitive, @responses) = @_;
    $cmdlog_alllog = "";
    $cmdlog_response_buffer = "";
    $cmdlog_response_sensitive = $sensitive;
    cmdlog_collectlog({ xcatresponse => [ { data => [$_] } ] }) for @responses;
    cmdlog_finalize_response();
    return $cmdlog_alllog;
}

# A bare passwd value (gettab passwd.password) has no "passw" in the response,
# so only the request classification catches it.
my $bare = run(1, "S3cr3tPW");
unlike($bare, qr/S3cr3tPW/, 'a bare passwd value is not logged');
like($bare, qr/\*REDACTED\*/, 'a sensitive response is redacted');

# A secret split across callbacks is redacted regardless of order.
unlike(run(0, "password", "S3cr3tPW"), qr/S3cr3tPW/,
    'multi-callback, passw first: the secret fragment is not logged');
unlike(run(0, "S3cr3tPW", "password"), qr/S3cr3tPW/,
    'multi-callback, secret first: the earlier fragment is redacted too');

# Fallback: a response mentioning a password is redacted even without request signal.
like(run(0, "invalid password for node"), qr/\*REDACTED\*/,
    'a response mentioning a password is redacted by the fallback');

# A benign response is logged verbatim.
my $benign = run(0, "node01: on");
like($benign, qr/node01: on/, 'a benign response is logged verbatim');
unlike($benign, qr/\*REDACTED\*/, 'a benign response is not redacted');

# A detailed object listing expands attributes the request never named.
my $lsdef = run(0, 'Object name: pdu01', '    authkey=AUTH_SECRET', '    privkey=PRIV_SECRET');
unlike($lsdef, qr/AUTH_SECRET|PRIV_SECRET/, 'implicit lsdef secrets are not logged');
like($lsdef, qr/\*REDACTED\*/, 'lsdef response containing secret attributes is redacted');
my $colon = run(0, 'node01: prodkey.key: AAAAA-BBBBB');
unlike($colon, qr/AAAAA/, 'a colon separated secret column is redacted');
my $plain = run(0, 'Object name: node01', '    groups=compute', '    mgt=ipmi');
unlike($plain, qr/\*REDACTED\*/, 'a benign object listing is not redacted');

# Two requests on one connection: the finalizer runs at the next command's
# start. The earlier response must be preserved (redacted), the flag reset, and
# the next benign response neither lost nor over-redacted.
$cmdlog_alllog = "";
$cmdlog_response_buffer = "";
$cmdlog_response_sensitive = 1;
cmdlog_collectlog({ xcatresponse => [ { data => ["SECRET_N"] } ] });
cmdlog_finalize_response();
is($cmdlog_response_sensitive, 0, 'finalize clears the sensitive flag');
cmdlog_collectlog({ xcatresponse => [ { data => ["benign_np1"] } ] });
cmdlog_finalize_response();
like($cmdlog_alllog, qr/\*REDACTED\*/, 'the earlier sensitive response is preserved as redacted, not lost');
like($cmdlog_alllog, qr/benign_np1/, 'the next benign response is logged, not over-redacted');
unlike($cmdlog_alllog, qr/SECRET_N/, 'the earlier secret is not leaked');

done_testing();
