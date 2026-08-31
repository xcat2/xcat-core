#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $postscript = repo_path(
    File::Spec->catfile( 'xCAT', 'postscripts', 'xcatdsklspost' ) );
my $library = repo_path(
    File::Spec->catfile( 'xCAT', 'postscripts', 'xcatlib.sh' ) );

is( system( 'bash', '-n', $postscript ), 0,
    'xcatdsklspost retains valid Bash syntax' );
is( system( 'bash', '-n', $library ), 0,
    'xcatlib retains valid Bash syntax' );

my ( $runner_fh, $runner ) = tempfile( UNLINK => 1 );
print {$runner_fh} <<'BASH';
source "$POST_TEST_LIBRARY"
xcatpost=$POST_TEST_ROOT
GETPOSTSCRIPT_ARGS=${POST_TEST_NODE-}

if [ "$POST_TEST_MODE" = "twice" ]; then
    first=$(fetch_mypostscript "$xcatpost" $GETPOSTSCRIPT_ARGS)
    first_status=$?
    second=$(fetch_mypostscript "$xcatpost" $GETPOSTSCRIPT_ARGS)
    second_status=$?
    printf 'first_status=%s\nfirst=%s\n' "$first_status" "$first"
    printf 'second_status=%s\nsecond=%s\n' "$second_status" "$second"
    exit 0
fi

fetch_mypostscript "$xcatpost" $GETPOSTSCRIPT_ARGS
BASH
close($runner_fh);

sub run_fetch {
    my (%options) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $responses = File::Spec->catdir( $root, 'responses' );
    mkdir($responses) or die "Unable to create $responses: $!";

    my $fetcher = File::Spec->catfile( $root, 'getpostscript.awk' );
    write_file(
        $fetcher,
        <<'SH'
#!/bin/sh
count=0
if [ -r "$POST_TEST_COUNTER" ]; then
    IFS= read -r count < "$POST_TEST_COUNTER"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$POST_TEST_COUNTER"
printf 'argc=%s argv=%s\n' "$#" "$*" >> "$POST_TEST_ARGV"
cat "$POST_TEST_RESPONSES/$count"
SH
    );
    chmod( 0755, $fetcher ) or die "Unable to make $fetcher executable: $!";

    my $index = 0;
    for my $response ( @{ $options{responses} } ) {
        $index++;
        write_file( File::Spec->catfile( $responses, $index ), $response );
    }

    my $target = File::Spec->catfile( $root, 'mypostscript' );
    write_file( $target, $options{preexisting} )
      if exists $options{preexisting};
    my $argv = File::Spec->catfile( $root, 'argv' );
    my $counter = File::Spec->catfile( $root, 'counter' );

    local %ENV = (
        %ENV,
        POST_TEST_ARGV      => $argv,
        POST_TEST_COUNTER   => $counter,
        POST_TEST_LIBRARY   => $library,
        POST_TEST_MODE      => $options{mode} // 'single',
        POST_TEST_NODE      => $options{node} // '',
        POST_TEST_RESPONSES => $responses,
        POST_TEST_ROOT      => $root,
    );

    open( my $output_fh, '-|', 'bash', '--noprofile', '--norc', $runner )
      or die "Unable to run xcatdsklspost helper: $!";
    my $output = do { local $/; <$output_fh> };
    close($output_fh);
    my $status = $? >> 8;

    return {
        argv   => -e $argv ? read_file($argv) : '',
        output => $output,
        status => $status,
        target => -e $target ? read_file($target) : undef,
    };
}

sub write_file {
    my ( $path, $contents ) = @_;
    open( my $fh, '>:raw', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh) or die "Unable to close $path: $!";
}

sub read_file {
    my ($path) = @_;
    open( my $fh, '<:raw', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "Unable to close $path: $!";
    return $contents;
}

my $decoded = run_fetch(
    node      => 'node01',
    responses => [ <<'XML' ],
<xcatresponse>
<data>  MASTER=192.0.2.1</data>
<data>  COMMAND=&lt;tag&gt; &amp; &quot;quoted&quot; &apos;single&apos;</data>
<data>  LITERAL=&amp;lt;</data>
<data>     </data>
<info>ignored</info>
</xcatresponse>
XML
);
is( $decoded->{status}, 0, 'a response containing MASTER succeeds' );
is( $decoded->{output}, "MASTER=192.0.2.1\n",
    'the helper returns the MASTER content used by the caller' );
is(
    $decoded->{target},
    "MASTER=192.0.2.1\nCOMMAND=<tag> & \"quoted\" 'single'\nLITERAL=&lt;\n",
    'the helper strips XML, empty lines, indentation, and decodes entities'
);
is( $decoded->{argv}, "argc=1 argv=node01\n",
    'the short node name is passed to getpostscript.awk' );

my $without_node = run_fetch(
    responses => [ "<data>MASTER=198.51.100.8</data>\n" ],
);
is( $without_node->{status}, 0, 'a fetch without a node name succeeds' );
is( $without_node->{argv}, "argc=0 argv=\n",
    'an empty node name does not add an argument' );

my $overwrite = run_fetch(
    preexisting => "MASTER=stale\n",
    responses   => [ "<data>POSTSCRIPT=ready</data>\n" ],
);
isnt( $overwrite->{status}, 0, 'a response without MASTER is incomplete' );
is( $overwrite->{output}, '', 'an incomplete response returns no MASTER content' );
is( $overwrite->{target}, "POSTSCRIPT=ready\n",
    'each fetch overwrites the previous mypostscript' );

my $empty = run_fetch( responses => [''] );
isnt( $empty->{status}, 0, 'an empty response is incomplete' );
is( $empty->{output}, '', 'an empty response returns no MASTER content' );
is( $empty->{target}, '', 'an empty response leaves an empty output file' );

my $retry = run_fetch(
    mode      => 'twice',
    node      => 'node02',
    responses => [
        "<data>POSTSCRIPT=not-ready</data>\n",
        "<data>MASTER=203.0.113.7</data>\n<data>POSTSCRIPT=ready</data>\n",
    ],
);
is( $retry->{status}, 0, 'two consecutive fetches complete' );
is(
    $retry->{output},
    "first_status=1\nfirst=\nsecond_status=0\nsecond=MASTER=203.0.113.7\n",
    'a later response supplies the MASTER content used to stop retries'
);
is(
    $retry->{target},
    "MASTER=203.0.113.7\nPOSTSCRIPT=ready\n",
    'the successful retry replaces the incomplete response'
);
is( $retry->{argv}, "argc=1 argv=node02\nargc=1 argv=node02\n",
    'each fetch retry passes the same short node name' );

done_testing();
