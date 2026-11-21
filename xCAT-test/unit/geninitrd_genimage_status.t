#!/usr/bin/env perl
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Storable qw(dclone);
use Test::More;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use XCAT::Test::File qw(repo_path);

local $ENV{XCATROOT} = repo_path('xCAT-server');
require(repo_path('xCAT-server/lib/xcat/plugins/geninitrd.pm'));

my $rootimgdir = tempdir(CLEANUP => 1);
make_path("$rootimgdir/rootimg/lib/modules");
my %attribs = (
    osimage    => { provmethod => 'netboot', osvers => 'ubuntu26.04', osarch => 'riscv64' },
    linuximage => { rootimgdir => $rootimgdir, pkgdir => '/install/ubuntu26.04/riscv64' },
);

# The genimage client prints build output on stdout and its own errors on stderr.
my $bindir = tempdir(CLEANUP => 1);
open(my $script, '>', "$bindir/genimage") or die "genimage: $!";
print $script <<'EOS';
#!/bin/sh
echo "$@" > "$GENIMAGE_ARGS"
echo 'the initial ramdisks are built'
echo 'Error: genimage command failed' >&2
exit "$GENIMAGE_RC"
EOS
close($script) or die "genimage: $!";
chmod(0755, "$bindir/genimage") or die "genimage: $!";
my $emptydir = tempdir(CLEANUP => 1);

sub geninitrd_with {
    my (%case) = @_;
    my $args = "$bindir/args";
    unlink($args);
    my @responses;
    {
        no warnings qw(redefine once);
        local *xCAT::Table::new = sub {
            my ($class, $table) = @_;
            die "Unexpected table $table\n" unless $attribs{$table};
            return bless { attribs => $attribs{$table} }, 'Local::ImageTable';
        };
        local $ENV{PATH}          = $case{path};
        local $ENV{GENIMAGE_RC}   = $case{rc} // 0;
        local $ENV{GENIMAGE_ARGS} = $args;
        xCAT_plugin::geninitrd::process_request({ command => ['geninitrd'], arg => ['compute'] },
            sub { push @responses, dclone($_[0]) }, sub { die "Unexpected subrequest\n" });
    }
    my %result;
    if (open(my $fh, '<', $args)) {
        $result{args} = do { local $/; <$fh> };
        close($fh);
    }
    for my $key (qw(info error errorcode)) {
        $result{$key} = [ map { @{ $_->{$key} // [] } } @responses ];
    }
    return \%result;
}

{
    my $result = geninitrd_with(path => $bindir, rc => 0);
    is($result->{args}, "compute --onlyinitrd\n", 'geninitrd runs genimage --onlyinitrd for the image');
    is_deeply($result->{error}, [], 'a genimage that succeeds reports no error');
    is_deeply($result->{errorcode}, [], 'a genimage that succeeds sets no exit code');
    ok((grep { /the initial ramdisks are built/ } @{ $result->{info} }), 'the genimage output reaches the client');
}

for my $rc (1, 2, 17) {
    my $result = geninitrd_with(path => $bindir, rc => $rc);
    is_deeply($result->{error}, ["genimage compute --onlyinitrd failed with rc $rc."], "a genimage that ends with $rc reports the failure");
    is_deeply($result->{errorcode}, [$rc], "the exit code of geninitrd is $rc");
    ok((grep { /Error: genimage command failed/ } @{ $result->{info} }), "the genimage error output reaches the client after rc $rc");
}

{
    my $result = geninitrd_with(path => $emptydir);
    is_deeply($result->{error}, ['genimage compute --onlyinitrd failed with rc 1.'], 'a genimage that cannot run reports the failure');
    is_deeply($result->{errorcode}, [1], 'the exit code of geninitrd is 1 when genimage cannot run');
}

done_testing();

package Local::ImageTable;

sub getAttribs {
    my ($self) = @_;
    return { %{ $self->{attribs} } };
}
