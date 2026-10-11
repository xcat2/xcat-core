#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$dir/config";
mkdir $ENV{XCATCFG} or die "mkdir $ENV{XCATCFG}: $!";
require lib;
lib->import(repo_path('perl-xCAT'), repo_path('xCAT-server/lib/perl'));
require xCAT::Postage;

my @lines = (
    '', '   ', '# comment', '  # indented comment',
    '  0  ', '  openssh-server  ', ' @Group With Space ',
    ' d-i tasksel/first multiselect standard,ssh-server ',
    ' #NEW_INSTALL_LIST# ', ' #ENV:SETTING=value# ',
    ' curl # inline note ', ' -snmpd ', '#INCLUDE:', '#ENV:',
    '#NEW_INSTALL_LIST_EXTRA#', '  gawk',
);
write_text("$dir/lines.pkglist", join("\n", @lines));
my @records = (
    '0', 'openssh-server', '@Group With Space',
    'd-i tasksel/first multiselect standard,ssh-server',
    '#NEW_INSTALL_LIST#', '#ENV:SETTING=value#',
    'curl # inline note', '-snmpd', 'gawk',
);
is_deeply([xCAT::Postage->get_pkglist_records("$dir/lines.pkglist")],
    \@records, 'record reader filters comments and preserves package-list directives');
is(xCAT::Postage->get_pkglist_tex("$dir/lines.pkglist"), join(',', @records),
    'legacy root reader applies the same line policy before joining records');
is(xCAT::Postage::get_pkglist_tex("$dir/lines.pkglist"), join(',', @records),
    'legacy function calls use the same policy as method calls');
is_deeply([xCAT::Postage::get_pkglist_records("$dir/lines.pkglist")],
    \@records, 'record function calls use the same policy as method calls');
write_text("$dir/included-lines.pkglist", "#INCLUDE:lines.pkglist#\n");
is(xCAT::Postage->get_pkglist_tex("$dir/included-lines.pkglist"),
    '  0,  openssh-server, @Group With Space, d-i tasksel/first multiselect standard,ssh-server, #NEW_INSTALL_LIST#, #ENV:SETTING=value#, curl # inline note, -snmpd,  gawk',
    'legacy includes retain leading whitespace but remove trailing whitespace');

write_text("$dir/crlf.pkglist", "  bc\r\n\t# comment\r\n0\r\nlast");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/crlf.pkglist")],
    [qw(bc 0 last)], 'record reader accepts CRLF and an unterminated last line');
is(xCAT::Postage->get_pkglist_tex("$dir/crlf.pkglist"), 'bc,0,last',
    'legacy reader accepts CRLF and an unterminated last line');

mkdir "$dir/sub" or die "mkdir $dir/sub: $!";
write_text("$dir/root.pkglist", "before\n#INCLUDE:sub/middle.pkglist# # tail note\nafter\n");
write_text("$dir/sub/middle.pkglist", "  #INCLUDE:leaf.pkglist#\n  bc  \n");
write_text("$dir/leaf.pkglist", "curl\n");
write_text("$dir/sub/leaf.pkglist", "wrong-directory\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/root.pkglist")],
    ['before', 'curl', 'bc # tail note', 'after'],
    'record includes retain root-relative lookup, order and a trailing note');
is(xCAT::Postage->get_pkglist_tex("$dir/root.pkglist"),
    'before,  curl,  bc # tail note,after',
    'legacy nested includes preserve whitespace and append the note after expansion');

local $ENV{XCAT_PKGLIST_TEST_INCLUDE} = "$dir/leaf.pkglist";
write_text("$dir/env.pkglist", '#INCLUDE:${XCAT_PKGLIST_TEST_INCLUDE}#' . "\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/env.pkglist")], ['curl'],
    'record includes expand an environment variable to an absolute filename');
is(xCAT::Postage->get_pkglist_tex("$dir/env.pkglist"), 'curl',
    'legacy includes expand an environment variable to an absolute filename');

write_text("$dir/empty.pkglist", "\n# comment only\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/empty.pkglist")], [],
    'a comment-only file has no records');
is(xCAT::Postage->get_pkglist_tex("$dir/empty.pkglist"), '',
    'a comment-only file has empty legacy text');
write_text("$dir/empty-include.pkglist", "before\n#INCLUDE:empty.pkglist# # note\nafter\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/empty-include.pkglist")],
    [qw(before after)], 'record reader omits a note on an empty include');
is(xCAT::Postage->get_pkglist_tex("$dir/empty-include.pkglist"),
    'before, # note,after', 'legacy reader keeps a note after an empty include');

my $missing = "$dir/missing.pkglist";
my $missing_record = "#INCLUDEBAD:cannot open pkglist file $missing#";
is_deeply([xCAT::Postage->get_pkglist_records($missing)], [$missing_record],
    'a missing root file yields a record error');
is(xCAT::Postage->get_pkglist_tex($missing), '',
    'a missing root file yields empty legacy text');
write_text("$dir/missing-include.pkglist", "before\n#INCLUDE:missing.pkglist#\nafter\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/missing-include.pkglist")],
    ['before', $missing_record, 'after'], 'record reader continues after a missing include');
is(xCAT::Postage->get_pkglist_tex("$dir/missing-include.pkglist"),
    "before,$missing_record,after", 'legacy reader continues after a missing include');

my $files = "$dir/leaf.pkglist,$missing,$dir/leaf.pkglist";
is_deeply([xCAT::Postage->get_pkglist_records($files)],
    ['curl', $missing_record, 'curl'], 'record reader preserves file order and repeated packages');
is(xCAT::Postage->get_pkglist_tex($files), 'curl,,curl',
    'legacy reader retains the empty slot for a missing middle file');

write_text("$dir/inline.pkglist", "first #INCLUDE:leaf.pkglist# last\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/inline.pkglist")],
    ['first #INCLUDE:leaf.pkglist# last'], 'record reader leaves a non-leading include unchanged');
is(xCAT::Postage->get_pkglist_tex("$dir/inline.pkglist"), 'first curl last',
    'legacy reader expands a non-leading include');

for my $depth (0 .. 20) {
    my $next = $depth + 1;
    write_text("$dir/depth$depth.pkglist", "#INCLUDE:depth$next.pkglist#\n");
}
write_text("$dir/depth21.pkglist", "curl\n");
is_deeply([xCAT::Postage->get_pkglist_records("$dir/depth0.pkglist")],
    ['#INCLUDE:depth21.pkglist#'], 'record reader retains its include-depth limit');
is(xCAT::Postage->get_pkglist_tex("$dir/depth0.pkglist"), 'curl',
    'legacy reader continues beyond the record reader depth limit');

done_testing();
