package XCAT::Test::Sandbox;

use strict;
use warnings;

use Exporter qw(import);
use File::Basename ();
use File::Path ();
use File::Spec;
use File::Temp ();
use POSIX ();

our @EXPORT_OK = qw(
  replace_required replace_required_re assert_no_host_paths
  stub_bin run_confined confine_self confinement
);

# Where real tools are looked up. The caller's PATH is not used: it may hold stubs of its own.
my @SYSTEM_PATH = qw(/usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin);

# Paths that hold host configuration or state. A rewritten product script that still names one
# of them would act on the host.
my @HOST_PREFIXES = qw(
  /etc /var /root /home /boot /opt /srv /install /tftpboot /xcatpost /proc/cmdline /lib/mkinitrd
);

# What a confined command may read but not write, as root.
my @READ_ONLY = qw(/etc /var /root /home /boot /usr /opt /srv /install /tftpboot /xcatpost);

my $placeholders = 0;
my $mode;

#-------------------------------------------------------------------------------

=head3 replace_required

    Descriptions: Rewrites every occurrence of a string, and dies when there is none. A
                  sandbox rewrite that matches nothing leaves the original path in place, so
                  the code under test would act on the host.
                  The occurrences go through a placeholder first: the replacement usually
                  contains the original ("/etc/x" becomes "$root/etc/x"), and a check made
                  after the final substitution would find it there.
    Arguments:
        $text_ref - a reference to the text to rewrite
        $from     - the string to replace
        $to       - its replacement
    Returns: the number of occurrences replaced

=cut

#-------------------------------------------------------------------------------
sub replace_required {
    my ( $text_ref, $from, $to ) = @_;

    die "replace_required: the string to replace is empty\n" unless defined $from && length $from;
    my $token = _placeholder();
    my $count = ( $$text_ref =~ s/\Q$from\E/$token/g );
    die "replace_required: '$from' does not occur, so the rewrite would redirect nothing\n" unless $count;
    die "replace_required: '$from' is still present after the rewrite\n" if index( $$text_ref, $from ) >= 0;
    $$text_ref =~ s/\Q$token\E/$to/g;

    return $count;
}

#-------------------------------------------------------------------------------

=head3 replace_required_re

    Descriptions: replace_required for a pattern. The replacement is a plain string.
    Arguments:
        $text_ref - a reference to the text to rewrite
        $pattern  - a compiled regex
        $to       - the replacement string
    Returns: the number of matches replaced

=cut

#-------------------------------------------------------------------------------
sub replace_required_re {
    my ( $text_ref, $pattern, $to ) = @_;

    my $token = _placeholder();
    my $count = ( $$text_ref =~ s/$pattern/$token/g );
    die "replace_required_re: $pattern does not match, so the rewrite would redirect nothing\n" unless $count;
    die "replace_required_re: $pattern still matches after the rewrite\n" if $$text_ref =~ $pattern;
    $$text_ref =~ s/\Q$token\E/$to/g;

    return $count;
}

#-------------------------------------------------------------------------------

=head3 assert_no_host_paths

    Descriptions: Dies when a rewritten script still names a host path outside the scratch
                  root. It catches a path respelled so that a rewrite no longer matches, e.g.
                  `etcdir=/etc; rm "$etcdir/resolv.conf"`.
                  A path right after a variable name (`$MNTDIR/etc`) is taken as relative to
                  that variable, which the test sets.
    Arguments:
        $text - the script
        %opt  - root => the scratch root; prefixes => [...] to replace the default list;
                allow => [ string or regex, ... ] lines to accept
    Returns: nothing

=cut

#-------------------------------------------------------------------------------
sub assert_no_host_paths {
    my ( $text, %opt ) = @_;

    my @prefixes    = @{ $opt{prefixes} || \@HOST_PREFIXES };
    my $alternation = join( '|', map { quotemeta } @prefixes );
    my $root        = $opt{root};
    my $host_path   = qr/(?<![\w}\])])(?:$alternation)\b/;

    my @found;
    my $number = 0;
  LINE:
    foreach my $line ( split /\n/, $text ) {
        $number++;

        # The root usually sits under a scanned prefix itself (/tmp, /var/tmp), so its own
        # occurrences are taken out before the scan rather than excluded by a lookbehind.
        my $scanned = $line;
        $scanned =~ s/\Q$root\E/ROOT/g if defined $root && length $root;
        next unless $scanned =~ $host_path;
        foreach my $allowed ( @{ $opt{allow} || [] } ) {
            next LINE if ref $allowed ? $line =~ $allowed : index( $line, $allowed ) >= 0;
        }
        push @found, "$number: $line";
    }
    return unless @found;

    die "assert_no_host_paths: the script still names host paths:\n" . join( '', map {"  $_\n"} @found );
}

#-------------------------------------------------------------------------------

=head3 stub_bin

    Descriptions: Builds a directory to use as the whole PATH: shell stubs, plus links to
                  the real tools the code under test is allowed to run. Any other command
                  is "not found" instead of reaching the host.
    Arguments:
        %opt - dir => the directory (a new temporary directory by default);
               stubs => { name => shell body }; tools => [ names ]
    Returns: the directory

=cut

#-------------------------------------------------------------------------------
sub stub_bin {
    my (%opt) = @_;

    my $dir = defined $opt{dir} ? $opt{dir} : File::Temp::tempdir( CLEANUP => 1 );
    File::Path::make_path($dir);

    my %stubs = %{ $opt{stubs} || {} };
    foreach my $name ( sort keys %stubs ) {
        my $path = File::Spec->catfile( $dir, $name );
        open( my $fh, '>', $path ) or die "stub_bin: unable to write $path: $!\n";
        print {$fh} "#!/bin/sh\n$stubs{$name}\n";
        close($fh) or die "stub_bin: unable to close $path: $!\n";
        chmod( 0755, $path ) or die "stub_bin: unable to chmod $path: $!\n";
    }

    foreach my $tool ( @{ $opt{tools} || [] } ) {
        die "stub_bin: $tool is both a stub and a tool\n" if exists $stubs{$tool};
        my $real = _system_executable($tool) or die "stub_bin: $tool is not installed\n";
        my $link = File::Spec->catfile( $dir, $tool );
        symlink( $real, $link ) or die "stub_bin: unable to link $link: $!\n";
    }

    return $dir;
}

#-------------------------------------------------------------------------------

=head3 confinement

    Descriptions: How run_confined can contain a command on this host.
                  "root": private mount and network namespaces, host paths read-only.
                  "user": the same, inside a user namespace.
                  "none": no namespaces; only file permissions protect the host, which is
                  enough for a normal user and never for root, so root dies here instead.
    Arguments: none
    Returns: "root", "user" or "none"

=cut

#-------------------------------------------------------------------------------
sub confinement {
    return $mode if defined $mode;

    my $unshare = _system_executable('unshare');
    my $true    = _system_executable('true');
    if ( $> == 0 ) {
        die "XCAT::Test::Sandbox: unshare is not installed, and a root test does not run unconfined\n"
            unless $unshare && $true;
        die "XCAT::Test::Sandbox: mount and network namespaces are not available, and a root test does not run unconfined\n"
            unless _quiet( $unshare, '--mount', '--net', $true ) == 0;
        return $mode = 'root';
    }

    return $mode = ( $unshare && $true && _quiet( $unshare, '--map-root-user', '--mount', '--net', $true ) == 0 )
        ? 'user'
        : 'none';
}

#-------------------------------------------------------------------------------

=head3 run_confined

    Descriptions: Runs a command with an empty environment, PATH limited to a stub
                  directory, and, where the host allows, inside private mount and network
                  namespaces: /run is empty (no systemd or D-Bus socket), host paths are
                  read-only, and only the loopback interface exists.
    Arguments:
        %opt - cmd => [ command, args ]; bin => the PATH directory (from stub_bin);
               env => { extra variables }; writable => [ directories to keep writable ];
               dir => the working directory
    Returns: the exit status and the combined stdout and stderr

=cut

#-------------------------------------------------------------------------------
sub run_confined {
    my (%opt) = @_;

    my @cmd = @{ $opt{cmd} || die "run_confined: cmd is required\n" };
    my $bin = $opt{bin} or die "run_confined: bin is required\n";
    my $env = _system_executable('env') or die "run_confined: env is not installed\n";
    my $tmp = defined $ENV{TMPDIR} && -d $ENV{TMPDIR} ? $ENV{TMPDIR} : File::Spec->tmpdir();

    my %vars = ( PATH => $bin, HOME => $tmp, TMPDIR => $tmp, LANG => 'C', LC_ALL => 'C', %{ $opt{env} || {} } );
    my @run = ( $env, '-i', map( {"$_=$vars{$_}"} sort keys %vars ), @cmd );

    my $how = confinement();
    if ( $how ne 'none' ) {
        my $script = _setup_script( dir => $tmp, writable => [ $tmp, @{ $opt{writable} || [] } ] );
        my @flags = $how eq 'root' ? qw(--mount --net) : qw(--map-root-user --mount --net);
        @run = ( _system_executable('unshare'), @flags, _system_executable('sh'), $script, @run );
    }

    return _capture( dir => $opt{dir}, cmd => \@run );
}

#-------------------------------------------------------------------------------

=head3 confine_self

    Descriptions: As root, runs the rest of this test again inside the namespaces
                  run_confined uses, for tests that call product Perl in process. Call it in
                  a BEGIN block right after `use XCAT::Test::Source`, before any output.
                  As a normal user it does nothing: file permissions protect the host.
    Arguments: none
    Returns: nothing, or does not return

=cut

#-------------------------------------------------------------------------------
sub confine_self {
    return if $ENV{XCAT_TEST_CONFINED};
    return unless $> == 0;

    confinement();

    # exec skips END blocks, so the scratch tree of this process is removed here. The setup
    # script therefore goes next to that tree, not inside it.
    my $scratch = defined &XCAT::Test::Source::scratch_dir ? XCAT::Test::Source::scratch_dir() : undef;
    my $outside = $scratch ? File::Basename::dirname($scratch) : File::Spec->tmpdir();
    my $script  = _setup_script( dir => $outside, writable => [$outside] );
    File::Path::remove_tree($scratch) if $scratch;

    $ENV{XCAT_TEST_CONFINED} = 1;
    exec( _system_executable('unshare'), '--mount', '--net', _system_executable('sh'), $script, $^X, $0, @ARGV )
        or die "confine_self: unable to exec: $!\n";
}

sub _setup_script {
    my (%opt) = @_;

    my $mount = _system_executable('mount') or die "XCAT::Test::Sandbox: mount is not installed\n";
    my $ip    = _system_executable('ip');

    my $script = File::Temp->new( TEMPLATE => 'xcat-confine-XXXXXXXX', DIR => $opt{dir}, SUFFIX => '.sh', UNLINK => 0 );
    print {$script} "set -e\n";
    print {$script} "$ip link set lo up\n" if $ip;
    print {$script} "$mount -t tmpfs tmpfs /run\n";
    foreach my $dir (@READ_ONLY) {
        print {$script} "if [ -d '$dir' ]; then $mount --bind '$dir' '$dir' && $mount -o remount,bind,ro '$dir'; fi\n";
    }
    foreach my $dir ( grep { defined $_ && -d $_ } @{ $opt{writable} || [] } ) {
        print {$script} "$mount --bind '$dir' '$dir' && $mount -o remount,bind,rw '$dir'\n";
    }
    print {$script} "rm -f \"\$0\"\nexec \"\$@\"\n";
    close($script) or die "XCAT::Test::Sandbox: unable to write the confinement script: $!\n";

    return $script->filename;
}

sub _capture {
    my (%opt) = @_;

    my $log = File::Temp->new( TEMPLATE => 'xcat-confined-XXXXXXXX', TMPDIR => 1 );
    my $pid = fork();
    die "XCAT::Test::Sandbox: unable to fork: $!\n" unless defined $pid;
    if ( !$pid ) {
        if ( defined $opt{dir} ) { chdir( $opt{dir} ) or POSIX::_exit(126); }
        open( STDIN,  '<',  File::Spec->devnull() ) or POSIX::_exit(126);
        open( STDOUT, '>',  $log->filename )        or POSIX::_exit(126);
        open( STDERR, '>&', \*STDOUT )              or POSIX::_exit(126);
        exec( @{ $opt{cmd} } ) or POSIX::_exit(127);
    }
    waitpid( $pid, 0 );
    my $status = $? & 127 ? 128 + ( $? & 127 ) : $? >> 8;

    open( my $fh, '<', $log->filename ) or die "XCAT::Test::Sandbox: unable to read command output: $!\n";
    my $output = do { local $/; <$fh> };
    close($fh);

    return ( $status, defined $output ? $output : '' );
}

sub _quiet {
    my (@cmd) = @_;
    my ($status) = _capture( cmd => \@cmd );
    return $status;
}

sub _system_executable {
    my ($name) = @_;
    foreach my $dir (@SYSTEM_PATH) {
        my $path = File::Spec->catfile( $dir, $name );
        return $path if -f $path && -x _;
    }
    return;
}

sub _placeholder {
    $placeholders++;
    return "\x{0}XCAT-TEST-SANDBOX-$$-$placeholders\x{0}";
}

1;

__END__

=head1 NAME

XCAT::Test::Sandbox - run product code from a unit test without letting it reach the host

=head1 SYNOPSIS

    use XCAT::Test::Source qw(repo_path slurp_repo_file);
    use XCAT::Test::Sandbox qw(replace_required assert_no_host_paths stub_bin run_confined);

    my $script = slurp_repo_file('xCAT/postscripts/ospkgs');
    replace_required( \$script, '/etc/yum.repos.d', "$root/yum.repos.d" );
    assert_no_host_paths( $script, root => $root );
    my $bin = stub_bin( tools => [qw(sed grep cat)], stubs => { dnf => 'exit 0' } );
    my ( $status, $output ) = run_confined( cmd => [ 'bash', $copy ], bin => $bin );

=head1 DESCRIPTION

A sandbox built from path rewrites and command stubs fails open: when a rewrite stops matching,
or the product calls a command the test did not stub, the code acts on the host, and the suite
may run as root. The functions here fail closed instead. A rewrite that matches nothing dies. A
host path left in a script dies. A command that is not in the stub directory is not found.

C<run_confined> and C<confine_self> add namespaces where the host allows them. As root they are
required, and a host without them fails the test rather than running it unconfined. As a normal
user without namespaces the command runs with the stub PATH only, and file permissions protect
the host.

=cut
