#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Storable qw(nstore retrieve);
use Test::More;
use XCAT::Test::File qw(repo_path slurp_repo_file);
use imgutils;
use xCAT::Schema;

my $key = 'file:///tmp/genimage-rpm-keys.abc123';

is(imgutils::rpm_repository_config('rocky9.6', 'rocky9.6-x86_64-0', 'file:///install/rocky9.6/x86_64'),
    "[rocky9.6-x86_64-0]\nname=rocky9.6-x86_64-0\nbaseurl=file:///install/rocky9.6/x86_64\n" .
    "gpgcheck=0\nskip_if_unavailable=True\n\n",
    'EL repositories stay unverified by default');
is(imgutils::rpm_repository_config('rocky9.6', 'otherpkgs1', 'https://repo.example/epel/9/', ''),
    "[otherpkgs1]\nname=otherpkgs1\nbaseurl=https://repo.example/epel/9/\n" .
    "gpgcheck=0\nskip_if_unavailable=True\n\n",
    'an empty key set does not enable EL verification');
is(imgutils::rpm_repository_config('rocky9.6', 'otherpkgs1', 'https://repo.example/epel/9/', $key),
    "[otherpkgs1]\nname=otherpkgs1\nbaseurl=https://repo.example/epel/9/\n" .
    "gpgcheck=1\ngpgkey=$key\nskip_if_unavailable=True\n\n",
    'EL repositories verify against the supplied trusted keys');
is(imgutils::rpm_repository_config('openeuler24.03sp3', 'otherpkgs1', 'https://repo.example/oe/', $key),
    "[otherpkgs1]\nname=otherpkgs1\nbaseurl=https://repo.example/oe/\n" .
    "gpgcheck=1\ngpgkey=$key\nskip_if_unavailable=False\n\n",
    'openEuler repositories keep their strict verification');
ok(!eval { imgutils::rpm_repository_config('openeuler24.03sp3', 'otherpkgs1', 'https://repo.example/oe/'); 1 },
    'openEuler repositories still require trusted keys');

my @urls = ('https://repo.example/epel/9/', 'https://repo.example/ohpc/3/');
is_deeply([imgutils::otherpkgs_repository_urls('.', undef, @urls)], \@urls,
    'URL-only otherpkgdir does not add a file:/// repository');
is_deeply([imgutils::otherpkgs_repository_urls('xcat', '', @urls)], \@urls,
    'an empty local otherpkgdir does not add a file:/// repository');
is_deeply([imgutils::otherpkgs_repository_urls('xcat', '/install/post/otherpkgs/rocky9.6/x86_64', @urls)],
    [@urls, 'file:///install/post/otherpkgs/rocky9.6/x86_64/xcat'],
    'a local otherpkgdir adds its subdirectory after the URLs');
is_deeply([imgutils::otherpkgs_repository_urls('.', '/install/post/otherpkgs/rocky9.6/x86_64')],
    ['file:///install/post/otherpkgs/rocky9.6/x86_64/.'],
    'a local-only otherpkgdir keeps its repository');

ok(scalar(grep { $_ eq 'gpgcheck' } @{ $xCAT::Schema::tabspec{linuximage}->{cols} }),
    'linuximage table includes gpgcheck');
ok(length($xCAT::Schema::tabspec{linuximage}->{descriptions}->{gpgcheck} // ''),
    'linuximage.gpgcheck is described');
is($xCAT::Schema::defspec{osimage}->{attrhash}->{gpgcheck}->{tabentry}, 'linuximage.gpgcheck',
    'osimage object exposes gpgcheck');

$ENV{XCATROOT} = repo_path('xCAT-server');
require(repo_path('xCAT-server/lib/xcat/plugins/genimage.pm'));
my $pkgdir = tempdir(CLEANUP => 1);
write_text("$pkgdir/compute.pkglist", "bash\n");

sub dispatch {
    my ($os, $gpgcheck) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $out = "$dir/command";
    my %rows = (
        osimage    => { osvers => $os, osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' },
        linuximage => { pkglist => "$pkgdir/compute.pkglist", otherpkglist => '', postinstall => '',
            rootimgdir => "$dir/image", (defined($gpgcheck) ? (gpgcheck => $gpgcheck) : ()) },
    );
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        my @responses;
        no warnings qw(redefine once);
        local *xCAT::Table::new = sub {
            my ($class, $table) = @_;
            die "Unexpected table $table" unless $rows{$table};
            return bless { row => $rows{$table} }, 'Local::ImageTable';
        };
        local *Local::ImageTable::getAttribs = sub { return { %{ $_[0]{row} } }; };
        local *xCAT::TableUtils::getInstallDir = sub { return '/install'; };
        local *xCAT::TableUtils::get_site_attribute = sub { return (); };
        local *xCAT::Utils::runcmd = sub { die 'Dry run attempted to execute an image build'; };
        xCAT_plugin::genimage::process_request({ command => ['genimage'], arg => [
            '--dryrun', '--tempfile', $out, 'testimage',
        ] }, sub { push @responses, @_ }, sub { die 'Dry run attempted a database update'; });
        nstore(\@responses, "$dir/responses");
        exit 0;
    }
    waitpid($pid, 0);
    die "Plugin child failed: $?" if $?;
    return (retrieve("$dir/responses"), -f $out ? read_text($out) : '');
}

for my $value (undef, '', '0', 'no') {
    my $label = defined($value) ? "'$value'" : 'unset';
    my ($responses, $out) = dispatch('rocky9.6', $value);
    ok(!grep({ $_->{error} } @$responses), "gpgcheck $label builds the image");
    like($out, qr{netboot/rocky; ./genimage .* testimage\n}, "gpgcheck $label uses the EL builder");
    unlike($out, qr/--gpgcheck/, "gpgcheck $label leaves verification off");
}
for my $value ('1', 'yes', 'YES') {
    my ($responses, $out) = dispatch('rocky9.6', $value);
    ok(!grep({ $_->{error} } @$responses), "gpgcheck '$value' builds the image");
    like($out, qr{netboot/rocky; ./genimage .* --gpgcheck testimage\n}, "gpgcheck '$value' enables verification");
}
{
    my ($responses, $out) = dispatch('rocky9.6', 'maybe');
    is_deeply([map { @{ $_->{error} // [] } } @$responses],
        ["Invalid linuximage.gpgcheck value 'maybe' for image 'testimage'. Valid values are 1, yes, 0 or no."],
        'an invalid gpgcheck value is rejected');
    is($out, '', 'an invalid gpgcheck value does not produce a build command');
}
{
    my ($responses, $out) = dispatch('sles15.6', 'yes');
    is_deeply([map { @{ $_->{error} // [] } } @$responses],
        ['linuximage.gpgcheck is not supported for sles15.6 diskless images.'],
        'a builder without gpgcheck support does not silently skip verification');
    is($out, '', 'an unsupported gpgcheck image does not produce a build command');
}

my $builder = slurp_repo_file('xCAT-server/share/xcat/netboot/rh/genimage');
like($builder, qr/'gpgcheck'\s*=>\s*\\\$gpgcheck/, 'the RPM builder accepts --gpgcheck');
like($builder, qr/if \(\$gpgcheck \|\| defined\(imgutils::openeuler_release_version\(\$osver\)\)\)/,
    'the RPM builder exports the trusted keys when verification is requested');
like($builder, qr/imgutils::otherpkgs_repository_urls\(/, 'the RPM builder uses the shared otherpkgs repository list');

done_testing();
