#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $recipe = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-xcat xcat-genesis-bmcsetup xcat-genesis-bmcsetup_1.0.bb)
);
my $wrapper = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-xcat xcat-genesis-bmcsetup files genesis-bmcsetup)
);
my $credential_wait = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-xcat xcat-genesis-bmcsetup files genesis-credential-wait)
);
my $image_recipe = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core images xcat-genesis-image.bb)
);
my $legacy_dir = File::Spec->catdir(
    $repo_root, qw(xCAT-genesis-scripts usr bin)
);

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

sub write_file {
    my ( $path, $contents, $mode ) = @_;
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh);
    chmod( $mode, $path );
}

for my $script (qw(bmcsetup getipmi remoteimmsetup)) {
    is(
        system(
            '/bin/bash', '-n',
            File::Spec->catfile( $legacy_dir, $script )
        ) >> 8,
        0,
        "$script is valid Bash"
    );
}
is( system( '/bin/bash', '-n', $wrapper, $credential_wait ) >> 8,
    0, 'BMC action helpers are valid Bash' );

my $root = tempdir( CLEANUP => 1 );
my $support_dir = File::Spec->catdir( $root, 'support' );
my $implementation = File::Spec->catfile( $root, 'implementation' );
my $log = File::Spec->catfile( $root, 'wrapper.log' );
make_path($support_dir);
write_file(
    $implementation,
    <<'SH', 0755
#!/bin/bash
printf 'path=%s\n' "$PATH" >"$XCAT_TEST_LOG"
printf 'arguments=%s\n' "$*" >>"$XCAT_TEST_LOG"
SH
);
local %ENV = (
    %ENV,
    XCAT_BMC_SUPPORT_DIR        => $support_dir,
    XCAT_BMC_SETUP_IMPLEMENTATION => $implementation,
    XCAT_TEST_LOG               => $log,
);
is( system( '/bin/bash', $wrapper, 'first', 'second' ) >> 8,
    0, 'BMC action starts the packaged implementation' );
my $wrapper_log = read_file($log);
like( $wrapper_log, qr/^path=\Q$support_dir\E:/m,
    'BMC support commands take precedence' );
like( $wrapper_log, qr/^arguments=first second$/m,
    'BMC action preserves its arguments' );

my $recipe_text = read_file($recipe);
for my $source (qw(bmcsetup getipmi remoteimmsetup updateflag.awk)) {
    like( $recipe_text, qr/file:\/\/\Q$source\E\b/,
        "$source is sourced from the existing Genesis implementation" );
}
like( $recipe_text,
    qr{\$\{libexecdir\}/xcat/genesis/actions/bmcsetup},
    'bmcsetup is installed as an approved action' );
like( $recipe_text, qr/\bxcat-genesis-discovery\b/,
    'the BMC action uses the credential callback socket' );
like( $recipe_text, qr/\bgawk\b/,
    'the legacy status callback has its required awk implementation' );
like( read_file($image_recipe), qr/\bxcat-genesis-bmcsetup\b/,
    'the base Genesis image includes BMC setup' );

done_testing();
