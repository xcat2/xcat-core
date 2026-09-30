#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
make_path("$dir/db", "$dir/install");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Table;
require xCAT::TableUtils;
require xCAT::SvrUtils;

my $site = xCAT::Table->new('site', -create => 1);
$site->setAttribs({ key => 'installdir' }, { value => "$dir/install" });
$site->close();

for my $case (
    ['openeuler20.03sp4', 'x86_64'], ['openeuler22.03sp4', 'x86_64'],
    ['openeuler24.03sp1', 'x86_64'], ['openeuler24.03sp3', 'x86_64'],
    ['openeuler24.03sp4', 'x86_64'], ['openeuler24.03', 'ppc64le'],
) {
    my ($os, $arch) = @$case;
    subtest "$os $arch" => sub {
        my $media = "$dir/install/$os/$arch";
        my $distro = "$os-$arch";
        my @install = xCAT::SvrUtils->update_tables_with_templates($os, $arch, $media, $distro);
        is($install[0], 0, 'install profiles create real image records');
        my @diskless = xCAT::SvrUtils->update_tables_with_diskless_image($os, $arch, undef, 'netboot', $media, $distro);
        is($diskless[0], 0, 'diskless compute profile creates real image records');

        my $images = xCAT::Table->new('osimage');
        my $linux = xCAT::Table->new('linuximage');
        for my $mode_profile (['install', 'compute'], ['install', 'service'], ['netboot', 'compute']) {
            my ($mode, $profile) = @$mode_profile;
            my $name = "$os-$arch-$mode-$profile";
            my $image = $images->getAttribs({ imagename => $name }, 'osvers', 'osarch', 'osdistroname', 'postscripts');
            is($image->{osvers}, $os, "$mode-$profile keeps exact release/SP");
            is($image->{osarch}, $arch, "$mode-$profile keeps native architecture");
            is($image->{osdistroname}, $distro, "$mode-$profile links its imported distribution");
            my $assets = $linux->getAttribs({ imagename => $name }, 'template', 'pkglist', 'pkgdir', 'postinstall', 'exlist', 'rootimgdir', 'otherpkglist');
            is($assets->{pkgdir}, $media, "$mode-$profile uses the imported package directory");
            ok(-r $assets->{pkglist}, "$mode-$profile selects an existing package list");
            if ($mode eq 'install') {
                ok(-r $assets->{template}, "$profile selects an existing installation template");
            } else {
                ok(-x $assets->{postinstall}, 'diskless postinstall resolves an executable shared script');
                ok(-r $assets->{exlist}, 'diskless exclude list resolves');
                is($assets->{rootimgdir}, "$dir/install/netboot/$os/$arch/compute", 'diskless root path keeps exact release and architecture');
            }
            is($image->{postscripts}, 'servicenode', 'install-service activates the Service Node postscript')
              if $profile eq 'service';
            if ($profile eq 'service') {
                like($assets->{otherpkglist}, qr{/service\.\Q$os\E\.\Q$arch\E\.otherpkgs\.pkglist$},
                    'Service Node packages select the exact native release and architecture');
                ok(-r $assets->{otherpkglist}, 'Service Node package list exists');
            }
        }

        my $install_name = "$os-$arch-install-compute";
        my $netboot_name = "$os-$arch-netboot-compute";
        $linux->setAttribs({ imagename => $install_name }, {
            template => '/admin/custom.tmpl', pkglist => '/admin/custom.pkglist', pkgdir => '/admin/media',
        });
        $linux->setAttribs({ imagename => $netboot_name }, {
            postinstall => '/admin/postinstall', rootimgdir => '/admin/retained-image', pkglist => '/admin/diskless.pkglist',
        });
        xCAT::SvrUtils->update_tables_with_templates($os, $arch, "$dir/reimport", $distro);
        xCAT::SvrUtils->update_tables_with_diskless_image($os, $arch, undef, 'netboot', "$dir/reimport", $distro);
        is_deeply($linux->getAttribs({ imagename => $install_name }, 'template', 'pkglist', 'pkgdir'),
            { template => '/admin/custom.tmpl', pkglist => '/admin/custom.pkglist', pkgdir => '/admin/media' },
            'reimport preserves administrator install assets');
        is_deeply($linux->getAttribs({ imagename => $netboot_name }, 'postinstall', 'rootimgdir', 'pkglist'),
            { postinstall => '/admin/postinstall', rootimgdir => '/admin/retained-image', pkglist => '/admin/diskless.pkglist' },
            'reimport preserves administrator diskless assets and retained image');

        my @service = xCAT::SvrUtils->update_tables_with_diskless_image($os, $arch, 'service', 'netboot', $media, $distro);
        is($service[0], 0, 'the established explicit diskless Service Node workflow resolves');
        my $service_assets = $linux->getAttribs({ imagename => "$os-$arch-netboot-service" }, 'pkglist', 'rootimgdir', 'otherpkglist');
        like($service_assets->{pkglist}, qr{/service\.openeuler\.pkglist$}, 'diskless Service Node uses its service package list');
        is($service_assets->{rootimgdir}, "$dir/install/netboot/$os/$arch/service", 'diskless Service Node has an independent image root');
        ok(-r $service_assets->{otherpkglist}, 'diskless Service Node has a readable native xCAT package list');

        for my $mode_profile (['install', 'compute'], ['install', 'service'],
            ['netboot', 'compute'], ['netboot', 'service']) {
            my ($mode, $profile) = @$mode_profile;
            subtest "$mode-$profile reimport recovery" => sub {
                my $name = "$os-$arch-$mode-$profile";
                my $key = { imagename => $name };
                my @image_fields = qw(osvers osarch profile provmethod description synclists postscripts);
                my @asset_fields = qw(template pkgdir pkglist otherpkglist rootimgdir postinstall addkcmdline);
                my $reimport = sub {
                    return $mode eq 'install'
                      ? xCAT::SvrUtils->update_tables_with_templates($os, $arch, $media, $distro)
                      : xCAT::SvrUtils->update_tables_with_diskless_image($os, $arch, $profile, 'netboot', $media, $distro);
                };
                $images->setAttribs($key, {
                    description => 'administrator image', synclists => '/admin/image.synclist',
                });
                my $original_image = $images->getAttribs($key, @image_fields);
                $linux->delEntries($key);
                ok(!$linux->getAttribs($key, 'imagename'), 'fixture leaves only the osimage record');
                my @result = $reimport->();
                is($result[0], 0, 'reimport repairs an interrupted image-pair creation');
                is_deeply($images->getAttribs($key, @image_fields), $original_image,
                    'repair preserves the existing osimage customizations');
                my $repaired = $linux->getAttribs($key, @asset_fields);
                is($repaired->{pkgdir}, $media, 'the missing linuximage receives its native media directory');
                ok(-r $repaired->{pkglist}, 'the repaired image has a readable package list');
                if ($mode eq 'install') {
                    ok(-r $repaired->{template}, 'the repaired installed image has a readable template');
                } else {
                    is($repaired->{rootimgdir}, "$dir/install/netboot/$os/$arch/$profile",
                        'the repaired diskless image has its native root directory');
                }

                $linux->setAttribs($key, { pkgdir => '/admin/retained-media', addkcmdline => 'admin-option' });
                my $original_assets = $linux->getAttribs($key, @asset_fields);
                $images->delEntries($key);
                ok(!$images->getAttribs($key, 'imagename'), 'fixture leaves only the linuximage record');
                @result = $reimport->();
                is($result[0], 0, 'reimport creates the missing osimage record');
                is($images->getAttribs($key, 'osvers')->{osvers}, $os,
                    'the restored osimage retains the exact native release');
                is_deeply($linux->getAttribs($key, @asset_fields), $original_assets,
                    'repair preserves the existing linuximage customizations');

                my $renamed_key = { imagename => "renamed-$name" };
                $images->setAttribs($renamed_key, $original_image);
                $linux->setAttribs($renamed_key, $original_assets);
                $images->delEntries($key);
                $linux->delEntries($key);
                @result = $reimport->();
                is($result[0], 0, 'a renamed matching image does not prevent importing defaults');
                ok($images->getAttribs($key, 'imagename'), 'the canonical osimage is created');
                ok($linux->getAttribs($key, 'imagename'), 'the canonical linuximage is created');
                is_deeply($images->getAttribs($renamed_key, @image_fields), $original_image,
                    'the renamed osimage is preserved');
                is_deeply($linux->getAttribs($renamed_key, @asset_fields), $original_assets,
                    'the renamed linuximage is preserved');
            };
        }
        $images->close();
        $linux->close();
    };
}

done_testing();
