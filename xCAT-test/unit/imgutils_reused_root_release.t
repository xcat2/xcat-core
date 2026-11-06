#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Find;
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

# A finished root image with the os-release and the dpkg status that Ubuntu writes.
sub image_root {
    my (%overrides) = @_;
    my %image = (codename => 'resolute', arch => 'riscv64', field => 'VERSION_CODENAME', %overrides);
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/usr/lib", "$root/etc", "$root/var/lib/dpkg");
    write_text("$root/usr/lib/os-release", "NAME=\"Ubuntu\"\nVERSION_ID=\"26.04\"\n$image{field}=$image{codename}\nID=ubuntu\n")
      if defined $image{codename};
    symlink('../usr/lib/os-release', "$root/etc/os-release") or die "symlink: $!";
    write_text("$root/var/lib/dpkg/status",
        "Package: debconf\nStatus: install ok installed\nArchitecture: all\n\n"
          . "Package: dpkg\nEssential: yes\nStatus: install ok installed\nArchitecture: $image{arch}\nVersion: 1.23.5ubuntu1\n\n"
          . "Package: dpkg-dev\nStatus: install ok installed\nArchitecture: all\n");
    return $root;
}

sub snapshot {
    my ($root) = @_;
    my @entries;
    find({ wanted => sub { push @entries, join(' ', $File::Find::name, (lstat)[1, 2, 7, 9]) }, no_chdir => 1 }, $root);
    return [sort @entries];
}

for my $case (
    [ 'resolute',          'riscv64', 'the release and architecture that built the image' ],
    [ 'resolute-updates',  'riscv64', 'the updates pocket of that release' ],
    [ 'resolute-security', 'riscv64', 'the security pocket of that release' ],
) {
    my ($suite, $arch, $label) = @$case;
    is(eval { imgutils::check_reused_root(image_root(), $suite, $arch) }, 1, "a root image is reused for $label") or diag($@);
}

{
    my $root = image_root(codename => '"resolute"');
    is(eval { imgutils::check_reused_root($root, 'resolute', 'riscv64') }, 1, 'a quoted VERSION_CODENAME is read') or diag($@);
}

{
    my $root = image_root(codename => 'xenial', arch => 'amd64', field => 'UBUNTU_CODENAME');
    is(eval { imgutils::check_reused_root($root, 'xenial', 'amd64') }, 1, 'an Ubuntu 16.04 image with only UBUNTU_CODENAME is reused') or diag($@);
}

{
    # Ubuntu 14.04 names its release only in lsb-release.
    my $root = image_root(codename => undef, arch => 'amd64');
    unlink("$root/etc/os-release");
    write_text("$root/etc/os-release", "NAME=\"Ubuntu\"\nVERSION_ID=\"14.04\"\nID=ubuntu\n");
    write_text("$root/etc/lsb-release", "DISTRIB_ID=Ubuntu\nDISTRIB_RELEASE=14.04\nDISTRIB_CODENAME=trusty\n");
    is(eval { imgutils::check_reused_root($root, 'trusty', 'amd64') }, 1, 'an Ubuntu 14.04 image with only DISTRIB_CODENAME is reused') or diag($@);
    is(eval { imgutils::check_reused_root($root, 'xenial', 'amd64') }, undef, 'an Ubuntu 14.04 image is not reused for Ubuntu 16.04');
    like($@, qr/holds Ubuntu trusty for amd64, not xenial for amd64/, 'the error names the release of the Ubuntu 14.04 image');
}

for my $case (
    [ [],                                  'noble',    'riscv64', qr/holds Ubuntu resolute for riscv64, not noble for riscv64\. Remove /, 'another release' ],
    [ [],                                  'resolute', 'amd64',   qr/holds Ubuntu resolute for riscv64, not resolute for amd64\. Remove /, 'another architecture' ],
    [ [ codename => undef ],               'resolute', 'riscv64', qr/cannot tell the Ubuntu release and architecture/,                 'no os-release' ],
    [ [ arch => '' ],                      'resolute', 'riscv64', qr/cannot tell the Ubuntu release and architecture/,                 'no dpkg architecture' ],
) {
    my ($image, $suite, $arch, $error, $label) = @$case;
    my $root   = image_root(@$image);
    my $before = snapshot($root);
    my $result = eval { imgutils::check_reused_root($root, $suite, $arch) };
    is($result, undef, "a root image is not reused for $label");
    like($@, $error, "the error for $label names the mismatch");
    is_deeply(snapshot($root), $before, "a root image refused for $label is left as it was");
}

{
    my $root = image_root();
    make_path("$root/bin");
    write_text("$root/bin/uname-binary", "uname\n");
    my $before = snapshot($root);
    is(eval { imgutils::check_reused_root($root, 'resolute', 'riscv64') }, undef,
        'a root image with the uname backup of an interrupted run is not reused');
    like($@, qr/holds bin\/uname-binary, which an interrupted genimage run left\. Restore bin\/uname from it or remove /,
        'the error says how to recover the uname of the image');
    is_deeply(snapshot($root), $before, 'a root image with the uname backup is left as it was');
}

{
    # An absolute link would read the os-release of the build host, which can name the same release.
    my $root = image_root(codename => undef);
    my $host = tempdir(CLEANUP => 1) . '/os-release';
    write_text($host, "VERSION_CODENAME=resolute\n");
    unlink("$root/etc/os-release");
    symlink($host, "$root/etc/os-release") or die "symlink: $!";
    is(eval { imgutils::check_reused_root($root, 'resolute', 'riscv64') }, undef, 'an os-release link that leaves the image is not followed');
}

done_testing();
