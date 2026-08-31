#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)

BEGIN {
    *CORE::GLOBAL::readpipe = sub {
        return "testarch\n" if $_[0] eq 'uname -i';
        return CORE::readpipe( $_[0] );
    };

    package xCAT::Table;
    our %tables;
    sub new { return $tables{ $_[1] }; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::NodeRange;
    sub noderange { return; }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;

    package xCAT::Utils;
    our $osver = 'testos1';
    sub osver { return $osver; }
    sub version_cmp { return 0; }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    our $install_dir;
    sub getInstallDir { return $install_dir; }
    sub get_site_attribute { return; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;
}

package Local::Table;

sub new {
    my ( $class, $row ) = @_;
    return bless {
        attrib_queries => [],
        row            => $row ? {%$row} : {},
        writes         => [],
    }, $class;
}

sub getAllEntries { return []; }

sub getAttribs {
    my ( $self, $key, @attributes ) = @_;
    push @{ $self->{attrib_queries} }, [ {%$key}, @attributes ];

    return unless defined $self->{row}->{imagename};
    return unless $self->{row}->{imagename} eq $key->{imagename};

    my %result;
    foreach my $attribute (@attributes) {
        my $value = $self->{row}->{$attribute};
        $result{$attribute} = $value
          if defined($value) and $value ne '';
    }
    return keys(%result) ? \%result : undef;
}

sub setAttribs {
    my ( $self, $key, $attributes ) = @_;
    push @{ $self->{writes} }, [ {%$key}, {%$attributes} ];
    $self->{row} = { %{ $self->{row} }, %$key, %$attributes };
    return;
}

sub close { return; }

package main;

no warnings qw(once redefine);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $fixture_root = tempdir( CLEANUP => 1 );
my $install_root = File::Spec->catdir( $fixture_root, 'install' );
my $install_assets = File::Spec->catdir(
    $fixture_root, 'share', 'xcat', 'install', 'testos1' );
my $netboot_assets = File::Spec->catdir(
    $fixture_root, 'share', 'xcat', 'netboot', 'testos1' );
make_path( $install_root, $install_assets, $netboot_assets );

my $profile_file = File::Spec->catfile(
    $install_assets, 'compute.fixture.tmpl' );
open( my $profile_handle, '>', $profile_file )
  or die "Cannot create $profile_file: $!";
close($profile_handle) or die "Cannot close $profile_file: $!";

$ENV{XCATROOT} = $fixture_root;
$xCAT::TableUtils::install_dir = $install_root;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $svrutils = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'perl', 'xCAT', 'SvrUtils.pm' );
require $svrutils;

sub run_case {
    my ( $case, $state ) = @_;
    my $linuximage_row =
      $state eq 'existing'
      ? {
        imagename   => $case->{imagename},
        pkgdir      => '/existing/packages',
        addkcmdline => 'debug',
      }
      : $state eq 'empty-pkgdir'
      ? {
        imagename   => $case->{imagename},
        addkcmdline => 'debug',
      }
      : undef;

    my $osimage_table = Local::Table->new();
    my $linuximage_table = Local::Table->new($linuximage_row);
    %xCAT::Table::tables = (
        osimage    => $osimage_table,
        linuximage => $linuximage_table,
    );

    my @result = $case->{call}->();
    return {
        linuximage => $linuximage_table,
        result     => \@result,
    };
}

my @cases = (
    {
        name      => 'install image',
        imagename => 'testos1-testarch-install-compute',
        call      => sub {
            return xCAT::SvrUtils->update_tables_with_templates(
                'testos1', 'testarch', '/packages', 'testos1-testarch' );
        },
    },
    {
        name      => 'management image',
        imagename => 'testos1-testarch-stateful-mgmtnode',
        call      => sub {
            return xCAT::SvrUtils->update_tables_with_mgt_image(
                'testos1', 'testarch', '/packages', 'testos1-testarch' );
        },
    },
    {
        name      => 'diskless image',
        imagename => 'testos1-testarch-netboot-compute',
        call      => sub {
            return xCAT::SvrUtils->update_tables_with_diskless_image(
                'testos1', 'testarch', 'compute', 'netboot',
                '/packages', 'testos1-testarch' );
        },
    },
);

{
    local *xCAT::SvrUtils::_profile_file_matches = sub { return 1; };
    local *xCAT::SvrUtils::get_tmpl_file_name = sub { return '/assets/template'; };
    local *xCAT::SvrUtils::get_pkglist_file_name = sub { return '/assets/pkglist'; };
    local *xCAT::SvrUtils::get_otherpkgs_pkglist_file_name =
      sub { return '/assets/otherpkgs.pkglist'; };
    local *xCAT::SvrUtils::get_postinstall_file_name =
      sub { return '/assets/postinstall'; };
    local *xCAT::SvrUtils::get_exlist_file_name = sub { return '/assets/exlist'; };
    local *xCAT::SvrUtils::getsynclistfile = sub { return '/assets/synclist'; };

    foreach my $case (@cases) {
        subtest "$case->{name} defaults" => sub {
            my $created = run_case( $case, 'new' );
            is_deeply( $created->{result}, [ 0, '' ],
                'the table update succeeds' );
            is( $created->{linuximage}->{row}->{addkcmdline}, 'quiet',
                'a row without pkgdir receives the quiet default' );
            is_deeply(
                $created->{linuximage}->{attrib_queries},
                [ [ { imagename => $case->{imagename} }, 'pkgdir' ] ],
                'the default decision reads only the existing pkgdir',
            );

            my $without_pkgdir = run_case( $case, 'empty-pkgdir' );
            is( $without_pkgdir->{linuximage}->{row}->{addkcmdline}, 'quiet',
                'an existing row without pkgdir receives the current default' );

            my $existing = run_case( $case, 'existing' );
            is_deeply( $existing->{result}, [ 0, '' ],
                'updating an existing image succeeds' );
            is( $existing->{linuximage}->{row}->{addkcmdline}, 'debug',
                'an existing image keeps its kernel arguments' );
            is( scalar( @{ $existing->{linuximage}->{writes} } ), 1,
                'the caller performs one linuximage update' );
        };
    }
}

done_testing();
