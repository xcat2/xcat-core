package XCAT::BuildUtils;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(targetarch_from_target);

sub targetarch_from_target {
    my ( $target, $default_arch ) = @_;
    return $default_arch unless defined($target) && length($target);

    my @parts = map {
        my $part = lc($_);
        $part =~ s/^\s+|\s+$//g;
        $part;
    } split /-/, $target;

    for my $part (reverse @parts) {
        return $part
          if $part =~ /^(?:x86_64|i[3-6]86|ppc64le|ppc64|aarch64|riscv64|s390x|armv7hl)$/;
    }
    return $parts[-1];
}

1;
