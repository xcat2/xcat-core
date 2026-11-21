use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);

my $source = shift @ARGV // repo_path('xCAT-server/share/xcat/netboot/imgutils');
my $root = tempdir(CLEANUP => 1);
my ($status, $output) = run_command('cp', '-R', $source, "$root/imgutils");
die "copy imgutils: $output" if $status;
make_path("$root/assets");
my $assets = realpath("$root/assets");

local $ENV{PERL5LIB} = '';
local $ENV{XCATROOT} = '/nonexistent';
for my $extension (qw(pkglist otherpkgs.pkglist postinstall)) {
    my $selected = "$assets/compute.debian12.x86_64.$extension";
    write_text($selected, "selected\n");
    write_text("$root/assets/compute.$extension", "fallback\n");
    my ($rc, $result) = run_command($^X,
        '-I' . repo_path('perl-xCAT'), '-I' . repo_path('xCAT-server/lib/perl'),
        '-e', 'require shift @ARGV; print imgutils::get_profile_def_filename(@ARGV)',
        "$root/imgutils/imgutils.pm",
        'debian12.5', 'compute', 'x86_64', "$root/assets", $extension);
    is($rc, 0, "copied imgutils loads without any sibling distro directory") or diag($result);
    is($result, $selected, "copied imgutils selects the $extension version fallback");
}

done_testing();
