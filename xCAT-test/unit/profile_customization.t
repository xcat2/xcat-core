#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use Fcntl qw(S_IMODE);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $prefix = shift @ARGV // repo_path('xCAT-server');
my $work = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = $prefix;
$ENV{XCATCFG} = "SQLite:$work/db";
make_path("$work/db", "$work/install");
require xCAT::SvrUtils;
require xCAT::Postage;
require xCAT::Table;

my %packages = (
    'install/compute' => ['@Minimal Install', qw(kernel chrony net-tools nfs-utils
        openssh-server openssl rsync util-linux wget python3 tar bzip2
        perl-interpreter grub2-efi-riscv64 efibootmgr)],
    'netboot/compute' => ['@minimal-environment', qw(initscripts chrony kernel
        net-tools nfs-utils openssh-server rsync tar util-linux wget python3 tar
        bzip2 bc dracut dracut-network NetworkManager rsyslog hostname e2fsprogs
        ethtool parted openssl openssh-clients bash vim-minimal rpm iputils
        perl-interpreter)],
    'netboot/service' => ['@minimal-environment', qw(chrony kernel net-tools
        nfs-utils openssh-server rsync tar util-linux wget perl-DBD-MySQL
        perl-DBD-Pg perl-lib python3 tar bzip2 bc dracut dracut-network rsyslog
        hostname e2fsprogs ethtool parted openssl openssh-clients bash
        vim-minimal rpm iputils)],
);

my @cases;
for my $family (['rh', 'rhels10'], ['rocky', 'rocky10']) {
    my ($directory, $os) = @$family;
    for my $profile (qw(compute service)) {
        push @cases, map { ['install', $directory, $profile, $os, 'riscv64', $_] }
            qw(tmpl pkglist);
        push @cases, map { ['netboot', $directory, $profile, $os, 'riscv64', $_] }
            qw(pkglist exlist postinstall);
    }
    push @cases, map { [$_, $directory, 'service', $os, 'riscv64', 'otherpkgs.pkglist'] }
        qw(install netboot);
}

for my $case (@cases) {
    my ($kind, $directory, $profile, $os, $arch, $extension) = @$case;
    my $base = "$prefix/share/xcat/$kind/$directory";
    my $name = "$profile.$os.$arch.$extension";
    subtest "$kind/$directory/$name" => sub {
        my $selected = $extension eq 'postinstall'
            ? xCAT::SvrUtils->get_postinstall_file_name($base, $profile, "$os.2", $arch)
            : xCAT::SvrUtils::get_file_name($base, $extension, $profile, "$os.2", $arch);
        is($selected, "$base/$name", 'retains the public profile filename');
        ok(defined($selected) && -r $selected, 'selected asset is readable') or return;
        is(sprintf('%04o', S_IMODE((stat($selected))[2])),
            $extension eq 'postinstall' ? '0755' : '0644',
            'retains the asset permissions');
        my $original = read_binary($selected);
        my $custom = "$work/$name";
        copy($selected, $custom) or die "copy $selected: $!";
        is(read_binary($custom), $original, 'a custom copy contains the complete asset');
        if ($extension eq 'otherpkgs.pkglist') {
            is_deeply([xCAT::Postage::get_pkglist_records($selected)],
                ['xcat/xcat-core/xCATsn', 'xcat/xcat-dep/rh10/riscv64/goconserver'],
                'the service node retains its architecture-specific packages');
        }
        if ($extension eq 'pkglist' && $packages{"$kind/$profile"}) {
            is_deeply([xCAT::Postage::get_pkglist_records($selected)],
                $packages{"$kind/$profile"}, 'retains package order and repeated entries');
        }
    };
}

my $site = xCAT::Table->new('site', -create => 1) or die 'Cannot create site table';
$site->setAttribs({key => 'installdir'}, {value => "$work/install"});
$site->close();
my $custom = "$work/install/custom/install/rocky";
make_path($custom);
my $name = 'compute.rocky10.riscv64';
copy("$prefix/share/xcat/install/rocky/$name.tmpl", "$custom/$name.tmpl") or die $!;
write_binary("$custom/$name.pkglist", "local-package\n");
my ($status, $error) = xCAT::SvrUtils->update_tables_with_templates(
    'rocky10.2', 'riscv64', '/install/media', 'fixture');
is($status, 0, 'discovers the custom and shipped profiles') or diag($error);
my $images = xCAT::Table->new('linuximage') or die 'Cannot open linuximage table';
my $compute = $images->getAttribs({imagename => 'rocky10.2-riscv64-install-compute'}, 'template', 'pkglist');
is($compute->{template}, "$custom/$name.tmpl", 'image discovery prefers the custom template');
is($compute->{pkglist}, "$custom/$name.pkglist", 'image discovery prefers the custom package list');
is(xCAT::Postage::get_pkglist_tex($compute->{pkglist}), 'local-package',
    'the selected custom package list reaches the package reader');
my $service = $images->getAttribs({imagename => 'rocky10.2-riscv64-install-service'}, 'template');
is($service->{template}, "$prefix/share/xcat/install/rocky/service.rocky10.riscv64.tmpl",
    'a different profile still uses its shipped template');
$images->close();

my $rh_custom = "$work/install/custom/install/rh";
make_path($rh_custom);
my $rh_name = 'compute.rhels10.riscv64.tmpl';
my $shipped = read_binary("$prefix/share/xcat/install/rh/$rh_name");
write_binary("$rh_custom/$rh_name", $shipped . "\n# custom compute template\n");
($status, $error) = xCAT::SvrUtils->update_tables_with_templates(
    'rhels10.2', 'riscv64', '/install/media', 'fixture');
is($status, 0, 'discovers the customized canonical profile and shipped alias') or diag($error);
$images = xCAT::Table->new('linuximage') or die 'Cannot open linuximage table';
$compute = $images->getAttribs({imagename => 'rhels10.2-riscv64-install-compute'}, 'template');
is($compute->{template}, "$rh_custom/$rh_name", 'image discovery selects the custom canonical profile');
$service = $images->getAttribs({imagename => 'rhels10.2-riscv64-install-service'}, 'template');
is($service->{template}, "$prefix/share/xcat/install/rh/service.rhels10.riscv64.tmpl",
    'the service profile retains its shipped alias');
is(read_binary($service->{template}), $shipped,
    'the shipped alias does not inherit the custom canonical profile');
$images->close();

done_testing();
