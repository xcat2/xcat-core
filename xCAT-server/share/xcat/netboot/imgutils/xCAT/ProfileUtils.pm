package xCAT::ProfileUtils;

use strict;
use warnings;

sub find_profile_asset {
    my ($base, $profile, $arch, $ext, @versions) = @_;

    my @suffixes = ((map { "$_.$arch" } @versions), $arch, @versions, '');
    foreach my $suffix (@suffixes) {
        my $file = "$base/$profile" . (length($suffix) ? ".$suffix" : '') . ".$ext";
        return $file if -r $file;
    }
    return '';
}

1;
