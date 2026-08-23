#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;
use Getopt::Long qw(GetOptionsFromArray);

my $plugin = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'xcat', 'plugins', 'nodestat.pm' );
plan skip_all => 'nodestat.pm not found' unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# nodestat parses its arguments twice, once in the preprocessor and once in the
# handler. Both have to read the same specification, or an option that one
# accepts is dropped or misread by the other.
my $calls = () = $source =~ /GetOptions\s*\(\s*\\%opt,\s*option_spec\(\)\s*\)/g;
is( $calls, 2, 'both places parse through the one specification' );

my ($routine) = $source =~ /(sub option_spec \{.*?\n\}\n)/s;
BAIL_OUT('could not extract option_spec from nodestat.pm') unless $routine;
eval "package NodestatSpec; $routine 1;" or BAIL_OUT("could not evaluate: $@");

# The daemon leaves Getopt::Long in pass_through, because xCAT::Usage sets it
# and the setting lasts for the life of the process.
sub parse {
    my (@argv) = @_;
    Getopt::Long::ConfigDefaults();
    Getopt::Long::Configure( 'pass_through', 'bundling' );
    $Getopt::Long::ignorecase = 0;
    my %opt;
    do { local $SIG{__WARN__} = sub { }; GetOptionsFromArray( \@argv, \%opt, NodestatSpec::option_spec() ) };
    return \%opt;
}

# The option that the manual page and the usage message give.
foreach my $given (qw(-f --usefping)) {
    ok( parse($given)->{f}, "$given selects fping" );
}

# The spelling that the code has carried since 2.14.2. A site can have it in a
# script, so it keeps working.
ok( parse('--useping')->{f}, '--useping still selects fping' );

# usemon owns these abbreviations. They were unambiguous before the fping
# option gained a long name beginning with the same letters, and an
# administrator who monitors with them must not silently lose monitoring.
foreach my $given (qw(--use --us --usemon -m)) {
    my $opt = parse($given);
    ok( $opt->{m}, "$given still selects usemon" );
    ok( !$opt->{f}, "$given does not select fping" );
}

# Short options bundle, so both orders have to give both settings.
foreach my $given (qw(-mf -fm)) {
    my $opt = parse($given);
    ok( $opt->{m} && $opt->{f}, "$given selects usemon and fping" );
}

# The other options keep their own letters.
is_deeply(
    [ map { parse($_) } qw(-u -p -q) ],
    [ { u => 1 }, { p => 1 }, { q => 1 } ],
    'the remaining options are unchanged'
);

# The usage text is what an administrator types.
my ($usage) = $source =~ /(nodestat \[noderange\][^"]*)/;
ok( defined $usage, 'the usage message was found' );
my ($long) = grep { /^f\|/ } NodestatSpec::option_spec();
($long) = $long =~ /^f\|([^|]+)/;
ok( defined $usage && $usage =~ /--\Q$long\E/,
    'the usage message names the option that the code accepts' );

done_testing();
