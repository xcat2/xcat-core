#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

unless ( eval { require Dpkg::Control::Info; require Dpkg::Deps; 1 } ) {
    die "Install libdpkg-perl to check Debian package requirements: $@"
      if -f '/etc/debian_version';
    plan skip_all => 'Dpkg::Control::Info and Dpkg::Deps are not available';
}

sub relations_of {
    my ( $source, $package, $arch ) = @_;
    my $file = repo_path("$source/debian/control");
    my $fields = Dpkg::Control::Info->new($file)->get_pkg_by_name($package)
      or die "No stanza for $package in $file\n";
    my %rel;
    foreach my $field (qw(Depends Recommends)) {
        my $value = $fields->{$field} // '';
        # Model dh_perl's generated dependency as Perl; module requirements must be declared explicitly.
        $value =~ s/\$\{perl:Depends\}/perl/g;
        $rel{$field} = Dpkg::Deps::deps_parse( $value, reduce_arch => 1, host_arch => $arch );
        die "Unable to parse $field of $package for $arch\n" unless defined $rel{$field};
    }
    return \%rel;
}

sub depends_on {
    my ( $rel, $requirement, $label ) = @_;
    my $term = Dpkg::Deps::Simple->new($requirement);
    # A one-term OR lets implies() check every branch of an alternative dependency.
    my $required = Dpkg::Deps::OR->new($term);
    ok( $rel->{Depends}->implies($required), "$label depends on $requirement" )
      or diag( 'Depends: ' . $rel->{Depends}->output() );

    my @recommended;
    Dpkg::Deps::deps_iterate( $rel->{Recommends}, sub {
        my ($dep) = @_;
        push @recommended, $dep->output() if $dep->{package} eq $term->{package};
        return 1;
    } );
    is_deeply( \@recommended, [], "$label does not also recommend $term->{package}" );
}

foreach my $arch (qw(amd64 ppc64el riscv64)) {
    subtest $arch => sub {
        my $perl_xcat = relations_of( 'perl-xCAT', 'perl-xcat', $arch );
        depends_on( $perl_xcat, $_, 'perl-xcat' ) for qw(
            libhtml-form-perl libxml-simple-perl libxml-parser-perl libio-socket-ssl-perl libdbi-perl libjson-perl
            libwww-perl libxml-libxml-perl libexpect-perl libsnmp-perl libsocket6-perl libio-socket-inet6-perl
        );

        my $client = relations_of( 'xCAT-client', 'xcat-client', $arch );
        depends_on( $client, 'libcapture-tiny-perl', 'xcat-client' );
        depends_on( $client, 'nmap', 'xcat-client' );

        my $server = relations_of( 'xCAT-server', 'xcat-server', $arch );
        depends_on( $server, 'libcgi-pm-perl', 'xcat-server' );

        foreach my $case ( [ 'xCAT', 'xcat' ], [ 'xCATsn', 'xcatsn' ] ) {
            my ( $source, $package ) = @$case;
            my $rel = relations_of( $source, $package, $arch );
            depends_on( $rel, 'nmap', $package );
            depends_on( $rel, 'ipmitool-xcat (>= 1.8.18-4)', $package );
        }
    };
}

done_testing();
