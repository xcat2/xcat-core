#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use Test::More;
use XCAT::Test::ImageSandbox;

plan skip_all => 'Linux namespaces require Linux' unless $^O eq 'linux';
die('Run the image caller tests as an unprivileged user') unless $>;

my $image = 'work/image/rootimg';
for my $case (['rh', 'rhels9.6'], ['rocky', 'rocky9.6'], ['rh', 'rhels6.10']) {
    my ($builder, $os) = @$case;
    my @expected = ("--bind /run /$image/run");
    unshift @expected, "proc /$image/proc -t proc", "sysfs /$image/sys -t sysfs" unless $os eq 'rhels6.10';
    for my $build (qw(first repeated blocked)) {
        subtest "$builder $os $build build" => sub {
            my $box = XCAT::Test::ImageSandbox->new();
            make_path("$box->{root}/install/$os/x86_64/repodata");
            make_path(map { "$box->{root}/$image/$_" } qw(proc sys dev run)) if $build eq 'repeated';
            chmod(oct('0700'), "$box->{root}/$image/run") or die $! if $build eq 'repeated';
            $box->write("$image/run", "blocked mount point\n") if $build eq 'blocked';
            $box->write('work/compute.pkglist', "bash\n");

            # Like mount(8), the fixture refuses a mount point that does not exist.
            $box->command('mount', <<'SH');
mount=$*
operands=0
while [ "$#" -gt 0 ]; do
    case $1 in
        -t|-o) shift ;;
        -*) ;;
        *) operands=$((operands + 1)); [ "$operands" -eq 2 ] && target=$1 ;;
    esac
    shift
done
if [ ! -d "$target" ]; then
    printf 'mount: %s: mount point does not exist.\n' "$target" >&2
    exit 32
fi
printf '%s\n' "$mount" >>/work/mounts
SH
            $box->command($_, ": >>/work/mounts\ncat /work/mounts >/work/install-mounts\nexit 1\n") for qw(dnf yum);

            my ($rc, $output, $error) = $box->run('perl', "/repo/xCAT-server/share/xcat/netboot/$builder/genimage",
                '-a', 'x86_64', '-o', $os, '-p', 'compute', '--pkglist', '/work/compute.pkglist',
                '--srcdir', "/install/$os/x86_64", '--rootimgdir', '/work/image', 'fixture-image');
            ok(-f "$box->{root}/work/install-mounts", 'the build reaches the package installation')
              or diag($output, $error);
            my $mounts = -f "$box->{root}/work/install-mounts" ? $box->read('work/install-mounts') : '';
            if ($build eq 'blocked') {
                like($error, qr/File exists/, 'reports the directory creation failure');
                like($error, qr/mount point does not exist/, 'still attempts the bind mount');
                is($box->read("$image/run"), "blocked mount point\n", 'retains the blocking file');
                is_deeply([split /\n/, $mounts], [grep { !/--bind/ } @expected],
                    'the package installation still runs after the failed mount');
            } else {
                unlike($error, qr/mount point does not exist/, 'every mount point exists before its mount');
                is_deeply([split /\n/, $mounts], \@expected, 'packages install with the host /run in the image');
                is((stat("$box->{root}/$image/run"))[2] & oct('0777'),
                    $build eq 'repeated' ? oct('0700') : (oct('0777') & ~umask), 'retains the expected directory mode');
            }
        };
    }
}
done_testing();
