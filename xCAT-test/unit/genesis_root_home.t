#!/usr/bin/env perl
# Drive the /etc/passwd rewrite out of the Genesis dracut cmdline hooks.
#
# mknb writes the management node key to /.ssh/authorized_keys for the legacy Genesis
# image, so sshd finds it only while the home directory of root is /. The hook makes it /
# by deleting the root entry the image ships and appending its own. Run that rewrite
# against every root entry shape dracut writes and read back the result.
use strict;
use warnings;

use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my @HOOKS = (
    'xCAT-genesis-builder/xcat-cmdline.sh',
    'xCAT-genesis-builder/dracut_105/el/xcat-cmdline.sh',
    'xCAT-genesis-builder/dracut_105/ubuntu/xcat-cmdline.sh',
);

# dracut 99base writes the root entry itself. Up to dracut 057 the password field is
# always x. From dracut 060 the x arrives only with --hostonly, and the Genesis image is
# built with -N, so el10 (dracut 107) ships an empty password field.
my %SHIPPED = (
    'dracut 049/057 (el8, el9)' => "root:x:0:0::/root:/bin/sh\n",
    'dracut 107 (el10)'         => "root::0:0::/root:/bin/sh\n",
);

# A user name that starts with root but is not root. The delete must keep this line.
my $DECOY = "rootfsadm:x:501:501::/home/rootfsadm:/sbin/nologin\n";

plan tests => 3 * @HOOKS * scalar(keys %SHIPPED);

my $tmpdir = tempdir(CLEANUP => 1);

foreach my $hook (@HOOKS) {
    my $block = extract_passwd_block(repo_path($hook), $hook);
    foreach my $shape (sort keys %SHIPPED) {
        my $passwd = run_rewrite($block, $SHIPPED{$shape} . $DECOY, $hook);
        my @root = grep { /^root:/ } split(/\n/, $passwd);

        is(scalar @root, 1,
            "$hook / $shape: one root entry is left in /etc/passwd");
        is($root[0], 'root:x:0:0::/:/bin/bash',
            "$hook / $shape: the home directory of root is /");
        like($passwd, qr/^\Qrootfsadm:x:501:501::\/home\/rootfsadm:\/sbin\/nologin\E$/m,
            "$hook / $shape: a user name that starts with root is kept");
    }
}

#---
# extract_passwd_block: lift the /etc/passwd rewrite out of a hook that cannot be sourced.
# The hook mounts filesystems, starts udev and ends in an endless loop.
# Bails out when the block stops being extractable, so a rewrite fails loudly instead of
# leaving the test asserting nothing.
#---
sub extract_passwd_block {
    my ($path, $label) = @_;
    my $text = read_text($path);
    my ($block) = $text =~ m{^(sed [^\n]*/etc/passwd\ncat >>/etc/passwd <<"__ENDL"\n.*?^__ENDL)$}ms;
    BAIL_OUT("$label: the /etc/passwd rewrite was not found") unless defined $block;
    return $block;
}

#---
# run_rewrite: run the extracted block against a scratch passwd file and return it.
# The block names /etc/passwd literally, so the path is redirected into the scratch tree
# first. Bails out if any reference to the real file survives, because the block runs as
# root under CI.
#---
sub run_rewrite {
    my ($block, $shipped, $label) = @_;
    my $dir    = tempdir(DIR => $tmpdir, CLEANUP => 1);
    my $passwd = "$dir/passwd";
    write_text($passwd, $shipped);

    my $script = $block;
    my $hits = ($script =~ s{/etc/passwd}{$passwd}g);
    BAIL_OUT("$label: expected 2 references to /etc/passwd, found $hits") unless $hits == 2;
    BAIL_OUT("$label: a reference to the real /etc/passwd survived") if index($script, '/etc/passwd') >= 0;

    write_text("$dir/rewrite.sh", "set -e\n$script\n");
    system('/bin/bash', "$dir/rewrite.sh") == 0
      or BAIL_OUT("$label: the /etc/passwd rewrite failed to run");
    return read_text($passwd);
}
