#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Storable qw(retrieve);
use Test::More;

plan skip_all => 'requires Linux filesystem semantics and an unprivileged test user'
  unless $^O eq 'linux' && $>;
my $repo = File::Spec->rel2abs("$FindBin::Bin/../..");
my $dir = tempdir(CLEANUP => 1);
my $driver = "$dir/driver.pl";
write_file($driver, <<'PERL');
use strict;
use warnings;
use Errno qw(EACCES EIO);
use File::Copy ();
use File::Basename qw(dirname);
use FindBin;
use Storable qw(nstore);
our (@commands, $dracut_calls, $lock_calls);
BEGIN {
    *CORE::GLOBAL::readpipe = sub {
        return "4.18.2\n" if $_[0] =~ /rpm --version/;
        return "059\n" if $_[0] =~ /^rpm --root .* -qi dracut /;
        return '' if $_[0] =~ /type -p pigz/;
        die "Unexpected command: $_[0]";
    };
    *CORE::GLOBAL::system = sub {
        my $command = join(' ', @_);
        push @commands, $command;
        if ($command =~ /^chroot (\S+) dracut .* -f (\S+) /) {
            $dracut_calls++;
            open(my $file, '>', "$1$2") or die $!;
            print {$file} "new initrd\n";
            close($file) or die $!;
            return 29 << 8 if $ENV{GENIMAGE_FAILURE} eq 'dracut';
        }
        if ($command =~ m{^sed -i -e '[^']+' \Q$ENV{GENIMAGE_DEST}\E/rootimg/etc/yum\.repos\.d/[A-Za-z0-9.-]+\.repo$}) {
            return CORE::system($command);
        }
        return 0;
    };
    *CORE::GLOBAL::rename = sub {
        my $failure = $ENV{GENIMAGE_FAILURE};
        if (($failure =~ /^(?:publish-initrd|rollback)$/
                && $_[1] eq "$ENV{GENIMAGE_DEST}/initrd-stateless.gz")
            || ($failure eq 'publish-kernel' && $_[1] eq "$ENV{GENIMAGE_DEST}/kernel")
            || ($failure eq 'rollback' && $_[0] =~ m{/previous-kernel$})) {
            $! = EACCES;
            return 0;
        }
        return CORE::rename($_[0], $_[1]);
    };
    *CORE::GLOBAL::link = sub {
        if ($ENV{GENIMAGE_FAILURE} eq 'backup-kernel') {
            $! = EACCES;
            return 0;
        }
        return CORE::link($_[0], $_[1]);
    };
}
my $move = \&File::Copy::move;
{
    no warnings 'redefine';
    *File::Copy::move = sub {
        if ($ENV{GENIMAGE_FAILURE} eq 'move-initrd' && $_[0] =~ m{/tmp/initrd\.\d+\.gz$}) {
            $! = EIO;
            return 0;
        }
        return $move->(@_);
    };
}
END {
    nstore({ commands => \@commands, dracut_calls => $dracut_calls || 0, lock_calls => $lock_calls || 0 },
        "$ENV{GENIMAGE_CASE}/result");
}
require xCAT::Utils;
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub {
        $lock_calls++;
        return ($ENV{GENIMAGE_FAILURE} eq 'lock' ? 1 : 0, undef);
    };
}
$0 = $ENV{GENIMAGE_SCRIPT};
$FindBin::Bin = dirname($0);
do $0;
die $@ if $@;
PERL

for my $os (qw(openeuler20.03sp4 openeuler24.03sp3)) {
    for my $failure (qw(none kernel-copy dracut move-initrd backup-kernel publish-kernel publish-initrd no-dracut)) {
        my ($rc, $state, $output, $case) = run_case($os, $failure, 'vmlinuz', 1);
        my $label = "$os $failure";
        if ($failure eq 'none') {
            is($rc, 0, "$label completes") or diag($output);
            is(read_file("$case/image/kernel"), "new kernel\n", "$label publishes the kernel");
            is(read_file("$case/image/initrd-stateless.gz"), "new initrd\n", "$label publishes the initrd");
        } else {
            isnt($rc, 0, "$label fails");
            like($output, qr/Error: failed to (?:copy|generate|move|publish|preserve).*?(?:kernel|ramdisk|initrd)/i,
                "$label reports the failed boot file operation");
            is(read_file("$case/image/kernel"), "old kernel\n", "$label preserves the previous kernel");
            is(read_file("$case/image/initrd-stateless.gz"), "old initrd\n", "$label preserves the previous initrd");
            ok(grep({ /^findmnt .*\/dev\// } @{$state->{commands}}), "$label invokes mount cleanup");
        }
        is($state->{dracut_calls}, $failure =~ /^(?:kernel-copy|no-dracut)$/ ? 0 : 1,
            "$label only reaches dracut after a successful kernel copy");
        is($state->{lock_calls}, 1, "$label acquires the image operation lock");
        is_deeply([glob("$case/image/rootimg/tmp/initrd.*.gz")], [], "$label removes temporary dracut output");
        is_deeply([glob("$case/image/.genimage*")], [], "$label removes boot staging files");
    }
}
for my $kernel (qw(vmlinux image modules)) {
    my ($rc, $state, $output, $case) = run_case('openeuler24.03', 'none', $kernel, 0);
    is($rc, 0, "$kernel kernel layout completes") or diag($output);
    is(read_file("$case/image/kernel"), "new kernel\n", "$kernel layout publishes its kernel");
    is(read_file("$case/image/initrd-stateless.gz"), "new initrd\n", "$kernel layout publishes its initrd");
}
my ($rc, $state, $output, $case) = run_case('openeuler24.03sp3', 'publish-initrd', 'vmlinuz', 0);
isnt($rc, 0, 'first build publication failure is fatal');
ok(!-e "$case/image/kernel", 'first build failure removes the unpaired kernel');
ok(!-e "$case/image/initrd-stateless.gz", 'first build failure does not expose an initrd');

($rc, $state, $output, $case) = run_case('openeuler24.03sp3', 'lock', 'vmlinuz', 1);
isnt($rc, 0, 'lock refusal is fatal');
like($output, qr/Could not acquire image operation lock/, 'lock refusal reports the contested image');
is($state->{lock_calls}, 1, 'lock refusal uses the existing lock owner');
is($state->{dracut_calls}, 0, 'lock refusal does not run dracut');
is(read_file("$case/image/kernel"), "old kernel\n", 'lock refusal preserves kernel');
is(read_file("$case/image/initrd-stateless.gz"), "old initrd\n", 'lock refusal preserves initrd');
is_deeply($state->{commands}, [], 'lock refusal does not run mount cleanup against the active build');
is_deeply([glob("$case/image/.genimage*")], [], 'lock refusal creates no staging directory');

($rc, $state, $output, $case) = run_case('openeuler24.03sp3', 'rollback', 'vmlinuz', 1);
isnt($rc, 0, 'rollback failure is fatal');
my @backups = glob("$case/image/.genimage*/previous-kernel");
is(scalar(@backups), 1, 'rollback failure retains one previous kernel backup');
is(read_file($backups[0]), "old kernel\n", 'retained backup contains the previous kernel');
like($output, qr/kernel rollback failed: .*Boot files retained in \Q$case\E\/image\/\.genimage/,
    'rollback failure reports the recoverable backup directory');
is(read_file("$case/image/initrd-stateless.gz"), "old initrd\n", 'rollback failure preserves previous initrd');

for my $failure (qw(none kernel-copy dracut move-initrd)) {
    ($rc, $state, $output, $case) = run_case('rhels9.6', $failure, 'vmlinuz', 1);
    is($rc == 0 ? 0 : 1, $failure eq 'dracut' ? 1 : 0, "EL $failure retains its exit behavior") or diag($output);
    is(read_file("$case/image/kernel"), $failure eq 'kernel-copy' ? "old kernel\n" : "new kernel\n",
        "EL $failure retains kernel copy behavior");
    is($state->{dracut_calls}, $failure eq 'dracut' ? 1 : 2, "EL $failure retains both initrd modes");
    is($state->{lock_calls}, 0, "EL $failure retains its existing onlyinitrd lock behavior");
}

my @legacy_repositories = qw(Rocky-BaseOS.repo almalinux.repo CentOS-Base.repo oracle-linux-ol10.repo);
my @custom_repositories = qw(local-repository-0.repo xCAT-custom.repo administrator.repo);
my $enabled = "[fixture]\nenabled=1\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
my $disabled = "[fixture]\nenabled=0\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
my $native = "[OS]\nenabled=1\ngpgcheck=1\n[update]\n \tenabled = 1\n[disabled]\nenabled=0\n#enabled=1\n";
my $native_disabled = "[OS]\nenabled=0\ngpgcheck=1\n[update]\nenabled=0\n[disabled]\nenabled=0\n#enabled=1\n";
for my $os (qw(openeuler20.03sp4 openeuler24.03sp3)) {
    for my $repository_case (
        ['enabled', $native, $native_disabled],
        ['already-disabled', $native_disabled, $native_disabled],
        ['absent', undef, undef],
    ) {
        my ($name, $input, $expected) = @$repository_case;
        subtest "$os repositories $name" => sub {
            my %repositories = map { $_ => $enabled } (@legacy_repositories, @custom_repositories);
            $repositories{'openEuler.repo'} = $input if defined $input;
            my ($status, $result, $log, $fixture) = run_case($os, 'none', 'vmlinuz', 0, \%repositories);
            my $repos = "$fixture/image/rootimg/etc/yum.repos.d";
            for my $pass (1, 2) {
                ($status, $result, $log) = run_owner($os, 'none', $fixture) if $pass == 2;
                is($status, 0, "pass $pass completes the whole genimage owner") or diag($log);
                if (defined $expected) {
                    is(read_file("$repos/openEuler.repo"), $expected,
                        "pass $pass disables only active native repository assignments");
                } else {
                    ok(!-e "$repos/openEuler.repo", "pass $pass does not create an absent vendor file");
                }
                is(read_file("$repos/$_"), $disabled, "pass $pass preserves policy for $_")
                    for @legacy_repositories;
                is(read_file("$repos/$_"), $enabled, "pass $pass leaves $_ unchanged")
                    for @custom_repositories;
            }
        };
    }
}

done_testing();

sub run_case {
    my ($os, $failure, $kernel, $old, $repositories) = @_;
    my $case = tempdir(DIR => $dir, CLEANUP => 1);
    my $root = "$case/image/rootimg";
    make_path(map { "$root/$_" } qw(boot lib/modules/fixture etc dev run tmp
        usr/lib/dracut/modules.d/98syslog usr/lib/dracut/modules.d/35network-manager));
    if ($failure eq 'no-dracut') {
        require File::Path;
        File::Path::remove_tree("$root/usr/lib/dracut");
    }
    write_file("$root/lib/modules/fixture/modules.dep", '');
    my $kernel_file = $kernel eq 'modules' ? "$root/lib/modules/fixture/vmlinuz" : "$root/boot/$kernel-fixture";
    write_file($kernel_file, "new kernel\n");
    chmod 0000, $kernel_file if $failure eq 'kernel-copy';
    if ($old) {
        write_file("$case/image/kernel", "old kernel\n");
        write_file("$case/image/initrd-stateless.gz", "old initrd\n");
    }
    if ($repositories) {
        make_path("$root/etc/yum.repos.d");
        write_file("$root/etc/yum.repos.d/$_", $repositories->{$_}) for keys %$repositories;
    }
    my @result = run_owner($os, $failure, $case);
    chmod 0644, $kernel_file;
    return (@result, $case);
}

sub run_owner {
    my ($os, $failure, $case) = @_;
    local %ENV = %ENV;
    @ENV{qw(GENIMAGE_SCRIPT GENIMAGE_DEST GENIMAGE_CASE GENIMAGE_FAILURE XCATROOT)} =
      ("$repo/xCAT-server/share/xcat/netboot/rh/genimage", "$case/image", $case, $failure, "$repo/xCAT-server");
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        open(STDOUT, '>', "$case/output") or die $!;
        open(STDERR, '>&', STDOUT) or die $!;
        exec $^X, "-I$repo/perl-xCAT", "-I$repo/xCAT-server/lib/perl",
          "-I$repo/xCAT-server/share/xcat/netboot/imgutils", $driver,
          '-o', $os, '-a', 'x86_64', '-p', 'compute', '-k', 'fixture',
          '--onlyinitrd', '--rootimgdir', "$case/image", 'boot-fixture';
        die "exec: $!";
    }
    waitpid($pid, 0);
    my $status = $?;
    return ($status, retrieve("$case/result"), read_file("$case/output"));
}

sub read_file {
    my ($path) = @_;
    return undef unless -e $path;
    open(my $file, '<', $path) or die "read $path: $!";
    my $contents = do { local $/; <$file> };
    close($file) or die $!;
    return $contents;
}

sub write_file {
    my ($path, $contents) = @_;
    open(my $file, '>', $path) or die "write $path: $!";
    print {$file} $contents or die $!;
    close($file) or die $!;
}
