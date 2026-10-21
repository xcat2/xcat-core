#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'postinstall execution requires Linux' unless $^O eq 'linux';
my $netboot = repo_path('xCAT-server/share/xcat/netboot');
my @owners = qw(
    rh/compute.rhels7.ppc64.postinstall
    rh/compute.rhels7.x86_64.postinstall
    rh/compute.rhels8.ppc64le.postinstall
    rh/compute.rhels8.x86_64.postinstall
    rh/compute.rhels9.ppc64le.postinstall
    rh/compute.rhels9.x86_64.postinstall
    rh/compute.rhels10.aarch64.postinstall
    rh/compute.rhels10.ppc64le.postinstall
    rh/compute.rhels10.x86_64.postinstall
    rh/service.postinstall
    rocky/compute.rocky10.riscv64.postinstall
);
my %owners;
for my $owner (@owners) {
    ok(-x "$netboot/$owner", "$owner is executable");
    $owners{abs_path("$netboot/$owner")} = 1;
}
my @aliases;
find({no_chdir => 1, wanted => sub {
    return unless -l $_ && /[.]postinstall$/;
    my $target = abs_path($_);
    push @aliases, substr($_, length($netboot) + 1) if defined $target && $owners{$target};
}}, $netboot);
ok(@aliases, 'finds profile aliases for the affected owners');

my $unchanged = "# SELINUX=enforcing or permissive\nSELINUXTYPE=targeted\n" .
    "OTHER_SELINUX=permissive\n#SELINUX=permissive\n";
my @cases = (
    ['enforcing', "SELINUX=enforcing\n", "SELINUX=disabled\n"],
    ['permissive', "SELINUX=permissive\n", "SELINUX=disabled\n"],
    ['disabled', "SELINUX=disabled\n", "SELINUX=disabled\n"],
    ['absent', undef, undef],
    ['no assignment', '', ''],
    ['whitespace and comments', "\tSELINUX=permissive \t# image policy\n",
        "\tSELINUX=disabled \t# image policy\n"],
    ['enforcing comment', "SELINUX=enforcing # image policy\n",
        "SELINUX=disabled # image policy\n"],
);

for my $relative (@owners, sort @aliases) {
    my @selected = -l "$netboot/$relative" ? ($cases[1]) : @cases;
    for my $case (@selected) {
        my ($label, $input, $expected) = @$case;
        subtest "$relative: $label" => sub {
            my $root = sandbox_root();
            my $image = "$root/target";
            make_path("$image/etc/selinux", "$root/etc/selinux");
            my $host_policy = "SELINUX=enforcing\n# host policy\n";
            write_text("$root/etc/selinux/config", $host_policy);
            write_text("$root/etc/fstab", "host fstab\n");
            write_text("$root/etc/inittab", "host inittab\n");
            my $config = "$image/etc/selinux/config";
            if (defined $input) {
                write_text($config, $input . $unchanged);
                chmod 0640, $config or die "chmod $config: $!";
            }
            my @metadata = defined $input ? (stat($config))[2, 4, 5] : ();
            my ($profile, $osver, $arch) = split /[.]/, basename($relative);
            for my $pass (1, 2) {
                my ($status, $output) = sandbox_run($root,
                    {read_only => {repo_path('.') => repo_path('.'), '/bin/bash' => '/bin/' . basename(abs_path('/bin/sh'))}},
                    "$netboot/$relative", '/target', $osver, $arch // '', $profile);
                is($status, 0, "pass $pass executes the profile") or diag($output);
                is($output, '', "pass $pass has no shell errors");
                is(read_text("$root/etc/selinux/config"), $host_policy, 'host policy is unchanged');
                is(read_text("$root/etc/fstab"), "host fstab\n", 'host fstab is unchanged');
                is(read_text("$root/etc/inittab"), "host inittab\n", 'host inittab is unchanged');
                if (defined $input) {
                    is(read_text($config), $expected . $unchanged,
                        "pass $pass changes only the active SELinux mode");
                    is_deeply([(stat($config))[2, 4, 5]], \@metadata,
                        'policy permissions and ownership are preserved');
                } else {
                    ok(!-e $config, 'absent policy remains absent');
                }
            }
        };
    }
}

done_testing();
