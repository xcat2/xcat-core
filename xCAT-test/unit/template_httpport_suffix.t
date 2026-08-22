#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp;
use Test::More;

use XCAT::Test::File qw(repo_path);

my $module = repo_path('xCAT-server/lib/perl/xCAT/Template.pm');
plan skip_all => 'Template.pm not found' unless -r $module;

my @incs = (
    repo_path('perl-xCAT'),
    repo_path('xCAT-server/lib/perl'),
);

# A mismatched DBI aborts the process instead of dying, so ask a child before
# loading the module in this process.
my $devnull = File::Spec->devnull();
my $probe = join( ' ', $^X, ( map { "-I$_" } @incs ),
    '-e', "'require xCAT::Template; 1'", ">$devnull", "2>&1" );
plan skip_all => 'xCAT::Template cannot be loaded here' if system($probe) != 0;

require lib;
lib->import(@incs);
require xCAT::Template;

sub suffix { return xCAT::Template::httpport_suffix(@_); }

is( suffix('80'), '', 'the default port gives no suffix' );
is( suffix('8080'), ':8080', 'another port gives a suffix' );
is( suffix('443'), ':443', 'the https port gives a suffix' );

# The port is text, as it is in the netboot plugins, so a port that is only
# equal to 80 as a number keeps the value that the site gave.
is( suffix('080'), ':080', 'the port is compared as text' );

# site.httpport can be missing, and it can be present but empty.
is( suffix(undef), '', 'a port that is not set gives no suffix' );
is( suffix(''),    '', 'a port that is set to nothing gives no suffix' );

my %site;
no warnings 'redefine', 'once';
local *xCAT::TableUtils::get_site_attribute = sub {
    my ( undef, $key ) = @_;
    return defined $site{$key} ? ( $site{$key} ) : ();
};
local *xCAT::NetworkUtils::getipaddr          = sub { return '192.0.2.10'; };
local *xCAT::Template::getPersistentKcmdline = sub { return ''; };
use warnings;

my $dir = File::Temp->newdir();
my $in  = File::Spec->catfile( "$dir", 'in.tmpl' );
write_text(
    $in,
    "url --url http://192.0.2.10#COLONHTTPPORT#/install/pkg\n"
      . "#INCLUDE_GET_INSTALL_DISK_SCRIPT#\n"
);

my $render = sub {
    my ($port) = @_;
    %site = ( installdir => '/install' );
    $site{httpport} = $port if defined $port;
    my $out = File::Spec->catfile( "$dir", "out.${\ ($port || 'default') }" );
    xCAT::Template->subvars( $in, $out, 'testnode', undef, '/install/pkg',
        'ubuntu', undef, { xcatmaster => '192.0.2.10' } );
    return read_text($out);
};

my $default = $render->(undef);
like( $default, qr{http://192\.0\.2\.10/install/pkg},
    'the default port leaves no port in a rendered URL' );
unlike( $default, qr{:80/}, 'the default port writes no :80' );
like( $default, qr{wget http://`cat /tmp/xcatserver`/install/autoinst/getinstdisk},
    'the default getinstdisk URL omits port 80' );
is( xCAT::Template::ubuntu_subiquity_pkgdir_uri('/install/otherpkgs'),
    'http://192.0.2.10/install/otherpkgs',
    'the subiquity URI leaves no port for the default port' );

my $custom = $render->('8080');
like( $custom, qr{http://192\.0\.2\.10:8080/install/pkg},
    'another port stays in a rendered URL' );
like( $custom, qr{wget http://`cat /tmp/xcatserver`:8080/install/autoinst/getinstdisk},
    'the getinstdisk URL keeps a custom port' );
is( xCAT::Template::ubuntu_subiquity_pkgdir_uri('/install/otherpkgs'),
    'http://192.0.2.10:8080/install/otherpkgs',
    'the subiquity URI keeps another port' );
is( xCAT::Template::ubuntu_subiquity_pkgdir_uri('http://mirror/pkg'),
    'http://mirror/pkg', 'a URI that is already whole is left alone' );

{
    package Local::TemplateNodetype;
    sub getNodesAttribs {
        return { testnode => [ { provmethod => 'test-image' } ] };
    }

    package Local::TemplateLinuximage;
    sub getAttribs { return { pkgdir => '/install/pkg,/install/other' }; }
}

no warnings qw(redefine once);
local *xCAT::Table::new = sub {
    my ( undef, $name ) = @_;
    return bless {}, 'Local::TemplateNodetype'  if $name eq 'nodetype';
    return bless {}, 'Local::TemplateLinuximage' if $name eq 'linuximage';
    die "Unexpected table $name";
};
local *xCAT::TableUtils::get_site_Master = sub { return '192.0.2.10'; };
{
    local $ENV{HTTPPORT} = '80';
    my $mirror = xCAT::Template::mirrorspec();
    like( $mirror, qr{d-i apt-setup/security_host string 192\.0\.2\.10\n},
        'the default mirror security host omits port 80' );
    like( $mirror, qr{deb http://192\.0\.2\.10/install/other \./},
        'a default-port local mirror omits port 80' );
}

{
    local $ENV{HTTPPORT} = '8080';
    my $mirror = xCAT::Template::mirrorspec();
    like( $mirror, qr{d-i apt-setup/security_host string 192\.0\.2\.10:8080\n},
        'the mirror security host keeps a custom port' );
    like( $mirror, qr{deb http://192\.0\.2\.10:8080/install/other \./},
        'a local mirror keeps a custom port' );
}

done_testing();
