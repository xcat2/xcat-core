# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::BootUtils;

use strict;
use warnings;

use xCAT::Utils;

sub volatile_addkcmdline {
    my ($kcmdline) = @_;

    return $kcmdline unless $kcmdline;

    my $cmdhashref = xCAT::Utils->splitkcmdline($kcmdline);
    return $cmdhashref->{volatile} // '';
}

1;
