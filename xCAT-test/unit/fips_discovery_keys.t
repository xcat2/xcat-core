#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));
my @key_generators = (
    'xCAT-genesis-scripts/usr/bin/doxcat',
    'xCAT/postscripts/documulusdiscovery',
);

foreach my $file (@key_generators) {
    my $source = read_file($file);
    like(
        $source,
        qr{
            Generating\ private\ key
            .*?grep\ -q\ '\^1\$'\ /proc/sys/crypto/fips_enabled
            .*?openssl\ ecparam\ -name\ prime256v1\ -genkey
            .*?else
            .*?openssl\ genrsa[^\n]*\b1024\b
        }xs,
        "$file selects P-256 only in FIPS mode"
    );
}

foreach my $file (
    @key_generators,
    'xCAT-genesis-scripts/usr/bin/dodiscovery',
) {
    my $source = read_file($file);
    like(
        $source,
        qr{
            if\ grep\ -q\ '\^1\$'\ /proc/sys/crypto/fips_enabled
            .*?PUBKEY=.*?openssl\ ec\ -in\ /etc/xcat/privkey\.pem\ -pubout
            .*?else
            .*?PUBKEY=.*?openssl\ rsa\ -in\ /etc/xcat/privkey\.pem\ -pubout
        }xs,
        "$file exports the matching FIPS or legacy public key"
    );
}

my $openssl = qx(command -v openssl 2>/dev/null);
chomp($openssl);
SKIP: {
    skip 'openssl is not available', 6 unless $openssl && -x $openssl;

    my $tmpdir  = tempdir(CLEANUP => 1);
    my $key     = File::Spec->catfile($tmpdir, 'discovery-key.pem');
    my $public  = File::Spec->catfile($tmpdir, 'discovery-key.pub');
    my $packet  = File::Spec->catfile($tmpdir, 'discovery-packet');
    my $signature = File::Spec->catfile($tmpdir, 'discovery-packet.sha512');

    is(
        system(
            $openssl, 'ecparam', '-name', 'prime256v1',
            '-genkey', '-noout', '-out', $key
        ),
        0,
        'OpenSSL generates the selected FIPS discovery key'
    );

    my $key_text = command_output($openssl, 'ec', '-in', $key, '-text', '-noout');
    like($key_text, qr/Private-Key: \(256 bit\)/,
        'generated discovery key uses P-256');

    is(system($openssl, 'ec', '-in', $key, '-pubout', '-out', $public), 0,
        'OpenSSL derives the discovery public key');
    my $public_pem = read_absolute_file($public);
    my $public_body = $public_pem;
    $public_body =~ s/-----[^-]+-----//g;
    $public_body =~ s/\s+//g;
    # lldpad reads the configured system description into a 256-byte buffer.
    cmp_ok(length($public_body), '<=', 255,
        'compact public key fits the lldpad system-description buffer');

    write_file($packet, "<xcatrequest><command>findme</command></xcatrequest>\n");
    is(system($openssl, 'dgst', '-sha512', '-sign', $key, '-out', $signature, $packet), 0,
        'OpenSSL signs a discovery request with SHA-512');
    is(system($openssl, 'dgst', '-sha512', '-verify', $public, '-signature', $signature, $packet), 0,
        'OpenSSL verifies the discovery request signature');
}

done_testing();

sub command_output {
    my @command = @_;
    open(my $fh, '-|', @command) or die "run @command: $!";
    my $output = do { local $/; <$fh> };
    close($fh) or die "close @command: $!";
    return $output;
}

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile($repo_root, split m{/}, $file);
    return read_absolute_file($path);
}

sub read_absolute_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "open $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $contents;
}

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "open $path: $!";
    print {$fh} $contents;
    close($fh) or die "close $path: $!";
}
