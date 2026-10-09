#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use File::Path qw(make_path);
use POSIX qw(getgid);
use XCAT::Test::Lifecycle;
use XCAT::Test::RPM;

plan skip_all => 'Run as an ordinary user on Linux; missing package or namespace tools fail'
    unless $^O eq 'linux' && $< != 0;
my $debian = -f '/etc/debian_version';

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag "$result[1]$result[2]";
    unlike($result[2], qr/scriptlet failed|scriptlet failure/i, "$label completes scriptlets");
}

sub serve_headers {
    my ($root, $configuration) = @_;
    my $modules = $debian ? '/usr/lib/apache2/modules' : '/usr/lib64/httpd/modules';
    my $apache = $debian ? '/usr/sbin/apache2' : '/usr/sbin/httpd';
    my $headers = $debian ? 'IncludeOptional /etc/apache2/mods-enabled/headers.load'
        : "LoadModule headers_module $modules/mod_headers.so";
    $root->write('/test-httpd.conf', "ServerRoot /tmp\nServerName localhost\nListen 127.0.0.1:8080\n" .
        "LoadModule mpm_event_module $modules/mod_mpm_event.so\n" .
        "LoadModule authz_core_module $modules/mod_authz_core.so\nLoadModule alias_module $modules/mod_alias.so\n" .
        "StartServers 1\nServerLimit 1\nThreadsPerChild 2\nMaxRequestWorkers 2\nMinSpareThreads 1\nMaxSpareThreads 2\n" .
        ($debian ? '' : "LoadModule unixd_module $modules/mod_unixd.so\n") .
        "$headers\nUser #$<\nGroup #" . getgid() . "\nPidFile /tmp/apache.pid\nErrorLog /tmp/apache.log\n" .
        "DocumentRoot /install\nInclude $configuration\n");
    $root->write('/install/probe.txt', "served fixture\n");
    $root->write('/tftpboot/probe.txt', "served fixture\n");
    local $root->{uid} = $<;
    local $root->{gid} = getgid();
    my @result = $root->run('/bin/sh', '-c', q{
        "$1" -f /test-httpd.conf -DFOREGROUND > /tmp/apache-output 2>&1 &
        server=$!
        trap 'kill "$server" 2>/dev/null; wait "$server" 2>/dev/null' EXIT
        attempt=0
        until curl --max-time 2 --connect-timeout 1 --noproxy '*' -fsS -D /tmp/headers http://127.0.0.1:8080/install/probe.txt > /tmp/body 2>/dev/null; do
            attempt=$((attempt + 1))
            if [ "$attempt" -ge 50 ] || ! kill -0 "$server" 2>/dev/null; then
                cat /tmp/apache-output /tmp/apache.log >&2
                exit 1
            fi
            sleep 0.1
        done
        cat /tmp/headers /tmp/body
        curl --max-time 2 --connect-timeout 1 --noproxy '*' -fsS -D - http://127.0.0.1:8080/tftpboot/probe.txt
    }, 'serve', $apache);
    succeeds('serve packaged Apache configuration', @result);
    my @responses = split /(?=HTTP\/1\.[01] 200)/, $result[1];
    @responses = grep { length } @responses;
    is(scalar @responses, 2, 'install and tftp endpoints both respond');
    for my $response (@responses) {
        like($response, qr/^X-Frame-Options: SAMEORIGIN\r?$/mi, 'framing policy is served');
        like($response, qr/^X-Content-Type-Options: nosniff\r?$/mi, 'content sniffing is disabled');
        like($response, qr/^Content-Security-Policy: script-src 'self' 'unsafe-eval'\r?$/mi, 'script policy is served');
        like($response, qr/^X-Permitted-Cross-Domain-Policies: none\r?$/mi, 'cross-domain policy is served');
        like($response, qr/served fixture\n\z/, 'the response contains the requested file');
    }
}

for my $package (qw(xCAT xCATsn)) {
    my $artifact = $debian ? XCAT::Test::Lifecycle::build_deb($package)
        : XCAT::Test::RPM->build($package, 1, '--define', 'rhel 8');
    for my $platform ($debian ? ('debian') : ('el', 'suse')) {
        for my $mode (qw(systemd legacy without-proc inactive), $debian ? () : ('proc-chroot')) {
            subtest "$package $platform $mode" => sub {
                my $root = $debian ? XCAT::Test::Lifecycle->new : XCAT::Test::RPM->new;
                $root->{live} = $mode ne 'without-proc';
                $root->{chroot} = $mode eq 'proc-chroot';
                my $gated = $mode eq 'without-proc' || $mode eq 'proc-chroot';
                if ($root->{chroot}) {
                    succeeds('proc exists but the process root differs', $root->run('/bin/sh', '-c',
                        q{test -f /proc/cmdline && outer=$(stat -c '%d:%i' /proc/1/root/.) && test -n "$outer" && test "$(stat -c '%d:%i' /)" != "$outer"}));
                }
                $root->write('/calls', '');
                for my $command (qw(xcatconfig restartxcatd)) {
                    $root->record_command("/opt/xcat/sbin/$command");
                }
                $root->record_command('/etc/init.d/xcatd') if $mode eq 'legacy';
                $root->write('/opt/xcat/share/xcat/scripts/xHRM', '');
                make_path($root->path('/install/postscripts'));
                make_path($root->path('/var/log/xcat'));
                make_path($root->path('/run/systemd/system')) unless $mode eq 'legacy';
                $root->write('/usr/sbin/systemctl', <<'SH', 0755);
#!/bin/sh
printf 'systemctl' >> /calls
for arg do printf ' <%s>' "$arg" >> /calls; done
printf '\n' >> /calls
if [ "$1" = is-active ]; then test ! -e /inactive; fi
SH
                $root->hide_command('systemctl') if $mode eq 'legacy';
                $root->write('/inactive', '') if $mode eq 'inactive';
                my $daemon = $platform eq 'el' ? 'httpd' : 'apache2';
                $root->record_command("/etc/init.d/$daemon") if $debian || $mode eq 'legacy';
                my $check_dispatch = sub {
                    my ($event) = @_;
                    my $calls = $root->read('/calls');
                    if ($package eq 'xCATsn') {
                        my $action = $debian ? 'start' : 'restart';
                        my $expected = $gated ? '' : $mode eq 'legacy' ? "xcatd <$action>\n" : "systemctl <$action> <xcatd.service>\n";
                        my $actual = join '', $calls =~ /^(xcatd[^\n]*\n|systemctl <(?:start|restart)> <xcatd.service>\n)/mg;
                        is($actual, $expected, "$event service-node daemon dispatch respects the init environment");
                    } else {
                        like($calls, $event eq 'install' ? qr/^xcatconfig <-i>$/m : qr/^xcatconfig <-u> <-V>$/m,
                            "$event selects the management configuration action");
                    }
                    if ($debian) {
                        like($calls, qr/^apache2 <restart>$/m, "$event management node requests Apache restart") if $package eq 'xCAT';
                        is(scalar(() = $calls =~ /^apache2 <reload>$/mg), $package eq 'xCATsn' && !$gated ? 1 : 0,
                            "$event service-node Apache reload requires proc");
                    } else {
                        is(scalar(() = $calls =~ /^a2enmod <headers>$/mg), $platform eq 'suse' ? 1 : 0,
                            "$event RPM enables headers when a2enmod exists");
                        my @reloads = $calls =~ /^(systemctl <reload> <$daemon(?:\.service)?>|$daemon <reload>)$/mg;
                        my $reload = !$gated && ($package eq 'xCATsn' || ($event eq 'upgrade' && $mode ne 'inactive'));
                        my $expected = $mode eq 'legacy' ? "$daemon <reload>" :
                            'systemctl <reload> <' . $daemon . ($package eq 'xCATsn' ? '.service' : '') . '>';
                        is_deeply(\@reloads, $reload ? [$expected] : [], "$event RPM Apache reload respects service activity and chroot state");
                    }
                };
                if ($debian) {
                    make_path($root->path('/var/lock'));
                    XCAT::Test::Lifecycle::checked('tar', '-cf', $root->path('/tmp/apache.tar'), '-C', '/', 'etc/apache2');
                    succeeds('stage native Apache settings', $root->run('tar', '-xf', '/tmp/apache.tar', '-C', '/'));
                    $root->write('/etc/apache2/envvars', $root->read('/etc/apache2/envvars') .
                        "\nexport APACHE_RUN_USER=root\nexport APACHE_RUN_GROUP=root\n");
                    succeeds('start with headers disabled', $root->run('a2dismod', '-f', 'headers'));
                    succeeds('native Apache version query', $root->run('apache2ctl', '-v'));
                    $root->record_command('/test-bin/update-rc.d');
                    local $root->{deb} = $artifact;
                    succeeds('unpack built Debian payload', $root->run('dpkg-deb', '-x', '/package.deb', '/'));
                    succeeds('configure built Debian package', $root->deb_script($artifact, 'postinst', 'configure'));
                    $check_dispatch->('install');
                    $root->write('/calls', '');
                    succeeds('prepare Debian upgrade', $root->deb_script($artifact, 'prerm', 'upgrade', '2.20.0')) if $package eq 'xCAT';
                    succeeds('configure Debian upgrade', $root->deb_script($artifact, 'postinst', 'configure', '2.18.0'));
                    $check_dispatch->('upgrade');
                } else {
                    $root->write('/etc/redhat-release', 'test') if $platform eq 'el';
                    $root->write("/usr/lib/systemd/system/$daemon.service", '') unless $mode eq 'legacy';
                    unlink $root->path('/usr/sbin/chkconfig') or die "unlink chkconfig fixture: $!";
                    $root->record_command('/usr/sbin/chkconfig');
                    $root->record_command('/usr/sbin/a2enmod') if $platform eq 'suse';
                    succeeds('install built RPM', $root->install($artifact));
                    $check_dispatch->('install');
                    $root->write('/calls', '');
                    succeeds('run RPM upgrade scriptlets', $root->install($artifact, '--replacepkgs'));
                    $check_dispatch->('upgrade');
                }
                $root->{chroot} = 0;
                serve_headers($root, $debian ? '/etc/apache2/conf-enabled/xcat.conf' : "/etc/$daemon/conf.d/xcat.conf");
            };
        }
    }
}
done_testing();
