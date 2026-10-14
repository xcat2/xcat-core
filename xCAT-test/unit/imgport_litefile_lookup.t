#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(write_binary);
use Capture::Tiny qw(capture);
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
local $ENV{XCATCFG} = "$root/cfg";
make_path($ENV{XCATCFG}, "$root/import", "$root/install");
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
xCAT::Table->new('litefile', -create => 1)->setAttribs({ image => 'ALL', file => '/etc/hosts' }, { options => 'tmpfs' });
write_binary("$root/import/litefile.csv", qq{"image","/etc/hosts","tmpfs",,\n"image","/var/log/","tmpfs",,\n});

my (@where, $result, @messages);
{
    no warnings 'redefine';
    local *xCAT::TableUtils::getInstallDir = sub { "$root/install" };

    # The configured database is MySQL, which takes a name in double quotes for a string. The fixture stays SQLite.
    my $xcatcfg = \&xCAT::Table::get_xcatcfg;
    local *xCAT::Table::get_xcatcfg = sub {
        return (caller(1))[3] eq 'xCAT::Table::delimitcol' ? 'mysql:dbname=xcatdb;host=localhost' : $xcatcfg->(@_);
    };
    my $lookup = \&xCAT::Table::getAllAttribsWhere;
    local *xCAT::Table::getAllAttribsWhere = sub {
        push @where, $_[1] if $_[0]{tabname} eq 'litefile';
        goto &$lookup;
    };
    my $data = {
        osimage  => { imagename => 'image', osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'statelite' },
        litefile => "$root/install/litefile.csv",
    };
    my ($out, $err);
    ($out, $err, $result) = capture { xCAT_plugin::imgport::make_files($data, "$root/import", sub { push @messages, $_[0] }) };
}
is($result, 1, 'a statelite import with a litefile succeeds');
is_deeply([ map { @{ $_->{error} || [] } } @messages ], [], 'no error is reported');
is_deeply(\@where, ["`image` = 'ALL'"], 'the litefile lookup quotes the image column the way the database needs');

my %files = map { ($_->{file} => 1) } xCAT::Table->new('litefile')->getAllAttribsWhere("image = 'image'", 'file');
is_deeply(\%files, { '/var/log/' => 1 }, 'the import adds only the entries that no ALL entry covers');

done_testing();
