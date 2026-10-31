# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::BootUtils;

use strict;
use warnings;
use Exporter qw(import);

use xCAT::Utils;
use xCAT::Table;

our @EXPORT_OK = qw(find_genesis_boot_files grub2_kernel_commands);

sub find_genesis_boot_files {
    my ($tftpdir, $arch) = @_;
    return unless defined($arch) && $arch =~ /\A[A-Za-z0-9_]+\z/;

    my $directory = "$tftpdir/xcat";
    my $kernel = "genesis.kernel.$arch";
    return unless -r "$directory/$kernel";

    my $lzma = "genesis.fs.$arch.lzma";
    my $gzip = "genesis.fs.$arch.gz";
    my $initrd;
    if (-r "$directory/$lzma" && -r "$directory/$gzip") {
        $initrd = -C "$directory/$lzma" > -C "$directory/$gzip"
          ? $gzip
          : $lzma;
    } elsif (-r "$directory/$lzma") {
        $initrd = $lzma;
    } elsif (-r "$directory/$gzip") {
        $initrd = $gzip;
    }
    return unless defined($initrd);
    return ($kernel, $initrd);
}

sub volatile_addkcmdline {
    my ($kcmdline) = @_;

    return $kcmdline unless $kcmdline;

    my $cmdhashref = xCAT::Utils->splitkcmdline($kcmdline);
    return $cmdhashref->{volatile} // '';
}

#-------------------------------------------------------------------------------

=head3 grub2_kernel_commands

    Descriptions: The commands a grub2 image provides to load a kernel and an
                  initial ramdisk.

                  linuxefi and initrdefi come from a downstream patch. An image
                  built from upstream grub carries neither, and its linux command
                  performs the EFI handover itself. A node offered a command its
                  own image does not carry stops at the grub menu with
                  "can't find command `linuxefi'" and never asks for the kernel.

    Arguments:    $image the path of the grub2 image served to the node
                  $arch the architecture of the node
    Returns:      the kernel command and the initial ramdisk command

=cut

#-------------------------------------------------------------------------------
sub grub2_kernel_commands {
    my ($image, $arch) = @_;

    # linuxefi loads an EFI binary. x86 is the architecture whose grub2 loader is one, so
    # a ppc node takes linux whatever its image carries.
    return ('linux', 'initrd') unless defined($arch) && $arch =~ /x86/i;
    return ('linux', 'initrd') unless grub2_image_provides($image, 'linuxefi');
    return ('linuxefi', 'initrdefi');
}

#-------------------------------------------------------------------------------

=head3 grub2_image_provides

    Descriptions: Whether a grub2 image carries a command. grub records the name
                  of each command its modules register, so the name is present in
                  the image exactly when the command can be run.

    Arguments:    $image the path of the grub2 image
                  $command the name of the command
    Returns:      1 when the image carries the command, 0 otherwise

=cut

#-------------------------------------------------------------------------------
sub grub2_image_provides {
    my ($image, $command) = @_;

    return 0 unless defined($image) && defined($command) && length($command);
    return 0 unless -r $image;
    open(my $fh, '<:raw', $image) or return 0;
    my $found = 0;
    my $tail  = '';
    while (read($fh, my $chunk, 1 << 20)) {
        # A command name can straddle two reads, so keep the end of the last one.
        $found = 1 if ($tail . $chunk) =~ /\0\Q$command\E\0/;
        last if $found;
        $tail = substr($chunk, -length($command) - 1);
    }
    close($fh);
    return $found;
}

sub expand_node_template {
    my ($node, $text, $on_error) = @_;
    return $text unless defined($text);

    # Each initial token contributes to its pass's shared replacement budget.
    my $replacements_per_token = 16;
    my $remaining = $replacements_per_token * (() = $text =~ /#NODEATTRIB:[^:#]+:[^:#]+#/g);
    while ($text =~ /#NODEATTRIB:([^:#]+):([^:#]+)#/) {
        unless ($remaining--) {
            $on_error->("Node template expansion exceeded its replacement limit at #NODEATTRIB:$1:$2#");
            return;
        }
        my $table = xCAT::Table->new($1);
        my $entry = $table->getNodeAttribs($node, [$2]);
        my $value = $entry->{$2} // '';
        $text =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#/$value/;
    }
    $remaining = $replacements_per_token * (() = $text =~ /#TABLE:[^:#]+:[^:#]+:[^:#]+#/g);
    while ($text =~ /#TABLE:([^:#]+):([^:#]+):([^:#]+)#/) {
        unless ($remaining--) {
            $on_error->("Node template expansion exceeded its replacement limit at #TABLE:$1:$2:$3#");
            return;
        }
        my ($table_name, $key, $column) = ($1, $2, $3);
        if ($key =~ /THISNODE/ or $key =~ /\$NODE/) {
            my $table = xCAT::Table->new($table_name);
            my $entry = $table->getNodeAttribs($node, [$column]);
            my $value = $entry->{$column} // '';
            $text =~ s/#TABLE:([^:#]+):([^:#]+):([^:#]+)#/$value/;
        } else {
            $on_error->("Table key of $key not yet supported by boottarget mini-template");
            return;
        }
    }
    return $text;
}

1;
