#!/usr/bin/env perl
# xCAT and xCATsn pull the upstream iPXE loaders from ipxe-xcat beside xnba-undi, which netboot=xnba
# nodes still boot with. A server of any architecture can serve x86 nodes, so every rpm and deb needs
# ipxe-xcat: xCATsn on POWER and the riscv64 rpms require it without xnba-undi, and the debs
# recommend xnba-undi.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

sub command_exists { my ($c) = @_; return system("command -v $c >/dev/null 2>&1") == 0 }

# The loader requirements of a spec for one target, as rpm resolves them.
sub rpm_loader_requires {
    my ( $spec, $arch ) = @_;
    my @requires = `rpmspec --target $arch-linux -q --requires --define 'version 2.19.0' --define 'release snap0' @{[quotemeta repo_path($spec)]} 2>/dev/null`;
    die "rpmspec failed for $spec on $arch\n" if $? != 0 || !@requires;
    chomp(@requires);
    return [ sort grep { /^(?:ipxe-xcat|xnba-undi)\b/ } @requires ];
}

SKIP: {
    skip 'rpmspec is not installed', 10 unless command_exists('rpmspec');

    my @cases = (
        [ 'xCAT/xCAT.spec',     'x86_64',  [ 'ipxe-xcat >= 2.0.0-1', 'xnba-undi >= 1.21.1-1' ] ],
        [ 'xCAT/xCAT.spec',     'i686',    [ 'ipxe-xcat >= 2.0.0-1', 'xnba-undi >= 1.21.1-1' ] ],
        [ 'xCAT/xCAT.spec',     'ppc64le', [ 'ipxe-xcat >= 2.0.0-1', 'xnba-undi >= 1.21.1-1' ] ],
        [ 'xCAT/xCAT.spec',     'ppc64',   [ 'ipxe-xcat >= 2.0.0-1', 'xnba-undi >= 1.21.1-1' ] ],
        [ 'xCAT/xCAT.spec',     'riscv64', ['ipxe-xcat >= 2.0.0-1'] ],
        [ 'xCATsn/xCATsn.spec', 'x86_64',  [ 'ipxe-xcat', 'xnba-undi' ] ],
        [ 'xCATsn/xCATsn.spec', 'i686',    [ 'ipxe-xcat', 'xnba-undi' ] ],
        [ 'xCATsn/xCATsn.spec', 'ppc64le', ['ipxe-xcat'] ],
        [ 'xCATsn/xCATsn.spec', 'ppc64',   ['ipxe-xcat'] ],
        [ 'xCATsn/xCATsn.spec', 'riscv64', ['ipxe-xcat'] ],
    );
    for my $case (@cases) {
        my ( $spec, $arch, $want ) = @$case;
        is_deeply( rpm_loader_requires( $spec, $arch ), $want,
            "$spec on $arch: requires " . join( ' and ', map { (split)[0] } @$want ) );
    }
}

SKIP: {
    skip 'Dpkg::Control::Info and Dpkg::Deps are not available', 12
      unless eval { require Dpkg::Control::Info; require Dpkg::Deps; 1 };

    # The package names a dependency field gives a host architecture, alternatives included.
    my $names;
    $names = sub {
        my ($dep) = @_;
        return $dep->{package} if $dep->isa('Dpkg::Deps::Simple');
        return map { $names->($_) } $dep->get_deps();
    };

    for my $pkg ( [ 'xCAT/debian/control', 'xcat' ], [ 'xCATsn/debian/control', 'xcatsn' ] ) {
        my ( $control, $name ) = @$pkg;
        my $fields = Dpkg::Control::Info->new( repo_path($control) )->get_pkg_by_name($name);
        for my $arch (qw(amd64 ppc64el riscv64)) {
            my %field;
            for my $key (qw(Depends Recommends)) {
                # dpkg-gencontrol expands the substvars before any parser sees the field.
                ( my $value = $fields->{$key} // '' ) =~ s/\$\{[^}]*\}\s*,?\s*//g;
                my $deps = Dpkg::Deps::deps_parse( $value, reduce_arch => 1, host_arch => $arch )
                  or die "unable to parse $key of $name for $arch\n";
                $field{$key} = { map { $_ => 1 } $names->($deps) };
            }
            ok( $field{Depends}{'ipxe-xcat'}, "$name on $arch depends on ipxe-xcat" );
            ok( $field{Recommends}{'xnba-undi'}, "$name on $arch recommends xnba-undi" );
        }
    }
}

done_testing();
