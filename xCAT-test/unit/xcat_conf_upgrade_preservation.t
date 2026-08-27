#!/usr/bin/env perl
# xcat.conf used to be ordinary payload rewritten from a conf.orig template in
# %post, so an upgrade discarded local edits with no .rpmnew or .rpmsave. Pin
# the replacement: build-time source selection, config(noreplace) ownership,
# and a %pretrans migration that only removes a still-unmodified active file.
# The migration has to be in %pretrans: rpm fixes each config file's fate
# before %pre, so removing the file there can leave only a .rpmnew behind.
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($relative_path) = @_;
    my $path = File::Spec->catfile( $repo_root, split( '/', $relative_path ) );
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

# Only real section keywords end a section, so nested %if/%ifos/%define stay put.
my %SECTION = map { $_ => 1 }
    qw(description prep build pretrans pre install post preun postun posttrans clean files changelog);

sub section {
    my ( $spec, $wanted ) = @_;
    my ( $inside, @body ) = (0);
    for my $line ( split( /\n/, $spec, -1 ) ) {
        if ( $line =~ /^%(\w+)/ && $SECTION{$1} ) {
            $inside = ( $1 eq $wanted );
            next;
        }
        push @body, $line if $inside;
    }
    return join( "\n", @body ) . "\n";
}

my @packages = (
    {
        name => 'management-node',
        spec => 'xCAT/xCAT.spec',
        # %httpconfigdir redirects these to /etc/xcathttpdsave on s390x.
        templates => '/etc/%httpconfigdir/conf.orig',
        apache24  => 7,
        order     => [ 'httpd', 'apache2' ],
    },
    {
        name      => 'service-node',
        spec      => 'xCATsn/xCATsn.spec',
        templates => '/etc/xcat/conf.orig',
        apache24  => 6,
        order     => [ 'apache2', 'httpd' ],
    },
);

for my $pkg (@packages) {
    my $label     = $pkg->{name};
    my $spec      = read_file( $pkg->{spec} );
    my $templates = quotemeta $pkg->{templates};
    my $apache24  = $pkg->{apache24};
    my ( $first, $second ) = @{ $pkg->{order} };

    # The %install selection is by source number, so pin what each one holds.
    like( $spec, qr{^Source1:\s+xcat\.conf$}m,
        "$label package still takes the Apache 2.2 configuration from Source1" );
    like( $spec, qr{^Source$apache24:\s+xcat\.conf\.apach24$}m,
        "$label package still takes the Apache 2.4 configuration from Source$apache24" );

    my $install = section( $spec, 'install' );
    like(
        $install,
        qr{
            ^%if \s+ 0%\{\?fedora\} \s* \|\| \s*
                     0%\{\?rhel\} \s* >= \s* 7 \s* \|\| \s*
                     0%\{\?suse_version\} \s* >= \s* 1200 \s* $ \n
            ^cp \s+ %\{SOURCE$apache24\} \s+ \$RPM_BUILD_ROOT/etc/$first/conf\.d/xcat\.conf \s* $ \n
            ^cp \s+ %\{SOURCE$apache24\} \s+ \$RPM_BUILD_ROOT/etc/$second/conf\.d/xcat\.conf \s* $ \n
            ^%else \s* $ \n
            ^cp \s+ %\{SOURCE1\} \s+ \$RPM_BUILD_ROOT/etc/$first/conf\.d/xcat\.conf \s* $ \n
            ^cp \s+ %\{SOURCE1\} \s+ \$RPM_BUILD_ROOT/etc/$second/conf\.d/xcat\.conf \s* $ \n
            ^%endif \s* $
        }mx,
        "$label package selects the Apache generation at build time, Apache 2.4 on Fedora, EL7+ and SLES 12+"
    );

    # The next upgrade's %pretrans compares against these, so they must stay shipped.
    like( $install, qr{^cp \s+ %\{SOURCE$apache24\} \s+ \$RPM_BUILD_ROOT$templates/xcat\.conf\.apach24 \s* $}mx,
        "$label package still saves the Apache 2.4 template under conf.orig" );
    like( $install, qr{^cp \s+ %\{SOURCE1\} \s+ \$RPM_BUILD_ROOT$templates/xcat\.conf\.apach22 \s* $}mx,
        "$label package still saves the Apache 2.2 template under conf.orig" );

    my $files = section( $spec, 'files' );
    for my $dir ( 'httpd', 'apache2' ) {
        like( $files, qr{^%config\(noreplace\)\s+/etc/$dir/conf\.d/xcat\.conf\s*$}m,
            "$label package owns /etc/$dir/conf.d/xcat.conf as config(noreplace)" );
    }
    like( $files, qr{^$templates/xcat\.conf\.apach24\s*$}m,
        "$label package ships the Apache 2.4 template" );
    like( $files, qr{^$templates/xcat\.conf\.apach22\s*$}m,
        "$label package ships the Apache 2.2 template" );

    my $post = section( $spec, 'post' );
    unlike( $post, qr{\brm\b[^\n]*conf\.d/xcat\.conf},
        "$label %post never removes an active xcat.conf" );
    unlike( $post, qr{\bcp\b[^\n]*xcat\.conf},
        "$label %post never copies a template over an active xcat.conf" );
    unlike( $post, qr{conf\.orig},
        "$label %post no longer reads the saved templates at all" );

    # The only mention left in %post is the read-only guard around a2enmod.
    my @post_refs = ( $post =~ m{^([^\n]*conf\.d/xcat\.conf[^\n]*)$}mg );
    is( scalar @post_refs, 1,
        "$label %post refers to an active xcat.conf exactly once" );
    like( $post_refs[0] || '',
        qr{^\s*if \[ -e /etc/apache2/conf\.d/xcat\.conf \] && command -v a2enmod\b},
        "$label %post only tests for the file, to enable mod_headers" );

    # rpm decides each config file's fate before %pre, so the migration has to
    # run in %pretrans or it can delete a file rpm already resolved to .rpmnew.
    like( $spec, qr{^%pretrans -p <lua>$}m,
        "$label package migrates in %pretrans, as an embedded Lua scriptlet" );
    my $pre = section( $spec, 'pre' );
    unlike( $pre, qr{conf\.d/xcat\.conf},
        "$label %pre does not touch an active xcat.conf" );

    my $pretrans = section( $spec, 'pretrans' );
    like( $pretrans, qr{^if arg\[2\] and tonumber\(arg\[2\]\) == 1 then return end$}m,
        "$label migration returns early on a fresh install" );
    like(
        $pretrans,
        qr{
            ^local \s+ templates \s* = \s* \{ \s*
                contents\("$templates/xcat\.conf\.apach24"\), \s* $ \n
            ^\s* contents\("$templates/xcat\.conf\.apach22"\) \s* \} \s* $
        }mx,
        "$label migration reads both of the outgoing package's saved templates"
    );
    like(
        $pretrans,
        qr{
            ^for \s+ _, \s* active \s+ in \s+ ipairs\(\{ \s* "/etc/httpd/conf\.d/xcat\.conf", \s* $ \n
            ^\s* "/etc/apache2/conf\.d/xcat\.conf" \s* \}\) \s+ do \s* $ \n
            (?: ^\s* --[^\n]* \n )*                    # explanatory comment
            ^\s* if \s+ posix\.stat\(active, \s* "type"\) \s* == \s* "regular" \s+ then \s* $ \n
            ^\s* local \s+ current \s* = \s* contents\(active\) \s* $ \n
            ^\s* for \s+ _, \s* template \s+ in \s+ ipairs\(templates\) \s+ do \s* $ \n
            ^\s* if \s+ current \s+ and \s+ current \s* == \s* template \s+ then \s* $ \n
            ^\s* os\.remove\(active\) \s* $
        }mx,
        "$label migration removes an active xcat.conf only when it is a regular file whose contents still match a saved template"
    );

    # Nothing else may delete the active file, in any scriptlet.
    unlike( $spec, qr{\brm\b[^\n]*conf\.d/xcat\.conf},
        "$label package never shells out to rm for an active xcat.conf" );
    my @removals = ( $pretrans =~ m{^\s*(os\.remove\([^\n]*)$}mg );
    is_deeply( \@removals, ['os.remove(active)'],
        "$label migration removes exactly one validated path and nothing else" );
    unlike( $spec, qr{^Requires\(pre\):\s+/usr/bin/cmp$}m,
        "$label package needs no external tool for the comparison" );
}

done_testing();
