#!/usr/bin/env perl
use strict;
use warnings;
use Capture::Tiny qw(capture);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_command);

plan skip_all => 'installer execution requires Linux' unless $^O eq 'linux';
die 'Install bubblewrap to run this test' unless -x '/usr/bin/bwrap';

sub executable {
    my ($path, $contents) = @_;
    write_binary($path, "#!/bin/sh\n$contents");
    chmod 0755, $path or die "Cannot chmod $path: $!";
    return;
}

sub fixture {
    my $root = sandbox_root();
    make_path(map { "$root/$_" } qw(bin db opt/xcat etc/systemd/system/multi-user.target.wants
        etc/init.d etc/rc2.d etc/rc.d/rc3.d etc/rc.d/rc4.d etc/rc.d/rc5.d
        xcatpost log/xcat boot));
    write_binary("$root/etc/hosts", "127.0.0.1 localhost\n");
    executable("$root/bin/service-control", <<'SH');
name=${0##*/}
[ "$*" != --version ] || exit 0
printf '%s|%s\n' "$name" "$*" >>/fixture/events
case "$name:$*" in
    systemctl:disable*|chkconfig:*off|update-rc.d:*remove)
        [ "${SERVICE_RC:-0}" -ne 0 ] || touch /fixture/disabled
        exit "${SERVICE_RC:-0}"
        ;;
esac
SH
    symlink('service-control', "$root/bin/$_") or die $!
        for qw(systemctl chkconfig update-rc.d);
    executable("$root/bin/download", <<'SH');
case "$*" in
    *mypostscript.node*) cp /fixture/downloaded /xcatpost/mypostscript.node ;;
esac
SH
    symlink('download', "$root/bin/$_") or die $! for qw(wget curl);
    executable("$root/bin/quiet", 'exit 0' . "\n");
    symlink('quiet', "$root/bin/$_") or die $!
        for qw(logger sleep ping updateflag.awk);
    executable("$root/bin/ip", "printf '1: eth0: link/ether 52:54:00:12:34:56\\n'\n");
    write_binary("$root/xcatpost/xcatlib.sh", <<'SH');
msgutil_r() { printf 'message|%s|%s|%s\n' "$1" "$2" "$3" >>/fixture/events; }
SH
    write_binary("$root/downloaded", <<'SH');
MASTER=192.0.2.1
MASTER_IP='192.0.2.1'
OSVER='rhels8'
RUNBOOTSCRIPTS='no'
NODESTATUS='no'
XCATDEBUGMODE='0'
SH
    return $root;
}

sub isolated {
    my ($root, $stage, $environment, @command) = @_;
    my %read_only = $stage eq 'render'
        ? (repo_path('xCAT/postscripts') => '/install/postscripts',
            repo_path('.') => repo_path('.')) : ();
    my @args = sandbox_command($root, {
        preserve_links => 1, directories => [qw(opt etc xcatpost boot)],
        tmpfs => ['/tmp'], read_only => \%read_only,
        env => {PATH => '/fixture/bin:/usr/bin:/bin:/usr/sbin:/sbin', %$environment},
    });
    local %ENV = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
    my ($out, $err, $status) = capture { system(@args, @command) };
    return ($status, $out . $err);
}

my @cases = (
    {name => 'disabled', run => 'no', status => 'no', disable => 1},
    {name => 'node reporting', run => 'no', status => 'yes', ubuntu_only => 1},
    {name => 'empty status defaults enabled', run => 'no', status => '', ubuntu_only => 1},
    {name => 'run enabled', run => 'yes', status => 'no'},
    {name => 'numeric run enabled', run => '1', status => 'no'},
    {name => 'short run enabled', run => 'Y', status => 'no'},
    {name => 'numeric node enabled', run => 'no', status => '1', ubuntu_only => 1},
    {name => 'short node enabled', run => 'no', status => 'Y', ubuntu_only => 1},
    {name => 'uppercase flags', run => 'NO', status => 'NO', disable => 1},
    {name => 'debug one', run => 'no', status => 'no', disable => 1, debug => 1},
    {name => 'debug two', run => 'no', status => 'no', disable => 1, debug => 2},
    {name => 'debug while retained', run => 'yes', status => 'no', debug => 1},
    {name => 'service failure', run => 'no', status => 'no', disable => 1, service_rc => 5},
    {name => 'postscript failure', run => 'no', status => 'no', disable => 1, post_rc => 7},
    {name => 'missing node file', run => 'no', status => 'no', no_node => 1, ubuntu_only => 1},
    {name => 'missing postboot file', no_post => 1, disable => 1},
);

{
    my $root = fixture();
    for my $stage (qw(render client)) {
        my ($status, $output) = isolated($root, $stage, {}, '/bin/sh', '-c',
            'test ! -e /etc/os-release && test ! -e /tmp/fixture-marker && '
            . 'printf private > /tmp/fixture-marker && '
            . 'if test -r /install/postscripts/xcatlib.sh; then printf visible; else printf hidden; fi');
        is($status, 0, "$stage has private configuration and temporary files");
        is($output, $stage eq 'render' ? 'visible' : 'hidden', "$stage retains its postscripts visibility");
        ($status, $output) = isolated($root, $stage, {}, '/bin/sh', '-c',
            'test -r "$1/Version"', 'visibility', repo_path('.'));
        is($status, $stage eq 'render' ? 0 : 1 << 8, "$stage retains its repository visibility");
    }
    my ($status, $output) = isolated($root, 'client', {}, '/bin/sh', '-c',
        'printf error >&2; printf output; exit 7');
    is_deeply([$status, $output], [7 << 8, 'outputerror'], 'retains raw status and stdout-before-stderr capture');
}

for my $owner (qw(post.xcat post.xcat.ng post.xcat.rhels10)) {
    my $build = fixture();
    my ($status, $output) = isolated($build, 'render', {}, $^X,
        repo_path('xCAT-test/native/fixtures/postinstall-render.pl'), $owner);
    is($status, 0, "$owner renders with the production renderer") or diag($output);
    ($status, $output) = isolated($build, 'client', {}, '/bin/bash', '-n', '/fixture/installer');
    is($status, 0, "$owner rendered installer parses") or diag($output);
    ($status, $output) = isolated($build, 'client', {}, '/bin/bash', '/fixture/installer');
    is($status, 0, "$owner executes the complete installer script") or diag($output);
    ok(-x "$build/opt/xcat/xcatinstallpost", "$owner emits the executable postboot script");
    ($status, $output) = isolated($build, 'client', {}, '/bin/bash', '-n', '/opt/xcat/xcatinstallpost');
    is($status, 0, "$owner emitted script parses") or diag($output);
    for my $os (qw(rhels8 ubuntu20.04)) {
        for my $case (@cases) {
            subtest "$owner $os $case->{name}" => sub {
                my $root = fixture();
                copy("$build/opt/xcat/xcatinstallpost", "$root/opt/xcat/xcatinstallpost") or die $!;
                my $run = $case->{run} // 'no';
                my $node = $case->{status} // 'no';
                my $debug = $case->{debug} // 0;
                my $post_rc = $case->{post_rc} // 0;
                write_binary("$root/xcatpost/mypostscript", "NODESTATUS='$node'\n") unless $case->{no_node};
                unless ($case->{no_post}) {
                    write_binary("$root/xcatpost/mypostscript.post",
                        "OSVER='$os'\nRUNBOOTSCRIPTS='$run'\nXCATDEBUGMODE='$debug'\n"
                        . "MASTER_IP='192.0.2.2'\nMASTER='192.0.2.2'\nNODE='node'\n"
                        . "MACADDRESS='52:54:00:12:34:56'\n"
                        . "printf 'postboot|%s\\n' \"\$(test -f /fixture/disabled && echo disabled || echo enabled)\" >>/fixture/events\n"
                        . "exit $post_rc\n");
                }
                write_binary("$root/opt/xcat/xcatinfo", "XCATSERVER=192.0.2.1\n");
                my ($rc, $text) = isolated($root, 'client', {SERVICE_RC => $case->{service_rc} // 0},
                    '/bin/bash', '/opt/xcat/xcatinstallpost');
                is($rc, 0, 'preserves the postboot runner exit status') or diag($text);
                my $events = -e "$root/events" ? scalar read_binary("$root/events") : '';
                note($events) if $ENV{XCAT_POST_TEST_TRACE};
                my $ubuntu = !$case->{no_post} && $owner eq 'post.xcat' && $os =~ /^ubuntu/;
                my $disable = $case->{disable} || ($ubuntu && $case->{ubuntu_only});
                my $command = $owner ne 'post.xcat' ? 'systemctl|disable xcatpostinit1.service'
                    : $ubuntu ? 'update-rc.d|-f xcatpostinit1 remove' : 'chkconfig|xcatpostinit1 off';
                my @commands = grep { /^(?:systemctl|chkconfig|update-rc.d)\|/ } split /\n/, $events;
                is_deeply(\@commands, $disable ? [$command] : [], 'uses the caller-specific service policy');
                unless ($case->{no_post}) {
                    my $state = $disable && !$case->{service_rc} ? 'disabled' : 'enabled';
                    like($events, qr/^postboot\|$state$/m, 'postscript observes the service state');
                    if ($disable) {
                        ok(index($events, $command) < index($events, 'postboot|'),
                            'disables before executing the postscript');
                    }
                    my @messages = grep { /^message\|.*\|debug\|(?:service xcatpostinit1 disabled|systemctl disable|update-rc.d)/ }
                        split /\n/, $events;
                    my $message = $owner ne 'post.xcat' ? 'systemctl disable xcatpostinit1.service'
                        : $ubuntu ? 'update-rc.d -f xcatpostinit1 remove' : 'service xcatpostinit1 disabled';
                    is_deeply(\@messages, $debug && ($ubuntu || $disable)
                        ? ["message|192.0.2.2|debug|$message"] : [], 'preserves debug output and master selection');
                }
            };
        }
    }
}
done_testing();
