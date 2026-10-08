#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use JSON qw(decode_json);
use Test::More;
use XCAT::Test::ImageSandbox;

plan skip_all => 'Linux namespaces require Linux' unless $^O eq 'linux';
BAIL_OUT('Run the image caller tests as an unprivileged user') unless $>;

for my $os (qw(rhels10.1 alma10.1 rocky10.1)) {
    for my $arch (qw(x86_64 aarch64 ppc64le)) {
        subtest "$os $arch media import" => sub {
            my $box = XCAT::Test::ImageSandbox->new();
            $box->write('work/media/.discinfo', "1\nRed Hat Enterprise Linux 10.1\n$arch\n1\n");
            $box->write('work/media/.treeinfo', "[general]\nfamily = Red Hat Enterprise Linux\n");
            $box->write('work/media/package-marker', 'media bytes');
            $box->write('etc/os-release', "ID=rhel\nVERSION_ID=10.1\n");
            my ($rc, $output, $error) = $box->run('perl', '/repo/xCAT-test/native/fixtures/el10-copycd-driver.pl', $os, $arch);
            is($rc, 0, 'complete copycd caller succeeds twice') or diag($output, $error);
            for my $pass (1, 2) {
                my $file = "work/result-$pass.json";
                ok(-f "$box->{root}/$file", "import $pass produces a netboot image record") or next;
                my $result = decode_json($box->read($file));
                is_deeply($result->{errors}, [], "import $pass has no callback errors");
                is($result->{pkgdir}, "/install/$os/$arch", "import $pass uses only imported media");
                my %packages = map { $_ => 1 } @{ $result->{packages}{1}{'.'} || [] };
                ok($packages{NetworkManager}, "import $pass selects NetworkManager");
                ok(!$packages{dhclient} && !$packages{'dhcp-client'}, "import $pass excludes removed DHCP clients");
            }
            is($box->read("install/$os/$arch/package-marker"), 'media bytes', 'media bytes reach the package directory');
            ok(!-e "$box->{root}/install/dhcp_pkgs", 'import creates no hidden package directory');
        };
    }
}

for my $release (8, 9, 10) {
    for my $action (1, 2) {
        subtest "EL$release RPM installation $action" => sub {
            my $box = XCAT::Test::ImageSandbox->new(mounts => ['--tmpfs', '/usr/sbin']);
            $box->write('etc/os-release', "ID=rhel\nVERSION_ID=$release.1\n");
            $box->write('etc/redhat-release', "Red Hat Enterprise Linux release $release.1\n");
            make_path(map { "$box->{root}/work/xcat/$_" } qw(sbin share/xcat/install share/xcat/netboot share/xcat/scripts));
            my $compat = $box->write('work/xcat/share/xcat/scripts/xcatd-init-compat', <<'SH');
#!/bin/sh
printf '%s\n' "$*" >>/work/service-actions
case "$*" in
    uses-systemd*|can-use-systemctl|configure*|unregister-legacy) exit 0 ;;
    legacy-state) printf 'disabled\n' ;;
    *) exit 97 ;;
esac
SH
            chmod(0755, $compat) or die "chmod: $!";
            my $chtab = $box->write('work/xcat/sbin/chtab', "#!/bin/sh\nexit 0\n");
            chmod(0755, $chtab) or die "chmod: $!";
            $box->command('systemctl', "printf '%s\\n' \"\$*\" >>/work/systemctl-actions\n");
            for my $command (qw(dnf dnf5 microdnf yum curl wget)) {
                $box->command($command, "printf '%s\\n' '$command' >>/work/downloads\nexit 97\n");
            }
            for my $phase (qw(PREIN POSTIN POSTTRANS)) {
                my ($parse_rc, $script, $parse_error) = $box->run('rpmspec', '-q', '--qf', "%{$phase}",
                    '--define', 'version 2.19.0', '--define', 'release 1',
                    '--define', "rhel $release", '/repo/xCAT-server/xCAT-server.spec');
                is($parse_rc, 0, "RPM parses the complete $phase script") or diag($script, $parse_error);
                $box->write('work/scriptlet', $script);
                my ($rc, $output, $error) = $box->run('env', 'RPM_INSTALL_PREFIX0=/work/xcat',
                    'sh', '/work/scriptlet', $action);
                is($rc, 0, "$phase succeeds") or diag($output, $error);
                is($error, '', "$phase has no hidden command errors");
                ok(!-e "$box->{root}/work/downloads", "$phase does not invoke a package downloader");
                ok(!-e "$box->{root}/install/dhcp_pkgs", "$phase creates no hidden package directory");
            }
            ok(-s "$box->{root}/work/service-actions", 'installation reaches service setup');
        };
    }
}
done_testing();
