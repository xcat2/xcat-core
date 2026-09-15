#!/usr/bin/env perl
# XCAT::Test::Source keeps a unit test on the checkout: it must load product code from the
# tree, never from /opt/xcat, and fail the test when something slips through. Each case runs a
# child perl in an environment that points at the installed tree, and asserts on what the
# child loaded, what it saw and how it exited.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(repo_path scratch_dir);

use Cwd ();
use File::Path qw(make_path);
use File::Spec;
use File::Temp ();
use POSIX ();
use Test::More;

my $test_lib = repo_path('xCAT-test/lib');
my $checkout = Cwd::realpath( repo_path('perl-xCAT') );
$checkout =~ s{/perl-xCAT\z}{};

# What a careless caller hands a test: every variable points at an installed xCAT.
my %HOSTILE = (
    XCATROOT => '/opt/xcat',
    XCATCFG  => 'mysql:dbname=xcatdb;host=192.0.2.1',
    TMPDIR   => '/nonexistent-xcat-unit-tmp',
    PERL5LIB => '/opt/xcat/lib/perl',
);

#-------------------------------------------------------------------------------

=head3 run_child

    Descriptions: Runs a command with the hostile environment, stdin from /dev/null and
                  stdout and stderr in one file.
    Arguments:
        @cmd - the command and its arguments
    Returns: the exit status and the output

=cut

#-------------------------------------------------------------------------------
sub run_child {
    my (@cmd) = @_;

    my $log = File::Temp->new( DIR => scratch_dir() );
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ( !$pid ) {
        %ENV = ( %ENV, %HOSTILE );
        delete @ENV{qw(XCAT_TEST_SOURCE_CHILD XCAT_TEST_SOURCE_REPORT HARNESS_ACTIVE TAP_VERSION_13)};
        chdir('/') or POSIX::_exit(126);
        open( STDIN,  '<',  File::Spec->devnull() ) or POSIX::_exit(126);
        open( STDOUT, '>',  $log->filename )        or POSIX::_exit(126);
        open( STDERR, '>&', \*STDOUT )              or POSIX::_exit(126);
        exec(@cmd) or POSIX::_exit(127);
    }
    waitpid( $pid, 0 );
    my $status = $? >> 8;

    open( my $fh, '<', $log->filename ) or die "Unable to read child output: $!";
    my $output = do { local $/; <$fh> };
    close($fh);

    return ( $status, defined $output ? $output : '' );
}

#-------------------------------------------------------------------------------

=head3 run_perl

    Descriptions: Runs perl code in a child that loads XCAT::Test::Source first, as a test does.
    Arguments:
        $code - the code for -e, or the path of a script
    Returns: the exit status and the output

=cut

#-------------------------------------------------------------------------------
sub run_perl {
    my ($code) = @_;
    my @script = ( $code !~ /\n/ && -f $code ) ? ($code) : ( '-e', $code );
    return run_child( $^X, "-I$test_lib", '-MXCAT::Test::Source', @script );
}

sub fields {
    my ($output) = @_;
    return map { /\A([A-Za-z0-9_]+)=(.*)\z/ ? ( $1 => $2 ) : () } split /\n/, $output;
}

sub under {
    my ( $path, $dir ) = @_;
    return defined $path && defined $dir && length $dir && ( $path eq $dir || index( $path, "$dir/" ) == 0 );
}

# --- the environment a test sees ------------------------------------------------------------
# The child removes its scratch directory when it exits, so it reports the paths itself and the
# comparisons below are on those strings.
{
    my ( $status, $output ) = run_perl(<<'PERL');
my $root = $ENV{XCATROOT};
print "scratch=", XCAT::Test::Source::scratch_dir(), "\n";
print "xcatroot=$root\n";
print "xcatcfg=$ENV{XCATCFG}\n";
print "tmpdir=$ENV{TMPDIR}\n";
print "tmpdir_writable=", ( -d $ENV{TMPDIR} && -w _ ? 1 : 0 ), "\n";
print "share_server=", ( -d "$root/share/xcat/install" ? 1 : 0 ), "\n";
print "share_client=", ( -e "$root/share/xcat/tools/groupfiles4dsh" ? 1 : 0 ), "\n";
print "share_client_rvid=", ( -e "$root/share/xcat/rvid/rvid.kvm" ? 1 : 0 ), "\n";
print "lib_perl=", ( -e "$root/lib/perl" ? 1 : 0 ), "\n";
print "bin=", ( -e "$root/bin" || -e "$root/sbin" ? 1 : 0 ), "\n";
print "inc_installed=", ( scalar grep { !ref && m{\A/opt/xcat} } @INC ), "\n";
print "perl5lib_installed=", ( scalar grep { m{\A/opt/xcat} } split /:/, $ENV{PERL5LIB} ), "\n";
PERL
    my %f = fields($output);
    is( $status, 0, 'a child in an environment pointing at /opt/xcat starts cleanly' ) or diag($output);

    ok( $f{scratch} && $f{scratch} !~ m{\A/opt/xcat}, 'the child has a scratch directory of its own' )
        or diag($output);
    is( $f{xcatroot}, "$f{scratch}/xcatroot", 'XCATROOT points into the scratch directory' );
    is( $f{xcatcfg}, "SQLite:$f{scratch}/cfg", 'XCATCFG points into the scratch directory' );
    ok( under( $f{tmpdir}, $f{scratch} ), 'TMPDIR points into the scratch directory' ) or diag($output);
    is( $f{tmpdir_writable},    1, 'TMPDIR exists even though the caller named a missing directory' );
    is( $f{share_server},       1, 'share/xcat carries the server tree' );
    is( $f{share_client},       1, 'share/xcat merges the client tree into a directory both supply' );
    is( $f{share_client_rvid},  1, 'share/xcat carries a directory only the client supplies' );
    is( $f{lib_perl},           0, 'XCATROOT has no lib/perl for a module to be loaded from' );
    is( $f{bin},                0, 'XCATROOT has no bin or sbin for product code to run' );
    is( $f{inc_installed},      0, '@INC holds no /opt/xcat entry' );
    is( $f{perl5lib_installed}, 0, 'PERL5LIB holds no /opt/xcat entry' );
}

# --- product code comes from the checkout ---------------------------------------------------
{
    my ( $status, $output ) = run_perl(<<'PERL');
use B ();
require xCAT::BootUtils;
require xCAT_plugin::typemtms;
require xCAT_monitoring::bootttmon;
print "bootutils=", Cwd::realpath( $INC{'xCAT/BootUtils.pm'} ), "\n";
print "typemtms=", B::svref_2object( \&xCAT_plugin::typemtms::handled_commands )->FILE, "\n";
print "bootttmon=", ( defined $INC{'xCAT_monitoring/bootttmon.pm'} ? 1 : 0 ), "\n";
PERL
    my %f = fields($output);
    is( $status, 0, 'loading checkout modules does not fail the test' ) or diag($output);
    ok( under( $f{bootutils}, $checkout ), 'xCAT::BootUtils is loaded from the checkout' ) or diag($output);
    is( $f{typemtms}, Cwd::realpath( repo_path('xCAT-server/lib/xcat/plugins/typemtms.pm') ),
        'xCAT_plugin::typemtms is served from xCAT-server/lib/xcat/plugins, with its real file name' );
    is( $f{bootttmon}, 1, 'xCAT_monitoring::bootttmon is served from the checkout' );
}

# --- an installed-tree name with no checkout file does not fall through ---------------------
{
    my $decoy_dir = File::Temp::tempdir( DIR => scratch_dir() );
    make_path("$decoy_dir/xCAT_plugin");
    open( my $fh, '>', "$decoy_dir/xCAT_plugin/xcat_unit_decoy.pm" ) or die $!;
    print {$fh} "package xCAT_plugin::xcat_unit_decoy; print qq(decoy_loaded=1\\n); 1;\n";
    close($fh);

    my ( $status, $output ) = run_perl(<<"PERL");
push \@INC, '$decoy_dir';
my \$ok = eval { require xCAT_plugin::xcat_unit_decoy; 1 };
print "loaded=", ( \$ok ? 1 : 0 ), "\\n";
print "error=\$\@" unless \$ok;
PERL
    my %f = fields($output);
    is( $f{loaded}, 0, 'a plugin missing from the checkout is not loaded from a later @INC entry' )
        or diag($output);
    like( $output, qr/xcat_unit_decoy\.pm is not in the checkout/, 'the refusal names the missing file' );
    unlike( $output, qr/decoy_loaded=1/, 'the decoy never compiles' );
}

# --- an @INC entry for the installed tree fails the test ------------------------------------
{
    my ( $status, $output ) = run_perl(q{unshift @INC, '/opt/xcat/lib/perl'; print "ran=1\n";});
    like( $output, qr/ran=1/, 'the child ran to completion' );
    is( $status, 255, 'a test left with /opt/xcat in @INC fails' );
    like( $output, qr{\@INC holds the installed tree: /opt/xcat/lib/perl}, 'the failure names the entry' );
}

# --- a module from outside the checkout fails the test --------------------------------------
{
    my $outside = File::Temp::tempdir( DIR => scratch_dir() );
    open( my $fh, '>', "$outside/XcatUnitOutside.pm" ) or die $!;
    print {$fh} "package XcatUnitOutside; 1;\n";
    close($fh);

    my ( $status, $output ) = run_perl(qq{unshift \@INC, '$outside'; require XcatUnitOutside;});
    is( $status, 255, 'a module loaded from a directory outside the checkout fails the test' ) or diag($output);
    like( $output, qr/XcatUnitOutside\.pm loaded from outside the checkout/, 'the failure names the module' );
}

# --- stubs written the way the tests write them pass ----------------------------------------
{
    my $script = File::Temp->new( DIR => scratch_dir(), SUFFIX => '.t' );
    print {$script} <<'PERL';
BEGIN {
    package xCAT::Table;
    sub new { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;
    $INC{'xCAT/NodeRange.pm'} = 1;
}
print "stubbed=1\n";
PERL
    close($script);

    my ( $status, $output ) = run_perl( $script->filename );
    like( $output, qr/stubbed=1/, 'the stubbing script ran' );
    is( $status, 0, '$INC{...} = __FILE__ and = 1 stubs do not fail the test' ) or diag($output);
}

# --- the exit status of the test itself is kept ---------------------------------------------
{
    my ( $pass_status, $pass_output ) = run_perl(q{require Test::More; Test::More::ok(1); Test::More::done_testing();});
    is( $pass_status, 0, 'a passing test still exits 0' ) or diag($pass_output);

    my ( $fail_status, $fail_output ) = run_perl(q{require Test::More; Test::More::ok(0); Test::More::done_testing();});
    is( $fail_status, 1, 'a failing test keeps the status Test::More gave it' ) or diag($fail_output);
}

# --- a forked child neither judges the test nor removes its scratch directory ---------------
{
    my ( $status, $output ) = run_perl(<<'PERL');
my $scratch = XCAT::Test::Source::scratch_dir();
my $pid = fork();
if ( !$pid ) { unshift @INC, '/opt/xcat/lib/perl'; exit 0; }
waitpid( $pid, 0 );
print "grandchild_status=", $? >> 8, "\n";
print "scratch_kept=", ( -d $scratch ? 1 : 0 ), "\n";
PERL
    my %f = fields($output);
    is( $f{grandchild_status}, 0, 'the guard does not run in a forked child' ) or diag($output);
    is( $f{scratch_kept},      1, 'a forked child does not remove the scratch directory' );
    is( $status,               0, 'what a forked child did to its own @INC does not fail the parent' );
}

# --- parallel tests get separate scratch directories ----------------------------------------
{
    my ( undef, $first )  = run_perl(q{print "scratch=", XCAT::Test::Source::scratch_dir(), "\n";});
    my ( undef, $second ) = run_perl(q{print "scratch=", XCAT::Test::Source::scratch_dir(), "\n";});
    my %a = fields($first);
    my %b = fields($second);
    ok( $a{scratch} && $b{scratch} && $a{scratch} ne $b{scratch}, 'two test processes get two scratch directories' )
        or diag("$first\n$second");
}

# --- a child perl started with perl_command reports to its parent ---------------------------
{
    my ( $status, $output ) = run_perl(<<'PERL');
my @cmd = XCAT::Test::Source::perl_command( '-e', q{unshift @INC, '/opt/xcat/lib/perl'} );
system(@cmd);
print "child_status=", $? >> 8, "\n";
PERL
    my %f = fields($output);
    is( $f{child_status}, 0, 'the child perl keeps its own exit status' ) or diag($output);
    is( $status, 255, 'what the child perl loaded fails the test that started it' );
    like( $output, qr/child perl .*\@INC holds the installed tree/, 'the failure says the child reported it' );
}

done_testing();
