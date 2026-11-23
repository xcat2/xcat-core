package XCAT::Test::Chroot;

use strict;
use warnings;
use Carp qw(croak);
use Exporter qw(import);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use xCAT::FreeBSDPkg;

our @EXPORT_OK = qw(stage_binary);

sub stage_binary {
    my ($root, $program) = @_;
    make_path(dirname("$root$program"));
    copy($program, "$root$program") or croak $!;
    chmod(oct('0555'), "$root$program") == 1 or croak $!;
    my $loader = xCAT::FreeBSDPkg::run_command(['/usr/bin/ldd', $program], cwd => $root,
        environment => {PATH => '/usr/bin:/bin', LC_ALL => 'C'}, timeout => 10);
    croak 'Cannot inspect fixture dependencies' if $loader->{exitcode} || $loader->{signal};
    for my $library ($loader->{stdout} =~ m{(/[^\s()]+)}gx) {
        next unless -f $library;
        next if -f "$root$library";
        make_path(dirname("$root$library"));
        copy($library, "$root$library") or croak $!;
        chmod((stat($library))[2] & oct('0777'), "$root$library") == 1 or croak $!;
    }
    return;
}

1;
