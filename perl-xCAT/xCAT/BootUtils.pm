# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::BootUtils;

use strict;
use warnings;
use Exporter qw(import);

use xCAT::Utils;

our @EXPORT_OK = qw(_find_genesis_boot_files);

sub _find_genesis_boot_files {
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

1;
