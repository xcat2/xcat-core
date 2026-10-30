#!/usr/bin/env perl
# The [Object_*] blocks of an xcattest conf declare xCAT node attributes, and xcattest applies
# them with chdef. vm.othersettings holds several settings separated by a semicolon, which is the
# syntax the kvm plugin reads:
#
#     vmothersetting=cpumode:host-passthrough;firmware:efi-secureboot
#
# Two things have to hold for that line to reach the node. The reader has to keep the whole
# value, and the chdef command has to quote it, because xcattest runs every command through
# /bin/bash -c and an unquoted semicolon ends the command there.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

require xCAT::Test::Conf;

# The reader keeps every setting of a multi-setting value.
is_deeply(
    [ xCAT::Test::Conf::object_attr('    vmothersetting=cpumode:host-passthrough;firmware:efi-secureboot') ],
    [ 'vmothersetting', 'cpumode:host-passthrough;firmware:efi-secureboot' ],
    'an [Object_*] value keeps the settings after its first semicolon'
);

# The values the reader already took stay as they are.
is_deeply(
    [ xCAT::Test::Conf::object_attr('    vmnics=virbr-p147,virbr-p147,virbr-p147') ],
    [ 'vmnics', 'virbr-p147,virbr-p147,virbr-p147' ],
    'a comma-separated value is unchanged'
);
is_deeply(
    [ xCAT::Test::Conf::object_attr('    vmstorage=dir:///var/lib/libvirt/images/') ],
    [ 'vmstorage', 'dir:///var/lib/libvirt/images/' ],
    'a value with a colon and slashes is unchanged'
);
is_deeply( [ xCAT::Test::Conf::object_attr('Name=xcat147-cn-tmp-243') ],
    [ 'Name', 'xcat147-cn-tmp-243' ], 'the Name line is read like any other attribute' );
is_deeply( [ xCAT::Test::Conf::object_attr('this line has no equals sign') ],
    [], 'a line with no assignment yields no attribute' );

# chdef runs under /bin/bash -c, so each assignment is quoted. Without the quoting the shell
# reads the semicolon as a command separator and chdef gets half the value.
my $cmd = xCAT::Test::Conf::chdef_command( 'node', 'cn1',
    { vmothersetting => 'cpumode:host-passthrough;firmware:efi-secureboot' } );
like( $cmd, qr/^chdef -t 'node' -o 'cn1' /, 'chdef_command names the type and the object' );
like(
    $cmd,
    qr/'vmothersetting=cpumode:host-passthrough;firmware:efi-secureboot'/,
    'and quotes the assignment, so bash does not read the semicolon as a command separator'
);

# A single quote inside a value must not end the quoting.
like(
    xCAT::Test::Conf::chdef_command( 'node', 'cn1', { usercomment => "it's here" } ),
    qr/'usercomment=it'\\''s here'/,
    'a single quote in a value is escaped inside the quoted assignment'
);

# The order of the assignments is fixed, so two runs of one conf build the same command.
is( xCAT::Test::Conf::chdef_command( 'node', 'cn1', { b => '2', a => '1', c => '3' } ),
    "chdef -t 'node' -o 'cn1' 'a=1' 'b=2' 'c=3'",
    'the assignments are sorted by attribute name' );

done_testing();
