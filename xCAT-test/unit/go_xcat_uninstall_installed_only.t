#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# `go-xcat uninstall` hands GO_XCAT_UNINSTALL_LIST to the package manager. That list names
# packages xCAT stopped producing -- xCAT-genesis-builder, yaboot-xcat, conserver-xcat -- so
# most of it is not installed on any one node. apt answers "Unable to locate package" for a
# name it does not know, and go-xcat prints a warning for each; dnf answers "No match for
# argument" and fails the whole call when nothing in the list matches.
#
# So what is not installed does not reach the package manager. That is also what makes keeping
# a retired name in the list free, which is why the list outlives the build.
#
# uninstall_xcat is taken from the shipped script and run with the package database faked and
# remove_package shadowed, so the assertions read the argument list the package manager would
# have been given.

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
plan skip_all => 'go-xcat not found' unless -r $go_xcat;
plan tests => 4;

{
    my @handed = uninstall_args($go_xcat, ['xCAT-server', 'xCAT-client']);
    is_deeply([sort @handed], ['xCAT-client', 'xCAT-server'],
        'only the installed packages reach the package manager');
}

{
    # The point of keeping a retired name: where it IS installed, it is still removed.
    my @handed = uninstall_args($go_xcat, ['xCAT-genesis-builder']);
    is_deeply(\@handed, ['xCAT-genesis-builder'],
        'a retired package that is installed is still removed');
}

{
    my @handed = uninstall_args($go_xcat, []);
    is_deeply(\@handed, [],
        'a node with none of them installed hands the package manager nothing');
}

{
    # Guards the fake: a database that says everything is installed must hand over the list,
    # or the three assertions above would pass against a filter that drops everything.
    my @handed = uninstall_args($go_xcat, ['*']);
    ok(scalar(@handed) > 10, 'with everything installed the whole list is handed over');
}

# Extract `function NAME()` blocks by name, in the order asked for.
sub extract {
    my ($text, @names) = @_;
    my @blocks;
    for my $name (@names) {
        my ($block) = $text =~ /^(function \Q$name\E\(\)\s*\n\{.*?^\})/ms;
        push @blocks, $block if $block;
    }
    return @blocks;
}

# Run the shipped uninstall path with rpm and dpkg-query answering from a fake database and the
# package manager shadowed, and collect what it was asked to remove.
sub uninstall_args {
    my ($path, $installed) = @_;
    my $text = do { open my $fh, '<', $path or die "$path: $!"; local $/; <$fh> };

    my ($lists) = $text =~ /^(GO_XCAT_INSTALL_LIST=\(.*?\n)\n/ms;
    BAIL_OUT("no package lists in $path") unless $lists;
    my @functions = extract($text, qw(function_dispatch installed_packages
                                      installed_packages_rpm installed_packages_deb
                                      uninstall_xcat));
    BAIL_OUT("no uninstall_xcat() in $path")
        unless grep { /^function uninstall_xcat\(\)/ } @functions;

    my $dir = tempdir(CLEANUP => 1);
    my $driver = "$dir/driver.sh";
    my $present = join ' ', @{$installed};
    open my $fh, '>', $driver or die "$driver: $!";
    print {$fh} "set -u\n";
    # An rpm host: dpkg is absent, so the lists take the rpm branch and the deb arm of the
    # dispatch stands down. Shadowing `type` to fail for everything would stand both arms
    # down and the filter would answer nothing, whatever it does.
    print {$fh} "type() { case \"\$1\" in dpkg|dpkg-query|apt-get) return 1 ;; *) return 0 ;; esac; }\n";
    print {$fh} $lists, "\n";
    print {$fh} <<"BASH";
INSTALLED="$present"
present() {
    case "\$INSTALLED" in *"*"*) return 0 ;; esac
    case " \$INSTALLED " in *" \$1 "*) return 0 ;; *) return 1 ;; esac
}
rpm() { for a in "\$\@"; do case "\$a" in -*) continue ;; esac; present "\$a" || return 1; done; return 0; }
dpkg-query() {
    for a in "\$\@"; do
        case "\$a" in -*) continue ;; esac
        present "\$a" && echo "install ok installed"
    done
    return 0
}
exit_if_bad() { :; }
warn_if_bad() { :; }
remove_package() { for a in "\$\@"; do case "\$a" in -y) continue ;; esac; echo "\$a"; done; }
BASH
    print {$fh} join("\n", @functions), "\n";
    print {$fh} "uninstall_xcat -y\n";
    close $fh;

    my @out = qx{bash '$driver' 2>/dev/null};
    chomp @out;
    return grep { length } @out;
}
