#!/usr/bin/env perl
use strict;
use warnings;

use File::Slurper qw(read_text write_text);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'template rendering requires Linux namespaces' unless $^O eq 'linux';
my $database = template_database();
set_row('site', {key => 'secureroot'}, {value => 0});
set_row('nodetype', {node => 'node'}, {os => 'rhels10.0', arch => 'x86_64', provmethod => 'install'});
my $kickstart = repo_path('xCAT-server/share/xcat/install/rh/compute.rhels10.tmpl');
(my $pkglist = $kickstart) =~ s/\.tmpl$/.pkglist/;
my $output = "$database/ks";

sub render_kickstart {
    return eval {
        render_template($database, $kickstart, $output, 'node', $pkglist, '/install/media', 'rh', undef,
            {xcatmaster => '192.0.2.1'});
        1;
    } ? '' : $@;
}

my $error = render_kickstart();
like($error, qr/Unable to find requested field <password> from table <passwd>, with key <key=system,username=root>/,
    'a kickstart without a root password row is refused');

set_row('passwd', {key => 'system', username => 'root'}, {password => 'cluster'});
$error = render_kickstart();
is($error, '', 'a kickstart with a root password row renders') or diag($error);
my ($hash) = (-f $output ? read_text($output) : '') =~ /^rootpw --iscrypted (\S+)$/m;
ok(defined($hash) && crypt('cluster', $hash) eq $hash, 'the kickstart carries the hash of the root password');

set_row('nodetype', {node => 'node'}, {os => 'ubuntu24.04', arch => 'x86_64', provmethod => 'install'});
my $passwd = xCAT::Table->new('passwd') or die 'Cannot open passwd';
$passwd->delEntries({key => 'system', username => 'root'});
$passwd->close();
write_text("$database/image.pkglist", "vim\n");
my $autoinstall = "$database/autoinstall.yaml";
my $locked = eval {
    render_template($database, repo_path('xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl'),
        $autoinstall, 'node', "$database/image.pkglist", '/install/ubuntu24.04/x86_64', 'ubuntu', undef,
        {xcatmaster => '192.0.2.1'}, osarch => 'x86_64');
    1;
};
ok($locked, 'an autoinstall without a root password row renders') or diag($@);
like(-f $autoinstall ? read_text($autoinstall) : '', qr/^\s+password: "\*"$/m,
    'the autoinstall locks the password that has no row');

done_testing();
