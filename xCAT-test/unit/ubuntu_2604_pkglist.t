use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp ();
use Test::More;

use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

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

# ---------------------------------------------------- the rendered apt config --
# What Subiquity is handed, not how Template.pm is written. These assertions used
# to grep the `push @lines, '...'` literals out of Template.pm, which passed on any
# reordering and would have kept passing had the renderer moved somewhere it never
# runs. Only two collaborators are stubbed -- the two that read the xCAT database.
# The release branch is driven for real, by the media directory the renderer parses.
require xCAT::Template;

our @otherpkg_sources;
{
    no warnings qw(redefine once);
    *xCAT::Template::ubuntu_subiquity_apt_mirror       = sub { return $main::apt_mirror };
    *xCAT::Template::ubuntu_subiquity_otherpkg_sources = sub { return @main::otherpkg_sources };
}

our $apt_mirror = '';

sub apt_config_for {
    my ( $media_dir, %args ) = @_;
    local $apt_mirror   = $args{mirror} // '';
    local @otherpkg_sources = @{ $args{sources} || [] };
    return xCAT::Template::ubuntu_subiquity_apt_config($media_dir);
}

# 26.04's Subiquity writes its own cdrom.sources. A second file:///cdrom source
# collides with it, so the rendered one is present but inactive.
my $noble_plus = apt_config_for('ubuntu26.04');
like( $noble_plus, qr{^\s+URIs: http://xcat\.invalid/disabled$}m,
    'on 26.04 the install-media source is rendered inert' );
like( $noble_plus, qr/^\s+Enabled: no$/m,
    'and is explicitly disabled so Subiquity does not fetch from it' );
unlike( $noble_plus, qr{file:///cdrom},
    'so it cannot collide with the cdrom.sources Subiquity generates' );

# 24.04 has Deb822 but no generated cdrom.sources, so xCAT owns the media source.
my $noble = apt_config_for('ubuntu24.04');
like( $noble, qr/^\s+sources_list: \|$/m,
    'on 24.04 xCAT owns the Deb822 sources_list' );
like( $noble, qr{^\s+URIs: file:///cdrom$}m,
    'and points it at the mounted install media' );
like( $noble, qr/^\s+Check-Date: no$/m,
    'and waives Check-Date, which the media index would otherwise fail' );

# Before Deb822 the same intent is expressed with mirror-selection.
my $focal = apt_config_for('ubuntu20.04');
like( $focal, qr/^\s+mirror-selection:$/m,
    'older releases keep the classic mirror-selection form' );
like( $focal, qr{^\s+- uri: file:/cdrom$}m,
    'still served from the install media' );
unlike( $focal, qr/sources_list: \|/,
    'and are not given a Deb822 block they cannot parse' );

# Common to every offline render: no external mirror is required to finish.
foreach my $case ( [ '26.04', $noble_plus ], [ '24.04', $noble ], [ '20.04', $focal ] ) {
    my ( $name, $rendered ) = @{$case};
    like( $rendered, qr/^\s+fallback: offline-install$/m,
        "$name completes without an external apt mirror" );
    like( $rendered, qr/^\s+geoip: false$/m,
        "$name does not wait on a geoip lookup" );
    like( $rendered, qr/^\s+disable_suites:\n\s+- updates\n\s+- backports\n\s+- security$/m,
        "$name has the online update suites disabled" );
}

# otherpkgdir repositories reach the installer in whichever form the release reads.
my $with_otherpkgs = apt_config_for( 'ubuntu24.04', sources => ['http://mn/otherpkg'] );
like( $with_otherpkgs,
    qr/^\s+Types: deb\n\s+URIs: http:\/\/mn\/otherpkg\n\s+Suites: \.\/\n\s+Components:\n\s+Trusted: yes$/m,
    'Deb822 releases get the xCAT repository as a trusted Deb822 stanza' );

my $classic_otherpkgs = apt_config_for( 'ubuntu20.04', sources => ['http://mn/otherpkg'] );
like( $classic_otherpkgs, qr{source: "deb \[trusted=yes\] http://mn/otherpkg \./"},
    'and older releases get the same repository as a one-line source' );

# An online mirror turns the offline handling off entirely.
my $online = apt_config_for( 'ubuntu24.04', mirror => 'http://archive.example/ubuntu' );
like( $online, qr{^\s+- uri: http://archive\.example/ubuntu$}m,
    'a configured mirror becomes the primary' );
unlike( $online, qr/fallback: offline-install/,
    'and the offline fallback is not rendered alongside it' );
unlike( $online, qr/disable_suites/,
    'nor are updates and security disabled on an online install' );

# The reason a bare directory is not offered as a repository: apt needs an index.
my $repo_dir = File::Temp::tempdir( CLEANUP => 1 );
ok( !xCAT::Template::ubuntu_subiquity_local_apt_repo($repo_dir),
    'an empty directory is not treated as an apt repository' );
open( my $pkgs_fh, '>', File::Spec->catfile( $repo_dir, 'Packages' ) ) or die $!;
close($pkgs_fh);
ok( !xCAT::Template::ubuntu_subiquity_local_apt_repo($repo_dir),
    'nor is one with packages but no Release index' );
open( my $rel_fh, '>', File::Spec->catfile( $repo_dir, 'Release' ) ) or die $!;
close($rel_fh);
ok( xCAT::Template::ubuntu_subiquity_local_apt_repo($repo_dir),
    'an indexed directory is' );

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
