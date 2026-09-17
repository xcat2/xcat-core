#!/usr/bin/env perl
# xCAT-genesis-base.spec builds the Genesis image from a tarball that buildrpms.pl stages:
# the dracut_105 modules and 80-net-name-slot.rules. Renaming the directory they live in
# breaks that staging silently.
#
# buildsources_genesis_base() is lifted out of buildrpms.pl and run against a scratch
# checkout, because buildrpms.pl itself does not load outside a build.
use strict;
use warnings;

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $builder = repo_path('buildrpms.pl');
plan skip_all => 'buildrpms.pl not found' unless -f $builder;

my $source = read_text($builder);
our ($body) = $source =~ /(sub\s+buildsources_genesis_base\s*\(\$\).*?\n\}\n)/s;
# die rather than skip: a rename that stops this matching must fail loudly instead of
# quietly covering nothing.
die("could not extract buildsources_genesis_base from buildrpms.pl") unless $body;

# The staged directory the spec reads, as buildrpms.pl names it. Read back from the code so
# the test cannot disagree with it about the name.
my ($staged_dir) = $body =~ m{\bcp -a "([^/"]+)/dracut_105"};
die('buildsources_genesis_base stages no dracut_105 directory') unless $staged_dir;
is($staged_dir, 'xCAT-genesis-base', 'the dracut assets are staged from xCAT-genesis-base');
ok(-d repo_path($staged_dir), "$staged_dir is in the checkout");

{
    package Scratch;
    use File::Copy qw(cp);
    use File::Path qw(make_path remove_tree);
    our ($SOURCES, $SOURCE_DATE_EPOCH);
    sub sh_or_die {
        my ($cmd, $message) = @_;
        system($cmd) == 0 or die "$message\n";
        return 0;
    }
    eval $main::body;    ## no critic
    die $@ if $@;
}

my $scratch = tempdir(CLEANUP => 1);
my $checkout = "$scratch/checkout";
make_path("$checkout/$staged_dir/dracut_105/el", "$checkout/$staged_dir/dracut_105/ubuntu");
write_text("$checkout/$staged_dir/dracut_105/el/module-setup.sh", "el module\n");
write_text("$checkout/$staged_dir/dracut_105/ubuntu/module-setup.sh", "ubuntu module\n");
write_text("$checkout/$staged_dir/80-net-name-slot.rules", "rules\n");

$Scratch::SOURCES = "$scratch/SOURCES";
$Scratch::SOURCE_DATE_EPOCH = 1700000000;
make_path($Scratch::SOURCES);

my $cwd = getcwd();
chdir $checkout or die "chdir $checkout: $!";
my $ok = eval { Scratch::buildsources_genesis_base('alma+epel-10-x86_64'); 1 };
my $err = $@;
chdir $cwd or die "chdir back: $!";
ok($ok, 'buildsources_genesis_base stages the Genesis build sources') or diag($err);

my $tarball = "$Scratch::SOURCES/xCAT-genesis-base-build-support.tar.bz2";
ok(-s $tarball, 'the build support tarball is written');

my @members = split /\n/, (`tar tjf '$tarball' 2>/dev/null` // '');
ok(scalar(grep { m{dracut_105/el/module-setup\.sh$} } @members),
    'the EL dracut module is in the tarball');
ok(scalar(grep { m{dracut_105/ubuntu/module-setup\.sh$} } @members),
    'the Ubuntu dracut module is in the tarball');
ok(scalar(grep { m{/80-net-name-slot\.rules$} } @members),
    '80-net-name-slot.rules is in the tarball');

# A checkout without the directory must stop the build, not produce an empty tarball.
my $empty = "$scratch/empty";
make_path($empty);
chdir $empty or die "chdir $empty: $!";
my $died = !eval { Scratch::buildsources_genesis_base('alma+epel-10-x86_64'); 1 };
my $message = $@;
chdir $cwd or die "chdir back: $!";
ok($died, 'a checkout without the Genesis directory stops the build');
like($message, qr/\Q$staged_dir\E/, 'the message names the directory it wants');

done_testing();
