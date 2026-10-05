#!/usr/bin/env perl
# Starts a private Apache that includes the xcat-ws.conf fragment from the
# source tree, once without mod_rewrite and once with it, and checks what the
# REST aliases and a provisioning path answer.
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_text);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX qw(WNOHANG _exit setsid);
use Test::More;
use Time::HiRes qw(sleep);

my $fragment = $ENV{XCAT_WS_CONF}
  || File::Spec->rel2abs("$FindBin::Bin/../../xCAT-server/xCAT-wsapi/xcat-ws.conf");
plan skip_all => "the xcat-ws.conf fragment is not at $fragment"
  unless -r $fragment;

my $httpd = find_httpd();
plan skip_all => 'no Apache httpd binary is installed' unless $httpd;

my $builtin = join( "\n", `$httpd -l 2>/dev/null` );
my $moddir  = find_module_dir();
plan skip_all => 'no Apache module directory with mod_alias.so is present'
  unless $moddir;

#-----------------------------------------------------------------------------

=head3 find_httpd

    Descriptions: Finds the Apache binary of the distribution.
    Arguments: none
    Returns: the path, or undef when no binary is installed.
=cut

#-----------------------------------------------------------------------------
sub find_httpd {
    foreach my $path (qw(/usr/sbin/httpd /usr/sbin/apache2 /usr/sbin/httpd-prefork)) {
        return $path if -x $path;
    }
    return undef;
}

#-----------------------------------------------------------------------------

=head3 find_module_dir

    Descriptions: Finds the directory that holds the Apache shared modules.
    Arguments: none
    Returns: the path, or undef when no candidate holds mod_alias.so.
=cut

#-----------------------------------------------------------------------------
sub find_module_dir {
    foreach my $dir (
        qw(/usr/lib64/httpd/modules /usr/lib/httpd/modules /usr/lib/apache2/modules
        /usr/lib64/apache2-prefork /usr/lib64/apache2)
      )
    {
        return $dir if -e "$dir/mod_alias.so";
    }
    return undef;
}

#-----------------------------------------------------------------------------

=head3 load_module_lines

    Descriptions: Builds the LoadModule lines for the modules that are not
                  compiled into the binary.
    Arguments: the module names without the mod_ prefix
    Returns: the configuration text.
=cut

#-----------------------------------------------------------------------------
sub load_module_lines {
    my (@names) = @_;
    my $text = '';
    foreach my $name (@names) {
        next if $builtin =~ /\bmod_\Q$name\E\.c\b/;
        die "mod_$name.so is not in $moddir" unless -e "$moddir/mod_$name.so";
        $text .= "LoadModule ${name}_module $moddir/mod_$name.so\n";
    }
    return $text;
}

#-----------------------------------------------------------------------------

=head3 free_port

    Descriptions: Asks the kernel for a free TCP port on the loopback address.
    Arguments: none
    Returns: the port number.
=cut

#-----------------------------------------------------------------------------
sub free_port {
    my $sock = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp',
    ) or die "Unable to find a free port: $!";
    my $port = $sock->sockport();
    close($sock);
    return $port;
}

#-----------------------------------------------------------------------------

=head3 write_config

    Descriptions: Writes an Apache configuration that serves a stub REST CGI
                  through the xCAT aliases and a provisioning file under
                  /install, then includes the fragment.
    Arguments: the work directory, the port, true to load mod_rewrite
    Returns: the path of the configuration file.
=cut

#-----------------------------------------------------------------------------
sub write_config {
    my ( $dir, $port, $with_rewrite ) = @_;

    my @modules = qw(mpm_prefork unixd authz_core alias cgi);
    push @modules, 'rewrite' if $with_rewrite;
    @modules = grep { $_ ne 'mpm_prefork' } @modules
      if $builtin =~ /\b(prefork|worker|event)\.c\b/;

    my $user = '';
    if ( $> == 0 ) {
        my $group = getgrgid( ( getpwnam('nobody') )[3] );
        $user = "User nobody\nGroup $group\n";
    }

    # UseCanonicalName gives the fragment SERVER_PORT 80 on a private port.
    my $conf = load_module_lines(@modules) . <<"EOF";
ServerRoot $dir
ServerName localhost:80
UseCanonicalName On
Listen 127.0.0.1:$port
PidFile $dir/httpd.pid
DefaultRuntimeDir $dir
ErrorLog $dir/error_log
LogLevel warn
$user
DocumentRoot $dir/htdocs
<Directory />
    AllowOverride None
    Require all denied
</Directory>
<Directory $dir/htdocs>
    Require all granted
</Directory>
Alias /install $dir/install
<Directory $dir/install>
    Require all granted
</Directory>
ScriptAlias /xcatws $dir/ws/xcatws.cgi
ScriptAlias /xcatwsv2 $dir/ws/xcatws.cgi
Include $fragment
EOF

    my $path = "$dir/httpd.conf";
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print $fh $conf;
    close($fh) or die "Unable to close $path: $!";
    return $path;
}

#-----------------------------------------------------------------------------

=head3 make_tree

    Descriptions: Creates the document tree, the provisioning file and the
                  stub REST CGI under a new directory.
    Arguments: none
    Returns: the directory.
=cut

#-----------------------------------------------------------------------------
sub make_tree {
    my $dir = tempdir( CLEANUP => 1 );

    # Apache drops to nobody when the test runs as root.
    chmod 0755, $dir or die "Unable to chmod $dir: $!";
    foreach my $sub (qw(htdocs install ws)) {
        mkdir "$dir/$sub" or die "Unable to create $dir/$sub: $!";
    }

    open( my $probe, '>', "$dir/install/probe.txt" ) or die "probe.txt: $!";
    print $probe "install-probe\n";
    close($probe);

    my $cgi = "$dir/ws/xcatws.cgi";
    open( my $fh, '>', $cgi ) or die "Unable to write $cgi: $!";
    print $fh "#!/bin/sh\nprintf 'Content-Type: text/plain\\n\\nxcatws-stub\\n'\n";
    close($fh);
    chmod 0755, $cgi or die "Unable to chmod $cgi: $!";
    return $dir;
}

#-----------------------------------------------------------------------------

=head3 start_httpd

    Descriptions: Starts Apache in the foreground and waits for its port.
    Arguments: the configuration file, the port, the work directory
    Returns: the process id.
=cut

#-----------------------------------------------------------------------------
sub start_httpd {
    my ( $conf, $port, $dir ) = @_;

    my $pid = fork();
    die "Unable to fork: $!" unless defined $pid;
    if ( $pid == 0 ) {

        # prefork signals its whole process group when it stops.
        setsid();
        open( STDIN,  '<', '/dev/null' );
        open( STDOUT, '>', "$dir/stdout" );
        open( STDERR, '>&', \*STDOUT );
        { exec( $httpd, '-f', $conf, '-DFOREGROUND' ) };
        _exit(127);
    }

    foreach ( 1 .. 100 ) {
        if ( waitpid( $pid, WNOHANG ) == $pid ) {
            diag( read_log("$dir/stdout") . read_log("$dir/error_log") );
            die "Apache exited with status $?";
        }
        my $sock = IO::Socket::INET->new( PeerAddr => "127.0.0.1:$port" );
        return $pid if $sock;
        sleep 0.1;
    }
    stop_httpd($pid);
    die "Apache did not listen on port $port";
}

#-----------------------------------------------------------------------------

=head3 stop_httpd

    Descriptions: Stops the Apache parent process and reaps it.
    Arguments: the process id
    Returns: nothing.
=cut

#-----------------------------------------------------------------------------
sub stop_httpd {
    my ($pid) = @_;
    kill 'TERM', $pid;
    waitpid( $pid, 0 );
    return;
}

#-----------------------------------------------------------------------------

=head3 read_log

    Descriptions: Reads an Apache log for a diagnostic message.
    Arguments: the path
    Returns: the contents, or an empty string when the file is absent.
=cut

#-----------------------------------------------------------------------------
sub read_log {
    my ($path) = @_;
    return -e $path ? read_text($path) : '';
}

#-----------------------------------------------------------------------------

=head3 get

    Descriptions: Sends one GET request to the private Apache.
    Arguments: the port, the request path
    Returns: the status code, the Location header and the body.
=cut

#-----------------------------------------------------------------------------
sub get {
    my ( $port, $path ) = @_;
    my $sock = IO::Socket::INET->new( PeerAddr => "127.0.0.1:$port", Timeout => 10 )
      or die "Unable to connect to port $port: $!";
    print $sock "GET $path HTTP/1.0\r\nHost: localhost\r\n\r\n";
    local $/;
    my $response = <$sock>;
    close($sock);

    my ($status) = $response =~ m{^HTTP/\S+\s+(\d+)};
    my ($location) = $response =~ m{^Location:\s*(\S+)}mi;
    my ( undef, $body ) = split( /\r\n\r\n/, $response, 2 );
    return ( $status // 0, $location // '', $body // '' );
}

#-----------------------------------------------------------------------------

=head3 with_httpd

    Descriptions: Runs a block of checks against a private Apache.
    Arguments: true to load mod_rewrite, the block, which gets the port
    Returns: nothing.
=cut

#-----------------------------------------------------------------------------
sub with_httpd {
    my ( $with_rewrite, $code ) = @_;
    my $dir  = make_tree();
    my $port = free_port();
    my $conf = write_config( $dir, $port, $with_rewrite );

    my $syntax = `$httpd -t -f $conf 2>&1`;
    is( $?, 0, ( $with_rewrite ? 'with' : 'without' ) . ' mod_rewrite the configuration parses' )
      or diag($syntax);

    my $pid = start_httpd( $conf, $port, $dir );
    my $ok    = eval { $code->($port); 1 };
    my $error = $@;
    stop_httpd($pid);
    die $error unless $ok;
    return;
}

my @rest_paths = ( '/xcatws/version', '/xcatwsv2/version', '/xcatws', '/xcatwsv2' );

subtest 'without mod_rewrite' => sub {
    with_httpd(
        0,
        sub {
            my ($port) = @_;
            foreach my $path (@rest_paths) {
                my ( $status, undef, $body ) = get( $port, $path );
                is( $status, 403, "$path answers 403" );
                unlike( $body, qr/xcatws-stub/, "$path does not run the REST CGI" );
            }
            my ( $status, undef, $body ) = get( $port, '/install/probe.txt' );
            is( $status, 200, '/install is served' );
            like( $body, qr/install-probe/, '/install returns the file' );
        }
    );
};

subtest 'with mod_rewrite' => sub {
    with_httpd(
        1,
        sub {
            my ($port) = @_;
            foreach my $alias (qw(xcatws xcatwsv2)) {
                my ( $status, $location ) = get( $port, "/$alias/version" );
                is( $status, 302, "/$alias/version answers 302" );
                is( $location, "https://localhost/$alias/version",
                    "/$alias/version redirects to https" );
            }
            my ( $status, undef, $body ) = get( $port, '/install/probe.txt' );
            is( $status, 200, '/install is served' );
            like( $body, qr/install-probe/, '/install returns the file' );
        }
    );
};

done_testing();
