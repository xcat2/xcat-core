package xCAT::MediaPerms;

use strict;
use warnings;

use File::Find ();

#-------------------------------------------------------------------------------

=head1 NAME

xCAT::MediaPerms - the modes of a copied install tree

=head1 DESCRIPTION

xCAT serves the install directory over HTTP, and copycds copies the media with the modes the
media carries. EL media ships the EFI binaries of its boot loader mode 0700, so the web server
cannot read them and a node that fetches one over HTTP is answered 403.

=cut

#-------------------------------------------------------------------------------

=head3 readable_mode

    Descriptions:
        The mode one path needs so that the web server can read it.

        Read permission for the group and for others. A directory also needs search
        permission, because a mode without it hides the files under it. No write permission,
        and no execute permission on a file that has none.
    Arguments:
        $mode - the current mode, as stat reports it
        $is_dir - true for a directory
    Returns:
        the new mode, or undef when the path needs no change

=cut

#-------------------------------------------------------------------------------
sub readable_mode {
    my ($mode, $is_dir) = @_;
    return undef unless defined $mode;
    $mode &= 07777;
    my $wanted = $mode | 0044;
    $wanted |= 0011 if $is_dir;
    return undef if $wanted == $mode;
    return $wanted;
}

#-------------------------------------------------------------------------------

=head3 make_readable

    Descriptions:
        Give every path under one directory the mode readable_mode names. The directory
        itself is included.
    Arguments:
        $dir - the directory, which need not exist
    Returns:
        the number of paths whose mode changed

=cut

#-------------------------------------------------------------------------------
sub make_readable {
    my ($dir) = @_;
    return 0 unless defined($dir) and -d $dir;

    my $changed = 0;
    File::Find::find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                # A symbolic link carries no mode of its own, and chmod would follow it out of
                # the tree.
                return if -l $path;
                my @st = stat $path or return;
                my $new = readable_mode($st[2], -d _) or return;
                $changed++ if chmod $new, $path;
            },
        },
        $dir
    );
    return $changed;
}

1;
