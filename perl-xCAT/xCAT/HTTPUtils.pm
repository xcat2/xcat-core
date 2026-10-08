# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::HTTPUtils;

use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(httpport_suffix);

# Callers choose the default port before formatting it.
sub httpport_suffix {
    my $port = shift // '';
    return $port eq '80' ? '' : ":$port";
}

1;
