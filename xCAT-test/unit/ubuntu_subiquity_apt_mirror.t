#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# archive.ubuntu.com publishes amd64 and i386 only, so a ppc64el or riscv64 stateful install
# is handed a mirror that carries no package for it. The architecture being installed is the
# last component of the media directory.

BEGIN {
    package xCAT::Table;
    our $value;
    sub new { return bless {}, shift }
    sub getAttribs { return defined $value ? { value => $value } : undef }
    $INC{'xCAT/Table.pm'} = __FILE__;
}

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $module = "$FindBin::Bin/../../xCAT-server/lib/perl/xCAT/Template.pm";
plan skip_all => 'Template.pm not found' unless -r $module;
eval { require $module; 1 } or plan skip_all => "could not load Template.pm: $@";

my $mirror = \&xCAT::Template::ubuntu_subiquity_apt_mirror;

# The osimage's architecture decides the mirror. pkgdir cannot: it is whatever path the
# administrator configured, so an amd64 image under /srv/custom-media would be read as a
# non-x86 architecture and sent to the ports archive.
is( $mirror->('riscv64'), 'http://ports.ubuntu.com/ubuntu-ports',
    'a riscv64 image takes the ports archive' );
is( $mirror->('ppc64el'), 'http://ports.ubuntu.com/ubuntu-ports',
    'a ppc64el image takes the ports archive' );
is( $mirror->('ppc64le'), 'http://ports.ubuntu.com/ubuntu-ports',
    'the other spelling of ppc64 takes the ports archive' );

for my $x86 (qw(x86_64 amd64 x86 i386)) {
    is( $mirror->($x86), 'http://archive.ubuntu.com/ubuntu',
        "an $x86 image keeps the main archive" );
}

# With no architecture there is nothing to key on, so the previous default stands.
is( $mirror->(undef), 'http://archive.ubuntu.com/ubuntu',
    'an unknown architecture keeps the previous default' );

# site.ubuntu_apt_mirror still wins, which is how an airgapped cluster points at its own.
{
    local $xCAT::Table::value = 'http://mirror.example.invalid/ubuntu';
    is( $mirror->('riscv64'), 'http://mirror.example.invalid/ubuntu',
        'site.ubuntu_apt_mirror overrides the ports archive' );
    is( $mirror->('x86_64'), 'http://mirror.example.invalid/ubuntu',
        'site.ubuntu_apt_mirror overrides the main archive' );
}
{
    local $xCAT::Table::value = '';
    is( $mirror->('riscv64'), 'http://ports.ubuntu.com/ubuntu-ports',
        'an empty site.ubuntu_apt_mirror does not blank the mirror' );
}

done_testing();
