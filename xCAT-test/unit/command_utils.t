use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";

use Cwd qw/getcwd/;
use File::Path qw/make_path/;
use File::Slurper qw/write_text/;
use File::Temp qw/tempdir/;
use Test::More;

use xCAT::CommandUtils;

is_deeply(
    \@xCAT::CommandUtils::SYSTEM_FALLBACK_DIRS,
    [qw(/usr/sbin /usr/bin /sbin /bin)],
    'the built-in system fallback order matches the replaced callers'
);

my $root = tempdir(CLEANUP => 1);
my $first_dir = "$root/first";
my $second_dir = "$root/second";
my $fallback_dir = "$root/fallback";
make_path( $first_dir, $second_dir, $fallback_dir, "$root/relative" );

sub write_executable {
    my ($path) = @_;
    write_text( $path, "#!/bin/sh\nexit 0\n" );
    chmod 0755, $path or die "Unable to make $path executable: $!";
    return $path;
}

my $first_tool = write_executable("$first_dir/xcat-command-utils-tool");
my $second_tool = write_executable("$second_dir/xcat-command-utils-tool");

is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-tool',
        path          => "$first_dir:$second_dir",
        fallback_dirs => [],
    ),
    $first_tool,
    'PATH entries are searched in order'
);

chmod 0644, $first_tool or die "Unable to remove execute permission from $first_tool: $!";
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-tool',
        path          => "$first_dir:$second_dir",
        fallback_dirs => [],
    ),
    $second_tool,
    'non-executable candidates are skipped'
);

{
    local $ENV{PATH} = $second_dir;
    is(
        xCAT::CommandUtils::find_executable('xcat-command-utils-tool'),
        $second_tool,
        'the process PATH is used by default'
    );
    is(
        xCAT::CommandUtils::find_executable(
            'xcat-command-utils-tool',
            path          => $first_dir,
            fallback_dirs => [],
        ),
        undef,
        'an explicit path overrides the process PATH'
    );
}

my $fallback_tool = write_executable("$fallback_dir/xcat-command-utils-fallback");
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-fallback',
        path          => '',
        fallback_dirs => [ '', $fallback_dir ],
    ),
    $fallback_tool,
    'custom fallback directories are searched after PATH and ignore empty entries'
);
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-fallback',
        path          => '',
        fallback_dirs => [],
    ),
    undef,
    'fallback lookup can be disabled'
);
is(
    xCAT::CommandUtils::find_executable(
        'bin',
        path          => '',
        fallback_dirs => [''],
    ),
    undef,
    'empty fallback entries are ignored instead of matching executable root directories'
);
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-tool',
        path          => '',
        fallback_dirs => [$first_dir],
    ),
    undef,
    'non-executable fallback candidates are skipped'
);

my $fallback_order_first = write_executable("$first_dir/xcat-command-utils-fallback-order");
write_executable("$second_dir/xcat-command-utils-fallback-order");
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-fallback-order',
        path          => '',
        fallback_dirs => [ $first_dir, $second_dir ],
    ),
    $fallback_order_first,
    'custom fallback directories are searched in order'
);

my $path_collision = write_executable("$second_dir/xcat-command-utils-collision");
write_executable("$fallback_dir/xcat-command-utils-collision");
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-collision',
        path          => $second_dir,
        fallback_dirs => [$fallback_dir],
    ),
    $path_collision,
    'PATH matches take precedence over fallback matches'
);

my $system_shell = xCAT::CommandUtils::find_executable( 'sh', path => '' );
my ($expected_system_shell) = grep { -x "$_/sh" } qw(/usr/sbin /usr/bin /sbin /bin);
is(
    $system_shell,
    defined($expected_system_shell) ? "$expected_system_shell/sh" : undef,
    'standard system directories are searched by default'
);

my $original_dir = getcwd();
chdir($root) or die "Unable to enter $root: $!";
is(
    xCAT::CommandUtils::find_executable(
        'bin',
        path          => ":$second_dir",
        fallback_dirs => [],
    ),
    undef,
    'empty PATH entries are ignored instead of matching executable root directories'
);

write_executable("$root/relative/xcat-command-utils-relative");
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-relative',
        path          => 'relative',
        fallback_dirs => [],
    ),
    'relative/xcat-command-utils-relative',
    'relative PATH entries preserve the existing candidate path shape'
);

make_path("$root/0");
write_executable("$root/0/xcat-command-utils-zero-entry");
is(
    xCAT::CommandUtils::find_executable(
        'xcat-command-utils-zero-entry',
        path          => "0:$second_dir",
        fallback_dirs => [],
    ),
    undef,
    'a PATH component named zero retains the existing falsy-entry behavior'
);
chdir($original_dir) or die "Unable to restore $original_dir: $!";

my $marker = "$root/shell-was-invoked";
my $literal_name = 'xcat-command-utils;touch shell-was-invoked';
my $literal_tool = write_executable("$second_dir/$literal_name");
chdir($root) or die "Unable to enter $root for shell-safety lookup: $!";
is(
    xCAT::CommandUtils::find_executable(
        $literal_name,
        path          => $second_dir,
        fallback_dirs => [],
    ),
    $literal_tool,
    'command names are treated as filesystem paths without shell interpretation'
);
ok( !-e $marker, 'executable lookup never invokes a shell' );
chdir($original_dir) or die "Unable to restore $original_dir: $!";

is(
    xCAT::CommandUtils::find_executable( undef, path => $second_dir ),
    undef,
    'an undefined command is not searched'
);
is(
    xCAT::CommandUtils::find_executable( '', path => $second_dir ),
    undef,
    'an empty command is not searched'
);

done_testing();
