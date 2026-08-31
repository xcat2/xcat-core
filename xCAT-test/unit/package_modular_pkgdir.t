#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $library = repo_path('xCAT/postscripts/xcatpkgutils.sh');
my $loader  = repo_path('xCAT/postscripts/xcatpkgutils-loader.sh');

my @modular_osvers = qw(
  rhel8 rhel9.6 rhel10.0 rhels8.10 rhels19
  centos8-stream centos10 rocky9.4 rocky19
  alma8 alma10 almalinux9 almalinux19 ol8 ol10
);
my @other_osvers = ( '', qw(rhel rhel1 rhel7.9 rhel20 ubuntu24.04 RHEL9 el9) );

SKIP: {
    skip 'the shared predicate is introduced by the production commit',
      scalar( @modular_osvers + @other_osvers )
      unless shared_predicate_available();

    for my $osver (@modular_osvers) {
        is( predicate_status($osver), 0,
            "$osver uses modular package directories" );
    }
    for my $osver (@other_osvers) {
        is( predicate_status($osver), 1,
            ( $osver || 'an empty OS version' )
              . ' does not use modular package directories' );
    }
}

for my $caller (qw(ospkgs otherpkgs)) {
    is_deeply(
        [ caller_repository_paths( $caller, 'rocky9.4' ) ],
        [
            'package-test-server:INSTALLDIR/rocky9.4/x86_64/BaseOS',
            'package-test-server:INSTALLDIR/rocky9.4/x86_64/AppStream',
        ],
        "$caller expands a modular OS into BaseOS and AppStream"
    );
    is_deeply(
        [ caller_repository_paths( $caller, 'rocky7.9' ) ],
        ['package-test-server:INSTALLDIR/rocky7.9/x86_64'],
        "$caller retains the base directory for a non-modular OS"
    );
}

done_testing();

sub predicate_status {
    my ($osver) = @_;
    my $status = system(
        '/bin/sh', '-c', '. "$1"; xcat_is_el_modular_pkgdir "$2"',
        'package-modular-pkgdir-test', $library, $osver
    );
    die "Unable to execute /bin/sh: $!" if $status == -1;
    die "/bin/sh terminated by signal " . ( $status & 127 )
      if $status & 127;
    return $status >> 8;
}

sub shared_predicate_available {
    return system(
        '/bin/sh', '-c',
        '. "$1"; command -v xcat_is_el_modular_pkgdir >/dev/null 2>&1',
        'package-modular-pkgdir-test', $library
    ) == 0;
}

sub caller_repository_paths {
    my ( $caller, $osver ) = @_;
    my $tmpdir = tempdir( CLEANUP => 1 );
    my $bindir = File::Spec->catdir( $tmpdir, 'bin' );
    my $trace = File::Spec->catfile( $tmpdir, 'repository-paths.trace' );
    make_path($bindir);

    my $mount = File::Spec->catfile( $bindir, 'mount' );
    write_fixture( $mount, "#!/bin/sh\nexit 1\n" );
    chmod 0755, $mount or die "Unable to make $mount executable: $!";
    my $uname = File::Spec->catfile( $bindir, 'uname' );
    write_fixture( $uname, "#!/bin/sh\nprintf '%s\\n' Linux\n" );
    chmod 0755, $uname or die "Unable to make $uname executable: $!";

    for my $source (
        $library, $loader, repo_path("xCAT/postscripts/$caller")
      )
    {
        my $filename = ( File::Spec->splitpath($source) )[2];
        my $destination = File::Spec->catfile( $tmpdir, $filename );
        copy( $source, $destination )
          or die "Unable to stage $source as $destination: $!";
        chmod 0755, $destination
          or die "Unable to make $destination executable: $!";
    }

    my $bash_env = File::Spec->catfile( $tmpdir, 'bash-env.sh' );
    write_fixture(
        $bash_env,
        <<'SH'
logger()
{
    case " $* " in
        *" NFSSERVER="*)
            size=$(array_get_size os_path)
            index=0
            while [ "$index" -lt "$size" ]; do
                array_get_element os_path "$index"
                index=$((index + 1))
            done > "$XCAT_REPOSITORY_PATH_TRACE"
            exit 73
            ;;
    esac
    return 0
}
SH
    );

    local %ENV = %ENV;
    delete @ENV{
        qw(HTTPPORT KERNELDIR MASTER NODESETSTATE OTHERPKGDIR OSPKGDIR VERBOSE)
    };
    $ENV{ARCH} = 'x86_64';
    $ENV{BASH_ENV} = $bash_env;
    $ENV{INSTALLDIR} = 'INSTALLDIR';
    $ENV{NFSSERVER} = 'package-test-server';
    $ENV{OSVER} = $osver;
    $ENV{PATH} = "$bindir:$ENV{PATH}";
    $ENV{UPDATENODE} = 1;
    $ENV{XCAT_REPOSITORY_PATH_TRACE} = $trace;
    if ( $caller eq 'ospkgs' ) {
        $ENV{OSPKGS} = 'package-test';
        delete @ENV{qw(OTHERPKGS OTHERPKGS_INDEX)};
    } else {
        $ENV{OTHERPKGS_INDEX} = 1;
        delete @ENV{qw(OSPKGS)};
    }

    my $script = File::Spec->catfile( $tmpdir, $caller );
    my $status = system($script);
    die "Unable to execute $script: $!" if $status == -1;
    die "$script terminated by signal " . ( $status & 127 )
      if $status & 127;
    die "$script exited unexpectedly with " . ( $status >> 8 )
      unless ( $status >> 8 ) == 73;

    my $contents = read_fixture($trace);
    chomp($contents);
    return split /\n/, $contents;
}

sub write_fixture {
    my ( $path, $contents ) = @_;
    open( my $fh, '>:raw', $path )
      or die "Unable to open $path for writing: $!";
    print {$fh} $contents or die "Unable to write $path: $!";
    close($fh) or die "Unable to close $path: $!";
}

sub read_fixture {
    my ($path) = @_;
    open( my $fh, '<:raw', $path )
      or die "Unable to open $path for reading: $!";
    my $contents = do { local $/; <$fh> };
    die "Unable to read $path: $!" unless defined $contents;
    close($fh) or die "Unable to close $path: $!";
    return $contents;
}
