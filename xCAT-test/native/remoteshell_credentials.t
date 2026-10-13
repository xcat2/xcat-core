#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';
die 'install openssl for the remoteshell postscript' unless -x '/usr/bin/openssl';
my $postscripts = repo_path('xCAT/postscripts');
my $keys = sandbox_root();
my @types = qw(dsa rsa ecdsa ed25519);
my %public_keys;
for my $type (@types) {
    my ($rc, $output) = run_command('ssh-keygen', '-q', '-t', $type,
        '-f', "$keys/$type", '-N', '', '-C', '');
    die "cannot generate $type fixture: $output" if $rc;
    $public_keys{$type} = read_binary("$keys/$type.pub");
    $public_keys{$type} =~ s/\s+\z//;
}
my $hash = '$6$saltsalt$hashhashhash';

sub write_stub {
    my ($path, $body) = @_;
    write_binary($path, "#!/bin/sh\n$body");
    chmod 0755, $path or die "chmod $path: $!";
}

sub read_optional {
    my ($path) = @_;
    return -f $path ? scalar read_binary($path) : '';
}

sub reply {
    my ($content) = @_;
    return "<xcatresponse>\n<data>\n<content>\n$content</content>\n</data>\n</xcatresponse>\n"
        . "<xcatresponse>\n<serverdone></serverdone>\n</xcatresponse>\n";
}

sub run_remoteshell {
    my (%opt) = @_;
    my $root = sandbox_root();
    make_path(map { "$root/$_" } qw(etc/ssh etc/systemd/system root/.ssh xcatpost replies));
    make_path("$root/tmp/ssh_dsa_hostkey") if $opt{blocked_staging};
    my $passwd = "root:x:0:0::/root:/bin/bash\n";
    $passwd .= "runner:x:$>:0::/root:/bin/bash\n" if $>;
    write_binary("$root/etc/passwd", $passwd);
    write_binary("$root/etc/group", "root:x:0:\n");
    write_binary("$root/etc/nsswitch.conf", "passwd: files\ngroup: files\n");
    write_binary("$root/etc/os-release", "ID=almalinux\n");
    write_binary("$root/etc/ssh/sshd_config", "Port 22\n");
    write_binary("$root/etc/ssh/ssh_config", "Host *\n");
    write_binary("$root/etc/systemd/system/sshd.service", "[Service]\n");
    for my $type (@types) {
        write_binary("$root/replies/ssh_${type}_hostkey", reply(read_binary("$keys/$type")));
    }
    my $zone = $opt{zone} ? ":$opt{zone}" : '';
    my $public = "$public_keys{rsa} fixture &lt;node&gt; &apos;\n";
    write_binary("$root/replies/ssh_root_pub_key$zone", reply($public));
    write_binary("$root/replies/ssh_root_key$zone", reply(read_binary("$keys/rsa")));
    write_binary("$root/replies/xcat_secure_pw:root",
        "<xcatresponse>\n<content>$hash</content>\n</xcatresponse>\n");
    if ($opt{error}) {
        for my $path (glob "$root/replies/*") {
            next if $opt{error} eq 'root' && $path !~ /xcat_secure_pw:root$/;
            write_binary($path, "<xcatresponse>\n<error>denied &lt;node&gt; &apos;</error>\n</xcatresponse>\n");
        }
    }
    write_stub("$root/bin/getcredentials.awk", <<'SH');
echo "getcredentials $*" >> /fixture/calls
count=$(grep -c -x -F "getcredentials $*" /fixture/calls)
[ "$count" -le "$EMPTY_REPLIES" ] && exit 0
cat "/fixture/replies/$1"
SH
    write_stub("$root/bin/allowcred.awk", "exec /bin/sleep 30\n");
    write_stub("$root/bin/sleep", "echo \"sleep \$*\" >> /fixture/calls\n");
    write_stub("$root/bin/logger", "echo \"\$*\" >> /fixture/messages\n");
    write_stub("$root/bin/systemctl", "echo \"systemctl \$*\" >> /fixture/calls\n");
    write_stub("$root/bin/usermod", "echo \"usermod \$*\" >> /fixture/calls\n");
    write_stub("$root/xcatpost/xcatflowrequest",
        "echo \"flow \$*\" >> /fixture/calls\nexit \${FLOW_STATUS:-0}\n");
    my ($rc, $output) = sandbox_run($root, {
        read_only => {$postscripts => '/postscripts', "$root/xcatpost" => '/xcatpost'},
        writable => {"$root/root" => '/root'},
        env => {MASTER => '192.0.2.1', OSVER => 'rhels8', NTYPE => 'compute',
            ENABLESSHBETWEENNODES => 'YES', NODESETSTATE => 'netboot', SECUREROOT => '1',
            UPDATENODE => '0', ZONENAME => $opt{zone} || '',
            USEFLOWCONTROL => $opt{flow} ? 'YES' : 'NO', FLOW_STATUS => $opt{flow_status} || 0,
            EMPTY_REPLIES => $opt{empty} || 0}},
        '/bin/bash', '/postscripts/remoteshell');
    diag($output) if $rc || $output =~ /bwrap:/;
    return {root => $root, rc => $rc, output => $output,
        calls => read_optional("$root/calls"), log => read_optional("$root/messages")};
}

for my $case (
    ['initial replies', {}],
    ['retried replies', {empty => 1, flow => 1, zone => 'zone-a'}],
    ['flow failure', {empty => 1, flow => 1, flow_status => 1}],
    ['unwritable staging path', {blocked_staging => 1, flow => 1}],
) {
    my ($label, $options) = @$case;
    subtest $label => sub {
        my $r = run_remoteshell(%$options);
        is($r->{rc}, 0, 'full postscript completes');
        for my $type (@types) {
            is(read_optional("$r->{root}/etc/ssh/ssh_host_${type}_key"),
                read_binary("$keys/$type"), "$type private key is unchanged");
            is(read_optional("$r->{root}/etc/ssh/ssh_host_${type}_key.pub"),
                "$public_keys{$type}\n", "$type public key is derived by ssh-keygen");
            is(scalar(() = $r->{calls} =~ /^getcredentials ssh_${type}_hostkey$/mg),
                $options->{empty} || ($type eq 'dsa' && $options->{blocked_staging}) ? 2 : 1,
                "$type request count");
        }
        is(read_optional("$r->{root}/root/.ssh/id_rsa"), read_binary("$keys/rsa"),
            'root private key is unchanged');
        my $public = "$public_keys{rsa} fixture <node> '\n";
        is(read_optional("$r->{root}/root/.ssh/id_rsa.pub"), $public, 'public key comment is decoded');
        is(read_optional("$r->{root}/root/.ssh/authorized_keys"), $public, 'authorized key is decoded');
        my $zone = $options->{zone} ? ":$options->{zone}" : '';
        is(scalar(() = $r->{calls} =~ /^getcredentials ssh_root_pub_key\Q$zone\E$/mg),
            $options->{empty} ? 3 : 1, 'root public key retains its separate retry requests');
        is(scalar(() = $r->{calls} =~ /^getcredentials ssh_root_key\Q$zone\E$/mg),
            $options->{empty} ? 2 : 1, 'root private key request count');
        is(scalar(() = $r->{calls} =~ /^getcredentials xcat_secure_pw:root$/mg),
            $options->{empty} ? 2 : 1, 'secure root request count');
        like($r->{calls}, qr/^usermod -p \Q$hash\E root$/m, 'root receives the password field');
        unlike($r->{log} . $r->{output}, qr/\Q$hash\E/, 'password field is not logged or printed');
        like($r->{calls}, qr/^systemctl restart sshd/m, 'script reaches the SSH service boundary');
        my @sleeps = $r->{calls} =~ /^sleep (\d+)$/mg;
        is(shift @sleeps, 1, 'credential listener startup delay is retained');
        is(scalar @sleeps, $options->{flow_status} ? 7 : 0, 'only failed flow control adds retry delays');
        ok(!grep($_ < 10 || $_ > 19, @sleeps), 'retry delays are in the existing range');
        is(scalar(() = $r->{calls} =~ /^flow /mg),
            $options->{flow_status} ? 1 : $options->{blocked_staging} ? 8 : $options->{flow} ? 14 : 0,
            'remoteshell disables flow control after a failed request');
    };
}

for my $case (['initial errors', 0, 'all'], ['retry error', 1, 'root'], ['exhausted retries', 20, '']) {
    my ($label, $empty, $error) = @$case;
    subtest $label => sub {
        my $r = run_remoteshell(empty => $empty, error => $error, flow => 1);
        is($r->{rc}, 0, 'caller completes after a credential failure');
        unlike($r->{calls}, qr/^usermod /m, 'failed password retrieval does not change root');
        is(scalar(() = $r->{calls} =~ /^getcredentials xcat_secure_pw:root$/mg),
            $empty == 20 ? 10 : $empty + 1, 'root keeps its retry limit and error stop');
        if ($error) {
            like($r->{log}, qr/Failed to acquire secure root password: denied <node> '/,
                'server error survives filtering and decoding');
        } else {
            like($r->{log}, qr/Too many retries/, 'retry exhaustion is logged');
        }
        if ($error eq 'all' || $empty == 20) {
            for my $type (@types) {
                ok(!-s "$r->{root}/etc/ssh/ssh_host_${type}_key", "no unusable $type key installed");
                is(scalar(() = $r->{calls} =~ /^getcredentials ssh_${type}_hostkey$/mg),
                    $empty == 20 ? 10 : 1, "$type retry limit");
            }
            is(read_optional("$r->{root}/root/.ssh/authorized_keys"), '', 'no authorized key is installed');
        }
    };
}

done_testing();
