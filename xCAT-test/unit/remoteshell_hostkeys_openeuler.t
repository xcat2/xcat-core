#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

plan skip_all => 'requires Linux root and mount namespaces' unless $^O eq 'linux' && $> == 0;
plan skip_all => 'mount namespaces unavailable' if system('unshare -m -- true >/dev/null 2>&1');
plan skip_all => 'requires native ssh-keygen' unless -x '/usr/bin/ssh-keygen';
my $source = $ENV{XCAT_HOSTKEY_SOURCE_ROOT} || abs_path("$FindBin::Bin/../..");
my $tmp = tempdir(DIR => '/var/tmp', CLEANUP => 1);
chmod 0700, $tmp;
make_path("$tmp/keys", "$tmp/bin");

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die "$path: $!";
}
sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    return <$fh> // '';
}
sub public_identity {
    my ($path) = @_;
    my @fields = split /\s+/, read_file($path);
    return join(' ', @fields[0, 1]) if @fields >= 2;
    return '';
}

my @types = qw(dsa rsa ecdsa ed25519);
for my $type (@types) {
    my $rc = system('/usr/bin/ssh-keygen', '-q', '-t', $type, '-f', "$tmp/keys/$type", '-N', '', '-C', '');
    BAIL_OUT("native ssh-keygen cannot generate disposable $type fixture") if $rc;
}
for my $name (qw(remoteshell xcatlib.sh remoteshell-sshd-config)) {
    copy("$source/xCAT/postscripts/$name", "$tmp/bin/$name") or die $!;
    chmod 0755, "$tmp/bin/$name";
}
write_file("$tmp/bin/namespace", <<'SH');
#!/bin/bash
set -e
mount --make-rprivate /
mount --bind "$XCAT_KEY_FIXTURE/etc" /etc
mount --bind "$XCAT_KEY_FIXTURE/root" /root
mount --bind "$XCAT_KEY_FIXTURE/tmp" /tmp
exec "$@"
SH
write_file("$tmp/bin/getcredentials.awk", <<'SH');
#!/bin/bash
case "$1" in
    ssh_dsa_hostkey) cat "$XCAT_KEY_INPUT/dsa" ;;
    ssh_rsa_hostkey) cat "$XCAT_KEY_INPUT/rsa" ;;
    ssh_ecdsa_hostkey) cat "$XCAT_KEY_INPUT/ecdsa" ;;
    ssh_ed25519_hostkey) cat "$XCAT_KEY_INPUT/ed25519" ;;
    ssh_root_pub_key) cat "$XCAT_KEY_INPUT/rsa.pub" ;;
    *) printf '<error>unexpected credential request</error>\n'; exit 1 ;;
esac
SH
write_file("$tmp/bin/allowcred.awk", "#!/bin/sh\nexec /bin/sleep 60\n");
write_file("$tmp/bin/logger", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >> \"\$XCAT_KEY_FIXTURE/logger.log\"\n");
write_file("$tmp/bin/systemctl", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >> \"\$XCAT_KEY_FIXTURE/services.log\"\nexit 0\n");
write_file("$tmp/bin/sleep", "#!/bin/sh\nexit 0\n");
for my $command (qw(chown chmod)) {
    write_file("$tmp/bin/$command", "#!/bin/bash\n" .
        'if [ "$XCAT_KEY_FAIL_COMMAND" = "${0##*/}" ] && [[ "${!#}" = "/etc/ssh/ssh_host_${XCAT_KEY_FAIL_TYPE}_key" ]]; then exit 42; fi' . "\n" .
        'exec /usr/bin/' . $command . ' "$@"' . "\n");
}
for my $name (qw(namespace getcredentials.awk allowcred.awk logger systemctl sleep chown chmod)) {
    chmod 0755, "$tmp/bin/$name";
}

for my $case (
    ['native fresh', 'openeuler24.03sp3', 'openEuler', 1, 0],
    ['native existing', 'openeuler20.03sp4', 'openEuler', 1, 1],
    ['native no ssh_keys group', 'openeuler24.03', 'openEuler', 0, 1],
    ['native os-release fallback', '', 'openEuler', 1, 1],
    ['legacy with ssh_keys group', 'rhels9.6', 'rhel', 1, 0],
    ['legacy without ssh_keys group', 'rhels9.6', 'rhel', 0, 0],
    ['native chmod failure', 'openeuler24.03sp3', 'openEuler', 1, 1, 'chmod', 'dsa'],
    ['native chown failure', 'openeuler24.03sp3', 'openEuler', 1, 1, 'chown', 'ed25519'],
) {
    my ($label, $osver, $id, $group, $existing, $fail_command, $fail_type) = @$case;
    my $fixture = tempdir(DIR => $tmp, CLEANUP => 1);
    make_path(map { "$fixture/$_" } qw(etc/ssh root tmp));
    write_file("$fixture/etc/passwd", "root:x:0:0:root:/root:/bin/bash\n");
    write_file("$fixture/etc/group", "root:x:0:\n" . ($group ? "ssh_keys:x:4242:\n" : ''));
    write_file("$fixture/etc/nsswitch.conf", "passwd: files\ngroup: files\n");
    write_file("$fixture/etc/os-release", "ID=$id\n");
    write_file("$fixture/etc/ssh/sshd_config", "Port 22\n");
    write_file("$fixture/etc/ssh/ssh_config", "Host *\n");
    for my $type (@types) {
        next unless $existing;
        my $key = "$fixture/etc/ssh/ssh_host_${type}_key";
        copy("$tmp/keys/$type", $key) or die $!;
        chmod 0640, $key;
        chown 0, 4242, $key;
    }
    for my $run (1, 2) {
        my $output;
        my $rc;
        {
            local %ENV = (%ENV, PATH => "$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                OSVER => $osver, MASTER => '192.0.2.1', USEFLOWCONTROL => 'NO',
                NTYPE => 'compute', ENABLESSHBETWEENNODES => 'NO', NODESETSTATE => 'netboot',
                SECUREROOT => '0', ZONENAME => '', XCAT_KEY_FIXTURE => $fixture,
                XCAT_KEY_INPUT => "$tmp/keys", XCAT_SSH_ETC => '/etc/ssh',
                XCAT_KEY_FAIL_COMMAND => $fail_command || '', XCAT_KEY_FAIL_TYPE => $fail_type || '');
            open(my $pipe, '-|', 'sh', '-c', 'exec "$@" 2>&1', 'sh',
                'unshare', '-m', '--', "$tmp/bin/namespace", "$tmp/bin/remoteshell") or die $!;
            $output = do { local $/; <$pipe> };
            close($pipe);
            $rc = $? >> 8;
        }
        if ($fail_command) {
            is($rc, 1, "$label run $run reports failed key protection");
            like(read_file("$fixture/logger.log"), qr/failed to secure .*ssh_host_${fail_type}_key/, "$label run $run identifies the failed key");
            ok(!-e "$fixture/etc/ssh/ssh_host_${fail_type}_key.pub", "$label run $run stops before public key derivation");
            is(read_file("$fixture/services.log"), '', "$label run $run stops before service restart");
            next;
        }
        is($rc, 0, "$label run $run completes the full postscript");
        my $native = $id eq 'openEuler';
        if ($native || !$group) {
            unlike($output, qr/UNPROTECTED PRIVATE KEY|bad permissions/, "$label run $run has no permission rejection");
            for my $type (@types) {
                my $key = "$fixture/etc/ssh/ssh_host_${type}_key";
                is(sha256_hex(read_file($key)), sha256_hex(read_file("$tmp/keys/$type")), "$label run $run preserves provisioned $type identity");
                is(sha256_hex(public_identity("$key.pub")), sha256_hex(public_identity("$tmp/keys/$type.pub")), "$label run $run derives the matching $type public key");
                my @private = stat($key);
                my @public = stat("$key.pub");
                is_deeply([defined($private[2]) ? $private[2] & 0777 : undef, @private[4,5]], [0600, 0, 0], "$label run $run $type private ownership and mode");
                is_deeply([defined($public[2]) ? $public[2] & 0777 : undef, $public[4]], [0644, 0], "$label run $run $type public ownership and mode");
            }
        } else {
            my @rsa = stat("$fixture/etc/ssh/ssh_host_rsa_key");
            is_deeply([$rsa[2] & 0777, @rsa[4,5]], [0640, 0, 4242], "$label run $run retains the legacy permission chain");
        }
        like(read_file("$fixture/services.log"), qr/^restart sshd(?:\.service)?$/m, "$label run $run reaches the service command boundary");
    }
}
done_testing();
