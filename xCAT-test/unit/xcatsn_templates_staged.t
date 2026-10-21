#!/usr/bin/env perl
# xCATsn.spec extracts templates.tar.gz in %{prefix}/share/xcat, so every member must
# start with templates/.
use strict;
use warnings;

use Archive::Tar ();
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::BuildUtils qw(stage_xcatsn_templates);

my $epoch    = 1600000000;
my $checkout = tempdir(CLEANUP => 1);
make_path("$checkout/xCAT/templates/install/rh");
write_text("$checkout/xCAT/templates/install/rh/compute.tmpl", "first\n");

my $sources = tempdir(CLEANUP => 1);
my $tarball = stage_xcatsn_templates($checkout, $sources, $epoch);
is($tarball, "$sources/templates.tar.gz", 'the archive is the Source5 that xCATsn.spec names');

my @members = Archive::Tar->new($tarball)->list_files;
ok(scalar @members, 'the archive is not empty');
is_deeply([grep { !m{^templates(/|$)} } @members], [],
    'every member is rooted at templates/, so it extracts to share/xcat/templates');
is_deeply([grep { m{^xCAT/} } @members], [],
    'no member is rooted at xCAT/, which would extract to share/xcat/xCAT/templates');
ok((grep { $_ eq 'templates/install/rh/compute.tmpl' } @members),
    'a template extracts to share/xcat/templates/install/rh');

# A staging directory survives between builds. A second build must ship the current templates.
write_text("$checkout/xCAT/templates/install/rh/compute.tmpl", "second\n");
stage_xcatsn_templates($checkout, $sources, $epoch);
my ($file) = Archive::Tar->new($tarball)->get_files('templates/install/rh/compute.tmpl');
is($file && $file->get_content, "second\n", 'a later build replaces the archive with the current templates');

done_testing;
