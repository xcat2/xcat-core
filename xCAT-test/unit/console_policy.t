#!/usr/bin/env perl
#
# The console device each architecture is given, and the kernel arguments built from it.
#
# nodehm.serialport holds a port NUMBER, so the plugin that writes the kernel command line also
# names the device. Five plugins each chose between hvc and ttyS, so an aarch64 node was given
# console=ttyS0 while the platform presents pl011, which Linux names ttyAMA0.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::ConsolePolicy qw(console_device_name kernel_console_arguments);

# SBSA requires a PL011 serial port, and that is what the aarch64 qemu virt machine presents.
is( console_device_name('aarch64'), 'ttyAMA', 'aarch64 uses the pl011 console' );
is( console_device_name('arm64'),   'ttyAMA', 'the Debian spelling of aarch64 uses it too' );

# A POWER machine presents both the physical and the virtual port as a hypervisor console.
is( console_device_name('ppc64le'), 'hvc', 'ppc64le uses the hypervisor console' );
is( console_device_name('ppc64el'), 'hvc', 'the Debian spelling of ppc64le uses it too' );
is( console_device_name('ppc64'),   'hvc', 'big-endian ppc64 uses it as well' );

is( console_device_name('s390x'), 'ttysclp', 's390x uses the service-call console' );

# A 16550 at a numbered port is what the remaining architectures present.
is( console_device_name('x86_64'),  'ttyS', 'x86_64 uses the 16550 console' );
is( console_device_name('riscv64'), 'ttyS', 'riscv64 uses the 16550 console' );
is( console_device_name('i386'),    'ttyS', 'i386 uses the 16550 console' );

# An unset arch must still name a device, because the caller interpolates the result.
is( console_device_name(undef), 'ttyS', 'an unset architecture falls back to the 16550 console' );
is( console_device_name(''),    'ttyS', 'and so does an empty one' );

is(
    kernel_console_arguments( 'aarch64', '0', '115200' ),
    'console=tty0 console=ttyAMA0,115200',
    'an aarch64 node keeps tty0 and takes the pl011 port at its speed',
);
is(
    kernel_console_arguments( 'ppc64le', '1', '19200' ),
    'console=tty0 console=hvc1,19200',
    'the port number and the speed are the ones the node was given',
);

# Genesis takes no speed on this path, so the comma must not be written either.
is(
    kernel_console_arguments( 'aarch64', '0' ),
    'console=tty0 console=ttyAMA0',
    'an omitted speed leaves no trailing comma',
);

# nodehm.serialport unset is how a node says it has no serial console. The callers append the
# flow-control suffix to whatever comes back, so an empty string is the only safe answer.
is( kernel_console_arguments( 'aarch64', undef, '115200' ), '', 'no port means no console argument' );
is( kernel_console_arguments( 'aarch64', '',    '115200' ), '', 'and an empty port means the same' );

# Port 0 is the first port, not a missing one.
is(
    kernel_console_arguments( 'x86_64', 0, 115200 ),
    'console=tty0 console=ttyS0,115200',
    'port 0 is a port',
);

done_testing();
