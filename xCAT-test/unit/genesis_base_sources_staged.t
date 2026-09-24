#!/usr/bin/env perl
# xCAT-genesis-base.spec builds the Genesis image from a tarball that buildrpms.pl stages:
# the dracut_105 modules and 80-net-name-slot.rules. Renaming the directory they live in
# breaks that staging silently.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::Test::File qw(repo_path);
use XCAT::BuildUtils qw(stage_genesis_base_sources);

my $EPOCH   = 1700000000;
my $MODULE  = 'module-setup.sh';
my $scratch = tempdir(CLEANUP => 1);

sub members {
    my ($tarball) = @_;
    my @members = `TZ=UTC tar tjvf '$tarball'`;
    die "tar cannot list $tarball\n" if $?;
    chomp @members;
    return @members;
}

sub names { return sort map { (split ' ', $_)[-1] } @_ }

# A scratch checkout in the layout the spec expects.
my $checkout = "$scratch/checkout";
make_path("$checkout/xCAT-genesis-base/dracut_105/el",
    "$checkout/xCAT-genesis-base/dracut_105/ubuntu");
write_text("$checkout/xCAT-genesis-base/dracut_105/$_/$MODULE", "$_ module\n") for qw(el ubuntu);
write_text("$checkout/xCAT-genesis-base/80-net-name-slot.rules", "rules\n");

my $tarball = "$scratch/scratch.tar.bz2";
is(stage_genesis_base_sources($checkout, $tarball, $EPOCH), $tarball,
    'the dracut assets are staged from xCAT-genesis-base');

my @listing = members($tarball);
is_deeply([ names(@listing) ], [
        'xCAT-genesis-base-build-support/',
        'xCAT-genesis-base-build-support/80-net-name-slot.rules',
        'xCAT-genesis-base-build-support/dracut_105/',
        'xCAT-genesis-base-build-support/dracut_105/el/',
        "xCAT-genesis-base-build-support/dracut_105/el/$MODULE",
        'xCAT-genesis-base-build-support/dracut_105/ubuntu/',
        "xCAT-genesis-base-build-support/dracut_105/ubuntu/$MODULE",
    ],
    'the tarball holds the EL and Ubuntu dracut modules and 80-net-name-slot.rules');
is_deeply([ grep { !m{ root/root .* 2023-11-14 22:13 } } @listing ], [],
    'every member is owned by root and dated SOURCE_DATE_EPOCH');

# The checkout itself, so the directory the spec needs is known to be there.
my %shipped = map { $_ => 1 }
    names(members(stage_genesis_base_sources(repo_path('.'), "$scratch/shipped.tar.bz2", $EPOCH)));
is_deeply([ grep { !$shipped{"xCAT-genesis-base-build-support/$_"} }
        "dracut_105/el/$MODULE", "dracut_105/ubuntu/$MODULE", '80-net-name-slot.rules' ], [],
    'xCAT-genesis-base in the checkout carries both dracut modules and the rules file');

# A checkout that still uses the old name must stop the build, not produce an empty tarball.
my $old = "$scratch/old";
make_path("$old/xCAT-genesis-builder/dracut_105");
my $empty_tarball = "$scratch/empty.tar.bz2";
my $died = !eval { stage_genesis_base_sources($old, $empty_tarball, $EPOCH); 1 };
ok($died, 'a checkout without xCAT-genesis-base stops the build');
like($@, qr/No directory xCAT-genesis-base in \Q$old\E/,
    'the message names the directory it wants');
ok(!-e $empty_tarball, 'and no tarball is written');

done_testing();
