#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $xcatd  = File::Spec->catfile( $repo_root, 'xCAT-server/lib/perl/xCAT/xcatd.pm' );
my $schema = File::Spec->catfile( $repo_root, 'perl-xCAT/xCAT/Schema.pm' );

plan skip_all => 'xcatd.pm or Schema.pm not found' unless -r $xcatd && -r $schema;

sub slurp {
    open( my $fh, '<', $_[0] ) or die "Unable to read $_[0]: $!";
    my $c = do { local $/; <$fh> };
    close($fh);
    return $c;
}

my $source        = slurp($xcatd);
my $schema_source = slurp($schema);

# Run the real routine rather than inspecting its source. xcatd.pm cannot be
# loaded here because of its dependencies, so the routine is lifted out and
# evaluated on its own; it uses nothing outside itself.
my ($routine) = $source =~ /(sub redact_password \{.*?\n\}\n)/s;
ok( $routine, 'redact_password was located in xcatd.pm' )
  or BAIL_OUT('xcatd.pm no longer defines redact_password');
eval "package RedactUnderTest; $routine 1;" or BAIL_OUT("could not evaluate redact_password: $@");

sub redacted { return RedactUnderTest::redact_password( $_[0], $_[1] ); }

# A secret must never survive, whichever way it was written.
my %leaks = (
    'attribute assignment'      => [ 'chdef',   " node01 bmcpassword=SEKRET" ],
    'quoted assignment'         => [ 'chdef',   " node01 'bmcpassword=SEKRET'" ],
    'spaces around the equals'  => [ 'chdef',   " node01 'bmcpassword = SEKRET phrase'" ],
    'table qualified column'    => [ 'chtab',   " key=system passwd.username=root passwd.password=SEKRET" ],
    'several on one command'    => [ 'nodeadd', " n1 ipmi.password=SEKRET openbmc.password=SEKRET" ],
    'snmp passphrases'          => [ 'chdef',   " pdu1 authkey=SEKRET privkey=SEKRET" ],
    'positional flag'           => [ 'bmcdiscover', " -s nmap -p SEKRET --range 10.0.0.1" ],
);
foreach my $case ( sort keys %leaks ) {
    my ( $command, $args ) = @{ $leaks{$case} };
    unlike( redacted( $command, $args ), qr/SEKRET/, "no secret survives: $case" );
}

# Detail that is not secret has to stay, or the log stops being useful.
my $kept = redacted( 'chdef', " node01 sshkeydir=/etc/xcat/keys key=system groups=lab mgt=ipmi" );
like( $kept, qr/sshkeydir=\/etc\/xcat\/keys/, 'sshkeydir is kept, it is a directory' );
like( $kept, qr/key=system/,                  'key is kept, it names a monitoring attribute' );
like( $kept, qr/groups=lab/,                  'unrelated attributes are kept' );
like(
    redacted( 'chtab', " key=system passwd.username=root passwd.password=SEKRET" ),
    qr/passwd\.username=root/,
    'the username beside a redacted password is kept'
);

# Every attribute Schema.pm maps to a secret column has to be covered, so that
# one added later fails here instead of quietly reaching the logs.
my %expected;
while ( $schema_source =~ /attr_name\s*=>\s*'([^']+)'(.{0,400}?)tabentry\s*=>\s*'([^']+)'/gs ) {
    my ( $attr, $tabentry ) = ( $1, $3 );
    next unless $tabentry =~ /\.(password|passwd|authkey|privkey|adminpassword|sshpassword)$/i;
    $expected{$attr} = $tabentry;
}
ok( scalar( keys %expected ) > 0, 'Schema.pm yielded attributes mapped to secret columns' )
  or BAIL_OUT('the Schema.pm mapping could not be parsed, so this test proves nothing');

my @uncovered;
foreach my $attr ( sort keys %expected ) {
    push @uncovered, $attr
      if redacted( 'chdef', " node01 $attr=SEKRET" ) =~ /SEKRET/;
    my $column = $expected{$attr};
    push @uncovered, $column
      if redacted( 'chdef', " node01 $column=SEKRET" ) =~ /SEKRET/;
}
is_deeply( \@uncovered, [], 'every attribute and column Schema.pm marks secret is redacted' );

# The auditlog table was given the raw arguments while syslog was given the
# redacted ones, so both sinks must now use the same text.
like( $source, qr/\$redacted_arglist\s*=\s*redact_password/, 'the redacted arguments are computed once' );
like( $source, qr/\$rsp->\{args\}->\[0\]\s*=\s*\$redacted_arglist/, 'the auditlog table stores the redacted arguments' );

done_testing();
