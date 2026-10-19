#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use xCAT::FreeBSDPkg;
use XCAT::Test::Chroot qw(stage_binary);

plan(skip_all => 'Dispatch fixtures require a Linux lab root') unless $^O eq 'linux' && $> == 0;
my $sources = $ENV{XCAT_POSTSCRIPT_DISPATCH_DIR} || "$FindBin::Bin/../../xCAT/postscripts";
my $root = abs_path(tempdir(CLEANUP => 1));
make_path("$root/bin", "$root/usr/bin", "$root/scripts", "$root/fixture");

sub write_file {
    my ($path, $bytes, $mode) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    chmod($mode, $path) == 1 or croak $!;
    return;
}

sub read_file {
    my $path = shift;
    return '' unless -f $path;
    open(my $file, '<', $path) or croak $!;
    my $bytes = do { local $/ = undef; <$file> };
    close($file) or croak $!;
    return $bytes;
}

for my $binary ('/bin/sh', '/bin/bash', '/bin/cat', '/usr/bin/dirname', '/usr/bin/basename', '/usr/bin/tr') {
    stage_binary($root, $binary);
}
copy("$root/bin/sh", "$root/fixture/sh.real") or croak $!;
copy("$root/bin/bash", "$root/fixture/bash.real") or croak $!;
chmod(oct('0555'), "$root/fixture/bash.real") == 1 or croak $!;
write_file("$root/bin/uname", "#!/bin/sh\nexec /bin/cat /fixture/os\n", oct('0555'));
write_file("$root/bin/bash", <<'BASH', oct('0555'));
#!/bin/sh
printf '%s\000' "$@" > /fixture/bash.argv
exit 17
BASH
my $adapter = <<'ADAPTER';
#!/bin/sh
printf '%s\000' "$@" > /fixture/native.argv
printf '%s\n' "$DISPATCH_VALUE" > /fixture/native.env
printf 'native stdout\n'
printf 'native stderr\n' >&2
exit 23
ADAPTER
my %adapters = (syslog => 'syslog.freebsd', remoteshell => 'remoteshell.freebsd',
    syncfiles => 'syncfiles.freebsd', confignetwork => 'confignetwork.freebsd',
    ospkgs => 'xcatpackages.freebsd', otherpkgs => 'xcatpackages.freebsd');
for my $script (sort keys %adapters) {
    copy("$sources/$script", "$root/scripts/$script") or croak $!;
    chmod(oct('0555'), "$root/scripts/$script") == 1 or croak $!;
    write_file("$root/scripts/$adapters{$script}", $adapter, oct('0555'));
}

sub invoke {
    my ($entry, $platform, @arguments) = @_;
    unlink("$root/fixture/bash.argv", "$root/fixture/native.argv", "$root/fixture/native.env");
    write_file("$root/fixture/os", "$platform\n", oct('0444'));
    return xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, "/scripts/$entry", @arguments],
        cwd => $root, environment => { PATH => '/bin:/usr/bin', LC_ALL => 'C', DISPATCH_VALUE => 'retained value' },
        timeout => 10);
}

for my $name (sort keys %adapters) {
    write_file("$root/scripts/$adapters{$name}", $adapter, oct('0555'));
    subtest "$name preserves native arguments, environment and exit status" => sub {
        my $result = invoke($name, 'FreeBSD', 'two words', '', '-n', '$literal');
        is($result->{signal}, 0, 'native adapter exits normally');
        is($result->{exitcode}, 23, 'native failure is preserved');
        is(read_file("$root/fixture/native.argv"), "two words\0\0-n\0\$literal\0", 'arguments retain their exact boundaries');
        is(read_file("$root/fixture/native.env"), "retained value\n", 'environment reaches the native adapter');
        is($result->{stdout}, "native stdout\n", 'native output is preserved');
        is($result->{stderr}, "native stderr\n", 'native errors are preserved');
        ok(!-e "$root/fixture/bash.argv", 'FreeBSD does not require Bash');
        done_testing();
    };
    subtest "$name keeps the Bash entry contract for Linux and AIX" => sub {
        for my $platform (qw(Linux AIX)) {
            my $result = invoke($name, $platform, 'two words', '');
            is($result->{signal}, 0, "$platform launcher exits normally");
            is($result->{exitcode}, 17, "$platform retains its Bash interpreter status");
            is(read_file("$root/fixture/bash.argv"), "/scripts/$name\0two words\0\0", "$platform preserves script identity and arguments");
            ok(!-e "$root/fixture/native.argv", "$platform does not invoke the FreeBSD adapter");
        }
        done_testing();
    };
    subtest "$name rejects a missing native adapter" => sub {
        unlink("$root/scripts/$adapters{$name}") or croak $!;
        my $result = invoke($name, 'FreeBSD');
        isnt($result->{exitcode}, 0, 'missing adapter is a failure');
        ok(!-e "$root/fixture/bash.argv", 'missing adapter does not fall through to legacy operations');
        done_testing();
    };
}

sub bash_startup_tests {
    make_path("$root/etc", "$root/dev");
    write_file("$root/dev/null", '', oct('0666'));
    write_file("$root/etc/xCATMN", '', oct('0444'));
    write_file("$root/bin/logger", "#!/bin/sh\nexit 0\n", oct('0555'));
    write_file("$root/fixture/startup", "printf 'startup\\n' >> /fixture/bash.startup\n", oct('0444'));
    copy("$FindBin::Bin/../../xCAT/postscripts/xcatlib.sh", "$root/scripts/xcatlib.sh") or croak $!;
    write_file("$root/scripts/nicutils.sh", "exit 0\n", oct('0444'));
    for my $helper (qw(xcatpkgutils-loader.sh xcatpkgutils.sh)) {
        copy("$FindBin::Bin/../../xCAT/postscripts/$helper", "$root/scripts/$helper") or croak $!;
    }
    copy("$root/fixture/bash.real", "$root/bin/bash") or croak $!;
    chmod(oct('0555'), "$root/bin/bash") == 1 or croak $!;
    copy("$root/fixture/bash.real", "$root/usr/bin/bash") or croak $!;
    chmod(oct('0555'), "$root/usr/bin/bash") == 1 or croak $!;
    for my $legacy_entry (sort keys %adapters) {
        subtest "$legacy_entry preserves Bash startup with either sh implementation" => sub {
            for my $shell (qw(sh bash)) {
                copy("$root/fixture/$shell.real", "$root/bin/sh") or croak $!;
                chmod(oct('0555'), "$root/bin/sh") == 1 or croak $!;
                unlink("$root/fixture/bash.startup");
                write_file("$root/fixture/os", "Linux\n", oct('0444'));
                my $result = xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, "/scripts/$legacy_entry"],
                    cwd => $root, environment => { PATH => '/bin:/usr/bin', LC_ALL => 'C',
                        SYSLOG => 'ignore', UPDATENODE => 1, BASH_ENV => '/fixture/startup' }, timeout => 10);
                is($result->{signal}, 0, "$shell entry exits normally");
                is($result->{exitcode}, 0, "$shell entry retains the legacy early exit");
                is($result->{stderr}, '', "$shell entry has no interpreter errors");
                is(read_file("$root/fixture/bash.startup"), "startup\n", "$shell entry reads Bash startup once");
            }
            done_testing();
        };
        subtest "$legacy_entry preserves an existing Bash invocation" => sub {
            for my $shell ('/usr/bin/bash', '/fixture/bash.real') {
                for my $platform (qw(Linux AIX)) {
                    unlink("$root/fixture/bash.startup");
                    write_file("$root/fixture/os", "$platform\n", oct('0444'));
                    my $result = xCAT::FreeBSDPkg::run_command(
                        ['/usr/sbin/chroot', $root, $shell, '-x', "/scripts/$legacy_entry"],
                        cwd => $root, environment => { PATH => '/bin:/usr/bin', LC_ALL => 'C',
                            SYSLOG => 'ignore', UPDATENODE => 1, BASH_ENV => '/fixture/startup' }, timeout => 10);
                    is($result->{signal}, 0, "$platform $shell exits normally");
                    my $expected_exit = $legacy_entry eq 'confignetwork' && $platform eq 'AIX' ? 1 : 0;
                    is($result->{exitcode}, $expected_exit, "$platform $shell preserves the existing exit");
                    like($result->{stderr}, qr/^\+{1,2}[ ]exit[ ]$expected_exit$/mx, "$platform $shell traces the script body");
                    is(read_file("$root/fixture/bash.startup"), "startup\n",
                        "$platform $shell reads Bash startup exactly once");
                }
            }
            done_testing();
        };
    }
    return;
}

bash_startup_tests();

subtest 'FreeBSD syslog accepts numeric servers without reverse DNS' => sub {
    make_path("$root/etc/syslog.d");
    chmod(oct('0755'), "$root/etc/syslog.d") == 1 or croak $!;
    for my $utility (qw(/usr/bin/awk /usr/bin/id /usr/bin/stat /usr/bin/mktemp
        /usr/bin/chmod /usr/bin/chown /usr/bin/cmp /usr/bin/mv /usr/bin/rm /usr/bin/sync)) {
        stage_binary($root, $utility);
    }
    rename("$root/usr/bin/stat", "$root/usr/bin/stat.real") or croak $!;
    write_file("$root/usr/bin/stat", <<'STAT', oct('0555'));
#!/bin/sh
case "$2" in
    %u:%Lp) exec /usr/bin/stat.real -c '%u:%a' "$3" ;;
    %u:%Lp:%l) exec /usr/bin/stat.real -c '%u:%a:%h' "$3" ;;
    *) exit 1 ;;
esac
STAT
    write_file("$root/usr/bin/fsync", "#!/bin/sh\nexec /usr/bin/sync -f \"\$@\"\n", oct('0555'));
    write_file("$root/usr/bin/getent", <<'GETENT', oct('0555'));
#!/bin/sh
printf '%s\n' "$2" >> /fixture/lookups
[ "$1:$2" = hosts:logger.example.test ] || exit 2
printf '192.0.2.1 logger.example.test\n'
GETENT
    write_file("$root/usr/bin/sysrc", <<'SYSRC', oct('0555'));
#!/bin/sh
if [ "$1" = -n ]; then printf '%s\n' -s; else printf '%s\n' "$*" >> /fixture/sysrc; fi
SYSRC
    write_file("$root/usr/bin/service", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >> /fixture/services\n", oct('0555'));
    write_file("$root/fixture/os", "FreeBSD\n", oct('0444'));
    write_file("$root/etc/syslog.conf", "include /etc/syslog.d\n", oct('0644'));
    copy("$sources/syslog.freebsd", "$root/scripts/syslog.freebsd") or croak $!;
    chmod(oct('0555'), "$root/scripts/syslog.freebsd") == 1 or croak $!;
    my $configure = sub {
        return xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $root, '/scripts/syslog'],
            cwd => $root, environment => {PATH => '/bin:/usr/bin', LC_ALL => 'C', MASTER => $_[0]}, timeout => 10);
    };
    my $result = $configure->('192.0.2.1');
    is($result->{exitcode}, 0, 'public script configures an IPv4 literal with no PTR record');
    is($result->{signal}, 0, 'native adapter exits normally');
    like(read_file("$root/etc/syslog.d/90-xcat.conf"), qr/\@192[.]0[.]2[.]1\n\z/x,
        'published forwarding configuration retains the numeric server');
    ok(!-e "$root/fixture/lookups", 'a numeric server requires no resolver query');
    like(read_file("$root/fixture/services"), qr/^syslogd[ ]reload$/mx, 'successful configuration reloads syslogd');
    $result = $configure->('logger.example.test');
    is($result->{exitcode}, 0, 'resolvable hostname remains supported');
    is(read_file("$root/fixture/lookups"), "logger.example.test\n", 'hostname uses the resolver');
    my $configured = read_file("$root/etc/syslog.d/90-xcat.conf");
    for my $bad ('missing.example.test', '999.0.2.1') {
        $result = $configure->($bad);
        isnt($result->{exitcode}, 0, 'unresolvable hostname or invalid numeric address is rejected');
        is(read_file("$root/etc/syslog.d/90-xcat.conf"), $configured, 'rejection preserves the previous forwarding policy');
    }
    return;
};

done_testing();
