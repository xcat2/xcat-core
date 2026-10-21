#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempfile);
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );

sub read_file {
    my ($relative_path) = @_;
    my $path = File::Spec->catfile( $repo_root, split( '/', $relative_path ) );
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return ( $path, $contents );
}

sub shell_function {
    my ( $script, $name ) = @_;
    my ($definition) = $script =~ /((?:function\s+)?\Q$name\E\(\)\s*\n\{.*?^\})/ms;
    return $definition;
}

sub run_shell_function {
    my ( $definitions, $invocation, @args ) = @_;
    my $program = "$definitions\n$invocation";
    open( my $pipe, '-|', 'bash', '-c', $program, 'bash', @args )
      or die "Unable to run bash: $!";
    my $output = do { local $/; <$pipe> };
    close($pipe);
    is( $?, 0, "$invocation exits successfully" );
    chomp($output);
    return $output;
}

my ( $pre_path, $pre ) = read_file('xCAT-server/share/xcat/install/scripts/pre.rhels10');
my ( $post_path, $post ) = read_file('xCAT-server/share/xcat/install/scripts/post.xcat.rhels10');
my ( $updateflag_path, $updateflag ) = read_file('xCAT/postscripts/updateflag.awk');

is( system( 'bash', '-n', $pre_path ),  0, 'EL10 pre-install script has valid bash syntax' );
is( system( 'bash', '-n', $post_path ), 0, 'EL10 post-install script has valid bash syntax' );

unlike(
    $pre,
    qr/socket\.socket\(socket\.AF_INET,\s*socket\.SOCK_STREAM\)/,
    'EL10 installer callbacks do not hard-code IPv4 sockets'
);
is(
    scalar( () = $pre =~ /socket\.create_connection\(\('#ENV:MASTER_IP#'/g ),
    2,
    'both EL10 installer callback clients use family-neutral connections to the facing master address'
);
like( $pre, qr/socket\.getaddrinfo\(master, None, socket\.AF_UNSPEC,/, 'install monitor selects the listener family from the master address' );
like( $pre, qr/None, port, master_family, socket\.SOCK_STREAM, 0, socket\.AI_PASSIVE/, 'install monitor requests a passive listener only in the provisioning family' );
like( $pre, qr/socket\.IPV6_V6ONLY, 1/, 'IPv6 monitor listener rejects IPv4-mapped clients' );
like( $pre, qr/if address\[0\] not in allowed_peers:/, 'install monitor rejects callback clients other than the configured master' );
unlike( $pre, qr/os\.popen\(newcommand\)/, 'screen capture does not construct a shell command from network input' );
like( $pre, qr/screen and not screen\.isdigit\(\)/, 'screen capture accepts only a numeric virtual-console suffix' );

my $extract_url_host = shell_function( $pre, 'extract_url_host' );
ok( defined($extract_url_host), 'pre-install URL host helper is present' );
is(
    run_shell_function( $extract_url_host, 'extract_url_host "$1"', 'http://192.0.2.10:8080/install/repo' ),
    '192.0.2.10',
    'pre-install repository discovery preserves an IPv4 host'
);
is(
    run_shell_function( $extract_url_host, 'extract_url_host "$1"', 'http://[2001:db8::10]:8080/install/repo' ),
    '2001:db8::10',
    'pre-install repository discovery extracts a complete bracketed IPv6 literal'
);
is(
    run_shell_function( $extract_url_host, 'extract_url_host "$1"', 'https://provision.example.test/install/repo' ),
    'provision.example.test',
    'pre-install repository discovery preserves a hostname'
);
like(
    $pre,
    qr/grep -oE 'https\?:\/\/\(\\\[\[\^\]\]\+\\\]\|\[\^\[:space:\]\/?:\]\+\)\(:\[0-9\]\+\)\?'/,
    'kernel command-line URL discovery recognizes bracketed IPv6 authorities'
);

my $python = `command -v python3 2>/dev/null`;
chomp($python);
SKIP: {
    skip 'python3 is unavailable', 4 unless $python;
    foreach my $name (qw(baz foo)) {
        my ($source) = $pre =~ /cat >\/tmp\/\Q$name\E\.py <<'EOF'\n(.*?)\nEOF/ms;
        ok( defined($source), "$name.py installer helper is embedded" ) or next;
        $source =~ s/#ENV:MASTER_IP#/2001:db8::1/g;
        $source =~ s/#TABLE:site:key=xcatiport:value#/3002/g;
        my ( $fh, $path ) = tempfile();
        print {$fh} $source;
        close($fh);
        is(
            system( $python, '-c', 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")', $path ),
            0,
            "$name.py remains valid Python after template expansion"
        );
    }
}

my $format_uri_host = shell_function( $post, 'format_uri_host' );
my $format_host_port = shell_function( $post, 'format_host_port' );
ok( defined($format_uri_host),  'post-install URI host helper is present' );
ok( defined($format_host_port), 'post-install host-port helper is present' );
my $post_helpers = "$format_uri_host\n$format_host_port";
is(
    run_shell_function( $post_helpers, 'format_uri_host "$1"', '192.0.2.10' ),
    '192.0.2.10',
    'IPv4 URL hosts remain byte-for-byte unchanged'
);
is(
    run_shell_function( $post_helpers, 'format_uri_host "$1"', '2001:db8::10' ),
    '[2001:db8::10]',
    'IPv6 URL hosts are bracketed'
);
is(
    run_shell_function( $post_helpers, 'format_uri_host "$1"', '[2001:db8::10]' ),
    '[2001:db8::10]',
    'an already-bracketed IPv6 URL host is not double-bracketed'
);
is(
    run_shell_function( $post_helpers, 'format_host_port "$1" "$2"', '2001:db8::10', '3001' ),
    '[2001:db8::10]:3001',
    'OpenSSL receives an unambiguous IPv6 host-port endpoint'
);
like( $post, qr{http://\$\{MASTER_HTTP_HOST\}:\$\{HTTPPORT\}\$INSTALLDIR/postscripts/}, 'postscript tree URL uses the formatted master host' );
like( $post, qr{http://\$\{MASTER_HTTP_HOST\}:\$\{HTTPPORT\}\$TFTPDIR/mypostscripts/}, 'node postscript URL uses the formatted master host' );
unlike( $post, qr{http://\$MASTER_IP:}, 'post-install HTTP URLs never append a port to a raw master address' );
unlike( $post, qr/updateflag(?:\.awk)?\s+"\$MASTER"\s/, 'status callbacks do not depend on a possibly unresolved master hostname' );
is(
    scalar( () = $post =~ /updateflag(?:\.awk)?\s+"\$MASTER_IP"\s/g ),
    6,
    'every EL10 status callback uses the facing master address'
);

like( $updateflag, qr/netfamily = index\(xcatdhost, ":"\) \? "inet6" : "inet"/, 'updateflag selects the gawk IPv6 socket namespace for IPv6 literals' );
like( $updateflag, qr{ns = "/" netfamily "/tcp/0/" xcatdhost "/" xcatdport}, 'updateflag constructs the socket path from the selected family' );
like( $updateflag, qr/xcatdhost ~ \/\^\\\[\.\*\\\]\$\//, 'updateflag accepts a bracketed IPv6 host as input' );

done_testing();
