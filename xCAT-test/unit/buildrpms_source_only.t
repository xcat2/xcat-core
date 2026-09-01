#!/usr/bin/env perl
# buildrpms.pl --source-only: build the source rpms and stop.
#
# buildrpms.pl cannot be loaded -- it runs mkdir/git/read_text at file scope and
# expects a working tree -- so the routines whose behaviour changed are lifted out
# with a regex and eval'd into a scratch package with their collaborators stubbed,
# per the repo's code standard. The CLI contract is exercised by running the real
# program.
use strict;
use warnings;

use Cwd qw(getcwd);
use File::Copy ();
use File::Slurper qw(read_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $builder = repo_path('buildrpms.pl');
plan skip_all => 'buildrpms.pl not found' unless -r $builder;

my $source = read_text($builder);

# ---------------------------------------------------------------- extraction --
# Lift the two routines that decide what a source-only run publishes. BAIL_OUT
# rather than skip: if the extraction stops matching, this file would silently
# cover nothing.
my %routine;
for my $name (qw(index_repo write_repo_metadata_dir buildall)) {
    my ($body) = $source =~ /\n(sub \Q$name\E \{.*?\n\})\n/s;
    BAIL_OUT("could not extract $name from buildrpms.pl") unless $body;
    $routine{$name} = $body;
}

our @CREATEREPO;
our @METADATA_WRITTEN;
our @STAGES;

{
    package Scratch;
    no warnings 'redefine';
    # Collaborators the lifted code calls. Each records instead of acting.
    sub createrepo_dir { push @main::CREATEREPO, $_[0]; }
    # The four stages buildall drives. Each records that it was reached.
    sub createmockconfig { push @main::STAGES, 'createmockconfig'; }
    sub buildsources     { push @main::STAGES, 'buildsources'; }
    sub buildspkgs       { push @main::STAGES, 'buildspkgs'; }
    sub buildpkgs        { push @main::STAGES, 'buildpkgs'; }
}

# %opts lives in the scratch package and is set directly. Aliasing it to a hash in
# main and localising that does NOT work: local swaps the container, so the lifted
# code keeps reading the hash the glob pointed at before.
my $harness = join "\n",
    'package Scratch;',
    'use strict; use warnings;',
    'our %opts;',
    'sub say { }',
    # write_repo_metadata_dir does real work past the guard; stop it there so the
    # test observes the guard and nothing else.
    $routine{index_repo},
    $routine{buildall},
    ($routine{write_repo_metadata_dir} =~ s/(return if \$opts\{source_only\};).*\n\}\z/$1\n    push \@main::METADATA_WRITTEN, \$repodir;\n    return 1;\n}/sr),
    '1;';

eval $harness or BAIL_OUT("could not evaluate the extracted routines: $@");

sub run_index {
    my (%args) = @_;
    %Scratch::opts = (source_only => $args{source_only});
    local @CREATEREPO = ();
    my $dir = tempdir(CLEANUP => 1);
    mkdir File::Spec->catdir($dir, 'SRPMS');
    Scratch::index_repo($dir);
    return [map { $_ eq $dir ? 'BINARY' : 'SRPMS' } @CREATEREPO];
}

# ------------------------------------------------------------------ behaviour --
is_deeply( run_index(source_only => 0), ['BINARY', 'SRPMS'],
    'a normal run indexes the binary repository and the srpms' );

is_deeply( run_index(source_only => 1), ['SRPMS'],
    'a source-only run indexes only the srpms' );

# The reason for the guard: re-indexing a directory with no binaries in it would
# replace working metadata with metadata for an empty repository.
ok( !grep({ $_ eq 'BINARY' } @{ run_index(source_only => 1) }),
    'a source-only run leaves the binary metadata alone' );

{
    %Scratch::opts = (source_only => 1);
    local @METADATA_WRITTEN = ();
    my $dir = tempdir(CLEANUP => 1);
    Scratch::write_repo_metadata_dir($dir);
    is_deeply( \@METADATA_WRITTEN, [],
        'a source-only run emits no .repo file for packages it did not build' );
}
{
    %Scratch::opts = (source_only => 0);
    local @METADATA_WRITTEN = ();
    my $dir = tempdir(CLEANUP => 1);
    Scratch::write_repo_metadata_dir($dir);
    is_deeply( \@METADATA_WRITTEN, [$dir],
        'a normal run still emits the repository metadata' );
}


# ------------------------------------------------------------------ the build --
# The point of the option: the source rpm is built and the binary rebuild is not.
# Without this, removing the guard from buildall leaves every other assertion in
# this file green -- the repository ones only observe what index_repo does.
sub stages_for {
    my ($source_only) = @_;
    %Scratch::opts = (source_only => $source_only);
    local @STAGES = ();
    Scratch::buildall('xCAT-vlan', 'alma+epel-9-x86_64');
    return [@STAGES];
}

is_deeply( stages_for(0),
    [qw(createmockconfig buildsources buildspkgs buildpkgs)],
    'a normal run builds the source rpm and then rebuilds it into binaries' );

is_deeply( stages_for(1),
    [qw(createmockconfig buildsources buildspkgs)],
    'a source-only run stops once the source rpm exists' );

ok( !grep( { $_ eq 'buildpkgs' } @{ stages_for(1) } ),
    'and never enters the binary rebuild, which is the expensive half' );

# ------------------------------------------------------------------- the CLI --
# Run the real program. --source-only and --merge-core-repos are different modes:
# one builds, the other assembles trees that are already built.
#
# Run it from a copy, never from the checkout: before it looks at @ARGV,
# buildrpms.pl rewrites the tracked Gitinfo in its working directory and creates
# $HOME/rpmbuild. Running it in place left the developer's tree dirty and reached
# into their home for a test that only exercises argument parsing. Version is
# staged because the same file-scope code reads it and dies without it, and
# BuildUtils.pm because buildrpms.pl loads it from its own directory.
my $sandbox = tempdir(CLEANUP => 1);
for my $needed (qw(buildrpms.pl Version BuildUtils.pm)) {
    my $from = repo_path($needed);
    BAIL_OUT("$needed is missing from the repository") unless -r $from;
    File::Copy::copy($from, File::Spec->catfile($sandbox, $needed))
        or BAIL_OUT("could not stage $needed: $!");
}

my $cwd = getcwd();
chdir $sandbox or BAIL_OUT("cannot chdir to the sandbox: $!");
local $ENV{HOME} = $sandbox;
my $out = qx($^X buildrpms.pl --source-only --merge-core-repos 2>&1);
my $rc  = $? >> 8;
chdir $cwd;

# 2 is usage()'s exit code, but perl also exits 2 when compilation aborts, so the
# status alone does not say the option check ran -- it passed in CI while
# buildrpms.pl could not even load Parallel::ForkManager. The message below is
# what distinguishes the two; this only pins the code usage() is meant to use.
is( $rc, 2, 'combining --source-only with --merge-core-repos is refused' );
like( $out, qr/--source-only and --merge-core-repos/,
    'and the refusal names both options' );

done_testing();
