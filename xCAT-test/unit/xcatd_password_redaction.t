#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $xcatd  = File::Spec->catfile( $repo_root, 'xCAT-server/lib/perl/xCAT/xcatd.pm' );
my $daemon = File::Spec->catfile( $repo_root, 'xCAT-server/sbin/xcatd' );
my $schema = File::Spec->catfile( $repo_root, 'perl-xCAT/xCAT/Schema.pm' );

plan skip_all => 'xcatd.pm, xcatd or Schema.pm not found' unless -r $xcatd && -r $daemon && -r $schema;

sub slurp {
    open( my $fh, '<', $_[0] ) or die "Unable to read $_[0]: $!";
    my $c = do { local $/; <$fh> };
    close($fh);
    return $c;
}

my $source        = slurp($xcatd);
my $daemon_source = slurp($daemon);
my $schema_source = slurp($schema);

# xcatd.pm cannot be loaded here (dependencies), so lift out the secret set, the
# command maps, and the redaction routines and evaluate them alone.
my ($set)      = $source =~ /(my \@secret_attributes = qw\(.*?\);\s*my %secret_attribute = map.*?;)/s;
my ($maps)     = $source =~ /(my %secret_command_options = \(.*?my %secret_site_keys = map.*?;)/s;
my ($arg_sub)  = $source =~ /(sub redact_password_arg \{.*?\n\}\n)/s;
my ($args_sub) = $source =~ /(sub redact_password_args \{.*?\n\}\n)/s;
my ($cmd_sub)  = $source =~ /(sub redact_password \{.*?\n\}\n)/s;
BAIL_OUT('could not extract the secret set from xcatd.pm')       unless $set;
BAIL_OUT('could not extract the command maps from xcatd.pm')     unless $maps;
BAIL_OUT('could not extract redact_password_arg from xcatd.pm')  unless $arg_sub;
BAIL_OUT('could not extract redact_password_args from xcatd.pm') unless $args_sub;
BAIL_OUT('could not extract redact_password from xcatd.pm')      unless $cmd_sub;
eval "package RedactUnderTest; $set $maps $arg_sub $args_sub $cmd_sub 1;"
  or BAIL_OUT("could not evaluate the redaction routines: $@");

sub arg { return RedactUnderTest::redact_password_arg( 'xCAT::xcatd', $_[0] ); }
sub cmd { return RedactUnderTest::redact_password( $_[0], $_[1] ); }

sub vec_ {
    my ( $command, @args ) = @_;
    my ( $redacted, $changed ) =
      RedactUnderTest->redact_password_args( $command, \@args );
    return ( join( ' ', @$redacted ), $changed );
}

# A secret in an attribute assignment must never survive, however it was written.
unlike( arg('bmcpassword=SEKRET'),        qr/SEKRET/,        'a bare attribute value is redacted' );
unlike( arg('bmcpassword=SEKRET phrase'), qr/SEKRET|phrase/, 'a value with spaces is redacted whole' );
unlike( arg("bmcpassword=has'quote"),     qr/quote/,         'a value with a quote is redacted whole' );
unlike( arg('passwd.password+=SEKRET'),   qr/SEKRET/,        'a += splice assignment is redacted' );
unlike( arg('pdu.community=SEKRET'),      qr/SEKRET/,        'the SNMP community string is redacted' );
unlike( arg('community=SEKRET'),          qr/SEKRET/,        'a bare community value is redacted' );

# The chdef/mkdef parser trims whitespace around '=', so an attribute may be
# written with spaces. The value must still be redacted.
unlike( arg('bmcpassword = SEKRET'),        qr/SEKRET/,        'spaces around the equals are redacted' );
unlike( arg('bmcpassword =SEKRET'),         qr/SEKRET/,        'a space before the equals is redacted' );
unlike( arg('bmcpassword= SEKRET'),         qr/SEKRET/,        'a space after the equals is redacted' );
unlike( arg('bmcpassword = SEKRET phrase'), qr/SEKRET|phrase/, 'spaces around the equals with a multi-word value are redacted whole' );

# nodech and node selection accept operators other than a bare '='.
unlike( arg('ipmi.password,=SEKRET'), qr/SEKRET/, 'a ,= append assignment is redacted' );
unlike( arg('ipmi.password^=SEKRET'), qr/SEKRET/, 'a ^= remove assignment is redacted' );
unlike( arg('ipmi.password!=SEKRET'), qr/SEKRET/, 'a != selection is redacted' );
unlike( arg('ipmi.password!~SEKRET'), qr/SEKRET/, 'a !~ selection is redacted' );
unlike( arg('ipmi.password=~SEKRET'), qr/SEKRET/, 'a =~ selection is redacted' );

# Non-secret detail stays, or the log stops being useful.
is( arg('groups=lab'),                'groups=lab',                'an unrelated attribute is kept' );
is( arg('key=system'),                'key=system',                'key is kept, it is not a secret' );
is( arg('sshkeydir=/etc/xcat/keys'),  'sshkeydir=/etc/xcat/keys',  'sshkeydir is kept, it is a directory' );
is( arg('n1'),                        'n1',                        'a plain argument is kept' );

# The command-flag mechanism still redacts positional password flags.
unlike( cmd( 'bmcdiscover', ' -s nmap -p SEKRET --range 10.0.0.1' ), qr/SEKRET/,
    'a -p flag value is redacted' );

# An assignment embedded in a compound argument, for example an xdsh remote
# command string, must be masked to the end of the argument, because a shell
# value may hold quotes and spaces.
unlike( cmd( 'xdsh', " compute 'echo bmcpassword=SEKRET > /etc/x'" ), qr/SEKRET/,
    'a secret embedded in a compound argument is redacted' );
unlike( cmd( 'xdsh', q{ compute "export password='SEKRET phrase'; run-app"} ), qr/SEKRET|phrase/,
    'a quoted secret embedded in a compound argument is redacted whole' );
unlike( arg(q{export password='SEKRET phrase'; run-app}), qr/SEKRET|phrase/,
    'a quoted secret inside one argument is redacted to the end' );
unlike( arg('usercomment=password=SEKRET'), qr/SEKRET/,
    'a secret glued to a prior assignment is redacted' );
is( arg('echo groups=lab; ls'), 'echo groups=lab; ls', 'an embedded non-secret assignment is kept' );

# A password given through a command option must be redacted in every form
# Getopt::Long accepts: a separate argument, a compact short option, a long
# option, and a long option with an equals sign.
my ( $out, $changed );
( $out, $changed ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-p', 'SEKRET phrase' );
unlike( $out, qr/SEKRET|phrase/, 'a -p value in the next argument is redacted whole' );
is( $changed, 1, 'the option redaction reports the change' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-pSEKRET' );
unlike( $out, qr/SEKRET/, 'a compact -pSEKRET is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcpasswd', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a --bmcpasswd value in the next argument is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcpasswd=SEKRET' );
unlike( $out, qr/SEKRET/, 'a --bmcpasswd=value is redacted' );
( $out ) = vec_( 'bmcdiscover', '-n', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a -n new password is redacted' );
( $out ) = vec_( 'bmcdiscover', '--newbmcpw', 'SEKRET' );
is( $out, '--newbmcpw xxxxxxxx', 'the full --newbmcpw name is kept and its value is masked' );
( $out ) = vec_( 'mkvm', 'zvm02', '-password', 'SEKRET' );
is( $out, 'zvm02 -password xxxxxxxx', 'a single-dash long -password keeps its name and masks its value' );
( $out ) = vec_( 'switchdiscover', '--range', '10.0.0.0/24', '-c', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'the switchdiscover -c community is redacted' );
( $out ) = vec_( 'mkhwconn', 'frame', '-p', 'hmc01', '-PSEKRET' );
unlike( $out, qr/SEKRET/, 'the mkhwconn -P password is redacted' );
like( $out, qr/-p hmc01/, 'the mkhwconn -p hardware control point is kept' );
( $out ) = vec_( 'mkvm', 'zvm02', '--password', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'the mkvm --password value is redacted' );
( $out ) = vec_( 'rspconfig', 'admin_passwd=SEKRET phrase' );
unlike( $out, qr/SEKRET|phrase/, 'a rspconfig password assignment is redacted whole' );

# Getopt::Long also accepts an abbreviated long option, a bundle of short
# options, and, for parsers that keep the default configuration, any letter
# case. Each of those forms must redact too.
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcp', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'an abbreviated --bmcp is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '--bmcpas=SEKRET' );
unlike( $out, qr/SEKRET/, 'an abbreviated --bmcpas=value is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-zp', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a bundled -zp is redacted' );
( $out ) = vec_( 'bmcdiscover', '--range', '10.0.0.1', '-zpSEKRET' );
unlike( $out, qr/SEKRET/, 'a bundled compact -zpSEKRET is redacted' );
( $out ) = vec_( 'bmcdiscover', '-pApple' );
is( $out, '-pxxxxxxxx', 'a compact value keeps no leading letters' );
( $out ) = vec_( 'bmcdiscover', '-pAdmin', '--range', '10.0.0.1' );
is( $out, '-pxxxxxxxx --range 10.0.0.1', 'a compact value ending in a secret letter is masked, not the next argument' );
( $out ) = vec_( 'bmcdiscover', '-nstop', '--range', '10.0.0.1' );
is( $out, '-nxxxxxxxx --range 10.0.0.1', 'a compact -n value is masked whole' );
( $out ) = vec_( 'bmcdiscover', '-pbanana' );
is( $out, '-pxxxxxxxx', 'a compact value with a later secret letter is masked from the option' );
( $out ) = vec_( 'bmcdiscover', '--p=SEKRET' );
unlike( $out, qr/SEKRET/, 'a double-dash --p=value is redacted' );
( $out ) = vec_( 'switchdiscover', '--c', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a double-dash --c community is redacted' );
( $out ) = vec_( 'mkhwconn', 'frame', '--P=SEKRET' );
unlike( $out, qr/SEKRET/, 'a double-dash --P=value is redacted' );
( $out, $changed ) = vec_( 'mkhwconn', 'frame', '--p', 'hmc01' );
is( $changed, 0, 'the double-dash --p control point is kept, the case differs' );
( $out ) = vec_( 'mkvm', 'zvm02', '--W', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a double-dash --W is redacted, the parser ignores case' );

# The vCenter cluster commands log in with a --password option.
( $out ) = vec_( 'createvcluster', '--vcenter', 'vc01', '--username', 'admin', '--password', 'SEKRET', 'cluster01' );
unlike( $out, qr/SEKRET/, 'the createvcluster password is redacted' );
like( $out, qr/--username admin/, 'the createvcluster username is kept' );
( $out ) = vec_( 'lsvcluster', '--vcenter', 'vc01', '--password=SEKRET' );
unlike( $out, qr/SEKRET/, 'the lsvcluster password is redacted' );
( $out ) = vec_( 'rmvcluster', '--vcenter', 'vc01', '--PASSWORD', 'SEKRET', 'cluster01' );
unlike( $out, qr/SEKRET/, 'the rmvcluster password is redacted, the parser ignores case' );

# In a bundle a non-secret option that takes a value absorbs the rest, so a
# secret letter inside that value must not redact.
( $out, $changed ) = vec_( 'bmcdiscover', '-snmap', '--range', '10.0.0.0/24' );
is( $out, '-snmap --range 10.0.0.0/24', 'the -snmap scan method is kept, n is the value of -s' );
is( $changed, 0, 'a non-secret compact value reports no change' );
( $out, $changed ) = vec_( 'bmcdiscover', '-sopenbmc' );
is( $out, '-sopenbmc', 'the -sopenbmc scan method is kept, p is inside the value' );
is( $changed, 0, 'the -sopenbmc value reports no change' );
( $out, $changed ) = vec_( 'mkhwconn', 'frame', '-pPOWERHMC' );
is( $changed, 0, 'the mkhwconn -p value is kept, P is inside the value of -p' );
( $out, $changed ) = vec_( 'bmcdiscover', '-zsp', 'SEKRET' );
is( $changed, 0, 'a bundle stops at a value option, -zsp is the value p of -s' );
( $out ) = vec_( 'bmcdiscover', '-zps', 'topsecret' );
is( $out, '-zpxxxxxxxx topsecret', 'a bundle masks from the secret letter, the next argument is positional' );
( $out ) = vec_( 'bmcdiscover', '-?pSEKRET' );
unlike( $out, qr/SEKRET/, 'a bundle with the ? help letter is redacted' );
( $out ) = vec_( 'bmcdiscover', '-?n', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a -?n bundle masks the next argument' );
( $out, $changed ) = vec_( 'mkvm', 'lpar01', '-cpower10', '-pprofile1' );
is( $out, 'lpar01 -cpower10 -pprofile1', 'the mkvm compact values are kept, w is inside the value of -c' );
is( $changed, 0, 'the mkvm compact values report no change' );
( $out, $changed ) = vec_( 'mkvm', 'lpar01', '-p', 'profile1' );
is( $out, 'lpar01 -p profile1', 'the PPC mkvm profile remains visible' );
is( $changed, 0, 'the PPC mkvm profile reports no redaction' );

# In the z/VM grammar -s is a boolean and -c takes an integer, so a bundle can
# continue into the real password option.
( $out ) = vec_( 'mkvm', 'zvm02', '-swSEKRET' );
unlike( $out, qr/SEKRET/, 'zVM -s followed by bundled -w is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '-sw', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'zVM bundled -sw masks the next argument' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c1wSEKRET' );
unlike( $out, qr/SEKRET/, 'zVM resumes after the numeric -c value and redacts -w' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c1w', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'zVM numeric bundle masks the following password argument' );
( $out, $changed ) = vec_( 'mkvm', 'zvm02', '-c12' );
is( $changed, 0, 'a plain numeric cpu bundle is kept' );

# Bundled short options keep letter case, so a capital letter is unknown to
# the parser and the bundle continues into the password option.
( $out ) = vec_( 'mkvm', 'zvm02', '-Rw', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a capital -Rw bundle masks the next argument' );
( $out ) = vec_( 'mkvm', 'zvm02', '-RwSEKRET' );
unlike( $out, qr/SEKRET/, 'a glued capital -RwSEKRET is redacted' );

# A bundled integer value may carry a sign or underscores.
( $out ) = vec_( 'mkvm', 'zvm02', '-c+1w', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a signed cpu value still reaches the password option' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c-1wSEKRET' );
unlike( $out, qr/SEKRET/, 'a negative cpu value still reaches the password option' );
( $out ) = vec_( 'mkvm', 'zvm02', '-c1_0w', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'an underscored cpu value still reaches the password option' );
( $out, $changed ) = vec_( 'mkvm', 'zvm02', '-rabcw', 'KEEPME' );
is( $changed, 0, 'a lowercase -r value absorbs the rest of the bundle' );

# Getopt::Long compatibility mode also accepts "+" as an option starter.
( $out ) = vec_( 'bmcdiscover', '+p', 'SEKRET', '--range', '10.0.0.1' );
unlike( $out, qr/SEKRET/, 'a +p option is redacted' );
( $out ) = vec_( 'bmcdiscover', '+bmcpasswd=SEKRET' );
unlike( $out, qr/SEKRET/, 'a +bmcpasswd=value is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '+w', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a +w option is redacted' );
( $out ) = vec_( 'switchdiscover', '--range', '10.0.0.0/24', '-xc', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a bundled -xc community is redacted' );
( $out ) = vec_( 'mkhwconn', 'frame', '-tP', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'a bundled -tP password is redacted' );
( $out, $changed ) = vec_( 'mkhwconn', 'frame', '-p', 'hmc01' );
is( $out, 'frame -p hmc01', 'the mkhwconn -p stays visible, it is not the password' );
is( $changed, 0, 'the mkhwconn hardware control point reports no change' );
( $out ) = vec_( 'mkvm', 'zvm02', '-W', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'the mkvm -W is redacted, the parser ignores case' );
( $out ) = vec_( 'mkvm', 'zvm02', '--PASSWORD=SEKRET' );
unlike( $out, qr/SEKRET/, 'the mkvm --PASSWORD=value is redacted' );
( $out ) = vec_( 'mkvm', 'zvm02', '--Pass', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'the mkvm abbreviated --Pass is redacted' );
( $out ) = vec_( 'mkvm', 'gpok4', 'gpok3', 'pool=POOL1', 'pw=SEKRET' );
unlike( $out, qr/SEKRET/, 'the mkvm clone pw= operand is redacted' );
like( $out, qr/pool=POOL1/, 'the mkvm clone pool= operand is kept' );

# chvm carries passwords as positional operands.
( $out ) = vec_( 'chvm', '--setpassword', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'the chvm --setpassword operand is redacted' );
( $out ) = vec_( 'chvm', '--add3390', 'POOL1', '0101', '3g', 'MR', 'RSEKRET', 'WSEKRET', 'MSEKRET' );
unlike( $out, qr/SEKRET/, 'the chvm --add3390 disk passwords are redacted' );
like( $out, qr/POOL1 0101 3g MR/, 'the chvm --add3390 disk parameters are kept' );
( $out ) = vec_( 'chvm', '--formatdisk', '0100', 'SEKRET' );
unlike( $out, qr/SEKRET/, 'the chvm --formatdisk password is redacted' );
like( $out, qr/--formatdisk 0100/, 'the chvm --formatdisk address is kept' );

# The site table stores the global SNMP community string under the snmpc key.
( $out ) = vec_( 'tabch', 'key=snmpc', 'site.value=SEKRET' );
unlike( $out, qr/SEKRET/, 'a tabch of the snmpc site value is redacted' );
( $out ) = vec_( 'tabch', 'key=snmpc', 'site.value+=SEKRET' );
unlike( $out, qr/SEKRET/, 'a tabch += splice of the snmpc site value is redacted' );
( $out ) = vec_( 'tabch', 'key=snmpc,key=snmpc', 'site.value=SEKRET' );
unlike( $out, qr/SEKRET/, 'a compound tabch selector with snmpc is redacted' );
( $out ) = vec_( 'tabch', 'key=temporary', 'site.key=snmpc', 'site.value=SEKRET' );
unlike( $out, qr/SEKRET/, 'a site.key=snmpc assignment marks the value secret' );
( $out ) = vec_( 'tabch', 'site.key=snmpc', 'site.value=SEKRET' );
unlike( $out, qr/SEKRET/, 'a table-qualified snmpc selector is redacted' );
( $out, $changed ) = vec_( 'tabch', 'key=domain', 'site.value=lab' );
is( $out, 'key=domain site.value=lab', 'a tabch of a plain site value is kept' );
is( $changed, 0, 'a benign vector reports no change' );
unlike( arg('snmpc=SEKRET'), qr/SEKRET/, 'the snmpc site attribute is redacted' );

# Product keys are license secrets.
unlike( arg('productkey=SEKRET'), qr/SEKRET/, 'a product key is redacted' );
unlike( arg('prodkey.key=SEKRET'), qr/SEKRET/, 'a table-qualified product key is redacted' );

# The token table stores bearer credentials under tokenid.
unlike( arg('tokenid=SEKRET'), qr/SEKRET/, 'an authentication token is redacted' );
unlike( arg('token.tokenid=SEKRET'), qr/SEKRET/, 'a table-qualified token is redacted' );

# Every attribute and column Schema.pm marks secret must be covered. Keep every
# (attribute, column) pair so a removed table-qualified column is caught, not
# masked by another pair that shares the attribute name.
my @pairs;
while ( $schema_source =~ /attr_name\s*=>\s*'([^']+)'(.{0,400}?)tabentry\s*=>\s*'([^']+)'/gs ) {
    my ( $attr, $tabentry ) = ( $1, $3 );
    next
      unless $tabentry =~ /\.(password|passwd|authkey|privkey|adminpassword|sshpassword|community)$/i
      or $tabentry eq 'prodkey.key';
    push @pairs, [ $attr, $tabentry ];
}
ok( scalar(@pairs) > 0, 'Schema.pm yielded attributes mapped to secret columns' )
  or BAIL_OUT('the Schema.pm mapping could not be parsed, so this test proves nothing');

my @uncovered;
foreach my $pair (@pairs) {
    my ( $attr, $column ) = @$pair;
    push @uncovered, $attr   if arg("$attr=SEKRET")   =~ /SEKRET/;
    push @uncovered, $column if arg("$column=SEKRET") =~ /SEKRET/;
}
is_deeply( \@uncovered, [], 'every attribute and column Schema.pm marks secret is redacted' );

# validate() must redact the argument vector and still run the joined result
# through redact_password, so every secret reaches syslog and the auditlog
# table redacted.
like( $source, qr/=\s*xCAT::xcatd->redact_password_args\(\$request->\{command\}->\[0\]/, 'validate() redacts the argument vector' );
like( $source, qr/\$redacted_arglist\s*=\s*redact_password\b/, 'validate() redacts the arguments through redact_password' );

# The debug dispatch trace must not rebuild the command from the raw request.
like( $daemon_source, qr/\(\$trace_args\)\s*=\s*xCAT::xcatd->redact_password_args\(\$req->\{command\}->\[0\]/,
    'the dispatch trace builds its text from redacted arguments' );

# The auditlog table and syslog use the same redacted arguments.
like( $source, qr/\$rsp->\{args\}->\[0\]\s*=\s*\$redacted_arglist/, 'the auditlog table stores the redacted arguments' );

done_testing();
