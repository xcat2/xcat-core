#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

use XCAT::Test::File qw(repo_path);

my $bash = qx(command -v bash 2>/dev/null);
chomp($bash);
my $sh = qx(command -v sh 2>/dev/null);
chomp($sh);
my $openssl = qx(command -v openssl 2>/dev/null);
chomp($openssl);
my $host_fips = 0;
if (-r '/proc/sys/crypto/fips_enabled') {
    $host_fips = read_text('/proc/sys/crypto/fips_enabled') =~ /^1\s*$/;
}

SKIP: {
    skip 'sh, bash, and openssl are required', 33
        unless $sh && -x $sh && $bash && -x $bash && $openssl && -x $openssl;

    foreach my $runtime (
        ['xCAT-genesis-scripts/usr/lib/xcat/fips.sh', $sh],
        ['xCAT/postscripts/xcatlib.sh', $bash],
    ) {
        my ($relative, $shell) = @{$runtime};
        my $library = repo_path($relative);
        my $tmpdir = tempdir(CLEANUP => 1);
        my $status = File::Spec->catfile($tmpdir, 'fips_enabled');
        my $missing = File::Spec->catfile($tmpdir, 'missing');
        my $packet = File::Spec->catfile($tmpdir, 'discovery-packet');
        write_text($packet, "<xcatrequest><command>findme</command></xcatrequest>\n");

        write_text($status, "1\n");
        is(shell_output($shell, $library, 'xcat_fips_state "$2"', $status), '1',
            "$relative recognizes enabled FIPS state");
        write_text($status, "0\n");
        is(shell_output($shell, $library, 'xcat_fips_state "$2"', $status), '0',
            "$relative recognizes disabled FIPS state");
        write_text($status, "1 0\n");
        is(shell_output($shell, $library, 'xcat_fips_state "$2"', $status), '0',
            "$relative rejects malformed FIPS state");
        is(shell_output($shell, $library, 'xcat_fips_state "$2"', $missing), '0',
            "$relative treats missing FIPS state as disabled");
        my $invalid_key = File::Spec->catfile($tmpdir, 'invalid-key.pem');
        isnt(shell_status($shell, $library,
                'xcat_generate_discovery_private_key invalid "$2"', $invalid_key), 0,
            "$relative rejects invalid private-key policy");
        isnt(shell_status($shell, $library,
                'xcat_discovery_public_key invalid "$2"', $invalid_key), 0,
            "$relative rejects invalid public-key policy");

        my $fips_key = File::Spec->catfile($tmpdir, 'fips-key.pem');
        my $fips_public = File::Spec->catfile($tmpdir, 'fips-key.pub');
        my $fips_signature = File::Spec->catfile($tmpdir, 'fips-signature');
        write_text($status, "1\n");
        is(run_key_cycle($shell, $library, $status, 0, $fips_key, $fips_public), 0,
            "$relative reuses enabled state for key generation and extraction");
        my $fips_key_text = command_output(
            $openssl, 'ec', '-in', $fips_key, '-text', '-noout'
        );
        like($fips_key_text, qr/Private-Key: \(256 bit\)/,
            "$relative generates a P-256 FIPS key");
        my $public_body = read_text($fips_public);
        $public_body =~ s/-----[^-]+-----//g;
        $public_body =~ s/\s+//g;
        # lldpad reads the system description into a 256-byte buffer.
        cmp_ok(length($public_body), '<=', 255,
            "$relative FIPS public key fits the lldpad description buffer");
        is(system($openssl, 'dgst', '-sha512', '-sign', $fips_key,
                '-out', $fips_signature, $packet), 0,
            "$relative FIPS key signs discovery data");
        is(system($openssl, 'dgst', '-sha512', '-verify', $fips_public,
                '-signature', $fips_signature, $packet), 0,
            "$relative FIPS public key verifies discovery data");

        SKIP: {
            skip 'legacy RSA is unavailable on a FIPS-enabled test host', 4
                if $host_fips;

            my $legacy_key = File::Spec->catfile($tmpdir, 'legacy-key.pem');
            my $legacy_public = File::Spec->catfile($tmpdir, 'legacy-key.pub');
            my $legacy_signature = File::Spec->catfile($tmpdir, 'legacy-signature');
            write_text($status, "0\n");
            is(run_key_cycle($shell, $library, $status, 1, $legacy_key, $legacy_public), 0,
                "$relative reuses disabled state for key generation and extraction");
            my $legacy_key_text = command_output(
                $openssl, 'rsa', '-in', $legacy_key, '-text', '-noout'
            );
            like($legacy_key_text, qr/Private-Key: \(1024 bit/,
                "$relative preserves the legacy RSA key size");
            is(system($openssl, 'dgst', '-sha512', '-sign', $legacy_key,
                    '-out', $legacy_signature, $packet), 0,
                "$relative legacy key signs discovery data");
            is(system($openssl, 'dgst', '-sha512', '-verify', $legacy_public,
                    '-signature', $legacy_signature, $packet), 0,
                "$relative legacy public key verifies discovery data");
        }
    }

    my $genesis_library = repo_path('xCAT-genesis-scripts/usr/lib/xcat/fips.sh');
    is(shell_status($sh, $genesis_library, 'xcat_dsa_allowed 0'), 0,
        'Genesis permits DSA outside FIPS mode');
    isnt(shell_status($sh, $genesis_library, 'xcat_dsa_allowed 1'), 0,
        'Genesis rejects DSA in FIPS mode');

    my $documulus = repo_path('xCAT/postscripts/documulusdiscovery');
    is(documulus_fips_state($bash, $documulus), $host_fips ? '1' : '0',
        'Cumulus discovery loads xcatlib and captures the host FIPS state');
}

done_testing();

sub shell_output {
    my ($shell, $library, $command, @arguments) = @_;
    return command_output(
        $shell, '-c', '. "$1"; ' . $command,
        'xcat-fips-test', $library, @arguments,
    );
}

sub shell_status {
    my ($shell, $library, $command, @arguments) = @_;
    system(
        $shell, '-c', '. "$1"; ' . $command,
        'xcat-fips-test', $library, @arguments,
    );
    return $? >> 8;
}

sub run_key_cycle {
    my ($shell, $library, $status, $next_state, $key, $public) = @_;
    my $command = <<'EOF';
. "$1"
fips_state=$(xcat_fips_state "$2")
printf '%s\n' "$3" > "$2"
xcat_generate_discovery_private_key "$fips_state" "$4" 2>/dev/null || exit
xcat_discovery_public_key "$fips_state" "$4" > "$5" 2>/dev/null
EOF
    system(
        $shell, '-c', $command,
        'xcat-fips-test', $library, $status, $next_state, $key, $public,
    );
    return $? >> 8;
}

sub documulus_fips_state {
    my ($bash, $script) = @_;
    my $command = <<'EOF';
exec 2>/dev/null
set -T
trap 'case "$BASH_COMMAND" in
    "cat > /tmp/helper.socat.sh"*) printf "%s" "$XCAT_FIPS_ENABLED"; exit 0 ;;
    cat*">"*|chmod*|socat*|mkdir*|logger*|openssl*|rm*|gzip*|mv*) exit 97 ;;
esac' DEBUG
. "$0"
exit 99
EOF
    return command_output($bash, '-c', $command, $script);
}

sub command_output {
    my @command = @_;
    open(my $fh, '-|', @command) or die "run @command: $!";
    my $output = do { local $/; <$fh> };
    close($fh) or die "close @command: $!";
    return $output;
}
