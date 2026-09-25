#!/usr/bin/env perl
# xCAT-genesis-base.spec builds the Genesis image from a tarball that buildrpms.pl stages:
# the dracut_105 modules, 80-net-name-slot.rules, and verify-genesis-payload with its module.
# Renaming the directory they live in breaks that staging silently.
use strict;
use warnings;

use Archive::Tar;
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

# The members of a tarball: name (a directory ends in /), uid, gid and mtime.
sub members {
    my ($tarball) = @_;
    my $tar = Archive::Tar->new($tarball) or die "cannot read $tarball: " . Archive::Tar->error . "\n";
    return map {
        { name => ($_->full_path =~ s{/+\z}{}r) . ($_->is_dir ? '/' : ''), uid => $_->uid, gid => $_->gid, mtime => $_->mtime }
    } $tar->get_files;
}

sub names { return sort map { $_->{name} } @_ }

# A scratch checkout in the layout the spec expects.
my $checkout = "$scratch/checkout";
make_path("$checkout/xCAT-genesis-base/dracut_105/el",
    "$checkout/xCAT-genesis-base/dracut_105/ubuntu");
write_text("$checkout/xCAT-genesis-base/dracut_105/$_/$MODULE", "$_ module\n") for qw(el ubuntu);
write_text("$checkout/xCAT-genesis-base/80-net-name-slot.rules", "rules\n");
write_text("$checkout/xCAT-genesis-base/verify-genesis-payload", "verifier\n");
make_path("$checkout/xCAT-genesis-base/lib/XCAT");
write_text("$checkout/xCAT-genesis-base/lib/XCAT/GenesisPayload.pm", "1;\n");

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
        'xCAT-genesis-base-build-support/lib/',
        'xCAT-genesis-base-build-support/lib/XCAT/',
        'xCAT-genesis-base-build-support/lib/XCAT/GenesisPayload.pm',
        'xCAT-genesis-base-build-support/verify-genesis-payload',
    ],
    'the tarball holds the dracut modules, the rules file and the payload verifier with its module');
is_deeply([ map { $_->{name} } grep { $_->{uid} != 0 || $_->{gid} != 0 || $_->{mtime} != $EPOCH } @listing ], [],
    'every member is owned by root and dated SOURCE_DATE_EPOCH');

# The checkout itself, so the directory the spec needs is known to be there.
my %shipped = map { $_ => 1 }
    names(members(stage_genesis_base_sources(repo_path('.'), "$scratch/shipped.tar.bz2", $EPOCH)));
is_deeply([ grep { !$shipped{"xCAT-genesis-base-build-support/$_"} }
        "dracut_105/el/$MODULE", "dracut_105/ubuntu/$MODULE", '80-net-name-slot.rules',
        'verify-genesis-payload', 'lib/XCAT/GenesisPayload.pm' ], [],
    'xCAT-genesis-base in the checkout carries the dracut modules, the rules file and the verifier');

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
