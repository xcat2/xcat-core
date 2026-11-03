# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::ConsolePolicy;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(console_device_name kernel_console_arguments);

# The serial console device of each architecture, keyed on the start of nodetype.arch. The order
# matters: the first match wins.
my @DEVICE_BY_ARCH = (
    # A POWER machine presents both the physical and the virtual serial port as a hypervisor
    # console, in a PowerVM LPAR and in a PowerKVM guest alike.
    [ qr/^ppc/i                  => 'hvc' ],
    [ qr/^s390/i                 => 'ttysclp' ],
    # SBSA requires a PL011 serial port, so this is what an aarch64 server and the aarch64 qemu
    # virt machine both present. An aarch64 platform that has a 16550 instead is not covered;
    # neither is a POWER machine without a hypervisor console.
    [ qr/^(?:aarch64|arm64|arm)/i => 'ttyAMA' ],
);

#---
# =head3 console_device_name
#
# Descriptions: The name Linux gives the serial console of an architecture, without the port
#               number. nodehm.serialport holds a port NUMBER, so each plugin that writes a
#               console= kernel argument has to supply the device name itself.
#
# Arguments: $arch -- nodetype.arch, or the osimage osarch
#
# Returns: 'hvc', 'ttysclp', 'ttyAMA', or 'ttyS' for anything else. ttyS is the default because
#          a 16550 at a numbered port is what the remaining architectures present.
#---
sub console_device_name {
    my ($arch) = @_;

    return 'ttyS' unless defined($arch) && length($arch);
    foreach my $rule (@DEVICE_BY_ARCH) {
        return $rule->[1] if $arch =~ $rule->[0];
    }
    return 'ttyS';
}

#---
# =head3 kernel_console_arguments
#
# Descriptions: The console= kernel arguments for a node, in the device of its architecture. The
#               callers append the flow-control suffix, so the speed comes last.
#
# Arguments: $arch  -- nodetype.arch
#            $port  -- nodehm.serialport, a port number
#            $speed -- nodehm.serialspeed. Omit it where the boot loader does not take one.
#
# Returns: "console=tty0 console=<device><port>[,<speed>]", or the empty string when no port is
#          set. tty0 stays in the list so a node with a display still shows the boot.
#---
sub kernel_console_arguments {
    my ( $arch, $port, $speed ) = @_;

    return '' unless defined($port) && length($port);
    my $console = 'console=tty0 console=' . console_device_name($arch) . $port;
    $console .= ',' . $speed if defined($speed) && length($speed);
    return $console;
}

1;
