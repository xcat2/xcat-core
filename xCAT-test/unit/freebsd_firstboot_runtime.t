#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use MIME::Base64 qw(encode_base64);
use POSIX qw(WNOHANG);
use Test::More;
use Time::HiRes qw(time sleep);

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR} || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my %children;

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $content;
    close($fh) or die "$path: $!";
}

sub read_file {
    my $path = shift;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    my $data = <$fh>;
    close($fh) or die "$path: $!";
    return $data;
}

sub wait_for {
    my ($predicate, $seconds) = @_;
    my $deadline = time() + $seconds;
    while (time() < $deadline) {
        return 1 if $predicate->();
        sleep 0.02;
    }
    return $predicate->() ? 1 : 0;
}

sub wait_exit {
    my ($pid, $seconds) = @_;
    my $status;
    wait_for(sub {
        return 0 unless waitpid($pid, WNOHANG) == $pid;
        $status = $? >> 8;
        delete $children{$pid};
        return 1;
    }, $seconds);
    return $status;
}

sub fixture {
    my $root = tempdir(CLEANUP => 1);
    make_path(map { "$root/$_" } qw(bin etc/ssh usr/sbin var/run root));
    write_file("$root/etc/ssh/sshd_config", "UsePAM yes\n");
    write_file("$root/etc/rc.subr", <<'RC');
load_rc_config()
{
    xcatfirstboot_enable=$(cat "$FIXTURE_DIR/enabled")
}
run_rc_command()
{
    case "$1" in
        start) [ "$xcatfirstboot_enable" = YES ] || return 0; "$start_cmd" ;;
        report) "$report_cmd" ;;
        *) return 1 ;;
    esac
}
RC
    write_file("$root/bin/pw", "#!/bin/sh\nexit 0\n");
    write_file("$root/bin/sysrc", <<'SYSRC');
#!/bin/sh
for value in "$@"; do
    case "$value" in xcatfirstboot_enable=*) printf '%s\n' "${value#*=}" > "$FIXTURE_DIR/enabled" ;; esac
done
SYSRC
    write_file("$root/bin/date", "#!/bin/sh\nif [ -f \"\$FIXTURE_DIR/clock\" ]; then cat \"\$FIXTURE_DIR/clock\"; else printf '0\\n'; fi\n");
    write_file("$root/bin/sleep", "#!$^X\n" . <<'SLEEP');
use strict;
use warnings;
use Time::HiRes ();
my $path = "$ENV{FIXTURE_DIR}/clock";
my $now = 0;
if (open(my $in, '<', $path)) { $now = <$in>; close($in); }
open(my $out, '>', $path) or die $!;
print {$out} $now + $ARGV[0], "\n";
close($out) or die $!;
Time::HiRes::sleep(0.02);
SLEEP
    write_file("$root/bin/nc", "#!$^X\n" . <<'NC');
use strict;
use warnings;
my ($protocol, $generation, $attempt, $phase) = split(' ', scalar(<STDIN>));
open(my $events, '>>', "$ENV{FIXTURE_DIR}/requests") or die $!;
print {$events} "$protocol $generation $attempt $phase\n";
close($events) or die $!;
print "ready\n";
if (open(my $ack, '<', "$ENV{FIXTURE_DIR}/ack")) {
    my $mode = <$ack>;
    close($ack);
    $generation = 'c' x 32 unless $mode eq "matching\n";
    print "freebsd-install-v1 $generation $phase ok\n";
}
NC
    write_file("$root/usr/sbin/daemon", "#!$^X\n" . <<'DAEMON');
use strict;
use warnings;
use Fcntl qw(:flock);
use POSIX qw(setsid);
exit 73 if -f "$ENV{FIXTURE_DIR}/deny-daemon";
die "unexpected daemon arguments" unless shift(@ARGV) eq '-f';
my $syslog = @ARGV && $ARGV[0] eq '-S' ? shift(@ARGV) : '';
die "unexpected daemon arguments" unless shift(@ARGV) eq '-p';
my $pidfile = shift @ARGV;
open(my $lock, '>>', $pidfile) or die $!;
exit 3 unless flock($lock, LOCK_EX | LOCK_NB);
my $pid = fork();
die $! unless defined($pid);
exit 0 if $pid;
setsid() >= 0 or die $!;
open(STDIN, '<', '/dev/null') or die $!;
open(STDOUT, '>', $syslog ? "$ENV{FIXTURE_DIR}/syslog" : '/dev/null') or die $!;
open(STDERR, '>&', \*STDOUT) or die $!;
truncate($lock, 0) or die $!;
print {$lock} "$$\n";
open(my $started, '>>', "$ENV{FIXTURE_DIR}/workers") or die $!;
print {$started} "worker\n";
close($started);
system @ARGV;
my $status = $? >> 8;
open(my $result, '>', "$ENV{FIXTURE_DIR}/worker-exit") or die $!;
print {$result} "$status\n";
close($result);
unlink($pidfile) or die $!;
close($lock);
exit $status;
DAEMON
    chmod 0755, map { "$root/$_" } qw(bin/pw bin/sysrc bin/date bin/sleep bin/nc usr/sbin/daemon);
    local %ENV = (%ENV, FIXTURE_DIR => $root, PATH => "$root/bin:$ENV{PATH}",
        XCAT_WORK => "$root/work", XCAT_FILESYSTEM => 'zfs', XCAT_TARGET_DISK => 'vtbd0', XCAT_SWAP_SIZE => 0,
        XCAT_MASTER => '127.0.0.1', XCAT_PORT => 3002, XCAT_GENERATION => 'a' x 32, XCAT_ATTEMPT => 'b' x 32,
        XCAT_HOSTNAME => 'node01.example.test', XCAT_PROVISIONING_IF => 'em0', XCAT_IPV4 => '192.0.2.20',
        XCAT_NETMASK => '255.255.255.0', XCAT_GATEWAY => '', XCAT_NAMESERVERS => '',
        XCAT_AUTHORIZED_KEY_BASE64 => encode_base64('fixture public key', ''));
    open(my $render, '-|', 'sh', '-c', '. "$1"; xcat_write_installer "$2" "$1"',
        'sh', "$directory/xcat-install-lib.sh", "$directory/installerconfig.tmpl") or die $!;
    local $/;
    my $installer = <$render>;
    close($render) or die 'installer rendering failed';
    my (undef, $postscript) = split(/(?=^#!)/m, $installer, 2);
    die 'missing generated postscript' unless defined($postscript);
    $postscript =~ s{(?<![A-Za-z0-9_.+-])/(usr/local|usr/sbin/daemon|etc|root|var)(?=/|[\s"'])}{$root/$1}g;
    write_file("$root/postscript", $postscript);
    is(system('sh', "$root/postscript"), 0, 'production-generated postscript installs a service in an isolated filesystem');
    return $root;
}

sub start_service {
    my $root = shift;
    my $pid = fork();
    die $! unless defined($pid);
    if (!$pid) {
        $ENV{FIXTURE_DIR} = $root;
        $ENV{PATH} = "$root/bin:$ENV{PATH}";
        open(STDOUT, '>', "$root/start.log") or die $!;
        open(STDERR, '>&', \*STDOUT) or die $!;
        exec 'sh', "$root/usr/local/etc/rc.d/xcatfirstboot", 'start';
        die $!;
    }
    $children{$pid} = 1;
    return $pid;
}

{
    my $root = fixture();
    my $pending = read_file("$root/var/db/xcat/firstboot");
    my $first = start_service($root);
    is(wait_exit($first, 1), 0, 'service start returns while the controller is unavailable') or diag(read_file("$root/start.log"));
    ok(wait_for(sub { -s "$root/requests" }, 1), 'detached worker calls the production status protocol');
    is(read_file("$root/var/db/xcat/firstboot"), $pending, 'missing acknowledgment retains the pending marker');
    ok(!-e "$root/var/db/xcat/firstboot.done", 'no done marker appears before acknowledgment');
    write_file("$root/ack", "wrong-generation\n");
    sleep 0.15;
    ok(!-e "$root/var/db/xcat/firstboot.done", 'wrong-generation acknowledgments are rejected by xcat_status');
    my $second = start_service($root);
    my $duplicate_status = wait_exit($second, 1);
    ok(defined($duplicate_status) && $duplicate_status != 0, 'pidfile rejects a concurrent service start');
    is(read_file("$root/workers"), "worker\n", 'only one reporter is launched');
    write_file("$root/ack", "matching\n");
    ok(wait_for(sub { -e "$root/var/db/xcat/firstboot.done" }, 3), 'matching acknowledgment completes the marker');
    is(read_file("$root/var/db/xcat/firstboot.done"), $pending, 'completion preserves generation and attempt');
    ok(!-e "$root/var/db/xcat/firstboot", 'successful acknowledgment consumes the pending marker');
    ok(wait_for(sub { read_file("$root/enabled") eq "NO\n" }, 1), 'successful acknowledgment disables the service');
    ok(wait_for(sub { !-e "$root/var/run/xcatfirstboot.pid" }, 1), 'worker exit releases its pidfile');
    wait_exit($_, 2) for grep { exists($children{$_}) } ($first, $second);
}

{
    my $root = fixture();
    my $pid = start_service($root);
    is(wait_exit($pid, 1), 0, 'unavailable-controller start does not wait for the retry deadline');
    ok(wait_for(sub { -f "$root/worker-exit" }, 10), 'production retry policy eventually stops its worker');
    is(read_file("$root/worker-exit"), "1\n", 'exhausted acknowledgment retries fail');
    like(read_file("$root/syslog"), qr/Controller did not acknowledge booted/, 'daemon retains the production status failure diagnostic');
    is(read_file("$root/clock"), "900\n", 'worker retains the fifteen-minute retry policy');
    ok(-e "$root/var/db/xcat/firstboot" && !-e "$root/var/db/xcat/firstboot.done", 'timeout leaves installation reporting pending');
    is(read_file("$root/enabled"), "YES\n", 'timeout keeps the service enabled for a later boot');
    wait_exit($pid, 2) if exists($children{$pid});
}

{
    my $root = fixture();
    write_file("$root/deny-daemon", '');
    my $pid = start_service($root);
    is(wait_exit($pid, 1), 73, 'daemon launch failure propagates');
    ok(-e "$root/var/db/xcat/firstboot" && !-e "$root/requests", 'launch failure preserves the marker without reporting');
    unlink "$root/var/db/xcat/firstboot" or die $!;
    is(wait_exit(start_service($root), 1), 0, 'no pending marker is a no-op even if daemon launch is unavailable');
}

END {
    my $process_status = $?;
    for my $pid (keys %children) {
        kill 'TERM', $pid;
        waitpid($pid, 0);
    }
    $? = $process_status;
}

done_testing();
