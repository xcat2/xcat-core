#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Storable qw(retrieve);
use Test::More;

plan skip_all => 'requires Linux filesystem semantics and an unprivileged test user'
  unless $^O eq 'linux' && $>;
my $repo = File::Spec->rel2abs("$FindBin::Bin/../..");
my $dir = tempdir(CLEANUP => 1);
my $driver = "$FindBin::Bin/fixtures/openeuler-genimage-driver.pl";

for my $os (qw(openeuler20.03sp4 openeuler24.03sp3)) {
    for my $failure (qw(none kernel-copy dracut move-initrd publish-initrd no-dracut)) {
        my ($rc, $state, $output, $case) = run_case($os, $failure, 'vmlinuz', 1, $failure eq 'none');
        my $label = "$os $failure";
        if ($failure eq 'none') {
            is($rc, 0, "$label completes") or diag($output);
            is(read_text("$case/image/kernel"), "new kernel\n", "$label publishes the kernel");
            is(read_text("$case/image/initrd-stateless.gz"), "new initrd\n", "$label publishes the initrd");
            my $repos = "$case/image/rootimg/etc/yum.repos.d";
            is(read_text("$repos/$_"), "[fixture]\nenabled=0\n", "$label disables $_")
                for qw(openEuler.repo Rocky-BaseOS.repo);
            is(read_text("$repos/administrator.repo"), "[fixture]\nenabled=1\n",
                "$label preserves administrator repositories");
        } else {
            isnt($rc, 0, "$label fails");
            like($output, qr/Error: failed to (?:copy|generate|move|publish|preserve).*?(?:kernel|ramdisk|initrd)/i,
                "$label reports the failed boot file operation");
            is(read_text("$case/image/kernel"), "old kernel\n", "$label preserves the previous kernel");
            is(read_text("$case/image/initrd-stateless.gz"), "old initrd\n", "$label preserves the previous initrd");
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
    is(read_text("$case/image/kernel"), "new kernel\n", "$kernel layout publishes its kernel");
    is(read_text("$case/image/initrd-stateless.gz"), "new initrd\n", "$kernel layout publishes its initrd");
}
my ($rc, $state, $output, $case) = run_case('openeuler24.03sp3', 'lock', 'vmlinuz', 1);
isnt($rc, 0, 'lock refusal is fatal');
like($output, qr/Could not acquire image operation lock/, 'lock refusal reports the contested image');
is($state->{lock_calls}, 1, 'lock refusal uses the existing lock owner');
is($state->{dracut_calls}, 0, 'lock refusal does not run dracut');
is(read_text("$case/image/kernel"), "old kernel\n", 'lock refusal preserves kernel');
is(read_text("$case/image/initrd-stateless.gz"), "old initrd\n", 'lock refusal preserves initrd');
is_deeply($state->{commands}, [], 'lock refusal does not run mount cleanup against the active build');
is_deeply([glob("$case/image/.genimage*")], [], 'lock refusal creates no staging directory');

for my $failure (qw(none kernel-copy dracut move-initrd)) {
    ($rc, $state, $output, $case) = run_case('rhels9.6', $failure, 'vmlinuz', 1);
    is($rc == 0 ? 0 : 1, $failure eq 'dracut' ? 1 : 0, "EL $failure retains its exit behavior") or diag($output);
    is(read_text("$case/image/kernel"), $failure eq 'kernel-copy' ? "old kernel\n" : "new kernel\n",
        "EL $failure retains kernel copy behavior");
    is($state->{dracut_calls}, $failure eq 'dracut' ? 1 : 2, "EL $failure retains both initrd modes");
    is($state->{lock_calls}, 0, "EL $failure retains its existing onlyinitrd lock behavior");
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
    write_text("$root/lib/modules/fixture/modules.dep", '');
    my $kernel_file = $kernel eq 'modules' ? "$root/lib/modules/fixture/vmlinuz" : "$root/boot/$kernel-fixture";
    write_text($kernel_file, "new kernel\n");
    chmod 0000, $kernel_file if $failure eq 'kernel-copy';
    if ($old) {
        write_text("$case/image/kernel", "old kernel\n");
        write_text("$case/image/initrd-stateless.gz", "old initrd\n");
    }
    if ($repositories) {
        make_path("$root/etc/yum.repos.d");
        write_text("$root/etc/yum.repos.d/$_", "[fixture]\nenabled=1\n")
            for qw(openEuler.repo Rocky-BaseOS.repo administrator.repo);
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
    return ($status, retrieve("$case/result"), read_text("$case/output"));
}
