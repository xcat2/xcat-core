#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Path qw(make_path);
use File::Slurper qw(read_lines write_text);
use File::Temp qw(tempdir);
use Test::More;

use xCAT::SELinux;

like($INC{'xCAT/SELinux.pm'}, qr/\Q$FindBin::Bin\E/,
    'xCAT::SELinux comes from this checkout, not from /opt/xcat');

ok(xCAT::SELinux->mksquashfs_supports_pseudo_xattr('mksquashfs version 4.6.1 (2023/03/25)'),
    'squashfs-tools 4.6.1 (EL10, openEuler 24.03) takes pseudo xattr definitions');
ok(xCAT::SELinux->mksquashfs_supports_pseudo_xattr("mksquashfs version 4.10 (2030/01/01)\ncopyright"),
    'a later minor version takes them too');
ok(!xCAT::SELinux->mksquashfs_supports_pseudo_xattr('mksquashfs version 4.5 (2021/07/22)'),
    'squashfs-tools 4.5 (openEuler 22.03) does not');
ok(!xCAT::SELinux->mksquashfs_supports_pseudo_xattr('mksquashfs version 4.4-git.1 (2020/02/17)'),
    'squashfs-tools 4.4 (EL9) does not');
ok(!xCAT::SELinux->mksquashfs_supports_pseudo_xattr('mksquashfs version 4.3-git (2014/06/09)'),
    'squashfs-tools 4.3 (EL8) does not');
ok(!xCAT::SELinux->mksquashfs_supports_pseudo_xattr(undef), 'no version output means no support');

# A temporary copy of a rootimg, as packimage makes it before mksquashfs.
my $tmp  = tempdir(CLEANUP => 1);
my $root = "$tmp/copy";
make_path("$root/usr/bin", "$root/etc/selinux/targeted/contexts/files", "$root/a dir");
my $fc = "$root/etc/selinux/targeted/contexts/files/file_contexts";
write_text("$root/etc/selinux/config", "SELINUX=enforcing\nSELINUXTYPE=targeted\n");
write_text($fc, "/.* system_u:object_r:default_t:s0\n");
write_text("$root/usr/bin/ls", "ELF\n");
write_text("$root/a dir/say \"hi\"\\now", "x\n");
write_text("$root/etc/bad\nname", "x\n");
symlink('ls', "$root/usr/bin/dir") or die "symlink: $!";

# label_paths runs matchpathcon against the image policy. Answer by file type instead.
my @lookups;
my %context = (dir => 'root_t', file => 'bin_t', lnk_file => 'lnk_t');
sub run_args {
    my (%args) = @_;
    @lookups = ();
    no warnings 'redefine';
    local *xCAT::SELinux::label_paths = sub {
        my ($class, $file_contexts, $type, $paths) = @_;
        push @lookups, [ $file_contexts, $type, [ sort @{$paths} ] ];
        my %answer;
        foreach my $path (@{$paths}) {
            next if $path eq '/etc/selinux/config';
            $answer{$path} = "system_u:object_r:$context{$type}:s0";
        }
        return \%answer;
    };
    return xCAT::SELinux->squashfs_label_args(%args);
}

my $pseudo = "$tmp/pseudo";
my ($args, $warning) = run_args(root => $root, pseudo => $pseudo,
    version => 'mksquashfs version 4.6.1 (2023/03/25)');
is($warning, undef, 'squashfs-tools 4.6.1 gives no warning');
is_deeply($args, [ '-xattrs-exclude', '^security\.selinux$', '-pf', $pseudo ],
    'mksquashfs drops the labels of the copy and takes the labels of the image from the pseudo file');

is_deeply([ sort map { $_->[1] } @lookups ], [qw(dir file lnk_file)], 'one lookup for each file type');
is_deeply([ map { $_->[0] } @lookups ], [ ($fc) x 3 ], 'every lookup uses the file_contexts of the image');
my %paths = map { $_->[1] => $_->[2] } @lookups;
is_deeply($paths{dir}, [ '/', '/a dir', '/etc', '/etc/selinux', '/etc/selinux/targeted',
        '/etc/selinux/targeted/contexts', '/etc/selinux/targeted/contexts/files', '/usr', '/usr/bin' ],
    'directories are looked up at their path on the node');
is_deeply($paths{file}, [ "/a dir/say \"hi\"\\now", '/etc/selinux/config',
        '/etc/selinux/targeted/contexts/files/file_contexts', '/usr/bin/ls' ],
    'files are looked up, and a name with a newline is skipped');
is_deeply($paths{lnk_file}, ['/usr/bin/dir'], 'symbolic links are looked up as lnk_file');

my @lines = sort(read_lines($pseudo));
is_deeply(\@lines, [ sort(
            '"/" x security.selinux=system_u:object_r:root_t:s0',
            '"a dir" x security.selinux=system_u:object_r:root_t:s0',
            '"a dir/say \"hi\"\\\\now" x security.selinux=system_u:object_r:bin_t:s0',
            '"etc" x security.selinux=system_u:object_r:root_t:s0',
            '"etc/selinux" x security.selinux=system_u:object_r:root_t:s0',
            '"etc/selinux/targeted" x security.selinux=system_u:object_r:root_t:s0',
            '"etc/selinux/targeted/contexts" x security.selinux=system_u:object_r:root_t:s0',
            '"etc/selinux/targeted/contexts/files" x security.selinux=system_u:object_r:root_t:s0',
            '"etc/selinux/targeted/contexts/files/file_contexts" x security.selinux=system_u:object_r:bin_t:s0',
            '"usr" x security.selinux=system_u:object_r:root_t:s0',
            '"usr/bin" x security.selinux=system_u:object_r:root_t:s0',
            '"usr/bin/dir" x security.selinux=system_u:object_r:lnk_t:s0',
            '"usr/bin/ls" x security.selinux=system_u:object_r:bin_t:s0',
        ) ],
    'the pseudo file quotes each name and skips a path the policy gives no context');

unlink($pseudo);
($args, $warning) = run_args(root => $root, pseudo => $pseudo,
    version => 'mksquashfs version 4.4-git.1 (2020/02/17)');
is($args, undef, 'squashfs-tools 4.4 gives no label arguments');
like($warning, qr/4\.6/, 'the warning names the squashfs-tools version that labels the image');
is(scalar(@lookups), 0, 'squashfs-tools 4.4 looks up no label');
ok(!-e $pseudo, 'squashfs-tools 4.4 writes no pseudo file');

my $bare = "$tmp/bare";
make_path("$bare/usr");
($args, $warning) = run_args(root => $bare, pseudo => $pseudo,
    version => 'mksquashfs version 4.6.1 (2023/03/25)');
is($args, undef, 'an image without an SELinux policy gives no label arguments');
like($warning, qr/file_contexts/, 'the warning says the image has no file_contexts');

done_testing();
