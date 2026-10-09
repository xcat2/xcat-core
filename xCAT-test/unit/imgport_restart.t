#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(read_binary write_binary);
use Capture::Tiny qw(capture);
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
local $ENV{XCATROOT} = repo_path('xCAT-server');
local $ENV{XCATCFG} = "$root/cfg";
make_path($ENV{XCATCFG}, "$root/xcat/sbin", "$root/xcat/lib/perl/xCAT_plugin", "$root/import");
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
local $::XCATROOT = "$root/xcat";
write_binary("$root/xcat/sbin/restartxcatd", "#!/bin/sh\nprintf 'restart' >> '$root/calls'\n" .
    "for arg do printf ' <%s>' \"\$arg\" >> '$root/calls'; done\nprintf '\\n' >> '$root/calls'\n");
chmod 0755, "$root/xcat/sbin/restartxcatd" or die "chmod: $!";
write_binary("$root/calls", '');

{
    no warnings 'redefine';
    local *xCAT::TableUtils::getInstallDir = sub { "$root/install" };
    for my $case ([first => 0], [second => 1], [third => 0]) {
        my ($kit, $has_plugin) = @$case;
        make_path("$root/import/$kit/plugins");
        write_binary("$root/import/$kit/plugins/example.pm", "plugin fixture\n") if $has_plugin;
        my $data = {
            osimage => {osvers => 'test', osarch => 'x86_64', profile => 'compute', provmethod => 'install'},
            linuximage => {}, kit => {$kit => {kitdir => "$root/kits/$kit"}},
        };
        my @messages;
        my ($out, $err, $result) = capture {
            xCAT_plugin::imgport::make_files($data, "$root/import", sub { push @messages, $_[0] });
        };
        is($result, 1, "import succeeds (plugin=$has_plugin)") or diag "$out$err";
        ok(!grep({ $_->{error} } @messages), 'import reports no errors');
        if ($has_plugin) {
            is(read_binary("$root/xcat/lib/perl/xCAT_plugin/example.pm"), "plugin fixture\n", 'plugin reaches the daemon directory');
            is(read_binary("$root/calls"), "restart\n", 'plugin import requests a fast restart');
        }
    }
}
is(read_binary("$root/calls"), "restart\n", 'imports without plugins do not request another restart');
done_testing();
