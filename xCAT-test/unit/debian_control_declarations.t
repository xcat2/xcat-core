#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# dh_perl adds no module dependencies, unlike the rpm generator, so a deb declares only what its
# control file names. perl-xcat declared libhtml-form-perl alone while its files load nine other
# modules at top level, xcat-server shipped the REST API without CGI, xcat-client ships z/VM
# helpers that load Capture::Tiny, and nmap and ipmitool-xcat were recommendations where the rpm
# packages require them.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );

# The relation fields of one binary package stanza as sets of package names, plus the version
# bound of each relation that has one.
sub relations_of {
    my ( $source, $package ) = @_;
    my $file = File::Spec->catfile( $repo_root, $source, 'debian', 'control' );
    open( my $fh, '<', $file ) or die "Unable to read $file: $!";
    my $control = do { local $/; <$fh> };
    close($fh);
    my ($stanza) = $control =~ /^Package:\s*\Q$package\E\s*\n(.*?)(?:\n\n|\z)/ms;
    die "no stanza for $package in $file" unless defined $stanza;
    my %rel;
    foreach my $field (qw(Depends Recommends)) {
        my ($line) = $stanza =~ /^$field:\s*(.*)$/m;
        foreach my $entry ( split( /[,|]/, $line // '' ) ) {
            my ( $name, $bound ) = $entry =~ /^\s*(\S+?)\s*(?:\(([^)]*)\))?\s*(?:\[[^\]]*\])?\s*$/;
            next unless defined $name;
            $rel{$field}{$name} = 1;
            $rel{version}{$name} = $bound if defined $bound;
        }
    }
    return \%rel;
}

sub depends_on {
    my ( $rel, $name, $label ) = @_;
    ok( $rel->{Depends}{$name}, "$label depends on $name" );
    ok( !$rel->{Recommends}{$name}, "... and no longer only recommends it" ) if $rel->{Recommends}{$name};
}

my $perl_xcat = relations_of( 'perl-xCAT', 'perl-xcat' );
depends_on( $perl_xcat, $_, 'perl-xcat' ) for qw(
    libhtml-form-perl libxml-simple-perl libxml-parser-perl libio-socket-ssl-perl libdbi-perl libjson-perl
    libwww-perl libxml-libxml-perl libexpect-perl libsnmp-perl libsocket6-perl libio-socket-inet6-perl
);

my $client = relations_of( 'xCAT-client', 'xcat-client' );
depends_on( $client, 'libcapture-tiny-perl', 'xcat-client' );

my $server = relations_of( 'xCAT-server', 'xcat-server' );
depends_on( $server, 'libcgi-pm-perl', 'xcat-server' );

# nmap and ipmitool-xcat are hard requirements on EL and were only recommended here.
my $xcat   = relations_of( 'xCAT',   'xcat' );
my $xcatsn = relations_of( 'xCATsn', 'xcatsn' );
foreach my $case ( [ $xcat, 'xcat' ], [ $xcatsn, 'xcatsn' ], [ $client, 'xcat-client' ] ) {
    my ( $rel, $label ) = @$case;
    ok( $rel->{Depends}{nmap},        "$label depends on nmap" );
    ok( !$rel->{Recommends}{nmap},    "... and does not recommend it as well" );
}
foreach my $case ( [ $xcat, 'xcat' ], [ $xcatsn, 'xcatsn' ] ) {
    my ( $rel, $label ) = @$case;
    ok( $rel->{Depends}{'ipmitool-xcat'},     "$label depends on ipmitool-xcat" );
    ok( !$rel->{Recommends}{'ipmitool-xcat'}, "... and does not recommend it as well" );
    is( $rel->{version}{'ipmitool-xcat'}, '>= 1.8.18-4', "... at the floor xCAT.spec requires" );
}

done_testing();
