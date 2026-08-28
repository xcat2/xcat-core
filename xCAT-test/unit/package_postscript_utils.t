#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(getcwd);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $postscripts = repo_path(File::Spec->catdir('xCAT', 'postscripts'));
my $library = File::Spec->catfile( $postscripts, 'xcatpkgutils.sh' );
my $loader = File::Spec->catfile( $postscripts, 'xcatpkgutils-loader.sh' );
my @callers = qw(ospkgs otherpkgs);

for my $required ( $library, $loader,
    map { File::Spec->catfile( $postscripts, $_ ) } @callers ) {
    -r $required or BAIL_OUT("$required is required");
}

is( system( 'sh', '-n', $library ), 0,
    'the package utility library has POSIX shell syntax' );
is( system( 'sh', '-n', $loader ), 0,
    'the package utility loader has POSIX shell syntax' );
for my $caller (@callers) {
    my $path = File::Spec->catfile( $postscripts, $caller );
    is( system( 'bash', '-n', $path ), 0,
        "$caller retains valid Bash syntax" );
}
is(
    system(
        'sh', '-c', '. "$1"; [ "${XCATPKGUTILS_LOADED:-}" = "1" ]',
        'package-postscript-utils-test', $library
    ),
    0,
    'the utility library loads under a POSIX shell'
);

my $tmpdir = tempdir( CLEANUP => 1 );
my $test_bin = File::Spec->catdir( $tmpdir, 'bin' );
make_path($test_bin);
my $logger = File::Spec->catfile( $test_bin, 'logger' );
write_text( $logger, "#!/bin/sh\nexit 0\n" );
chmod 0755, $logger or die "Unable to make $logger executable: $!";
my $uname = File::Spec->catfile( $test_bin, 'uname' );
write_text( $uname, "#!/bin/sh\nprintf '%s\\n' Linux\n" );
chmod 0755, $uname or die "Unable to make $uname executable: $!";
my @layouts = (
    [ 'source checkout with relative invocation', 'relative', qw(source postscripts) ],
    [ 'installed path with absolute invocation',   'absolute', qw(install postscripts) ],
    [ 'runtime path resolved through PATH',         'path',     qw(xcatpost) ],
);

for my $layout (@layouts) {
    my ( $name, $invocation, @parts ) = @{$layout};
    my $directory = File::Spec->catdir( $tmpdir, @parts );
    make_path($directory);
    stage_postscript_tree($directory);

    for my $caller (@callers) {
        my ( $status, $output );
        if ( $invocation eq 'relative' ) {
            ( $status, $output ) = run_in_directory( $directory, "./$caller" );
        } elsif ( $invocation eq 'absolute' ) {
            ( $status, $output ) = run_command(
                File::Spec->catfile( $directory, $caller )
            );
        } else {
            local $ENV{PATH} = "$directory:$ENV{PATH}";
            ( $status, $output ) = run_command($caller);
        }

        is( $status, 0, "$caller loads the package helpers from the $name" )
          or diag($output);
        like( $output, qr/no extra (?:rpms|packages) to install/,
            "$caller reaches normal behavior after loading from the $name" );
    }
}

for my $failure (
    [ 'missing', undef, qr/package utility library is not readable/ ],
    [
        'markerless', "# no marker\n",
        qr/package utility library did not finish loading/
    ],
    [ 'broken', "if then\n", qr/package utility library could not be loaded/ ],
) {
    my ( $name, $contents, $error ) = @{$failure};
    my $directory = File::Spec->catdir( $tmpdir, "$name-library" );
    make_path($directory);
    stage_callers_and_loader($directory);
    if ( defined($contents) ) {
        write_text( File::Spec->catfile( $directory, 'xcatpkgutils.sh' ), $contents );
    }

    for my $caller (@callers) {
        local $ENV{XCATPKGUTILS_LOADED};
        $ENV{XCATPKGUTILS_LOADED} = 1 if $name eq 'markerless';
        my ( $status, $output ) = run_command(
            File::Spec->catfile( $directory, $caller )
        );
        isnt( $status, 0,
            "$caller stops when the package utility library is $name" )
          or diag($output);
        like( $output, $error,
            "$caller explains why the $name package utility library cannot be used" );
        unlike( $output, qr/no extra (?:rpms|packages) to install/,
            "$caller stops before package processing with a $name utility library" );
    }
}

my $missing_loader_dir = File::Spec->catdir( $tmpdir, 'missing-loader' );
make_path($missing_loader_dir);
for my $caller (@callers) {
    my $destination = File::Spec->catfile( $missing_loader_dir, $caller );
    copy( File::Spec->catfile( $postscripts, $caller ), $destination )
      or die "Unable to stage $caller: $!";
    chmod 0755, $destination or die "Unable to make $destination executable: $!";
    my ( $status, $output ) = run_command($destination);
    isnt( $status, 0, "$caller stops when the package utility loader is missing" )
      or diag($output);
    like( $output, qr/package utility loader is not readable/,
        "$caller explains that the package utility loader is missing" );
    unlike( $output, qr/no extra (?:rpms|packages) to install/,
        "$caller stops before package processing without the shared loader" );
}

my $rpm_spec = slurp_repo_file('xCAT/xCAT.spec');
my $debian_install = slurp_repo_file('xCAT/debian/install');
like( $rpm_spec, qr{^/install/postscripts\s*$}m,
    'the RPM payload owns the complete postscripts directory' );
like( $debian_install, qr{^postscripts/\*\s+install/postscripts/\s*$}m,
    'the Debian payload installs every postscript helper' );

done_testing();

sub stage_postscript_tree {
    my ($directory) = @_;
    stage_callers_and_loader($directory);
    my $destination = File::Spec->catfile( $directory, 'xcatpkgutils.sh' );
    copy( $library, $destination )
      or die "Unable to stage xcatpkgutils.sh: $!";
    chmod 0755, $destination
      or die "Unable to make $destination executable: $!";
}

sub stage_callers_and_loader {
    my ($directory) = @_;
    for my $name ( @callers, 'xcatpkgutils-loader.sh' ) {
        my $source = File::Spec->catfile( $postscripts, $name );
        my $destination = File::Spec->catfile( $directory, $name );
        copy( $source, $destination ) or die "Unable to stage $name: $!";
        chmod 0755, $destination
          or die "Unable to make $destination executable: $!";
    }
}

sub run_in_directory {
    my ( $directory, @command ) = @_;
    my $original = getcwd();
    chdir($directory) or die "Unable to enter $directory: $!";
    my @result = run_command(@command);
    chdir($original) or die "Unable to return to $original: $!";
    return @result;
}

sub run_command {
    my (@command) = @_;
    my $pid = open( my $pipe, '-|' );
    die "Unable to fork for @command: $!" unless defined($pid);
    if ( $pid == 0 ) {
        delete @ENV{qw(OSPKGS OTHERPKGS OTHERPKGS_INDEX UPDATENODE NODESETSTATE)};
        $ENV{PATH} = "$test_bin:$ENV{PATH}";
        open( STDERR, '>&', STDOUT ) or die "Unable to merge stderr: $!";
        exec { $command[0] } @command;
        die "Unable to execute @command: $!";
    }

    my $output = do { local $/; <$pipe> } // '';
    close($pipe);
    return ( $? >> 8, $output );
}
