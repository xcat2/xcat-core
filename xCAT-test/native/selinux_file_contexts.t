#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw(capture);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# semodule writes a private copy of the targeted policy store, and setfiles
# writes security.selinux attributes. Both need root, not an enforcing kernel.
die "run as root\n" unless $> == 0;
die "requires the targeted policy store\n" unless -d '/var/lib/selinux/targeted';

my $work = tempdir(CLEANUP => 1);

#---

=head3 run

    Descriptions: Run a command and die with its output when it fails.
    Arguments:    The command and its arguments.
    Returns:      The standard output of the command.

=cut

#---
sub run {
    my (@command) = @_;
    my ($out, $err, $rc) = capture { system(@command) };
    die "@command: rc=$rc\n$out$err" if $rc != 0;
    return $out;
}

my $build = "$work/build";
make_path($build);
run('cp', glob("$FindBin::Bin/../../xCAT-selinux/xcat.*"), $build);
run('make', '-C', $build, '-f', '/usr/share/selinux/devel/Makefile', 'xcat.pp');

# The policy root is a copy of the host store, so the host policy is unchanged.
my $root = "$work/root";
make_path("$root/etc/selinux", "$root/var/lib/selinux");
run('cp', '-a', '/etc/selinux/config', '/etc/selinux/targeted', "$root/etc/selinux/");
run('cp', '-a', '/var/lib/selinux/targeted', "$root/var/lib/selinux/");
my $fc = "$root/etc/selinux/targeted/contexts/files/file_contexts";

#---

=head3 install_module

    Descriptions: Install xcat.pp into the private store, as %post does.
    Arguments:    None.
    Returns:      Nothing.

=cut

#---
sub install_module {
    run('semodule', '-p', $root, '-i', "$build/xcat.pp");
}

#---

=head3 lookup

    Descriptions: Ask libselinux for the default label of a path.
    Arguments:    The path on the management node.
    Returns:      The type, or <<none>> when restorecon leaves the path alone.

=cut

#---
sub lookup {
    my ($path) = @_;
    my $out = run('matchpathcon', '-f', $fc, $path);
    return $1 if $out =~ /^\S+\s+[^:\s]+:[^:\s]+:(\w+):/;
    return '<<none>>' if $out =~ /^\S+\s+<<none>>$/;
    die "matchpathcon $path: unexpected output: $out";
}

install_module();

my @images = (
    '/install/netboot/rhels9/x86_64/compute',
    '/install/netboot/custom-image',
    '/install/custom/images/rhels9-compute',
);
my @guest = map { ("$_/rootimg/etc/shadow", "$_/rootimg-statelite/etc/shadow") } @images;
my @published = map {
    my $dir = $_;
    map { "$dir/$_" } qw(kernel initrd-stateless.gz initrd-statelite.gz rootimg.cpio.gz
        rootimg.cpio.gz.sha256 rootimg.cpio.gz.metainfo rootimg.tar.xz rootimg.sfs
        rootimg-statelite.gz)
} @images;

foreach my $path (@guest) {
    is(lookup($path), '<<none>>', "restorecon leaves $path alone");
}
foreach my $path (@published, '/install', '/install/postscripts/xcatdsklspost') {
    is(lookup($path), 'public_content_t', "$path is public_content_t");
}

# A management node: each guest file keeps the label of its own operating
# system, and each published file starts with the label it had before the
# package was installed.
my $mn = "$work/mn";
my %before;
$before{$_} = 'shadow_t'  foreach @guest;
$before{$_} = 'default_t' foreach @published;
foreach my $path (sort keys %before) {
    my $file = "$mn$path";
    (my $dir = $file) =~ s{/[^/]+$}{};
    make_path($dir);
    open(my $fh, '>', $file) or die "$file: $!";
    close($fh);
    run('setfattr', '-n', 'security.selinux', '-v', "system_u:object_r:$before{$path}:s0", $file);
}

#---

=head3 label_of

    Descriptions: Read the security.selinux attribute of a file.
    Arguments:    The path on the management node.
    Returns:      The type in the attribute.

=cut

#---
sub label_of {
    my ($path) = @_;
    my $value = run('getfattr', '--only-values', '-n', 'security.selinux', "$mn$path");
    return $value =~ /^[^:]+:[^:]+:(\w+):/ ? $1 : $value;
}

# %posttrans runs restorecon -R /install. setfiles -F applies the same
# file_contexts to the copy and also resets the user and role fields.
foreach my $step ('install', 'upgrade') {
    install_module() if $step eq 'upgrade';
    run('setfiles', '-F', '-r', $mn, $fc, "$mn/install");
    foreach my $path (@guest) {
        is(label_of($path), $before{$path}, "after the $step relabel $path keeps $before{$path}");
    }
    foreach my $path (@published) {
        is(label_of($path), 'public_content_t', "after the $step relabel $path is public_content_t");
    }
}

done_testing();
