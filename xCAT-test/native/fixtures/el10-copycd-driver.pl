use strict;
use warnings;
use lib '/repo/xCAT-test/lib', '/repo/perl-xCAT', '/repo/xCAT-server/lib/perl',
    '/repo/xCAT-server/share/xcat/netboot/imgutils';
use File::Slurper qw(write_text);
use JSON qw(encode_json);
use XCAT::Test::File qw(repo_path);
use xCAT::Table;
use xCAT::TableUtils;
use xCAT::SvrUtils;
use imgutils;
require(repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm'));

my ($os, $arch) = @ARGV;
my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({ key => 'installdir' }, { value => '/install' });
$site->close();
my @errors;
for my $pass (1 .. 2) {
    xCAT_plugin::anaconda::copycd(
        { arg => ['-m', '/work/media', '-n', $os, '-a', $arch] },
        sub { push @errors, $_[0]->{error} if $_[0]->{error}; },
        sub { die 'Unexpected nested request'; });
    my $table = xCAT::Table->new('linuximage');
    my $image = $table->getAttribs({ imagename => "$os-$arch-netboot-compute" }, 'pkgdir', 'pkglist');
    die 'No netboot image created' unless $image;
    my %packages = imgutils::get_package_names($image->{pkglist});
    write_text("/work/result-$pass.json", encode_json({
        %$image, packages => \%packages, errors => \@errors,
    }));
    $table->close();
}
