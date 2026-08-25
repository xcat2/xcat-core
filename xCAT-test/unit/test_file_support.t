#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $readme_relative = File::Spec->catfile( 'xCAT-test', 'unit', 'README.md' );
my $expected_root = abs_path( File::Spec->catdir( $FindBin::Bin, File::Spec->updir(), File::Spec->updir() ) );
my $readme_path = repo_path($readme_relative);
ok( File::Spec->file_name_is_absolute($readme_path), 'repo_path returns an absolute path' );
is( $readme_path, File::Spec->catfile( $expected_root, $readme_relative ), 'repo_path resolves from the checkout root' );

my $readme = slurp_repo_file($readme_relative);
like( $readme, qr/^# xCAT-test\/unit\n.*\n.*source tree/s, 'multiline text contents are preserved' );

is( slurp_repo_file('xCAT-genesis-builder/cmdlist_check'), '', 'empty file contents are preserved' );

my $favicon = slurp_repo_file('xCAT-UI/images/favicon.ico');
is( length($favicon), 5686, 'binary file length is preserved' );
is( substr( $favicon, 0, 8 ), "\x00\x00\x01\x00\x02\x00\x10\x10", 'binary file signature is preserved' );

my $original_cwd = getcwd();
chdir File::Spec->tmpdir() or die "Unable to change directory: $!";
is( slurp_repo_file($readme_relative), $readme, 'file reads do not depend on cwd' );
chdir $original_cwd or die "Unable to restore directory: $!";

SKIP: {
    my $relative_link = 'xCAT-server/share/xcat/netboot/rocky/compute.rocky10.x86_64.pkglist';
    my $relative_target = 'xCAT-server/share/xcat/netboot/rh/compute.rhels10.x86_64.pkglist';
    skip 'repository symlink fixture is unavailable', 1 unless -l repo_path($relative_link);
    is( slurp_repo_file($relative_link), slurp_repo_file($relative_target), 'file reads follow repository symlinks' );
}

my $missing_relative = 'xCAT-test/unit/does-not-exist';
my $missing_path = repo_path($missing_relative);
eval { slurp_repo_file($missing_relative) };
like( $@, qr/Unable to open \Q$missing_path\E for reading:/, 'open failures identify the resolved repository path' );

my $directory_relative = 'xCAT-test/unit';
my $directory_path = repo_path($directory_relative);
eval { slurp_repo_file($directory_relative) };
like( $@, qr/Unable to read \Q$directory_path\E:/, 'read failures identify the resolved repository path' );

foreach my $invalid ( '', File::Spec->rootdir(), File::Spec->catfile( 'xCAT-test', File::Spec->updir(), 'README' ) ) {
    eval { repo_path($invalid) };
    like( $@, qr/^Repository/, 'repo_path rejects paths outside its relative-path contract' );
}
eval { repo_path(undef) };
like( $@, qr/^Repository-relative path is required/, 'repo_path rejects an undefined path' );

my $child_code = <<'PERL';
BEGIN {
    no warnings 'redefine';
    *CORE::GLOBAL::close = sub (*) {
        $! = 5;
        return 0;
    };
}
use XCAT::Test::File qw(slurp_repo_file);
eval { slurp_repo_file($ARGV[0]) };
print $@;
PERL

open(
    my $child,
    '-|',
    $^X,
    '-I' . repo_path('xCAT-test/lib'),
    '-e',
    $child_code,
    $readme_relative,
) or die "Unable to start close-failure probe: $!";
my $close_error = do { local $/; <$child> };
close($child) or die "Close-failure probe failed: $?";
like( $close_error, qr/Unable to close \Q$readme_path\E:/, 'close failures identify the resolved repository path' );

done_testing();
