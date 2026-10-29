#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Cwd            qw(abs_path);
use File::Basename qw(basename dirname);
use File::Find     qw(find);
use File::Path     qw(make_path);
use File::Slurper  qw(read_text write_text);
use File::Spec;
use Test::More;
use XCAT::Test::File    qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'postinstall execution requires Linux' unless $^O eq 'linux';
my $netboot = repo_path('xCAT-server/share/xcat/netboot');
my @owners  = qw(
    rh/compute.rhels7.ppc64.postinstall
    rh/compute.rhels7.x86_64.postinstall
    rh/compute.rhels8.ppc64le.postinstall
    rh/compute.rhels8.x86_64.postinstall
    rh/compute.rhels9.ppc64le.postinstall
    rh/compute.rhels9.x86_64.postinstall
    rh/compute.rhels10.aarch64.postinstall
    rh/compute.rhels10.ppc64le.postinstall
    rh/compute.rhels10.x86_64.postinstall
    rh/service.postinstall
    rocky/compute.rocky10.riscv64.postinstall
);
my %owners;

for my $owner (@owners) {
    ok( -x "$netboot/$owner", "$owner is executable" );
    $owners{ abs_path("$netboot/$owner") } = 1;
}
my @aliases;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            return unless -l $_ && /[.]postinstall$/;
            my $target = abs_path($_);
            push @aliases, substr( $_, length($netboot) + 1 ) if defined $target && $owners{$target};
        }
    },
    $netboot
);
ok( @aliases, 'finds profile aliases for the affected owners' );
my %firewalld = map { abs_path("$netboot/$_") => 1 } qw(
    rh/compute.rhels8.ppc64le.postinstall
    rh/compute.rhels8.x86_64.postinstall
    rh/compute.rhels9.ppc64le.postinstall
    rh/compute.rhels9.x86_64.postinstall
    rh/compute.rhels10.aarch64.postinstall
    rh/compute.rhels10.ppc64le.postinstall
    rh/compute.rhels10.x86_64.postinstall
    rocky/compute.rocky10.riscv64.postinstall
);
my @shells = qw(/bin/bash /bin/dash);

sub shell_options {
    my ($shell) = @_;
    return { read_only => { repo_path('.') => repo_path('.'), $shell => '/bin/' . basename( abs_path('/bin/sh') ) } };
}

for my $shell (@shells) {
    BAIL_OUT("Install $shell to run this test") unless -x $shell;
    my $root = sandbox_root();
    write_text( "$root/bin/shell-probe", "#!/bin/sh\nprintf '%s\\n' \"\${BASH_VERSION:+bash}\"\n" );
    chmod 0755, "$root/bin/shell-probe" or die "chmod shell probe: $!";
    my ( $status, $output ) = sandbox_run( $root, shell_options($shell), '/fixture/bin/shell-probe' );
    my $expected = $shell eq '/bin/bash' ? "bash\n" : "\n";
    is( $status, 0,         "$shell probe executes through its shebang" ) or diag($output);
    is( $output, $expected, "/bin/sh runs the selected $shell" );
    BAIL_OUT("The sandbox did not select $shell") if $status || $output ne $expected;
}

sub run_profile {
    my ( $root, $relative, $shell ) = @_;
    my ( $profile, $osver, $arch ) = split /[.]/, basename($relative);
    return sandbox_run( $root, shell_options($shell), "$netboot/$relative", '/target', $osver, $arch // '', $profile );
}

my $unchanged =
    "# SELINUX=enforcing or permissive\nSELINUXTYPE=targeted\n" . "OTHER_SELINUX=permissive\n#SELINUX=permissive\n";
my @cases = (
    [ 'enforcing',               "SELINUX=enforcing\n",                     "SELINUX=disabled\n" ],
    [ 'permissive',              "SELINUX=permissive\n",                    "SELINUX=disabled\n" ],
    [ 'disabled',                "SELINUX=disabled\n",                      "SELINUX=disabled\n" ],
    [ 'absent',                  undef,                                     undef ],
    [ 'no assignment',           '',                                        '' ],
    [ 'whitespace and comments', "\tSELINUX=permissive \t# image policy\n", "\tSELINUX=disabled \t# image policy\n" ],
    [ 'enforcing comment',       "SELINUX=enforcing # image policy\n",      "SELINUX=disabled # image policy\n" ],
);

for my $shell (@shells) {
    for my $relative ( @owners, sort @aliases ) {
        my @selected = -l "$netboot/$relative" ? ( $cases[1] ) : @cases;
        for my $case (@selected) {
            my ( $label, $input, $expected ) = @$case;
            subtest "$relative: $shell SELinux $label" => sub {
                my $root  = sandbox_root();
                my $image = "$root/target";
                make_path( "$image/etc/selinux", "$root/etc/selinux" );
                my $host_policy = "SELINUX=enforcing\n# host policy\n";
                write_text( "$root/etc/selinux/config", $host_policy );
                write_text( "$root/etc/fstab",          "host fstab\n" );
                write_text( "$root/etc/inittab",        "host inittab\n" );
                my $config = "$image/etc/selinux/config";

                if ( defined $input ) {
                    write_text( $config, $input . $unchanged );
                    chmod 0640, $config or die "chmod $config: $!";
                }
                my @metadata = defined $input ? ( stat($config) )[ 2, 4, 5 ] : ();
                for my $pass ( 1, 2 ) {
                    my ( $status, $output ) = run_profile( $root, $relative, $shell );
                    is( $status,                               0,  "pass $pass executes the profile" ) or diag($output);
                    is( $output,                               '', "pass $pass has no shell errors" );
                    is( read_text("$root/etc/selinux/config"), $host_policy,     'host policy is unchanged' );
                    is( read_text("$root/etc/fstab"),          "host fstab\n",   'host fstab is unchanged' );
                    is( read_text("$root/etc/inittab"),        "host inittab\n", 'host inittab is unchanged' );
                    if ( defined $input ) {
                        is(
                            read_text($config),
                            $expected . $unchanged,
                            "pass $pass changes only the active SELinux mode"
                        );
                        is_deeply( [ ( stat($config) )[ 2, 4, 5 ] ],
                            \@metadata, 'policy permissions and ownership are preserved' );
                    }
                    else {
                        ok( !-e $config, 'absent policy remains absent' );
                    }
                }
            };
        }

        my @kinds = -l "$netboot/$relative" ? ('dangling') : qw(regular symlink dangling absent directory);
        for my $kind (@kinds) {
            subtest "$relative: $shell firewalld $kind" => sub {
                my $root  = sandbox_root();
                my $image = "$root/target";
                my $unit  = "$image/usr/lib/systemd/system/firewalld.service";
                make_path( dirname($unit) );
                write_text( $unit, "[Service]\nExecStart=/usr/bin/true\n" );
                my @links = qw(etc/systemd/system/multi-user.target.wants/firewalld.service
                    etc/systemd/system/dbus-org.fedoraproject.FirewallD1.service);
                my %targets;

                for my $relative_link (@links) {
                    my $link = "$image/$relative_link";
                    make_path( dirname($link), dirname("$root/$relative_link") );
                    write_text( "$root/$relative_link", "host firewalld\n" );
                    $targets{$link} =
                        File::Spec->abs2rel( $unit . ( $kind eq 'dangling' ? '.missing' : '' ), dirname($link) );
                    if ( $kind eq 'regular' ) {
                        write_text( $link, "image firewalld\n" );
                    }
                    elsif ( $kind eq 'symlink' || $kind eq 'dangling' ) {
                        symlink( $targets{$link}, $link ) or die "symlink $link: $!";
                    }
                    elsif ( $kind eq 'directory' ) {
                        make_path($link);
                        write_text( "$link/keep", "directory contents\n" );
                    }
                    symlink( $targets{$link}, "$link.unrelated" ) or die "symlink: $!";
                }
                for my $pass ( 1, 2 ) {
                    my ( $status, $output ) = run_profile( $root, $relative, $shell );
                    is( $status, 0,  "pass $pass executes the profile" ) or diag($output);
                    is( $output, '', 'both shell conditions execute without errors' );
                    for my $relative_link (@links) {
                        my $link = "$image/$relative_link";
                        if ( ( $firewalld{ abs_path("$netboot/$relative") } && $kind ne 'directory' )
                            || $kind eq 'absent' )
                        {
                            ok( !-e $link && !-l $link, 'firewalld entry is absent' );
                        }
                        elsif ( $kind eq 'regular' ) {
                            is( read_text($link), "image firewalld\n", 'older profile retains the entry' );
                        }
                        elsif ( $kind eq 'directory' ) {
                            is( read_text("$link/keep"), "directory contents\n", 'directory contents are retained' );
                        }
                        else {
                            is( readlink($link), $targets{$link}, 'older profile retains the link' );
                        }
                        is( readlink("$link.unrelated"),       $targets{$link},    'unrelated link is unchanged' );
                        is( read_text("$root/$relative_link"), "host firewalld\n", 'host entry is unchanged' );
                    }
                    is( read_text($unit), "[Service]\nExecStart=/usr/bin/true\n", 'unit target is unchanged' );
                }
            };
        }
    }
}

done_testing();
