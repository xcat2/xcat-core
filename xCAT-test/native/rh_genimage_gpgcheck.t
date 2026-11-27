#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;
use XCAT::Test::ImageSandbox;
use XCAT::Test::Lifecycle ();
use XCAT::Test::RPM;

plan skip_all => 'Linux namespaces require Linux' unless $^O eq 'linux';
die('Run image signature tests as an unprivileged user') unless $>;

my $root = tempdir(CLEANUP => 1);
make_path("$root/home/keys");
chmod 0700, "$root/home/keys" or die $!;
local %ENV = (%ENV, HOME => "$root/home", GNUPGHOME => "$root/home/keys", LC_ALL => 'C');
END {
    local $?;
    system('gpgconf', '--homedir', "$root/home/keys", '--kill', 'gpg-agent') if defined $root;
}

for my $key (qw(trusted untrusted)) {
    XCAT::Test::Lifecycle::checked('gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
        '--quick-generate-key', "$key <xcat-${key}\@example.test>", 'rsa2048', 'sign', '0');
}
write_text("$root/trusted.key", XCAT::Test::Lifecycle::checked('gpg', '--armor', '--export', 'xcat-trusted@example.test'));

for my $role (qw(base extra)) {
    my $rpm = XCAT::Test::RPM->build_fixture('genimage-signature', '--define', "fixture_role $role");
    for my $signature (qw(unsigned trusted untrusted)) {
        my $repo = "$root/repos/$signature/$role";
        make_path($repo);
        my $package = "$repo/xcat-gpg-$role-1-1.noarch.rpm";
        copy($rpm, $package) or die "copy RPM: $!";
        if ($signature ne 'unsigned') {
            XCAT::Test::Lifecycle::checked('rpmsign', '--define', '__gpg /usr/bin/gpg',
                '--define', "_gpg_path $root/home/keys", '--define', "_gpg_name xcat-$signature\@example.test",
                '--define', '_gpg_digest_algo sha256', '--addsign', $package);
        }
        XCAT::Test::Lifecycle::checked('createrepo_c', $repo);
    }
}

for my $case (
    ['default accepts unsigned packages', 0, 'unsigned', 'unsigned', 1, 1],
    ['opt-in accepts trusted packages', 1, 'trusted', 'trusted', 1, 1],
    ['opt-in rejects unsigned OS packages', 1, 'unsigned', 'trusted', 0, 0],
    ['opt-in rejects untrusted OS packages', 1, 'untrusted', 'trusted', 0, 0],
    ['opt-in rejects unsigned extra packages', 1, 'trusted', 'unsigned', 1, 0],
    ['opt-in rejects untrusted extra packages', 1, 'trusted', 'untrusted', 1, 0],
) {
    subtest $case->[0] => sub {
        my ($label, $verify, $base, $extra, $base_ok, $extra_ok) = @$case;
        my $box = image_box($base, $extra, 1);
        my ($rc) = run_builder($box, $verify, '/install/extra');
        is($rc, 1, 'builder exits at the package-phase boundary') or diag($box->{builder_output});
        for my $role (qw(base extra)) {
            my $expected = $role eq 'base' ? $base_ok : $extra_ok;
            my $payload = "work/image/rootimg/usr/share/xcat-signature-test/$role";
            is(-f "$box->{root}/$payload" ? 1 : 0, $expected, "$role payload installation matches the signature policy")
                or diag($box->{builder_output});
            is($box->read($payload), "$role\n", "$role payload has the package contents") if -f "$box->{root}/$payload";
            if ($role eq 'extra' && !$base_ok) {
                ok(!-e "$box->{root}/work/extra.json", 'OS rejection stops before the extra-package transaction');
                next;
            }
            my $result = transaction($box, $role);
            next unless $result;
            is($result->{rc} == 0 ? 1 : 0, $expected, "$role DNF transaction has the expected result")
                or diag($result->{out}, $result->{err});
            like($result->{out} . $result->{err}, qr/(?:GPG check FAILED|not signed|Public key.*not installed)/i,
                "$role rejection reports a signature failure") unless $expected;
            check_repositories($box, $result, $verify,
                ['file:///install/base', $role eq 'extra' ? 'file:///install/extra/.' : ()]);
        }
    };
}

subtest 'opt-in without trusted keys' => sub {
    my $box = image_box('trusted', 'trusted', 0);
    my ($rc, $out, $err) = run_builder($box, 1, '/install/extra');
    isnt($rc, 0, 'builder fails without trusted keys');
    like($out . $err, qr/No trusted RPM signing keys are installed/, 'missing trust is diagnosed');
    ok(!-e "$box->{root}/work/base.json", 'no package transaction starts without trusted keys');
    ok(!-e "$box->{root}/work/image/rootimg/usr/share/xcat-signature-test/base", 'no OS payload is installed');
};

for my $local (0, 1) {
    subtest $local ? 'mixed otherpkgdir' : 'URL-only otherpkgdir' => sub {
        my @urls = ('https://repo.example.test/epel/', 'https://repo.example.test/extra/');
        my $box = image_box('trusted', 'trusted', 1);
        $box->write('work/capture-extra', '');
        my ($rc) = run_builder($box, 1, join(',', @urls, $local ? '/install/extra' : ()));
        is($rc, 1, 'builder exits at the package-phase boundary') or diag($box->{builder_output});
        my $base = transaction($box, 'base');
        is($base->{rc}, 0, 'the real OS transaction succeeds') if $base;
        my $extra = transaction($box, 'extra');
        check_repositories($box, $extra, 1, ['file:///install/base', @urls,
            $local ? 'file:///install/extra/.' : ()]) if $extra;
    };
}

done_testing();

sub image_box {
    my ($base, $extra, $trust) = @_;
    my $box = XCAT::Test::ImageSandbox->new(mounts => [
        '--uid', '0', '--gid', '0', '--cap-add', 'CAP_SYS_CHROOT', '--cap-add', 'CAP_MKNOD',
        '--dir', '/var', '--dir', '/root', '--setenv', 'HOME', '/root',
        '--ro-bind', "$root/repos/$base/base", '/install/base',
        '--ro-bind', "$root/repos/$extra/extra", '/install/extra',
    ]);
    make_path("$box->{root}/work/image/rootimg/bin");
    $box->write('etc/passwd', "root:x:0:0:root:/root:/bin/sh\n");
    $box->write('etc/group', "root:x:0:\n");
    $box->write('work/compute.pkglist', "xcat-gpg-base\n");
    $box->write('work/compute.otherpkgs.pkglist', "xcat-gpg-extra\n");
    $box->command($_, "exit 0\n") for qw(mount umount);
    $box->command('rpm', "exec /usr/bin/rpm --dbpath /work/trusted-rpmdb \"\$\@\"\n");
    $box->command('dnf', "exec /usr/bin/perl /repo/xCAT-test/native/fixtures/genimage-dnf-observer.pl \"\$\@\"\n");
    XCAT::Test::Lifecycle::checked('rpm', '--dbpath', "$box->{root}/work/trusted-rpmdb", '--initdb');
    if ($trust) {
        XCAT::Test::Lifecycle::checked('rpm', '--dbpath', "$box->{root}/work/trusted-rpmdb", '--import', "$root/trusted.key");
    }
    $box->write('work/expected-keys', XCAT::Test::Lifecycle::checked('rpm', '--dbpath',
        "$box->{root}/work/trusted-rpmdb", '-qa', '--qf', "%{DESCRIPTION}\n", 'gpg-pubkey*'));
    return $box;
}

sub run_builder {
    my ($box, $verify, $extra) = @_;
    my ($rc, $out, $err) = $box->run('perl', '/repo/xCAT-server/share/xcat/netboot/rh/genimage',
        '-a', 'x86_64', '-o', 'rhels9.6', '-p', 'compute', '--noupdate',
        '--pkglist', '/work/compute.pkglist', '--otherpkglist', '/work/compute.otherpkgs.pkglist',
        '--srcdir', '/install/base', '--otherpkgdir', $extra, '--rootimgdir', '/work/image',
        $verify ? '--gpgcheck' : (), 'signature-test-image');
    $box->{builder_output} = $out . $err;
    return ($rc, $out, $err);
}

sub transaction {
    my ($box, $role) = @_;
    unless (ok(-f "$box->{root}/work/$role.json", "$role transaction was observed")) {
        diag($box->{builder_output});
        return;
    }
    return decode_json($box->read("work/$role.json"));
}

sub check_repositories {
    my ($box, $result, $verify, $urls) = @_;
    my (%sections, $section);
    for my $line (split /\n/, $result->{config}) {
        if ($line =~ /^\[([^]]+)\]$/) { $section = $1; }
        elsif ($line =~ /^([^=]+)=(.*)$/ && defined $section) { $sections{$section}{$1} = $2; }
        elsif ($line !~ /^\s*$/) { die "Unexpected repository configuration: $line"; }
    }
    delete $sections{main};
    is_deeply([sort map { $_->{baseurl} } values %sections], [sort @$urls], 'only the requested repositories are generated');
    for my $id (sort keys %sections) {
        my $repo = $sections{$id};
        is($repo->{gpgcheck}, "$verify", "$id has the requested signature policy");
        if ($verify) {
            my $key = $repo->{gpgkey} // '';
            $key =~ s{^file://}{};
            is($result->{keys}{$key}, $box->read('work/expected-keys'), "$id uses the exported trusted RPM keys");
        } else {
            ok(!exists $repo->{gpgkey}, "$id does not export keys by default");
        }
    }
}
