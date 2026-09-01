use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

use lib "$FindBin::Bin/../..";
use BuildUtils ();

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

my @pkglist_files = qw(
  xCAT-server/share/xcat/install/ubuntu/compute.ubuntu26.04.ppc64el.pkglist
  xCAT-server/share/xcat/install/ubuntu/compute.ubuntu26.04.x86_64.pkglist
  xCAT-server/share/xcat/netboot/ubuntu/compute.ubuntu26.04.ppc64el.pkglist
  xCAT-server/share/xcat/netboot/ubuntu/compute.ubuntu26.04.x86_64.pkglist
);

foreach my $file (@pkglist_files) {
    my $path = File::Spec->catfile( $repo_root, $file );
    ok( -r $path, "$file exists" );

    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my @packages = grep { /\S/ && !/^\s*#/ } map { chomp; $_ } <$fh>;
    close($fh);

    my %packages = map { $_ => 1 } @packages;
    ok( $packages{'bind9-dnsutils'}, "$file uses bind9-dnsutils" );
    ok( $packages{'chrony'},         "$file uses chrony" );
    ok( !$packages{'dnsutils'},      "$file avoids removed dnsutils package" );
    ok( !$packages{'ntp'},           "$file avoids removed ntp package" );
    ok( !$packages{'ntpdate'},       "$file avoids removed ntpdate package" );
}

foreach my $file (qw(
  xCAT-server/share/xcat/install/ubuntu/compute.ubuntu26.04.ppc64le.pkglist
  xCAT-server/share/xcat/netboot/ubuntu/compute.ubuntu26.04.ppc64le.pkglist
)) {
    my $path = File::Spec->catfile( $repo_root, $file );
    ok( -l $path, "$file aliases ppc64le to ppc64el" );
}

my $subiquity_template = File::Spec->catfile(
    $repo_root,
    'xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl'
);
open( my $tmpl_fh, '<', $subiquity_template ) or die "Unable to read $subiquity_template: $!";
my $template = do { local $/; <$tmpl_fh> };
close($tmpl_fh);

like( $template, qr/\n\s+- bind9-dnsutils\n/, 'subiquity template uses bind9-dnsutils' );
unlike( $template, qr/\n\s+- dnsutils\n/,      'subiquity template avoids removed dnsutils package' );
like( $template, qr/\n\s+- "root:#CRYPTORLOCKED:passwd:key=system,username=root:password#"\n/, 'subiquity uses a locked root password marker when unset' );
like( $template, qr/#UBUNTU_SUBIQUITY_APT_CONFIG#/, 'subiquity apt configuration is rendered from osimage package sources' );
like( $template, qr/package_update: false/, 'subiquity install does not require online package update' );
like( $template, qr/package_upgrade: false/, 'subiquity install does not require online package upgrade' );

my $template_module = File::Spec->catfile( $repo_root, 'xCAT-server/lib/perl/xCAT/Template.pm' );
open( my $module_fh, '<', $template_module ) or die "Unable to read $template_module: $!";
my $module = do { local $/; <$module_fh> };
close($module_fh);

like( $module, qr/URIs: http:\/\/xcat\.invalid\/disabled.*Enabled: no/s, 'subiquity renderer disables duplicate archive sources when Subiquity provides cdrom.sources' );
like( $module, qr/sources_list: \|/, 'subiquity renderer owns Deb822 install media sources when Subiquity does not provide cdrom.sources' );
like( $module, qr/URIs: file:\/\/\/cdrom/, 'subiquity renderer can use the mounted install media as the primary mirror' );
like( $module, qr/Check-Date: no/, 'subiquity renderer avoids cdrom Check-Date conflicts' );
like( $module, qr/fallback: offline-install/, 'subiquity renderer can complete without external apt mirrors' );
like( $module, qr/geoip: false/, 'subiquity renderer does not require external geoip lookup' );
like( $module, qr/- updates.*- backports.*- security/s, 'subiquity renderer disables online update suites' );
like( $module, qr/mirror-selection:/, 'subiquity renderer keeps classic mirror-selection fallback for older Ubuntu releases' );
like( $module, qr/Types: deb.*URIs: \$source.*Suites: \.\/.*Components:.*Trusted: yes/s, 'subiquity renderer includes trusted local xCAT otherpkgdir repositories in Deb822 sources_list' );
like( $module, qr/deb \[trusted=yes\] \$source \.\/"/, 'subiquity renderer keeps classic source-list fallback for older Ubuntu releases' );
like( $module, qr/-f "\$path\/Release"/, 'subiquity renderer requires indexed otherpkgdir repositories' );

my $subiquity_pre = File::Spec->catfile(
    $repo_root,
    'xCAT-server/share/xcat/install/scripts/pre.ubuntu.subiquity'
);
open( my $pre_fh, '<', $subiquity_pre ) or die "Unable to read $subiquity_pre: $!";
my $pre = do { local $/; <$pre_fh> };
close($pre_fh);

like( $pre, qr/id: efi-part\s+type: partition\s+device: disk-detected\s+size: 512M\s+flag: boot\s+number: 1\s+preserve: false\s+grub_device: true/s, 'subiquity UEFI storage marks the EFI partition as grub device' );
like( $pre, qr/id: efi-part-fs\s+type: format\s+fstype: fat32\s+volume: efi-part/s, 'subiquity UEFI storage formats ESP as fat32' );

# The releases the deb builder serves by default. Read from BuildUtils, which is where
# the builder itself reads them, rather than matched against the source that sets them:
# the old assertion passed on any file containing that shell fragment, and broke on a
# reflow that changed nothing.
ok( scalar( grep { $_ eq 'resolute' } BuildUtils::default_dists() ),
    'the Ubuntu repository serves resolute by default' );
like( BuildUtils::reprepro_distributions( [ BuildUtils::default_dists() ], undef ),
    qr/^Codename: resolute$/m,
    'and a resolute stanza reaches conf/distributions' );

done_testing();
