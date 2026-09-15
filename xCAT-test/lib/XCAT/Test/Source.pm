package XCAT::Test::Source;

use strict;
use warnings;

use Config ();
use Cwd ();
use Exporter ();
use File::Path ();
use File::Spec;
use File::Temp ();
use XCAT::Test::File ();

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(repo_root repo_path slurp_repo_file scratch_dir perl_command);

{
    no warnings 'once';
    *repo_root       = \&XCAT::Test::File::repo_root;
    *repo_path       = \&XCAT::Test::File::repo_path;
    *slurp_repo_file = \&XCAT::Test::File::slurp_repo_file;
}

# Product code resolves these names in the installed layout. The checkout keeps them in
# directories with different names, so a plain -I path cannot serve them.
my %NAMESPACE_DIR = (
    'xCAT_plugin/'     => 'xCAT-server/lib/xcat/plugins',
    'xCAT_monitoring/' => 'xCAT-server/lib/xcat/monitoring',
    'xCAT_schema/'     => 'xCAT-server/lib/xcat/schema',
    'Confluent/'       => 'xCAT-server/lib/xcat/Confluent',
);

# The directories that supply product modules, in the order the installed tree uses.
my @PRODUCT_LIB = qw(perl-xCAT xCAT-server/lib/perl xCAT-probe/lib/perl);

my $INSTALLED = qr{\A/opt/xcat(?:/|\z)};

my ( $root, $scratch, $importer_pid, $child, @trusted, %mapped_from );

#-------------------------------------------------------------------------------

=head3 import

    Descriptions: Points the test at the checkout, then exports as Exporter does.
    Arguments: the import list
    Returns: nothing

=cut

#-------------------------------------------------------------------------------
sub import {
    my ( $class, @names ) = @_;

    _setup() unless defined $importer_pid;
    $class->export_to_level( 1, $class, @names );

    return;
}

#-------------------------------------------------------------------------------

=head3 scratch_dir

    Descriptions: The per-process scratch directory that holds XCATROOT, XCATCFG and TMPDIR.
    Arguments: none
    Returns: an absolute path

=cut

#-------------------------------------------------------------------------------
sub scratch_dir {
    return $scratch;
}

#-------------------------------------------------------------------------------

=head3 perl_command

    Descriptions: A command line that starts a child perl with this helper loaded first.
                  The child reports what it loaded from outside the checkout to this
                  process, which fails the test for it.
    Arguments: @args - the arguments for the child perl
    Returns: the argument list for system() or exec()

=cut

#-------------------------------------------------------------------------------
sub perl_command {
    my (@args) = @_;

    return ( 'env', 'XCAT_TEST_SOURCE_CHILD=1', $^X,
        '-I' . File::Spec->catdir( $root, 'xCAT-test', 'lib' ),
        '-MXCAT::Test::Source', @args );
}

#-------------------------------------------------------------------------------

=head3 _setup

    Descriptions: Builds the scratch XCATROOT, sets the environment and fixes @INC.
    Arguments: none
    Returns: nothing

=cut

#-------------------------------------------------------------------------------
sub _setup {
    $importer_pid = $$;
    $root         = Cwd::realpath( repo_root() );
    die "XCAT::Test::Source: $root is not an xcat-core checkout\n"
        unless -f File::Spec->catfile( $root, 'perl-xCAT', 'xCAT', 'Utils.pm' );

    $child = $ENV{XCAT_TEST_SOURCE_CHILD} ? 1 : 0;
    if ($child) {
        # A child of a test shares the parent's scratch tree through the environment.
        die "XCAT::Test::Source: a child perl needs the environment of its parent test\n"
            unless $ENV{XCAT_TEST_SOURCE_REPORT} && $ENV{XCATROOT};
        $scratch = Cwd::realpath( File::Spec->catdir( $ENV{XCATROOT}, File::Spec->updir() ) );
    } else {
        # TMPDIR => 1 goes through File::Spec->tmpdir, which ignores a TMPDIR that does not
        # exist or cannot be written.
        $scratch = Cwd::realpath( File::Temp::tempdir( 'xcat-unit-XXXXXXXX', TMPDIR => 1, CLEANUP => 1 ) );
        my $share = File::Spec->catdir( $scratch, 'xcatroot', 'share', 'xcat' );
        File::Path::make_path( map { File::Spec->catdir( $scratch, $_ ) } 'tmp', 'cfg' );
        File::Path::make_path($share);
        _merge_tree( $share, map { File::Spec->catdir( $root, $_, 'share', 'xcat' ) } qw(xCAT-server xCAT-client) );

        # No lib/perl, bin or sbin: product code that runs an installed program fails here
        # instead of running the host's copy.
        $ENV{XCATROOT}                = File::Spec->catdir( $scratch, 'xcatroot' );
        $ENV{XCATCFG}                 = 'SQLite:' . File::Spec->catdir( $scratch, 'cfg' );
        $ENV{TMPDIR}                  = File::Spec->catdir( $scratch, 'tmp' );
        $ENV{XCAT_TEST_SOURCE_REPORT} = File::Spec->catfile( $scratch, 'child-violations' );
    }
    $::XCATROOT = $ENV{XCATROOT};

    my @lib = map { File::Spec->catdir( $root, $_ ) } @PRODUCT_LIB;
    $ENV{PERL5LIB} = join( ':',
        @lib,
        File::Spec->catdir( $root, 'xCAT-test', 'lib' ),
        grep { length($_) && !_installed($_) } split( /:/, defined $ENV{PERL5LIB} ? $ENV{PERL5LIB} : '' ) );

    @INC = grep { ref($_) || !_installed($_) } @INC;
    unshift @INC, \&_namespace_hook, @lib;

    my %seen;
    @trusted = grep { defined($_) && !$seen{$_}++ }
        map { Cwd::realpath($_) }
        grep { defined($_) && !ref($_) && length($_) }
        ( @INC, @Config::Config{qw(privlibexp archlibexp sitelibexp sitearchexp vendorlibexp vendorarchexp)} );

    return;
}

#-------------------------------------------------------------------------------

=head3 _merge_tree

    Descriptions: Fills a directory with symlinks to the entries of several source trees.
                  Where two trees supply a directory of the same name, it recurses; two
                  files of the same name are an error, because the installed layout would
                  have to pick one and the test would not know which.
    Arguments:
        $destination - the directory to fill
        @sources     - the source directories
    Returns: nothing

=cut

#-------------------------------------------------------------------------------
sub _merge_tree {
    my ( $destination, @sources ) = @_;

    my ( @order, %from );
    foreach my $source ( grep { -d $_ } @sources ) {
        opendir( my $dh, $source ) or die "XCAT::Test::Source: unable to read $source: $!\n";
        foreach my $name ( sort grep { $_ ne '.' && $_ ne '..' } readdir($dh) ) {
            push @order, $name unless $from{$name};
            push @{ $from{$name} }, File::Spec->catfile( $source, $name );
        }
        closedir($dh);
    }

    foreach my $name (@order) {
        my @paths = @{ $from{$name} };
        my $target = File::Spec->catfile( $destination, $name );
        if ( @paths == 1 ) {
            symlink( $paths[0], $target ) or die "XCAT::Test::Source: unable to link $target: $!\n";
            next;
        }
        die "XCAT::Test::Source: share/xcat entry $name is supplied as a file by more than one tree: @paths\n"
            if grep { !-d $_ } @paths;
        mkdir($target) or die "XCAT::Test::Source: unable to create $target: $!\n";
        _merge_tree( $target, @paths );
    }

    return;
}

#-------------------------------------------------------------------------------

=head3 _namespace_hook

    Descriptions: An @INC hook that serves the installed module namespaces from the checkout.
                  A name with no file in the checkout dies: the next @INC entry could only
                  hold an installed copy.
    Arguments:
        $hook - this sub
        $file - the path require is looking for, e.g. xCAT_plugin/pxe.pm
    Returns: a source prefix and a file handle, or nothing for other names

=cut

#-------------------------------------------------------------------------------
sub _namespace_hook {
    my ( $hook, $file ) = @_;

    foreach my $prefix ( keys %NAMESPACE_DIR ) {
        next unless index( $file, $prefix ) == 0;

        my $path = File::Spec->catfile( $root, $NAMESPACE_DIR{$prefix}, substr( $file, length $prefix ) );
        die "XCAT::Test::Source: $file is not in the checkout (looked for $path)\n" unless -f $path;
        open( my $fh, '<', $path ) or die "XCAT::Test::Source: unable to read $path: $!\n";
        $mapped_from{$file} = $path;

        # The #line directive keeps __FILE__, warnings and die messages on the real path.
        my $prefix_source = "#line 1 \"$path\"\n";
        return ( \$prefix_source, $fh );
    }

    return;
}

#-------------------------------------------------------------------------------

=head3 _violations

    Descriptions: Lists what this process loaded from the installed tree or from outside
                  the checkout.
    Arguments: none
    Returns: a list of messages, empty when there is nothing to report

=cut

#-------------------------------------------------------------------------------
sub _violations {
    my @found;

    # A hardcoded `use lib "/opt/xcat/lib/perl"` in a product module cannot be undone from
    # here. It can only be seen.
    foreach my $entry (@INC) {
        next if ref $entry;
        push @found, "\@INC holds the installed tree: $entry" if _installed($entry);
    }

    my $script = Cwd::realpath($0);
    foreach my $name ( sort keys %INC ) {
        my $value = $INC{$name};
        next unless defined $value;
        if ( ref $value ) {
            $value = $mapped_from{$name};
            next unless defined $value;
        }

        # Tests stub a module with $INC{...} = 1 or = __FILE__.
        next if $value eq '1';
        my $real = Cwd::realpath($value);
        next unless defined $real && -f $real;
        next if defined $script && $real eq $script;

        if ( _installed($value) || _installed($real) ) {
            push @found, "$name loaded from the installed tree: $value";
            next;
        }
        next if grep { _within( $real, $_ ) } $root, $scratch, @trusted;
        push @found, "$name loaded from outside the checkout: $value";
    }

    return @found;
}

#-------------------------------------------------------------------------------

=head3 _guard

    Descriptions: Fails the test process when it loaded code it should not have. A child
                  perl records its findings for its parent instead.
    Arguments: none
    Returns: nothing

=cut

#-------------------------------------------------------------------------------
sub _guard {
    return unless defined $importer_pid && $$ == $importer_pid;

    my @found = _violations();
    my $report = $ENV{XCAT_TEST_SOURCE_REPORT};

    if ($child) {
        return unless @found && $report;
        if ( open( my $fh, '>>', $report ) ) {
            print {$fh} "$0: $_\n" foreach @found;
            close($fh);
        }
        return;
    }

    if ( $report && open( my $fh, '<', $report ) ) {
        chomp( my @reported = <$fh> );
        close($fh);
        push @found, map {"child perl $_"} @reported;
    }
    return unless @found;

    print STDERR "# XCAT::Test::Source: this test did not measure the checkout alone:\n";
    print STDERR "#   $_\n" foreach @found;
    $? = 255;

    return;
}

sub _installed {
    my ($path) = @_;
    return 0 unless defined $path;
    return 1 if $path =~ $INSTALLED;
    my $real = Cwd::realpath($path);
    return defined $real && $real =~ $INSTALLED ? 1 : 0;
}

sub _within {
    my ( $path, $dir ) = @_;
    return 0 unless defined $dir && length $dir;
    return $path eq $dir || index( $path, "$dir/" ) == 0;
}

# `use XCAT::Test::Source ()` loads the module without calling import, so the setup runs when
# the module is loaded, not only from import.
_setup() unless defined $importer_pid;

# This module is loaded before Test::More, so this END block runs after Test::Builder has
# set the exit status, and its $? replaces that status.
END { _guard() }

1;

__END__

=head1 NAME

XCAT::Test::Source - run a unit test against the checkout it lives in, and nothing else

=head1 SYNOPSIS

    use strict;
    use warnings;
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use XCAT::Test::Source qw(repo_path);    # before any other module

=head1 DESCRIPTION

xCAT modules set C<$::XCATROOT> from C<$ENV{XCATROOT}>, or C</opt/xcat> when it is unset, and
run C<use lib "$::XCATROOT/lib/perl"> as they compile. On a host with xCAT installed, a unit
test that loads one of them without this module measures the installed product.

Loading this module:

=over

=item *

creates a scratch directory for the process and points C<XCATROOT> at a tree in it that holds
only C<share/xcat>, linked to C<xCAT-server/share/xcat> and C<xCAT-client/share/xcat> in the
checkout. There is no C<lib/perl>, C<bin> or C<sbin>;

=item *

points C<XCATCFG> and C<TMPDIR> into the scratch directory;

=item *

removes C</opt/xcat> from C<@INC> and C<PERL5LIB>, puts the checkout's C<perl-xCAT>,
C<xCAT-server/lib/perl> and C<xCAT-probe/lib/perl> first, and serves C<xCAT_plugin::>,
C<xCAT_monitoring::>, C<xCAT_schema::> and C<Confluent::> from the checkout;

=item *

fails the test at exit when a module came from C</opt/xcat> or from outside the checkout, the
scratch directory and Perl's own library directories, or when C<@INC> still holds C</opt/xcat>.

=back

C<share/xcat> is a tree of symlinks: a write through it reaches the checkout.

=head1 FUNCTIONS

C<repo_root>, C<repo_path> and C<slurp_repo_file> come from L<XCAT::Test::File>.
C<scratch_dir> returns the scratch directory. C<perl_command(@args)> returns a command line for
a child perl that loads this module first and reports its findings to the parent.

=cut
