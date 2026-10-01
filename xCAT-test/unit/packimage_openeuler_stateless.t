#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use xCAT::Table;

our ($capture, @commands);
BEGIN {
    *CORE::GLOBAL::system = sub {
        return CORE::system(@_) unless $capture;
        push @commands, ['system', join(' ', @_)];
        return 0;
    };
    *CORE::GLOBAL::readpipe = sub {
        return CORE::readpipe($_[0]) unless $capture;
        push @commands, ['readpipe', $_[0]];
        return '';
    };
}

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db", "$fixture/root/lib/perl", "$fixture/root/share",
    "$fixture/install/postscripts");
symlink(repo_path('perl-xCAT/xCAT'), "$fixture/root/lib/perl/xCAT") or die $!;
symlink(repo_path('xCAT-server/share/xcat'), "$fixture/root/share/xcat") or die $!;
write_text("$fixture/install/postscripts/xcatdsklspost", "fixture postscript\n");
$ENV{XCATROOT} = "$fixture/root";
$ENV{XCATCFG} = "SQLite:$fixture/db";
require(repo_path('xCAT-server/lib/xcat/plugins/packimage.pm'));
my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({key => 'installdir'}, {value => "$fixture/install"});
$site->setAttribs({key => 'secureroot'}, {value => '1'});
my $passwd = xCAT::Table->new('passwd', -create => 1);
$passwd->setAttribs({key => 'system', username => 'root'},
    {password => '*', cryptmethod => 'sha512'});
my $osimage = xCAT::Table->new('osimage', -create => 1);
my $linuximage = xCAT::Table->new('linuximage', -create => 1);
my $sequence = 0;

sub attempt {
    my ($os, $arch, $statelite) = @_;
    my $name = 'fixture-' . ++$sequence;
    my $dest = "$fixture/$name";
    my $root = "$dest/rootimg";
    make_path("$root/etc/init.d", "$root/opt/xcat", "$root/xcatpost",
        "$root/.statelite", "$root/usr/lib/dracut/modules.d/98xcat");
    write_text("$root/etc/shadow", "root:*:1:0:99999:7:::\n");
    write_text("$root/etc/init.d/statelite", "legacy script\n");
    write_text("$root/xcatpost/sentinel", "preserve on rejection\n");
    write_text("$root/usr/lib/dracut/modules.d/98xcat/install", "native module\n");
    write_text("$root/.statelite/litefile.save", "StateLite marker\n") if $statelite;
    $osimage->setAttribs({imagename => $name},
        {osvers => $os, osarch => $arch, profile => 'compute', provmethod => 'netboot'});
    $linuximage->setAttribs({imagename => $name}, {rootimgdir => $dest});
    my (@responses, $locks);
    $locks = 0;
    local $capture = 1;
    local @commands;
    no warnings qw(redefine once);
    local *xCAT::Utils::acquire_lock_imageop = sub { ++$locks; return (0, undef); };
    local *xCAT::Utils::runcmd = sub {
        push @commands, ['runcmd', $_[1]];
        $::RUNCMD_RC = 0;
        return ([]);
    };
    {
        my $output = '';
        open(my $stdout, '>', \$output) or die $!;
        local *STDOUT = $stdout;
        xCAT_plugin::packimage::process_request({arg => ['--nosyncfiles', '-c', 'fixture-stop', $name]},
            sub { push @responses, @_ });
    }
    return (\@responses, [@commands], $locks, $root);
}

for my $case (['openeuler20.03sp4', 'x86_64'], ['openeuler22.03sp4', 'x86_64'],
    ['openeuler24.03sp3', 'x86_64'], ['openeuler24.03', 'ppc64le']) {
    my ($responses, $commands, $locks, $root) = attempt(@$case, 0);
    ok(grep({ $_->{error} && $_->{error}[0] =~ /Invalid compress method/ } @$responses),
        "@$case reaches the archive boundary");
    is($locks, 1, 'native stateless image acquires its operation lock');
    ok(!grep({ $_->[1] =~ /ilitefile|\.statebackup|97xcat/ } @$commands),
        'native stateless image performs no StateLite lookup or restoration');
    is(read_text("$root/usr/lib/dracut/modules.d/98xcat/install"), "native module\n",
        'native dracut module remains intact');
}

for my $case (['openeuler24.03sp3', 'x86_64', 1], ['openeuler24.03', 'ppc64le', 1],
    ['openeuler25.03', 'x86_64', 0], ['openeuler24.03sp0', 'x86_64', 0],
    ['openeuler24.03sp3', 's390x', 0]) {
    my ($responses, $commands, $locks, $root) = attempt(@$case);
    my $error = $case->[2] ? qr/StateLite images are not supported/ : qr/Unsupported openEuler image/;
    ok(grep({ $_->{error} && $_->{error}[0] =~ $error } @$responses), "@$case is rejected");
    is($locks, 0, 'rejection precedes image locking');
    is_deeply($commands, [], 'rejection precedes image commands');
    is(read_text("$root/xcatpost/sentinel"), "preserve on rejection\n",
        'rejected image retains its existing postscripts');
}

for my $statelite (0, 1) {
    my ($responses, $commands) = attempt('rhels9.6', 'x86_64', $statelite);
    ok(grep({ $_->{error} && $_->{error}[0] =~ /Invalid compress method/ } @$responses),
        "existing EL image reaches the archive boundary, StateLite=$statelite");
    ok(grep({ $_->[0] eq 'runcmd' && $_->[1] =~ /^ilitefile / } @$commands),
        'existing EL StateLite lookup is preserved');
}

done_testing();
