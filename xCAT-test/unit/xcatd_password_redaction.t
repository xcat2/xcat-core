#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Capture::Tiny qw(capture);
use JSON::PP qw(encode_json decode_json);
use Storable qw(dclone);
use Test::More;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::File qw(repo_path);

use lib repo_path('perl-xCAT'), repo_path('xCAT-server/lib/perl');
use lib repo_path('xCAT-test/unit/fixtures/redaction');
use RedactionDependencies;

local $ENV{XCATROOT} = repo_path('xCAT-test/unit/fixtures/redaction');
require xCAT::Schema;
require xCAT::xcatd;
our %XCATSITEVALS;

sub arg { return xCAT::xcatd->redact_password_arg($_[0]); }
sub cmd { return xCAT::xcatd::redact_password($_[0], $_[1]); }

sub vec_ {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ( $command, @args ) = @_;
    my ( $redacted, $changed ) =
      xCAT::xcatd->redact_password_args( $command, \@args );
    is( scalar(@$redacted), scalar(@args), 'redaction preserves the argument count' );
    return ( join( ' ', @$redacted ), $changed );
}

# A secret in an attribute assignment must never survive, however it was written.
is( arg('bmcpassword=SEKRET'),        'bmcpassword=xxxxxxxx',     'a bare attribute value is redacted' );
is( arg('bmcpassword=SEKRET phrase'), 'bmcpassword=xxxxxxxx',     'a value with spaces is redacted whole' );
is( arg("bmcpassword=has'quote"),     'bmcpassword=xxxxxxxx',     'a value with a quote is redacted whole' );
is( arg('passwd.password+=SEKRET'),  'passwd.password+=xxxxxxxx', 'a += splice assignment is redacted' );
is( arg('pdu.community=SEKRET'),     'pdu.community=xxxxxxxx',   'the SNMP community string is redacted' );
is( arg('community=SEKRET'),         'community=xxxxxxxx',       'a bare community value is redacted' );

# The chdef/mkdef parser trims whitespace around '=', so an attribute may be
# written with spaces. The value must still be redacted.
is( arg('bmcpassword = SEKRET'),        'bmcpassword=xxxxxxxx', 'spaces around the equals are redacted' );
is( arg('bmcpassword =SEKRET'),         'bmcpassword=xxxxxxxx', 'a space before the equals is redacted' );
is( arg('bmcpassword= SEKRET'),         'bmcpassword=xxxxxxxx', 'a space after the equals is redacted' );
is( arg('bmcpassword = SEKRET phrase'), 'bmcpassword=xxxxxxxx', 'spaces around the equals with a multi-word value are redacted whole' );

# nodech and node selection accept operators other than a bare '='.
is( arg('ipmi.password,=SEKRET'), 'ipmi.password,=xxxxxxxx', 'a ,= append assignment is redacted' );
is( arg('ipmi.password^=SEKRET'), 'ipmi.password^=xxxxxxxx', 'a ^= remove assignment is redacted' );
is( arg('ipmi.password!=SEKRET'), 'ipmi.password!=xxxxxxxx', 'a != selection is redacted' );
is( arg('ipmi.password!~SEKRET'), 'ipmi.password!~xxxxxxxx', 'a !~ selection is redacted' );
is( arg('ipmi.password=~SEKRET'), 'ipmi.password=~xxxxxxxx', 'a =~ selection is redacted' );

# Non-secret detail stays, or the log stops being useful.
is( arg('groups=lab'),                'groups=lab',                'an unrelated attribute is kept' );
is( arg('key=system'),                'key=system',                'key is kept, it is not a secret' );
is( arg('sshkeydir=/etc/xcat/keys'),  'sshkeydir=/etc/xcat/keys',  'sshkeydir is kept, it is a directory' );
is( arg('n1'),                        'n1',                        'a plain argument is kept' );

# The command-flag mechanism still redacts positional password flags.
is( cmd( 'bmcdiscover', ' -s nmap -p SEKRET --range 10.0.0.1' ), ' -s nmap -p xxxxxxxx --range 10.0.0.1',
    'a -p flag value is redacted' );

# An assignment embedded in a compound argument, for example an xdsh remote
# command string, must be masked to the end of the argument, because a shell
# value may hold quotes and spaces.
is( cmd( 'xdsh', " compute 'echo bmcpassword=SEKRET > /etc/x'" ), " compute 'echo bmcpassword=xxxxxxxx",
    'a secret embedded in a compound argument is redacted' );
is( cmd( 'xdsh', q{ compute "export password='SEKRET phrase'; run-app"} ), ' compute "export password=xxxxxxxx',
    'a quoted secret embedded in a compound argument is redacted whole' );
is( arg(q{export password='SEKRET phrase'; run-app}), 'export password=xxxxxxxx',
    'a quoted secret inside one argument is redacted to the end' );
is( arg('usercomment=password=SEKRET'), 'usercomment=password=xxxxxxxx',
    'a secret glued to a prior assignment is redacted' );
is( arg('echo groups=lab; ls'), 'echo groups=lab; ls', 'an embedded non-secret assignment is kept' );

# A password given through a command option must be redacted in every form
# Getopt::Long accepts: a separate argument, a compact short option, a long
# option, and a long option with an equals sign.
my ( $out, $changed );
( $out, $changed ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-p', 'SEKRET phrase' );
is( $out, '--range 10.0.0.1 -p xxxxxxxx', 'a -p value in the next argument is redacted whole' );
is( $changed, 1, 'the option redaction reports the change' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-pSEKRET' );
is( $out, '--range 10.0.0.1 -pxxxxxxxx', 'a compact -pSEKRET is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcpasswd', 'SEKRET' );
is( $out, '--range 10.0.0.1 --bmcpasswd xxxxxxxx', 'a --bmcpasswd value in the next argument is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcpasswd=SEKRET' );
is( $out, '--range 10.0.0.1 --bmcpasswd=xxxxxxxx', 'a --bmcpasswd=value is redacted' );
( $out ) = vec_( 'bmcdiscover', '-n', 'SEKRET' );
is( $out, '-n xxxxxxxx', 'a -n new password is redacted' );
( $out ) = vec_( 'bmcdiscover', '--newbmcpw', 'SEKRET' );
is( $out, '--newbmcpw xxxxxxxx', 'the full --newbmcpw name is kept and its value is masked' );
( $out ) = vec_( 'mkvm', 'zvm02', '-password', 'SEKRET' );
is( $out, 'zvm02 -password xxxxxxxx', 'a single-dash long -password keeps its name and masks its value' );
( $out ) = vec_( 'switchdiscover', '--range', '10.0.0.0/24', '-c', 'SEKRET' );
is( $out, '--range 10.0.0.0/24 -c xxxxxxxx', 'the switchdiscover -c community is redacted' );
( $out ) = vec_( 'mkhwconn', 'frame', '-p', 'hmc01', '-PSEKRET' );
is( $out, 'frame -p hmc01 -Pxxxxxxxx', 'the mkhwconn -P password is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '--password', 'SEKRET' );
is( $out, 'zvm02 --password xxxxxxxx', 'the mkvm --password value is redacted' );
( $out ) = vec_( 'rspconfig', 'admin_passwd=SEKRET phrase' );
is( $out, 'admin_passwd=xxxxxxxx', 'a rspconfig password assignment is redacted whole' );
( $out ) = vec_( 'chdef', 'groups=compute', 'bmcpassword=SEKRET' );
is( $out, 'groups=compute bmcpassword=xxxxxxxx', 'a secret attribute after a non-secret argument is redacted' );

# Getopt::Long also accepts an abbreviated long option, a bundle of short
# options, and, for parsers that keep the default configuration, any letter
# case. Each of those forms must redact too.
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcp', 'SEKRET' );
is( $out, '--range 10.0.0.1 --bmcp xxxxxxxx', 'an abbreviated --bmcp is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcpas=SEKRET' );
is( $out, '--range 10.0.0.1 --bmcpas=xxxxxxxx', 'an abbreviated --bmcpas=value is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-zp', 'SEKRET' );
is( $out, '--range 10.0.0.1 -zp xxxxxxxx', 'a bundled -zp is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-zpSEKRET' );
is( $out, '--range 10.0.0.1 -zpxxxxxxxx', 'a bundled compact -zpSEKRET is redacted' );
( $out ) = vec_( 'bmcdiscover', '-pApple' );
is( $out, '-pxxxxxxxx', 'a compact value keeps no leading letters' );
( $out ) = vec_( 'bmcdiscover', '-pAdmin', '--range', '10.0.0.1' );
is( $out, '-pxxxxxxxx --range 10.0.0.1', 'a compact value ending in a secret letter is masked, not the next argument' );
( $out ) = vec_( 'bmcdiscover', '-nstop', '--range', '10.0.0.1' );
is( $out, '-nxxxxxxxx --range 10.0.0.1', 'a compact -n value is masked whole' );
( $out ) = vec_( 'bmcdiscover', '-pbanana' );
is( $out, '-pxxxxxxxx', 'a compact value with a later secret letter is masked from the option' );
# bmcdiscover --p= and mkhwconn --P= currently omit '=' in the log.
( $out ) = vec_( 'bmcdiscover', '--p=SEKRET' );
is( $out, '--pxxxxxxxx', 'a double-dash --p=value is redacted' );
( $out ) = vec_( 'switchdiscover', '--c', 'SEKRET' );
is( $out, '--c xxxxxxxx', 'a double-dash --c community is redacted' );
( $out ) = vec_( 'mkhwconn', 'frame', '--P=SEKRET' );
is( $out, 'frame --Pxxxxxxxx', 'a double-dash --P=value is redacted' );
( $out, $changed ) = vec_( 'mkhwconn', 'frame', '--p', 'hmc01' );
is( $out, 'frame --p hmc01', 'the double-dash control point stays visible' );
is( $changed, 0, 'the double-dash --p control point is kept, the case differs' );
( $out ) = vec_( 'mkvm', 'zvm02', '--W', 'SEKRET' );
is( $out, 'zvm02 --W xxxxxxxx', 'a double-dash --W is redacted, the parser ignores case' );

# The vCenter cluster commands log in with a --password option.
( $out ) = vec_( 'createvcluster', '--vcenter', 'vc01', '--username', 'admin', '--password', 'SEKRET', 'cluster01' );
is( $out, '--vcenter vc01 --username admin --password xxxxxxxx cluster01', 'the createvcluster password is redacted' );
( $out ) = vec_( 'lsvcluster', '--vcenter', 'vc01', '--password=SEKRET' );
is( $out, '--vcenter vc01 --password=xxxxxxxx', 'the lsvcluster password is redacted' );
( $out ) = vec_( 'rmvcluster', '--vcenter', 'vc01', '--PASSWORD', 'SEKRET', 'cluster01' );
is( $out, '--vcenter vc01 --PASSWORD xxxxxxxx cluster01', 'the rmvcluster password is redacted, the parser ignores case' );

# In a bundle a non-secret option that takes a value absorbs the rest, so a
# secret letter inside that value must not redact.
( $out, $changed ) = vec_( 'bmcdiscover', '-snmap', '--range', '10.0.0.0/24' );
is( $out, '-snmap --range 10.0.0.0/24', 'the -snmap scan method is kept, n is the value of -s' );
is( $changed, 0, 'a non-secret compact value reports no change' );
( $out, $changed ) = vec_( 'bmcdiscover', '-sopenbmc' );
is( $out, '-sopenbmc', 'the -sopenbmc scan method is kept, p is inside the value' );
is( $changed, 0, 'the -sopenbmc value reports no change' );
( $out, $changed ) = vec_( 'mkhwconn', 'frame', '-pPOWERHMC' );
is( $out, 'frame -pPOWERHMC', 'the compact control point stays visible' );
is( $changed, 0, 'the mkhwconn -p value is kept, P is inside the value of -p' );
( $out, $changed ) = vec_( 'bmcdiscover', '-zsp', 'SEKRET' );
is( $out, '-zsp SEKRET', 'the scan method and non-secret positional argument stay visible' );
is( $changed, 0, 'a bundle stops at a value option, -zsp is the value p of -s' );
( $out ) = vec_( 'bmcdiscover', '-zps', 'topsecret' );
is( $out, '-zpxxxxxxxx topsecret', 'a bundle masks from the secret letter, the next argument is positional' );
( $out ) = vec_( 'bmcdiscover', '-?pSEKRET' );
is( $out, '-?pxxxxxxxx', 'a bundle with the ? help letter is redacted' );
( $out ) = vec_( 'bmcdiscover', '-?n', 'SEKRET' );
is( $out, '-?n xxxxxxxx', 'a -?n bundle masks the next argument' );
( $out, $changed ) = vec_( 'mkvm', 'lpar01', '-cpower10', '-pprofile1' );
is( $out, 'lpar01 -cpower10 -pprofile1', 'the mkvm compact values are kept, w is inside the value of -c' );
is( $changed, 0, 'the mkvm compact values report no change' );
( $out, $changed ) = vec_( 'mkvm', 'lpar01', '-p', 'profile1' );
is( $out, 'lpar01 -p profile1', 'the PPC mkvm profile remains visible' );
is( $changed, 0, 'the PPC mkvm profile reports no redaction' );

# In the z/VM grammar -s is a boolean and -c takes an integer, so a bundle can
# continue into the real password option.
( $out ) = vec_( 'mkvm', 'zvm02', '-swSEKRET' );
is( $out, 'zvm02 -swxxxxxxxx', 'zVM -s followed by bundled -w is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '-sw', 'SEKRET' );
is( $out, 'zvm02 -sw xxxxxxxx', 'zVM bundled -sw masks the next argument' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c1wSEKRET' );
is( $out, 'zvm02 -c1wxxxxxxxx', 'zVM resumes after the numeric -c value and redacts -w' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c1w', 'SEKRET' );
is( $out, 'zvm02 -c1w xxxxxxxx', 'zVM numeric bundle masks the following password argument' );
( $out, $changed ) = vec_( 'mkvm', 'zvm02', '-c12' );
is( $out, 'zvm02 -c12', 'the numeric cpu value stays visible' );
is( $changed, 0, 'a plain numeric cpu bundle is kept' );

# Bundled short options keep letter case, so a capital letter is unknown to
# the parser and the bundle continues into the password option.
( $out ) = vec_( 'mkvm', 'zvm02', '-Rw', 'SEKRET' );
is( $out, 'zvm02 -Rw xxxxxxxx', 'a capital -Rw bundle masks the next argument' );
( $out ) = vec_( 'mkvm', 'zvm02', '-RwSEKRET' );
is( $out, 'zvm02 -Rwxxxxxxxx', 'a glued capital -RwSEKRET is redacted' );

# A bundled integer value may carry a sign or underscores.
( $out ) = vec_( 'mkvm', 'zvm02', '-c+1w', 'SEKRET' );
is( $out, 'zvm02 -c+1w xxxxxxxx', 'a signed cpu value still reaches the password option' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c-1wSEKRET' );
is( $out, 'zvm02 -c-1wxxxxxxxx', 'a negative cpu value still reaches the password option' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c1_0w', 'SEKRET' );
is( $out, 'zvm02 -c1_0w xxxxxxxx', 'an underscored cpu value still reaches the password option' );
( $out, $changed ) = vec_( 'mkvm', 'zvm02', '-rabcw', 'KEEPME' );
is( $out, 'zvm02 -rabcw KEEPME', 'the non-secret value and following argument stay visible' );
is( $changed, 0, 'a lowercase -r value absorbs the rest of the bundle' );

# Getopt::Long compatibility mode also accepts "+" as an option starter.
( $out ) = vec_( 'bmcdiscover', '+p', 'SEKRET', '--range', '10.0.0.1' );
is( $out, '+p xxxxxxxx --range 10.0.0.1', 'a +p option is redacted' );
( $out ) = vec_( 'bmcdiscover', '+bmcpasswd=SEKRET' );
is( $out, '+bmcpasswd=xxxxxxxx', 'a +bmcpasswd=value is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '+w', 'SEKRET' );
is( $out, 'zvm02 +w xxxxxxxx', 'a +w option is redacted' );
( $out ) = vec_( 'switchdiscover', '--range', '10.0.0.0/24', '-xc', 'SEKRET' );
is( $out, '--range 10.0.0.0/24 -xc xxxxxxxx', 'a bundled -xc community is redacted' );
( $out ) = vec_( 'mkhwconn', 'frame', '-tP', 'SEKRET' );
is( $out, 'frame -tP xxxxxxxx', 'a bundled -tP password is redacted' );
( $out, $changed ) = vec_( 'mkhwconn', 'frame', '-p', 'hmc01' );
is( $out, 'frame -p hmc01', 'the mkhwconn -p stays visible, it is not the password' );
is( $changed, 0, 'the mkhwconn hardware control point reports no change' );
( $out ) = vec_( 'mkvm', 'zvm02', '-W', 'SEKRET' );
is( $out, 'zvm02 -W xxxxxxxx', 'the mkvm -W is redacted, the parser ignores case' );
( $out ) = vec_( 'mkvm', 'zvm02', '--PASSWORD=SEKRET' );
is( $out, 'zvm02 --PASSWORD=xxxxxxxx', 'the mkvm --PASSWORD=value is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '--Pass', 'SEKRET' );
is( $out, 'zvm02 --Pass xxxxxxxx', 'the mkvm abbreviated --Pass is redacted' );
( $out ) = vec_( 'mkvm', 'gpok4', 'gpok3', 'pool=POOL1', 'pw=SEKRET' );
is( $out, 'gpok4 gpok3 pool=POOL1 pw=xxxxxxxx', 'the mkvm clone pw= operand is redacted' );

# chvm carries passwords as positional operands.
( $out ) = vec_( 'chvm', '--setpassword', 'SEKRET' );
is( $out, '--setpassword xxxxxxxx', 'the chvm --setpassword operand is redacted' );
( $out ) = vec_( 'chvm', '--add3390', 'POOL1', '0101', '3g', 'MR', 'RSEKRET', 'WSEKRET', 'MSEKRET' );
is( $out, '--add3390 POOL1 0101 3g MR xxxxxxxx xxxxxxxx xxxxxxxx', 'the chvm --add3390 disk passwords are redacted' );
( $out ) = vec_( 'chvm', '--formatdisk', '0100', 'SEKRET' );
is( $out, '--formatdisk 0100 xxxxxxxx', 'the chvm --formatdisk password is redacted' );

# The site table stores the global SNMP community string under the snmpc key.
( $out ) = vec_( 'tabch', 'key=snmpc', 'site.value=SEKRET' );
is( $out, 'key=snmpc site.value=xxxxxxxx', 'a tabch of the snmpc site value is redacted' );
( $out ) = vec_( 'tabch', 'key=snmpc', 'site.value+=SEKRET' );
is( $out, 'key=snmpc site.value+=xxxxxxxx', 'a tabch += splice of the snmpc site value is redacted' );
( $out ) = vec_( 'tabch', 'key=snmpc,key=snmpc', 'site.value=SEKRET' );
is( $out, 'key=snmpc,key=snmpc site.value=xxxxxxxx', 'a compound tabch selector with snmpc is redacted' );
( $out ) = vec_( 'tabch', 'key=temporary', 'site.key=snmpc', 'site.value=SEKRET' );
is( $out, 'key=temporary site.key=snmpc site.value=xxxxxxxx', 'a site.key=snmpc assignment marks the value secret' );
( $out ) = vec_( 'tabch', 'site.key=snmpc', 'site.value=SEKRET' );
is( $out, 'site.key=snmpc site.value=xxxxxxxx', 'a table-qualified snmpc selector is redacted' );
( $out, $changed ) = vec_( 'tabch', 'key=domain', 'site.value=lab' );
is( $out, 'key=domain site.value=lab', 'a tabch of a plain site value is kept' );
is( $changed, 0, 'a benign vector reports no change' );
is( arg('snmpc=SEKRET'), 'snmpc=xxxxxxxx', 'the snmpc site attribute is redacted' );

# Product keys are license secrets.
is( arg('productkey=SEKRET'), 'productkey=xxxxxxxx', 'a product key is redacted' );
is( arg('prodkey.key=SEKRET'), 'prodkey.key=xxxxxxxx', 'a table-qualified product key is redacted' );

# The token table stores bearer credentials under tokenid.
is( arg('tokenid=SEKRET'), 'tokenid=xxxxxxxx', 'an authentication token is redacted' );
is( arg('token.tokenid=SEKRET'), 'token.tokenid=xxxxxxxx', 'a table-qualified token is redacted' );

my @pairs;
foreach my $object ( sort keys %xCAT::Schema::defspec ) {
    foreach my $definition ( @{ $xCAT::Schema::defspec{$object}->{attrs} || [] } ) {
        my ($attr, $tabentry) = @{$definition}{qw(attr_name tabentry)};
        next unless defined $attr && defined $tabentry;
        next unless $tabentry =~ /\.(password|passwd|authkey|privkey|adminpassword|sshpassword|community)$/i
          || $tabentry eq 'prodkey.key';
        push @pairs, [ $attr, $tabentry ];
    }
}
ok( scalar(@pairs) > 0, 'the loaded schema exposes secret-column mappings' );

foreach my $pair (@pairs) {
    my ( $attr, $column ) = @$pair;
    is( arg("$attr=SEKRET"), "$attr=xxxxxxxx", "$attr keeps its name and masks its value" );
    is( arg("$column=SEKRET"), "$column=xxxxxxxx", "$column keeps its name and masks its value" );
}

is(arg(undef), undef, 'an undefined argument stays undefined');
is(arg(''), '', 'an empty argument stays empty');
for my $args (undef, [], [undef, '']) {
    my ($masked, $changed) = xCAT::xcatd->redact_password_args('chdef', $args);
    is_deeply($masked, $args || [], 'missing and empty arguments stay unchanged');
    is($changed, 0, 'missing and empty arguments report no redaction');
}

my @requests = (
    ['chdef', ['bmcpassword=SEKRET phrase', 'groups=compute'],
        ' bmcpassword=xxxxxxxx groups=compute'],
    ['bmcdiscover', ['--bmcpasswd=SEKRET', '--range', '192.0.2.1'],
        ' --bmcpasswd=xxxxxxxx --range 192.0.2.1'],
    ['rspconfig', ['USERID=SEKRET', 'general=visible'],
        ' USERID=xxxxxxxx general=visible'],
    ['rspconfig', ['HMC_user=x admin_passwd=SEKRET'],
        ' HMC_user=x admin_passwd=xxxxxxxx'],
    ['mkvm', ['zvm02', '--password', 'SEKRET'],
        ' zvm02 --password ******** '],
    ['mkvm', ['zvm02', '-w', 'SEKRET'],
        ' zvm02 -w ******** '],
    ['tabch', ['key=snmpc', 'site.value=SEKRET'],
        ' key=snmpc site.value=xxxxxxxx'],
    ['chdef', ['groups=compute', 'usercomment=visible'],
        ' groups=compute usercomment=visible'],
);

for my $rule ('allow', 'deny') {
    for my $sink ('SA', 'A', 'S') {
        for my $case (@requests) {
            my ($command, $args, $expected) = @$case;
            subtest "$rule $command to $sink: @$args" => sub {
                local $xCAT::Table::rule = $rule;
                local %XCATSITEVALS = $sink eq 'A' ? (auditnosyslog => 1)
                  : $sink eq 'S' ? (auditskipcmds => 'ALL') : ();
                my $request = {
                    command => [$command], arg => dclone($args),
                    node => ['node01'], username => ['operator'], clienttype => ['cli'],
                };
                my @deferred;
                my $allowed = xCAT::xcatd->validate(
                    'operator', 'client.example', $request, undef, \@deferred,
                );
                is($allowed, $rule eq 'allow' ? 1 : 0, 'policy result is preserved');
                is($deferred[0], $sink, 'the configured logging sinks are selected');
                my $status = $rule eq 'allow' ? 'Allowing' : 'Denying';
                my $syslog = "xCAT: $status $command to node01$expected for operator from client.example";
                if ($sink eq 'S') {
                    is($deferred[1], $syslog, 'syslog-only output masks secrets and keeps context');
                } else {
                    is($deferred[1]->{args}->[0], $expected, 'audit arguments mask secrets and keep context');
                    if ($sink eq 'SA') {
                        is($deferred[1]->{syslogdata}->[0], $syslog, 'syslog has the same masked arguments');
                    } else {
                        ok(!exists $deferred[1]->{syslogdata}, 'audit-only output omits syslog');
                    }
                }
                is_deeply($request->{arg}, $args, 'logging leaves execution arguments intact');
            };
        }
    }
}

my @traces = (
    ['password assignment', {command => ['rspconfig'], noderange => ['node01', 'node02'],
        arg => ['admin_passwd=SEKRET phrase', 'general=visible']},
        'rspconfig node01,node02 admin_passwd=xxxxxxxx general=visible'],
    ['bundled option', {command => ['bmcdiscover'], arg => ['-zpSEKRET', '--range', '192.0.2.1']},
        'bmcdiscover -zpxxxxxxxx --range 192.0.2.1'],
    ['nonsecret argument', {command => ['chdef'], arg => ['groups=compute']}, 'chdef groups=compute'],
    ['empty argument vector', {command => ['lsdef'], arg => []}, 'lsdef'],
    ['missing argument vector', {command => ['lsdef']}, 'lsdef '],
);
for my $case (@traces) {
    my ($name, $request, $expected) = @$case;
    subtest "dispatch trace: $name" => sub {
        local $ENV{XCATROOT} = repo_path('xCAT-test/unit/fixtures/redaction');
        local $ENV{ENABLE_TRACE_CODE};
        delete $ENV{ENABLE_TRACE_CODE};
        my ($stdout, $stderr, $status) = capture {
            system($^X, '-I', repo_path('perl-xCAT'),
                '-I', repo_path('xCAT-server/lib/perl'),
                '-I', repo_path('xCAT-test/unit/fixtures/redaction'),
                '-MDispatchTrace', repo_path('xCAT-server/sbin/xcatd'), encode_json($request));
        };
        is($status, 0, 'the real daemon reaches the trace sink') or diag($stderr);
        is($stderr, '', 'the trace emits no warnings');
        return unless $status == 0;
        my $result = decode_json($stdout);
        is_deeply($result->{trace}, ['xCAT::MsgUtils', 0, 'D',
            "xcatd: dispatch request '$expected' to plugin 'testplugin'"],
            'the dispatch trace masks secrets and keeps command context');
        is_deeply($result->{request}, $request, 'tracing leaves the request intact');
    };
}

done_testing();
