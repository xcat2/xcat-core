#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw(capture_merged);
use Cwd qw(getcwd);
use Errno qw(EACCES ENOENT);
use File::Slurper qw(write_binary);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::Process qw(run_command);

binmode STDOUT, ':raw' or die "Unable to set raw stdout: $!";

is_deeply( [ run_command( $^X, '-e', 'exit 0' ) ], [ 0, '' ],
    'a quiet successful command returns zero and empty output' );
is_deeply( [ run_command( $^X, '-e', 'exit 37' ) ], [ 37, '' ],
    'a quiet failure retains its exit code' );
is_deeply( [ run_command( $^X, '-e', 'exit 143' ) ], [ 143, '' ],
    'a normal high exit code is not mistaken for signal termination' );
is_deeply(
    [ run_command( $^X, '-e', 'binmode STDOUT; binmode STDERR; syswrite STDOUT, "out\n"; syswrite STDERR, "err\n"; exit 19' ) ],
    [ 19, "out\nerr\n" ],
    'stdout and stderr are merged without losing failure status'
);

my @arguments = ( '', 'two words', '$(false); *', "one\ntwo", q{a'b"c} );
is_deeply(
    [ run_command( $^X, '-e', 'print join "\0", @ARGV', @arguments ) ],
    [ 0, join "\0", @arguments ],
    'argument boundaries and shell metacharacters remain literal'
);

my $large_output = "x\0\xff\n" x 32768;
my ( $status, $output ) = run_command(
    $^X, '-e', 'binmode STDOUT; print "x\0\xff\n" x 32768'
);
is( $status, 0, 'a command with large output completes' );
is( $output, $large_output, 'binary output is complete and unchanged' );

binmode STDOUT, ':encoding(UTF-8)' or die "Unable to set stdout encoding: $!";
my @decoded = run_command( $^X, '-e', 'binmode STDOUT; print "\xe2\x82\xac"' );
binmode STDOUT, ':raw' or die "Unable to restore raw stdout: $!";
is_deeply( \@decoded, [ 0, "\x{20ac}" ],
    'capture follows the caller stdout encoding' );

my $directory = tempdir( CLEANUP => 1 );
my $executable = File::Spec->catfile( $directory, 'command with spaces' );
write_binary( $executable, "#!/bin/sh\nprintf 'single argument\\n'\n" );
chmod 0755, $executable or die "Unable to make $executable executable: $!";
is_deeply( [ run_command($executable) ], [ 0, "single argument\n" ],
    'a lone executable path with spaces is not passed through a shell' );
{
    local $ENV{PATH} = $directory;
    is_deeply( [ run_command('command with spaces') ],
        [ 0, "single argument\n" ], 'command lookup uses the caller PATH' );
}

{
    local $ENV{XCAT_PROCESS_TEST} = 'parent';
    {
        local $ENV{XCAT_PROCESS_TEST} = 'child';
        is_deeply(
            [ run_command( $^X, '-e', 'print $ENV{XCAT_PROCESS_TEST}' ) ],
            [ 0, 'child' ], 'a command inherits the caller environment' );
        is( $ENV{XCAT_PROCESS_TEST}, 'child', 'execution leaves caller values intact' );
    }
    {
        local %ENV = %ENV;
        delete $ENV{XCAT_PROCESS_TEST};
        is_deeply(
            [ run_command( $^X, '-e', 'print exists $ENV{XCAT_PROCESS_TEST} ? "set" : "absent"' ) ],
            [ 0, 'absent' ], 'removed environment values remain absent in the command' );
    }
}

my $original = getcwd();
chdir $directory or die "Unable to enter $directory: $!";
my $caller_directory = getcwd();
is_deeply( [ run_command( $^X, '-MCwd=getcwd', '-e', 'print getcwd' ) ],
    [ 0, $caller_directory ], 'the command inherits the caller directory' );
is( getcwd(), $caller_directory, 'execution leaves the caller directory intact' );
chdir $original or die "Unable to return to $original: $!";

my @nested_result;
my $outer_output = capture_merged {
    @nested_result = run_command( $^X, '-e', 'print "child"' );
    print "parent out\n";
    print STDERR "parent err\n";
};
is_deeply( \@nested_result, [ 0, 'child' ],
    'nested capture keeps command output separate' );
like( $outer_output, qr/parent out\n/, 'parent stdout is restored after capture' );
like( $outer_output, qr/parent err\n/, 'parent stderr is restored after capture' );
unlike( $outer_output, qr/child/, 'command output does not leak to the parent' );

chmod 0644, $executable or die "Unable to change $executable mode: $!";
for my $case (
    [ File::Spec->catfile( $directory, 'absent' ), ENOENT ],
    [ $executable, EACCES ],
) {
    my ( $command, $errno ) = @{$case};
    my $reason = do { local $! = $errno; "$!" };
    eval { my @result = run_command($command) };
    like( $@, qr/^Unable to execute \Q$command\E: \Q$reason\E\n\z/,
        'an execution failure keeps the command and operating-system error' );
}
my @signal_command = ( $^X, '-e', 'kill "KILL", $$; exit 0' );
eval { my @result = run_command(@signal_command) };
is( $@, "Command @signal_command terminated by signal 9\n",
    'signal termination cannot be mistaken for exit zero' );
eval { my @result = run_command() };
like( $@, qr/^Command is required\n/, 'an empty invocation fails explicitly' );
eval { scalar run_command( $^X, '-e', 'exit 37' ) };
like( $@, qr/^run_command must be called in list context\n/,
    'scalar context cannot discard a failed exit status' );
eval { run_command( $^X, '-e', 'exit 37' ); 1 };
like( $@, qr/^run_command must be called in list context\n/,
    'void context cannot discard a failed exit status' );
is_deeply( [ run_command( $^X, '-e', 'print "after failure"' ) ],
    [ 0, 'after failure' ], 'commands still run after a caught execution failure' );

done_testing();
