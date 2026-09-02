#!/usr/bin/env perl
# modifyUtils stamps the version and commit into xCAT::Version.
#
# It is run, not read: the script is copied into a scratch tree with a stand-in
# Version.pm carrying the real placeholders, and the assertions are about the file
# that comes out. The behaviour that matters is the failure path -- modifyUtils used
# to return 0 when handed no commit, doing nothing, and neither caller
# (perl-XCAT/debian/rules, perl-xCAT.spec) checks the status, so the package shipped
# with its placeholders intact and `lsxcatd -v` printed a bare "Version".
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $script = repo_path('perl-xCAT/modifyUtils');
plan skip_all => 'modifyUtils not found' unless -r $script;

# The real placeholders, as xCAT::Version ships them.
my $TEMPLATE = <<'PM';
sub Version
{
    my $version = shift;
    if ($version eq 'short')
    {
        $version = ''    #XCATVERSIONSUBHERE ;
    }
    else
    {
        $version = 'Version '    #XCATVERSIONSUBHERE #XCATSVNBUILDSUBHERE ;
    }
    return $version;
}
PM

# modifyUtils picks its target from /etc/debian_version, which differs between the
# build hosts and CI. Stage BOTH candidates so the test asserts the same behaviour
# wherever it runs, and read back whichever one it chose.
sub run_modify {
    my (@args) = @_;
    my $dir = tempdir(CLEANUP => 1);
    copy($script, "$dir/modifyUtils") or die "cannot stage modifyUtils: $!";
    chmod 0755, "$dir/modifyUtils";
    for my $rel ('xCAT', 'debian/perl-xcat/opt/xcat/lib/perl/xCAT') {
        make_path("$dir/$rel");
        open my $fh, '>', "$dir/$rel/Version.pm" or die $!;
        print {$fh} $TEMPLATE;
        close $fh;
    }

    my $out = qx(cd \Q$dir\E && ./modifyUtils @{[ join ' ', map { "'$_'" } @args ]} 2>&1);
    my $rc  = $? >> 8;

    my $stamped = '';
    for my $rel ('xCAT', 'debian/perl-xcat/opt/xcat/lib/perl/xCAT') {
        open my $fh, '<', "$dir/$rel/Version.pm" or next;
        my $text = do { local $/; <$fh> };
        close $fh;
        $stamped = $text if $text !~ /XCATVERSIONSUBHERE/;
    }
    return { rc => $rc, out => $out, stamped => $stamped };
}

# ------------------------------------------------------------------ the happy path --
my $ok = run_modify('2.19.0', 'abc123def456');
is( $ok->{rc}, 0, 'a version and a commit are stamped without error' );
like( $ok->{stamped}, qr/\Q'Version '\E\s*\. '2\.19\.0' \. ' \(git commit abc123def456\)'/,
    'the long form carries the version and the commit it was built from' );
like( $ok->{stamped}, qr/\$version = ''\s*\. '2\.19\.0'/,
    "and the 'short' form carries the bare version" );
unlike( $ok->{stamped}, qr/XCATVERSIONSUBHERE|XCATSVNBUILDSUBHERE/,
    'no placeholder survives a successful stamp' );

# -------------------------------------------------------------- the failure path --
# The whole point: a missing argument must stop the build, not pass silently.
my $no_commit = run_modify('2.19.0', '');
isnt( $no_commit->{rc}, 0,
    'a missing commit fails instead of shipping an unstamped package' );
like( $no_commit->{out}, qr/git commit/,
    'and says which argument is missing' );
is( $no_commit->{stamped}, '',
    'and stamps nothing, so the failure cannot be mistaken for a partial write' );

my $no_version = run_modify('', 'abc123def456');
isnt( $no_version->{rc}, 0, 'a missing version fails too' );
like( $no_version->{out}, qr/version/, 'and says so' );

done_testing();
