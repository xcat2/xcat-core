#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw(capture);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# The documented repair of a published artifact adds local file-context
# mappings, so this test writes to the policy store of the host. It runs only
# where SELinux is disabled, which is the container the CI uses, and it removes
# every mapping it adds.
die "run as root\n" unless $> == 0;
die "requires the targeted policy store\n" unless -d '/var/lib/selinux/targeted';
die "requires semanage\n" if system('command -v semanage >/dev/null 2>&1') != 0;
die "refuses to add mappings where SELinux is enabled\n" if -e '/sys/fs/selinux/enforce';

my $work = tempdir(CLEANUP => 1);
my @added;

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

#---

=head3 install_module

    Descriptions: Install xcat.pp into the policy store, as %post does.
    Arguments:    None.
    Returns:      Nothing.

=cut

#---
sub install_module {
    run('semodule', '-i', "$build/xcat.pp");
}

#---

=head3 add_mapping

    Descriptions: Add one persistent file-context mapping, as the documented
                  repair does, and record it for removal.
    Arguments:    The type, the path expression, and the -f value or undef.
    Returns:      Nothing.

=cut

#---
sub add_mapping {
    my ($type, $expression, $ftype) = @_;
    my @ftype = $ftype ? ('-f', $ftype) : ();
    run('semanage', 'fcontext', '-a', '-t', $type, @ftype, $expression);
    push @added, [ $expression, @ftype ];
}

END {
    foreach my $mapping (reverse @added) {
        my ($expression, @ftype) = @$mapping;
        system('semanage', 'fcontext', '-d', @ftype, $expression);
    }
}

#---

=head3 lookup

    Descriptions: Ask the policy store for the default label of a path, which
                  is what restorecon applies.
    Arguments:    The path on the management node.
    Returns:      The type, or <<none>> when restorecon leaves the path alone.

=cut

#---
sub lookup {
    my ($path, $fc) = @_;
    my @spec = $fc ? ('-f', $fc) : ();
    my $out = run('matchpathcon', @spec, $path);
    return $1 if $out =~ /^\S+\s+[^:\s]+:[^:\s]+:(\w+):/;
    return '<<none>>' if $out =~ /^\S+\s+<<none>>$/;
    die "matchpathcon $path: unexpected output: $out";
}

#---

=head3 merged_contexts

    Descriptions: Write the file contexts of the store and its local mappings
                  into one file, so setfiles applies what restorecon would.
                  restorecon is a no-op where SELinux is disabled.
    Arguments:    None.
    Returns:      The path of the file.
=cut

#---
sub merged_contexts {
    my $base = '/etc/selinux/targeted/contexts/files/file_contexts';
    my $out  = "$work/merged.fc";
    # libselinux reads file_contexts first and file_contexts.local last, and
    # between two expressions that both match, the later entry wins. Keep that
    # order, or a local mapping loses to the packaged one.
    open(my $fh, '>', $out) or die "$out: $!";
    foreach my $file ($base, "$base.local") {
        next unless -f $file;
        open(my $in, '<', $file) or die "$file: $!";
        print {$fh} <$in>;
        close($in);
    }
    close($fh);
    return $out;
}

#---

=head3 label_of

    Descriptions: Read the security.selinux attribute of a file.
    Arguments:    The path on the management node.
    Returns:      The type in the attribute.

=cut

#---
sub label_of {
    my ($root, $path) = @_;
    my $value = run('getfattr', '--only-values', '-n', 'security.selinux', "$root$path");
    return $value =~ /^[^:]+:[^:]+:(\w+):/ ? $1 : $value;
}

#---

=head3 make_tree

    Descriptions: Create a tree under a scratch root and set the label of each
                  path from the given map.
    Arguments:    The scratch root, and a map of path to type.
    Returns:      Nothing.

=cut

#---
sub make_tree {
    my ($root, $labels) = @_;
    foreach my $path (sort keys %$labels) {
        my $file = "$root$path";
        if ($path =~ m{/$}) {
            make_path($file);
        } else {
            (my $dir = $file) =~ s{/[^/]+$}{};
            make_path($dir);
            open(my $fh, '>', $file) or die "$file: $!";
            close($fh);
        }
        $file =~ s{/$}{};
        run('setfattr', '-n', 'security.selinux',
            '-v', "system_u:object_r:$labels->{$path}:s0", $file);
    }
}

install_module();

# The names genimage and packimage write in an image root, and the expression
# the repair maps for each one. Each expression names one regular file directly
# below the image root, so no path in a guest tree matches it.
my @published = qw(kernel hypervisor initrd-stateless.gz initrd-statelite.gz
    rootimg.cpio.gz rootimg-statelite.gz rootimgtree.gz litefile.csv
    common.filelist);
my @expressions = ('kernel', 'hypervisor', 'initrd[^/]*', 'rootimg\.[^/]*',
    'rootimg-statelite\.[^/]*', 'rootimgtree\.[^/]*', 'litefile\.csv',
    'common\.filelist');

# A guest file keeps the label of its own operating system. The tree root is a
# directory, so the -f f expressions cannot take it either.
my %guest_labels = (
    'etc/shadow'  => 'shadow_t',
    'etc/passwd'  => 'etc_t',
    'usr/bin/sh'  => 'bin_t',
    ''            => 'etc_t',
);

#---

=head3 scenario

    Descriptions: Build an image root whose published artifacts carry the wrong
                  type and whose two guest trees carry valid types, run the
                  documented repair, and verify the result after a recursive
                  relabel and after a policy upgrade.
    Arguments:    A name, the configured publication directory, the image root,
                  and a sub that adds the mappings of the repair.
    Returns:      Nothing.

=cut

#---
sub scenario {
    my ($name, $installdir, $imgroot, $repair) = @_;
    my $root = "$work/$name";
    my %labels;

    # Wrong on every published artifact. default_t is what a tree older than
    # the package carries, and httpd_t has no rule to read it.
    $labels{"$imgroot/$_"} = 'default_t' foreach @published;

    # Valid inside both guest trees. An image root can carry a rootimg
    # component of its own, so collect the guest paths here rather than by
    # matching the name rootimg anywhere in the path.
    my @guest;
    foreach my $tree ("$imgroot/rootimg", "$imgroot/rootimg-statelite") {
        foreach my $path (sort keys %guest_labels) {
            my $guest = $path eq '' ? $tree : "$tree/$path";
            $labels{$path eq '' ? "$tree/" : $guest} = $guest_labels{$path};
            push @guest, $guest;
        }
    }
    make_tree($root, \%labels);

    my %before = map { (my $p = $_) =~ s{/$}{}; ($p => $labels{$_}) } keys %labels;
    my @artifacts = map { "$imgroot/$_" } @published;

    $repair->();

    # The repair is applied with restorecon, which reads the store. setfiles
    # reads a file, so assert the two answer the same before relying on it.
    my $fc = merged_contexts();
    foreach my $path (@artifacts, @guest) {
        is(lookup($path, $fc), lookup($path),
            "$name: the merged contexts answer for $path what the store answers");
    }

    foreach my $path (@artifacts) {
        is(lookup($path), 'public_content_t', "$name: the repair maps $path");
    }
    foreach my $path (@guest) {
        is(lookup($path), '<<none>>', "$name: the repair leaves $path out");
    }

    foreach my $step ('repair', 'host relabel', 'policy upgrade') {
        install_module() if $step eq 'policy upgrade';
        $fc = merged_contexts();
        run('setfiles', '-F', '-r', $root, $fc, "$root$installdir");
        foreach my $path (@artifacts) {
            is(label_of($root, $path), 'public_content_t',
                "$name: after the $step $path is public_content_t");
        }
        foreach my $path (@guest) {
            is(label_of($root, $path), $before{$path},
                "$name: after the $step $path keeps $before{$path}");
        }
    }
}

# A rootimg component in the middle of an image root is ambiguous, so the
# packaged mappings leave every path in such a root alone, published artifacts
# included. The repair maps each published artifact of that one image root.
scenario(
    'standard installdir',
    '/install',
    '/install/netboot/rootimg/rhels9/x86_64/compute',
    sub {
        add_mapping('public_content_t',
            "/install/netboot/rootimg/rhels9/x86_64/compute/$_", 'f')
            foreach @expressions;
    });

# site.installdir selects the publication directory, and the packaged mappings
# name /install. A site that moved it maps the configured directory itself, and
# keeps both guest trees out with <<none>>.
scenario(
    'moved installdir',
    '/srv/xcat-install',
    '/srv/xcat-install/netboot/custom-image',
    sub {
        add_mapping('public_content_t', '/srv/xcat-install(/.*)?');
        add_mapping('<<none>>', '/srv/xcat-install(/.*)?/rootimg(/.*)?');
        add_mapping('<<none>>', '/srv/xcat-install(/.*)?/rootimg-statelite(/.*)?');
    });

done_testing();
