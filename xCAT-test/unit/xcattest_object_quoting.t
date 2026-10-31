#!/usr/bin/env perl
# The chdef command xcattest builds when it applies an [Object_*] section of a conf.
#
# xcattest joined each attribute to the command unquoted and ran the result through bash. A
# conf carries values a shell reads as syntax: vmothersetting separates its settings with a
# semicolon, so "vmothersetting=cpumode:host-passthrough;firmware:efi-insecure" ended the
# chdef at the semicolon. The node kept only the first setting, the compute node was defined
# with no firmware, and it came up as a BIOS guest that cannot network boot over IPv6.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Text::ParseWords qw(shellwords);

use xCAT::Test::OS;

# A value a shell would read as two commands.
is( xCAT::Test::OS::object_definition_command(
        'node', 'cn1', { vmothersetting => 'cpumode:host-passthrough;firmware:efi-insecure' } ),
    q{chdef -t 'node' -o 'cn1' 'vmothersetting=cpumode:host-passthrough;firmware:efi-insecure'},
    'a semicolon in a value stays inside one command' );

# Several attributes keep a stable order, so the command is reproducible.
is( xCAT::Test::OS::object_definition_command(
        'node', 'cn1', { arch => 'x86_64', netboot => 'grub2' } ),
    q{chdef -t 'node' -o 'cn1' 'arch=x86_64' 'netboot=grub2'},
    'every value is quoted, in attribute order' );

# The other characters a conf can carry.
is( xCAT::Test::OS::shell_quote('a b'),      q{'a b'},      'a space is quoted' );
is( xCAT::Test::OS::shell_quote('a$b'),      q{'a$b'},      'a dollar sign is quoted' );
is( xCAT::Test::OS::shell_quote('a`b`'),     q{'a`b`'},     'a backtick is quoted' );
is( xCAT::Test::OS::shell_quote(q{it's}),    q{'it'\''s'},  'a single quote is escaped' );
is( xCAT::Test::OS::shell_quote(undef),      q{''},         'an undefined value gives an empty argument' );

# The arguments the command actually delivers, which is the point of the quoting.
is_deeply(
    [ shellwords( xCAT::Test::OS::object_definition_command(
            'node', 'cn1',
            { vmothersetting => 'cpumode:host-passthrough;firmware:efi-insecure' } ) ) ],
    [ 'chdef', '-t', 'node', '-o', 'cn1',
        'vmothersetting=cpumode:host-passthrough;firmware:efi-insecure' ],
    'chdef receives the whole setting as one argument'
);

# ---- the chtab command for a [Table_*] section -------------------------------------------
# xcattest built this one by interpolation, with the row selector unquoted. The row of a
# [Table_vm] section carries othersettings, whose settings a semicolon separates, so the
# command ended at the semicolon and the shell ran the rest of the value as a command.
is( xCAT::Test::OS::table_row_command(
        'vm', 'node', 'cn1',
        { othersettings => 'cpumode:host-passthrough;firmware:efi-secureboot' } ),
    q{chtab 'node=cn1' 'vm.othersettings=cpumode:host-passthrough;firmware:efi-secureboot'},
    'the row selector is quoted with every other argument' );

is_deeply(
    [ shellwords( xCAT::Test::OS::table_row_command(
            'vm', 'node', 'cn1',
            { othersettings => 'cpumode:host-passthrough;firmware:efi-secureboot' } ) ) ],
    [ 'chtab', 'node=cn1',
        'vm.othersettings=cpumode:host-passthrough;firmware:efi-secureboot' ],
    'chtab receives the whole setting as one argument, not two commands'
);

# __KEY__ names the key column and is not a column of its own.
is_deeply(
    [ shellwords( xCAT::Test::OS::table_row_command(
            'vm', 'node', 'cn1',
            { __KEY__ => 'node', cpus => '4', memory => '8192' } ) ) ],
    [ 'chtab', 'node=cn1', 'vm.cpus=4', 'vm.memory=8192' ],
    'the key marker is not written as an attribute'
);

# A row name a shell would read as syntax.
is_deeply(
    [ shellwords( xCAT::Test::OS::table_row_command(
            'site', 'key', 'a b', { value => 'x;y' } ) ) ],
    [ 'chtab', 'key=a b', 'site.value=x;y' ],
    'a space in the row name stays in one argument'
);

# ---- what the conf parser keeps ----------------------------------------------------------
# The quoting above is useless if the value never reaches it whole. The value class had no
# ';', so "othersettings=cpumode:host-passthrough;firmware:efi-secureboot" was read as
# "cpumode:host-passthrough" and the rest was dropped with no warning.
is_deeply(
    [ xCAT::Test::OS::parse_conf_assignment(
            'othersettings=cpumode:host-passthrough;firmware:efi-secureboot') ],
    [ 'othersettings', 'cpumode:host-passthrough;firmware:efi-secureboot' ],
    'a semicolon value is read whole'
);
is_deeply(
    [ xCAT::Test::OS::parse_conf_assignment('net=2001:db8:176::') ],
    [ 'net', '2001:db8:176::' ],
    'an IPv6 network keeps its colons'
);
is_deeply(
    [ xCAT::Test::OS::parse_conf_assignment('export=/opt/xcat-ci-shared/isos') ],
    [ 'export', '/opt/xcat-ci-shared/isos' ],
    'a path keeps its slashes'
);
is_deeply(
    [ xCAT::Test::OS::parse_conf_assignment('[Table_vm]') ],
    [],
    'a section header is not an assignment'
);

done_testing();
