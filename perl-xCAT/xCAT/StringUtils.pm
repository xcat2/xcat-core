# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::StringUtils;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(trim);

sub trim {
    my ($value) = @_;

    return $value unless defined($value);

    $value =~ s/^\s+|\s+$//g;
    return $value;
}

1;
