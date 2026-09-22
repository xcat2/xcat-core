#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use File::Temp;
use Test::More;

use XCAT::Test::File qw(repo_path);

sub read_text  { my ($path) = @_; open( my $fh, '<', $path ) or die "$path: $!"; local $/; my $text = <$fh>; close($fh); return $text; }
sub write_text { my ( $path, $text ) = @_; open( my $fh, '>', $path ) or die "$path: $!"; print {$fh} $text; close($fh); return; }

# A Subiquity autoinstall installs the packages of its user-data packages list, and until now the
# template named a fixed set, so the osimage pkglist reached the node only through ospkgs after
# the first boot. The template can now carry #INCLUDE_DEFAULT_PKGLIST_AUTOINSTALL# on a list line,
# and Template.pm renders one list item per pkglist package in its place.

my $module = repo_path('xCAT-server/lib/perl/xCAT/Template.pm');
plan skip_all => 'Template.pm not found' unless -r $module;

my @incs = ( repo_path('perl-xCAT'), repo_path('xCAT-server/lib/perl') );

# Every xCAT module prepends $XCATROOT/lib/perl as it compiles, so on a host with xCAT installed
# the modules Template.pm loads afterwards would come from /opt/xcat. Point it at the checkout.
my $xcatroot = File::Temp->newdir();
mkdir "$xcatroot/lib" or die "$xcatroot/lib: $!";
symlink( repo_path('xCAT-server/lib/perl'), "$xcatroot/lib/perl" ) or die "symlink: $!";
$ENV{XCATROOT} = "$xcatroot";

my $devnull = File::Spec->devnull();
my $probe = join( ' ', $^X, ( map { "-I$_" } @incs ), '-e', "'require xCAT::Template; 1'", ">$devnull", "2>&1" );
plan skip_all => 'xCAT::Template cannot be loaded here' if system($probe) != 0;

require lib;
lib->import(@incs);
require xCAT::Template;
require xCAT::Postage;    # the pkglist reader Template.pm calls, loaded by the plugin in production

# ---- the record filter: only what apt can be asked for in an autoinstall packages list --------
my @packages = xCAT::Template::ubuntu_autoinstall_packages(
    'openssh-server', ' gawk', 'ntp', '-snmpd', '@core', '#NEW_INSTALL_LIST#', 'd-i pkgsel/include string foo',
    'd-i tasksel/first multiselect standard,not-a-real-package', 'nfs-common=1:2.6.4-3ubuntu5', 'gawk', 'Bad_Name', '',
    'libc6', 'libc6:i386', 'curl/noble', 'dns-server^', 'a/b/c', 'vim rsync -busybox-static gpg', '@Group With Space', 'wget Bad_Name', 'bc # a calculator',
    'wget-', 'libc6:i386-', 'tree+', '-snmpd apache2', '@core bc'
);
is_deeply( \@packages, [qw(openssh-server gawk ntp libc6 dns-server^ vim rsync gpg bc tree+)],
    'names and tasks are kept once each, a space-separated line gives each package, a comment ends it; pins, target releases, architecture qualifiers, removals in either hyphen form, a record that begins with a removal or a group, markers, directives and unknown syntax are not' );
is_deeply( [ xCAT::Template::ubuntu_autoinstall_packages( 'msodbcsql18', '#ENV:ACCEPT_EULA=Y#', 'gawk' ) ], [],
    'a list with an apt environment setting stays with ospkgs whole' );
is_deeply( [ xCAT::Template::ubuntu_autoinstall_packages( 'gawk', 'msodbcsql18 #ENV:ACCEPT_EULA=Y#' ) ], [],
    'so does a list with the setting after a package on the same line, where get_envlist reads it too' );
is_deeply( [ xCAT::Template::ubuntu_autoinstall_packages( 'gawk', '#INCLUDEBAD:cannot open pkglist file /absent.pkglist#' ) ], [],
    'a list with an unreadable include stays with ospkgs whole' );
is_deeply( [ xCAT::Template::ubuntu_autoinstall_packages() ], [], 'no records give no packages' );

# ---- the record reader: lines kept whole, includes followed, the comma text unchanged ---------
{
    my $d = File::Temp->newdir();
    write_text( "$d/common.pkglist", "# shared\nnfs-common\n\@Group With Space\n" );
    write_text( "$d/compute.pkglist", "openssh-server\n  # a comment\nd-i tasksel/first multiselect standard,not-a-real-package\n#INCLUDE:$d/common.pkglist#\n#NEW_INSTALL_LIST#\nchrony\n" );
    my @records = xCAT::Postage->get_pkglist_records("$d/compute.pkglist");
    is_deeply( \@records,
        [ 'openssh-server', 'd-i tasksel/first multiselect standard,not-a-real-package', 'nfs-common', '@Group With Space', '#NEW_INSTALL_LIST#', 'chrony' ],
        'records are whole lines, comments dropped, the include expanded in place' );
    is( xCAT::Postage->get_pkglist_tex("$d/compute.pkglist"),
        'openssh-server,d-i tasksel/first multiselect standard,not-a-real-package,nfs-common,@Group With Space,#NEW_INSTALL_LIST#,chrony',
        'the comma text ospkgs receives is unchanged, and cannot tell the directive comma apart' );
    my @missing = xCAT::Postage->get_pkglist_records("$d/absent.pkglist");
    like( $missing[0], qr/^#INCLUDEBAD:/, 'an unreadable file yields the INCLUDEBAD marker record' );

    # top.pkglist includes sub/common.pkglist, which includes leaf.pkglist: the leaf next to top.pkglist is the one meant
    mkdir "$d/sub" or die "$d/sub: $!";
    write_text( "$d/top.pkglist",        "#INCLUDE:sub/common.pkglist#\n" );
    write_text( "$d/sub/common.pkglist", "#INCLUDE:leaf.pkglist#\n" );
    write_text( "$d/leaf.pkglist",       "nfs-common\n" );
    write_text( "$d/sub/leaf.pkglist",   "snmpd\n" );
    is_deeply( [ xCAT::Postage->get_pkglist_records("$d/top.pkglist") ], ['nfs-common'],
        'a nested include resolves against the directory of the listed pkglist' );
    is_deeply( [ xCAT::Postage->get_pkglist_records("$d/top.pkglist") ], [ split /,/, xCAT::Postage->get_pkglist_tex("$d/top.pkglist") ],
        'and reads the same files get_pkglist_tex reads' );

    write_text( "$d/note.pkglist", "#INCLUDE:leaf.pkglist# # the shared leaf\nbc # a calculator\n" );
    my @noted = xCAT::Postage->get_pkglist_records("$d/note.pkglist");
    is_deeply( \@noted, [ split /,/, xCAT::Postage->get_pkglist_tex("$d/note.pkglist") ],
        'an include followed by a note is expanded, the note staying on the last record as get_pkglist_tex leaves it' );
    is_deeply( [ xCAT::Template::ubuntu_autoinstall_packages(@noted) ], [qw(nfs-common bc)], 'and the notes add no packages' );
}
is( xCAT::Template::ubuntu_autoinstall_items( "    ", "    - wget\n    - gpg\n", [qw(gawk gpg chrony)] ),
    "    - \"gawk\"\n    - \"chrony\"\n", 'items already listed above the token are not repeated, and every item is a quoted string' );
is( xCAT::Template::ubuntu_autoinstall_items( "  ", "", [qw(null true 12)] ), "  - \"null\"\n  - \"true\"\n  - \"12\"\n",
    'names YAML would read as null, boolean or number stay strings' );
is( xCAT::Template::ubuntu_autoinstall_items( "    ", "    - wget\n    - chrony\n", [qw(gawk ntp ntpdate snmpd)] ),
    "    - \"gawk\"\n    - \"snmpd\"\n", 'a time daemon the template installs keeps the pkglist time daemons with ospkgs' );
is( xCAT::Template::ubuntu_autoinstall_items( "    ", "    - wget\n", [qw(gawk ntp)] ),
    "    - \"gawk\"\n    - \"ntp\"\n", 'without a fixed time daemon the pkglist one is installed' );

# ---- the rendering: the token line becomes one item per package, at its own indentation -------
my %site;
no warnings 'redefine', 'once';
local *xCAT::TableUtils::get_site_attribute = sub {
    my ( undef, $key ) = @_;
    return defined $site{$key} ? ( $site{$key} ) : ();
};
local *xCAT::NetworkUtils::getipaddr          = sub { return '192.0.2.10'; };
local *xCAT::Template::getPersistentKcmdline = sub { return ''; };
use warnings;

my $dir      = File::Temp->newdir();
my $included = File::Spec->catfile( "$dir", 'common.pkglist' );
my $pkglist  = File::Spec->catfile( "$dir", 'compute.pkglist' );
write_text( $included, "# shared\nnfs-common\nsnmpd\n" );
write_text( $pkglist,  "openssh-server\n# a comment\nchrony rsync # time and files\nwget=1.21.2-2ubuntu1\n-ntp\nwget-\n\@standard\nd-i tasksel/first multiselect standard,not-a-real-package\n#INCLUDE:$included#\n" );

my $in = File::Spec->catfile( "$dir", 'in.tmpl' );
write_text( $in,
        "  packages:\n"
      . "    - openssh-server\n"
      . "    - wget\n"
      . "    - #INCLUDE_DEFAULT_PKGLIST_AUTOINSTALL#\n"
      . "  late-commands:\n"
      . "    - echo done\n" );

my $render = sub {
    my ( $list, %extra ) = @_;
    %site = ( installdir => '/install' );
    my $out = File::Spec->catfile( "$dir", 'out.' . ( defined $list ? 'list' : 'none' ) );
    xCAT::Template->subvars( $in, $out, 'testnode', $list, '/install/ubuntu24.04/x86_64', 'ubuntu', undef,
        { xcatmaster => '192.0.2.10' }, osarch => 'x86_64', %extra );
    return read_text($out);
};

my $rendered = $render->($pkglist);
is( $rendered,
        "  packages:\n"
      . "    - openssh-server\n"
      . "    - wget\n"
      . "    - \"chrony\"\n"
      . "    - \"rsync\"\n"
      . "    - \"nfs-common\"\n"
      . "    - \"snmpd\"\n"
      . "  late-commands:\n"
      . "    - echo done\n",
    'the pkglist packages, includes followed, become list items at the token indentation, without repeating the items above' );
unlike( $rendered, qr/not-a-real-package/, 'a package name inside a preseed directive with commas is not a package' );
unlike( $rendered, qr/wget=/, 'a version pin is not an item: it stays with ospkgs' );
unlike( $rendered, qr/wget-/, 'a trailing-hyphen removal is not an item either: the installer would remove the package the postscripts need' );
unlike( $rendered, qr/"(?:time|and|files)"/, 'an inline comment adds no items' );

# a site template that includes the stock one: the token arrives with the include and must be expanded too
my $wrapper = File::Spec->catfile( "$dir", 'wrapper.tmpl' );
write_text( $wrapper, "#INCLUDE:$in#\n" );
my $render_via = sub {
    my ($list) = @_;
    %site = ( installdir => '/install' );
    my $out = File::Spec->catfile( "$dir", 'out.wrapper.' . ( defined $list ? 'list' : 'none' ) );
    xCAT::Template->subvars( $wrapper, $out, 'testnode', $list, '/install/ubuntu24.04/x86_64', 'ubuntu', undef, { xcatmaster => '192.0.2.10' }, osarch => 'x86_64' );
    return read_text($out);
};
is( $render_via->($pkglist), $rendered, 'a template that includes the stock one renders the same package list' );

my $without = $render->(undef);
is( $without,
    "  packages:\n    - openssh-server\n    - wget\n  late-commands:\n    - echo done\n",
    'an osimage without a pkglist keeps the template packages and loses only the token line' );
is( $render_via->(undef), $without, 'and through an including template the token line goes as well, leaving no empty item' );

my $env_list     = File::Spec->catfile( "$dir", 'env.pkglist' );
my $env_included = File::Spec->catfile( "$dir", 'env-common.pkglist' );
write_text( $env_included, "msodbcsql18 #ENV:ACCEPT_EULA=Y#\n" );
write_text( $env_list,     "gawk\n#INCLUDE:$env_included#\n" );
is( $render->($env_list), $without, 'a pkglist whose include carries an apt environment setting is left to ospkgs whole, and the token line goes' );
is( $render->( $pkglist, environvar => 'ACCEPT_EULA=Y' ), $without,
    'an osimage with environvar installs its pkglist through ospkgs alone, where the variables reach apt-get, and the token line goes' );

# the pkgdir mirrors may need those variables as well, so they stay out of the installer's apt sources too
{
    no warnings 'redefine', 'once';
    local *xCAT::Template::ubuntu_subiquity_otherpkg_sources = sub { () };
    local *xCAT::Template::ubuntu_subiquity_apt_mirror       = sub { 'http://archive.example/ubuntu' };
    my $apt_in = File::Spec->catfile( "$dir", 'apt.tmpl' );
    write_text( $apt_in, "#UBUNTU_SUBIQUITY_APT_CONFIG#\n" );
    my $apt_render = sub {
        my (%extra) = @_;
        %site = ( installdir => '/install' );
        my $out = File::Spec->catfile( "$dir", 'out.apt' );
        xCAT::Template->subvars( $apt_in, $out, 'testnode', $pkglist, '/install/ubuntu24.04/x86_64', 'ubuntu', undef, { xcatmaster => '192.0.2.10' },
            osarch => 'x86_64', pkgdirs => '/install/ubuntu24.04/x86_64,http://mirror.example/ubuntu noble main', %extra );
        return read_text($out);
    };
    like( $apt_render->(), qr{URIs: http://mirror\.example/ubuntu}, 'the pkgdir mirror joins the installer sources' );
    like( $apt_render->(), qr{^    conf: 'APT::Install-Recommends "false";'$}m, 'the installer installs without recommended packages, as ospkgs does' );
    unlike( $apt_render->( environvar => 'http_proxy=http://proxy.example:3128' ), qr{mirror\.example|xcat-pkgdir},
        'but not for an osimage with environvar, whose mirrors may need those variables' );
}

done_testing();
