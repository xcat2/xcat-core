#!/usr/bin/env perl
# netboot=xnba is deprecated, so the x86 nodes that xCAT defines get netboot=ipxe: from an image
# profile, from the x86 node templates of mkdef --template, and from the e1350 noderes table. A
# profile change does not move an existing netboot=xnba node.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use Text::ParseWords qw(parse_line);

use xCAT::DBobjUtils;
use xCAT::ProfiledNodeUtils;

my $root = "$FindBin::Bin/../..";

# The image profiles and their operating system distributions, as the osimage and osdistro tables
# hold them.
my %distro = (
    'rhels9.4-x86_64'  => { basename => 'rhels',  majorversion => '9',  arch => 'x86_64' },
    'rhels9.4-x86'     => { basename => 'rhels',  majorversion => '9',  arch => 'x86' },
    'rhels9.4-ppc64le' => { basename => 'rhels',  majorversion => '9',  arch => 'ppc64le' },
    'rocky10-riscv64'  => { basename => 'rocky',  majorversion => '10', arch => 'riscv64' },
);

{
    package ProfiledNodeTable;
    sub new { my ( $class, $name ) = @_; return bless { name => $name }, $class; }
    sub getAttribs {
        my ( $self, $key ) = @_;
        return { osdistroname => $key->{imagename} } if $self->{name} eq 'osimage';
        return $distro{ $key->{osdistroname} } if $self->{name} eq 'osdistro';
        return;
    }
    sub getNodeAttribs { return; }
    sub close { return; }
}

{
    no warnings 'redefine';
    local *xCAT::TableUtils::list_all_node_groups = sub { return map { "__ImageProfile_$_" } keys %distro; };
    local *xCAT::Table::new = sub { shift; return ProfiledNodeTable->new(@_); };

    my %want = (
        'rhels9.4-x86_64'  => 'ipxe',
        'rhels9.4-x86'     => 'ipxe',
        'rhels9.4-ppc64le' => 'grub2',
        'rocky10-riscv64'  => 'grub2',
    );
    for my $profile ( sort keys %want ) {
        is_deeply( [ xCAT::ProfiledNodeUtils->get_netboot_attr("__ImageProfile_$profile") ], [ 1, $want{$profile} ],
            "a node of image profile $profile gets netboot=$want{$profile}" );
    }
}

# A profile change keeps netboot=xnba, since moving a node to the upstream loader is the choice of the site.
is( xCAT::ProfiledNodeUtils->profile_netboot( 'ipxe', 'xnba' ), 'xnba', 'a profile change keeps netboot=xnba on an x86 node' );
is( xCAT::ProfiledNodeUtils->profile_netboot( 'ipxe', undef ),  'ipxe', 'an x86 node without a method gets netboot=ipxe' );
is( xCAT::ProfiledNodeUtils->profile_netboot( 'ipxe', 'pxe' ),  'ipxe', 'a netboot=pxe node gets the method of its profile' );
is( xCAT::ProfiledNodeUtils->profile_netboot( 'grub2', 'xnba' ), 'grub2', 'a node that moves to another architecture gets the method of its profile' );

sub template_netboot {
    my ( $file, $name ) = @_;
    my $path = "$root/xCAT/templates/objects/node/$file.stanza";
    open( my $fh, '<', $path ) or die "Cannot read $path: $!";
    my $data = do { local $/; <$fh> };
    close($fh);
    local %::FILEATTRS;
    xCAT::DBobjUtils->readFileInput($data);
    return $::FILEATTRS{$name}{netboot};
}

is( template_netboot( 'x86_64', 'x86_64-template' ), 'ipxe', 'mkdef --template x86_64-template defines netboot=ipxe' );
is( template_netboot( 'x86_64kvmguest', 'x86_64kvmguest-template' ), 'ipxe',
    'mkdef --template x86_64kvmguest-template defines netboot=ipxe' );
is( template_netboot( 'ppc64le-ipmi', 'ppc64le-template' ), 'petitboot', 'the ppc64le template keeps its netboot method' );

{
    my $path = "$root/xCAT/templates/e1350/noderes.csv";
    open( my $fh, '<', $path ) or die "Cannot read $path: $!";
    chomp( my @lines = <$fh> );
    close($fh);
    ( my $header = shift @lines ) =~ s/^#//;
    my @columns = parse_line( ',', 0, $header );
    my %compute;
    @compute{@columns} = parse_line( ',', 0, ( grep { /^"compute"/ } @lines )[0] );
    is( $compute{netboot}, 'ipxe', 'the e1350 noderes table gives the compute group netboot=ipxe' );
}

done_testing();
