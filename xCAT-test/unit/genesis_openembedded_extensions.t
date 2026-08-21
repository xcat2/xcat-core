#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $loader = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-extensions files genesis-sysext)
);
my $signer = File::Spec->catfile(
    $repo_root, qw(xCAT-genesis-builder oe scripts sign-extension)
);
my $exporter = File::Spec->catfile(
    $repo_root, qw(xCAT-genesis-builder oe export-extension)
);
my $extension_recipe = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-extensions xcat-genesis-extensions_1.0.bb)
);

sub write_file {
    my ( $path, $contents, $mode ) = @_;
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh);
    chmod( $mode, $path ) if defined($mode);
}

sub shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub run_command {
    my (@command) = @_;
    my $shell_command = join( ' ', map { shell_quote($_) } @command );
    my $output = qx{$shell_command 2>&1};
    return ( $? >> 8, $output );
}

sub write_manifest {
    my ( $path, $hash, $changes ) = @_;
    my $manifest = {
        architecture   => 'x86_64',
        capabilities   => ['diagnostic.smoke'],
        genesis_release => '0.1',
        kernel_modules => JSON::PP::false,
        kernel_release => undef,
        key_id          => 'xcat-release',
        license_class   => 'open',
        name            => 'xcat-smoke',
        pci_ids         => [],
        schema          => 1,
        sha256          => $hash,
        version         => '1.0',
    };
    @{$manifest}{ keys %{$changes} } = values %{$changes};
    write_file( $path, JSON::PP->new->canonical->pretty->encode($manifest) );
}

my $root = tempdir( CLEANUP => 1 );
my $bin = File::Spec->catdir( $root, 'bin' );
my $keys = File::Spec->catdir( $root, 'keys' );
my $run_dir = File::Spec->catdir( $root, 'run' );
my $image = File::Spec->catfile( $root, 'xcat-smoke.squashfs-zst' );
my $manifest = File::Spec->catfile( $root, 'xcat-smoke.manifest.json' );
my $signature = File::Spec->catfile( $root, 'xcat-smoke.sig' );
my $private_key = File::Spec->catfile( $root, 'private.pem' );
my $public_key = File::Spec->catfile( $keys, 'xcat-release.pem' );
my $os_release = File::Spec->catfile( $root, 'os-release' );
my $command_log = File::Spec->catfile( $root, 'commands.log' );
my $status_log = File::Spec->catfile( $root, 'status.log' );

make_path( $bin, $keys, $run_dir );
write_file( $image, "extension payload\n" );
write_file( $os_release, "ID=xcat-genesis\nVERSION_ID=0.1\n" );
write_file( $command_log, '' );
write_file( $status_log, '' );
write_file(
    File::Spec->catfile( $bin, 'systemd-sysext' ),
    "#!/bin/sh\nprintf 'systemd-sysext %s\\n' \"\$*\" >>\"\$XCAT_TEST_LOG\"\n",
    0755
);
write_file(
    File::Spec->catfile( $bin, 'genesis-status' ),
    "#!/bin/sh\nprintf '%s\\n' \"\$*\" >>\"\$XCAT_STATUS_LOG\"\n",
    0755
);

is( system( 'openssl', 'genpkey', '-algorithm', 'ED25519', '-out', $private_key ) >> 8,
    0, 'test private key is generated' );
is( system( 'openssl', 'pkey', '-in', $private_key, '-pubout', '-out', $public_key ) >> 8,
    0, 'test public key is generated' );

my ( $hash_status, $hash_output ) = run_command( 'sha256sum', '--', $image );
is( $hash_status, 0, 'extension digest is generated' );
my ($hash) = $hash_output =~ /^([0-9a-f]{64})/;
write_manifest( $manifest, $hash, {} );

my ( $sign_status, $sign_output ) =
  run_command( $signer, $manifest, $private_key, $signature );
is( $sign_status, 0, 'extension manifest is signed' ) or diag($sign_output);

my $deploy = File::Spec->catdir( $root, 'deploy' );
my $machine = 'xcat-genesis-x86-64';
my $extension = 'xcat-genesis-extension-smoke';
my $stem = "$extension-$machine";
my $machine_dir = File::Spec->catdir( $deploy, 'images', $machine );
my $bundle = File::Spec->catdir( $root, 'bundle' );
make_path($machine_dir);
copy( $image, File::Spec->catfile( $machine_dir, "$stem.squashfs-zst" ) )
  or die "Unable to stage extension image: $!";
copy( $manifest, File::Spec->catfile( $machine_dir, "$stem.manifest.json" ) )
  or die "Unable to stage extension manifest: $!";
my ( $export_status, $export_output ) = run_command(
    $exporter, 'x86_64', $extension, $deploy,
    $private_key, $public_key, $bundle
);
is( $export_status, 0, 'built extension exports as a signed bundle' )
  or diag($export_output);
for my $artifact (
    [ extensions => "$stem.squashfs-zst" ],
    [ extensions => "$stem.manifest.json" ],
    [ extensions => "$stem.sig" ],
    [ 'extension-keys' => 'xcat-release.pem' ],
) {
    ok( -f File::Spec->catfile( $bundle, @{$artifact} ),
        "extension bundle includes $artifact->[1]" );
}
my ( $bundle_checksum_status, undef ) = run_command(
    'sh', '-c', 'cd "$1" && sha256sum -c SHA256SUMS >/dev/null',
    'sh', $bundle
);
is( $bundle_checksum_status, 0, 'extension bundle checksums verify' );

local %ENV = (
    %ENV,
    PATH                            => "$bin:$ENV{PATH}",
    XCAT_GENESIS_EXTENSION_KEY_DIR => $keys,
    XCAT_GENESIS_EXTENSION_RUN_DIR => $run_dir,
    XCAT_GENESIS_OS_RELEASE        => $os_release,
    XCAT_GENESIS_STATUS_COMMAND    => File::Spec->catfile( $bin, 'genesis-status' ),
    XCAT_GENESIS_UNAME_M           => 'x86_64',
    XCAT_GENESIS_UNAME_R           => '6.18.24-test',
    XCAT_TEST_LOG                  => $command_log,
    XCAT_STATUS_LOG                => $status_log,
);

my ( $verify_status, $verify_output ) =
  run_command( '/bin/bash', $loader, 'verify', $manifest, $image, $signature );
is( $verify_status, 0, 'valid extension is accepted' ) or diag($verify_output);

{
    local $ENV{XCAT_GENESIS_UNAME_M} = 'i586';
    my $x86_manifest = File::Spec->catfile( $root, 'xcat-smoke-x86.json' );
    my $x86_signature = File::Spec->catfile( $root, 'xcat-smoke-x86.sig' );
    write_manifest( $x86_manifest, $hash, { architecture => 'x86' } );
    my ( $x86_sign_status, $x86_sign_output ) =
      run_command( $signer, $x86_manifest, $private_key, $x86_signature );
    is( $x86_sign_status, 0, 'x86 extension manifest is signed' )
      or diag($x86_sign_output);
    my ( $x86_status, $x86_output ) = run_command(
        '/bin/bash', $loader, 'verify', $x86_manifest, $image, $x86_signature
    );
    is( $x86_status, 0, 'i586 runtime uses the x86 extension identity' )
      or diag($x86_output);
}

{
    local $ENV{XCAT_GENESIS_UNAME_M} = 'armv7l';
    my $arm_manifest = File::Spec->catfile( $root, 'xcat-smoke-armv7hf.json' );
    my $arm_signature = File::Spec->catfile( $root, 'xcat-smoke-armv7hf.sig' );
    write_manifest( $arm_manifest, $hash, { architecture => 'armv7hf' } );
    my ( $arm_sign_status, $arm_sign_output ) =
      run_command( $signer, $arm_manifest, $private_key, $arm_signature );
    is( $arm_sign_status, 0, 'armv7hf extension manifest is signed' )
      or diag($arm_sign_output);
    my ( $arm_status, $arm_output ) = run_command(
        '/bin/bash', $loader, 'verify', $arm_manifest, $image, $arm_signature
    );
    is( $arm_status, 0, 'armv7l runtime uses the armv7hf extension identity' )
      or diag($arm_output);
}

my ( $install_status, $install_output ) =
  run_command( '/bin/bash', $loader, 'install', $manifest, $image, $signature );
is( $install_status, 0, 'valid extension is installed' ) or diag($install_output);
ok( -f File::Spec->catfile( $run_dir, 'xcat-smoke.raw' ),
    'installed image uses the manifest name' );
open( my $log_fh, '<', $command_log ) or die "Unable to read $command_log: $!";
my $log = do { local $/; <$log_fh> };
close($log_fh);
like( $log, qr/^systemd-sysext refresh$/m,
    'installation refreshes system extensions' );

my ( $load_status, $load_output ) =
  run_command( '/bin/bash', $loader, 'load-all', $root );
is( $load_status, 0, 'valid extension directory is loaded' )
  or diag($load_output);
open( my $status_fh, '<', $status_log )
  or die "Unable to read $status_log: $!";
my $status_events = do { local $/; <$status_fh> };
close($status_fh);
like( $status_events,
    qr/^extensions RUNNING Verifying Genesis extensions$/m,
    'extension loading publishes its active state' );
like( $status_events,
    qr/^extensions READY Genesis extensions loaded$/m,
    'extension loading publishes its ready state' );

my $bad_signature = File::Spec->catfile( $root, 'bad.sig' );
write_file( $bad_signature, 'x' x 64 );
my ( $bad_signature_status, undef ) =
  run_command( '/bin/bash', $loader, 'verify', $manifest, $image, $bad_signature );
isnt( $bad_signature_status, 0, 'invalid signature is rejected' );

for my $case (
    [ architecture => 'riscv64', 'wrong architecture is rejected' ],
    [ genesis_release => '9.9', 'wrong release is rejected' ],
    [ sha256 => ( '0' x 64 ), 'wrong digest is rejected' ],
    [ kernel_modules => JSON::PP::true, 'wrong kernel ABI is rejected',
      kernel_release => '0.0-wrong' ],
  )
{
    my ( $field, $value, $label, @extra ) = @{$case};
    my %changes = ( $field => $value, @extra );
    my $case_manifest = File::Spec->catfile( $root, "$field.json" );
    my $case_signature = File::Spec->catfile( $root, "$field.sig" );
    write_manifest( $case_manifest, $hash, \%changes );
    my ( $case_sign_status, $case_sign_output ) =
      run_command( $signer, $case_manifest, $private_key, $case_signature );
    is( $case_sign_status, 0, "$field manifest is signed" )
      or diag($case_sign_output);
    my ( $case_status, undef ) =
      run_command( '/bin/bash', $loader, 'verify', $case_manifest, $image,
        $case_signature );
    isnt( $case_status, 0, $label );
}

my $linked_manifest = File::Spec->catfile( $root, 'linked.json' );
symlink( $manifest, $linked_manifest ) or die "Unable to link $linked_manifest: $!";
my ( $linked_status, undef ) =
  run_command( '/bin/bash', $loader, 'verify', $linked_manifest, $image,
    $signature );
isnt( $linked_status, 0, 'linked manifest is rejected' );

my $empty_dir = File::Spec->catdir( $root, 'empty' );
make_path($empty_dir);
write_file( $status_log, '' );
my ( $empty_status, undef ) =
  run_command( '/bin/bash', $loader, 'load-all', $empty_dir );
isnt( $empty_status, 0, 'empty extension directory is rejected' );
open( $status_fh, '<', $status_log )
  or die "Unable to read $status_log: $!";
$status_events = do { local $/; <$status_fh> };
close($status_fh);
like( $status_events,
    qr/^extensions FAILED no extension manifests found in:/m,
    'extension loading publishes verification failures' );
like( $status_events,
    qr/CODE=EXTENSION_VERIFICATION_FAILED .*RECOVERY=Check extension images, manifests, signatures, and trusted keys/m,
    'extension failures include structured recovery data' );

my $recipe_text = do {
    open( my $fh, '<', $extension_recipe )
      or die "Unable to read $extension_recipe: $!";
    local $/;
    <$fh>;
};
like( $recipe_text, qr/\$\{localstatedir\}\/lib\/xcat\/genesis\/extensions/,
    'the image creates the extension staging directory' );
like( $recipe_text, qr/^XCAT_GENESIS_EXTENSION_BUNDLE \?\?= ""$/m,
    'site layers can stage an exported extension bundle' );

done_testing();
