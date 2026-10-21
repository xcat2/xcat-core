#!/usr/bin/env perl
use strict;
use warnings;
use Errno qw(EACCES EIO);
use FindBin;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;

BEGIN {
    *CORE::GLOBAL::rename = sub { return CORE::rename($_[0], $_[1]); };
    *CORE::GLOBAL::link = sub { return CORE::link($_[0], $_[1]); };
}
use imgutils;

my $dir = tempdir(CLEANUP => 1);

for my $mode (qw(stateless statelite)) {
    for my $failure (qw(none move-initrd backup-kernel publish-kernel publish-initrd)) {
        my ($ok, $error, $case) = publish_case($mode, $failure, 1);
        my $label = "$mode $failure";
        if ($failure eq 'none') {
            ok($ok, "$label completes") or diag($error);
            is(read_text("$case/kernel"), "new kernel\n", "$label publishes the kernel");
            is(read_text("$case/initrd-$mode.gz"), "new initrd\n", "$label publishes the initrd");
        } else {
            ok(!$ok, "$label fails");
            like($error, qr/Error: failed to (?:move|publish|preserve).*?(?:kernel|ramdisk)/i,
                "$label reports the failed boot file operation");
            is(read_text("$case/kernel"), "old kernel\n", "$label preserves the previous kernel");
            is(read_text("$case/initrd-$mode.gz"), "old initrd\n", "$label preserves the previous initrd");
        }
        is_deeply([glob("$case/.genimage*")], [], "$label removes boot staging files");
    }
}

my ($ok, $error, $case) = publish_case('stateless', 'publish-initrd', 0);
ok(!$ok, 'first build publication failure is fatal');
ok(!-e "$case/kernel", 'first build failure removes the unpaired kernel');
ok(!-e "$case/initrd-stateless.gz", 'first build failure does not expose an initrd');
is_deeply([glob("$case/.genimage*")], [], 'first build failure removes boot staging files');

($ok, $error, $case) = publish_case('stateless', 'rollback', 1);
ok(!$ok, 'rollback failure is fatal');
my @backups = glob("$case/.genimage*/previous-kernel");
is(scalar(@backups), 1, 'rollback failure retains one previous kernel backup');
is(read_text($backups[0]), "old kernel\n", 'retained backup contains the previous kernel');
like($error, qr/kernel rollback failed: .*Boot files retained in \Q$case\E\/\.genimage/,
    'rollback failure reports the recoverable backup directory');
is(read_text("$case/initrd-stateless.gz"), "old initrd\n", 'rollback failure preserves previous initrd');

subtest 'vendor repositories' => sub {
    plan skip_all => 'requires Linux sed' unless $^O eq 'linux';
    my @legacy_repositories = qw(Rocky-BaseOS.repo almalinux.repo CentOS-Base.repo oracle-linux-ol10.repo);
    my @custom_repositories = qw(local-repository-0.repo xCAT-custom.repo administrator.repo);
    my $enabled = "[fixture]\nenabled=1\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
    my $disabled = "[fixture]\nenabled=0\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
    my $native = "[OS]\nenabled=1\ngpgcheck=1\n[update]\n \tenabled = 1\n[disabled]\nenabled=0\n#enabled=1\n";
    my $native_disabled = "[OS]\nenabled=0\ngpgcheck=1\n[update]\nenabled=0\n[disabled]\nenabled=0\n#enabled=1\n";
    for my $repository_case (
        ['enabled', $native, $native_disabled],
        ['already-disabled', $native_disabled, $native_disabled],
        ['absent', undef, undef],
    ) {
        my ($name, $input, $expected) = @$repository_case;
        subtest $name => sub {
            my $root = tempdir(DIR => $dir, CLEANUP => 1);
            my $repos = "$root/etc/yum.repos.d";
            make_path($repos);
            write_text("$repos/$_", $enabled) for (@legacy_repositories, @custom_repositories);
            write_text("$repos/openEuler.repo", $input) if defined $input;
            for my $pass (1, 2) {
                imgutils::disable_vendor_repositories($root);
                if (defined $expected) {
                    is(read_text("$repos/openEuler.repo"), $expected,
                        "pass $pass disables only active native repository assignments");
                } else {
                    ok(!-e "$repos/openEuler.repo", "pass $pass does not create an absent vendor file");
                }
                is(read_text("$repos/$_"), $disabled, "pass $pass preserves policy for $_")
                    for @legacy_repositories;
                is(read_text("$repos/$_"), $enabled, "pass $pass leaves $_ unchanged")
                    for @custom_repositories;
            }
        };
    }
};

done_testing();

sub publish_case {
    my ($mode, $failure, $old) = @_;
    my $case = tempdir(DIR => $dir, CLEANUP => 1);
    make_path("$case/tmp");
    my $staging = File::Temp->newdir('.genimage-boot.XXXXXX', DIR => $case, CLEANUP => 1);
    write_text("$staging/kernel", "new kernel\n");
    write_text("$case/tmp/initrd.gz", "new initrd\n");
    if ($old) {
        write_text("$case/kernel", "old kernel\n");
        write_text("$case/initrd-$mode.gz", "old initrd\n");
    }

    my $move = \&imgutils::move;
    my ($ok, $error);
    {
        no warnings 'redefine';
        local *imgutils::move = sub {
            if ($failure eq 'move-initrd') {
                $! = EIO;
                return 0;
            }
            return $move->(@_);
        };
        local *CORE::GLOBAL::link = sub {
            if ($failure eq 'backup-kernel') {
                $! = EACCES;
                return 0;
            }
            return CORE::link($_[0], $_[1]);
        };
        local *CORE::GLOBAL::rename = sub {
            if (($failure =~ /^(?:publish-initrd|rollback)$/
                    && $_[1] eq "$case/initrd-$mode.gz")
                || ($failure eq 'publish-kernel' && $_[1] eq "$case/kernel")
                || ($failure eq 'rollback' && $_[0] =~ m{/previous-kernel$})) {
                $! = EACCES;
                return 0;
            }
            return CORE::rename($_[0], $_[1]);
        };
        $ok = eval { imgutils::publish_boot_files($staging, $case, "$case/tmp/initrd.gz", $mode); };
        $error = $@;
    }
    undef $staging;
    return ($ok, $error, $case);
}
