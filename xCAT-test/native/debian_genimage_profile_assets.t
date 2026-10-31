use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::ImageSandbox;
use XCAT::Test::Process qw(run_command);

plan skip_all => 'Linux namespaces are required' unless $^O eq 'linux';
die 'Run image tests as an unprivileged user' unless $>;

my $payload = shift @ARGV;
my $source = $payload // repo_path('xCAT-server/share/xcat/netboot/debian');

sub standalone_image {
    my $box = XCAT::Test::ImageSandbox->new();
    make_path("$box->{root}/work/share/xcat/netboot");
    my @copy = ('-R', '--no-preserve=mode,ownership');
    push @copy, '-L' unless defined $payload;
    my ($rc, $output) = run_command('cp', @copy, $source, "$box->{root}/work/share/xcat/netboot/");
    die "copy Debian scripts: $output" if $rc;
    return $box;
}

for my $extension (qw(pkglist otherpkgs.pkglist postinstall)) {
    for my $custom (0, 1) {
        subtest "$extension " . ($custom ? 'custom' : 'shipped') => sub {
            my $box = standalone_image();
            my $shipped = 'work/share/xcat/netboot/debian';
            my $customdir = 'install/custom/netboot/debian';
            $box->write('install/debian12.5/x86_64/Packages.gz', 'index');
            make_path("$box->{root}/install/debian12.5/x86_64/dists/bookworm");
            $box->write('work/image/rootimg/lib/modules/fixture/modules.dep', '');

            my $file = "profile.debian12.5.x86_64.$extension";
            my $selected = $custom ? "/$customdir/profile.$extension"
                                  : "share/xcat/netboot/debian/$file";
            my $content = $extension eq 'postinstall'
              ? "#!/bin/sh\nprintf '%s\\n' \"\$0\" \"\$@\" > /work/selected\nexit 23\n"
              : "selected-package\n";
            my $target = $box->write("$shipped/$file", $custom ? "wrong-package\n" : $content);
            chmod(0755, $target) or die "chmod: $!";
            if ($custom) {
                $target = $box->write("$customdir/profile.$extension", $content);
                chmod(0755, $target) or die "chmod: $!";
            }

            $box->command('debootstrap', $extension eq 'pkglist' ? <<'SH' : 'exit 0');
printf '%s\n' "$@" > /work/selected
exit 23
SH
            $box->command('yum', <<'SH');
printf '%s\n' "$@" > /work/selected
exit 23
SH
            $box->write("$shipped/profile.pkglist", '') if $extension eq 'otherpkgs.pkglist';

            my @args = ('-o', 'debian12.5', '-a', 'x86_64', '-p', 'profile',
                '-i', 'eth0', '-n', 'fixture', '-k', 'fixture',
                '--rootimgdir', '/work/image', '--noupdate');
            push @args, '--onlyinitrd' if $extension eq 'postinstall';
            my ($rc, $output, $error) = $box->run('env', 'PERL5LIB=', 'XCATROOT=/nonexistent',
                'perl', 'share/xcat/netboot/debian/genimage', @args);
            is($rc, 1, 'caller stops at the selected external command failure') or diag($output, $error);
            my $observed = -f "$box->{root}/work/selected" ? $box->read('work/selected') : '';
            if ($extension eq 'postinstall') {
                is($observed, "$selected\n/work/image/rootimg\ndebian12.5\nx86_64\nprofile\n",
                    'postinstall gets the unchanged path spelling and arguments');
                like($output, qr/postinstall script \Q$selected\E failed/, 'caller reports the selected postinstall path');
            } elsif ($extension eq 'pkglist') {
                like($observed, qr/^--include=selected-package$/m, 'debootstrap receives the selected package');
                unlike($observed, qr/wrong-package/, 'custom directory takes precedence over a shipped exact match');
                like($output, qr/apt invocation failed/, 'caller reaches the bootstrap failure');
            } else {
                like($observed, qr/^selected-package$/m, 'extra-package installation consumes the selected list');
                unlike($observed, qr/wrong-package/, 'custom directory takes precedence over a shipped exact match');
                like($output, qr/yum invocation failed/, 'caller reaches the extra-package failure');
            }
        };
    }
}

subtest 'missing package list' => sub {
    my $box = standalone_image();
    $box->write('install/debian12.5/x86_64/Packages.gz', 'index');
    make_path("$box->{root}/install/debian12.5/x86_64/dists/bookworm");
    my ($rc, $output, $error) = $box->run('env', 'PERL5LIB=', 'XCATROOT=/nonexistent',
        'perl', 'share/xcat/netboot/debian/genimage',
        '-o', 'debian12.5', '-a', 'x86_64', '-p', 'missing', '-n', 'fixture', '-i', 'eth0',
        '--rootimgdir', '/work/image');
    is($rc, 1, 'missing package list stops image creation') or diag($output, $error);
    like($output, qr/Unable to find package list for missing!/, 'original missing-list diagnostic remains');
};

subtest 'standalone explicit image definition' => sub {
    my $box = standalone_image();
    my $postinstall = $box->write('work/postinstall', "#!/bin/sh\necho explicit > /work/selected\nexit 23\n");
    chmod(0755, $postinstall) or die "chmod: $!";
    $box->write('work/image/rootimg/lib/modules/fixture/modules.dep', '');
    my ($rc, $output, $error) = $box->run('env', 'PERL5LIB=', 'XCATROOT=/nonexistent',
        'perl', 'share/xcat/netboot/debian/genimage', '--onlyinitrd',
        '-o', 'debian12.5', '-a', 'x86_64', '-p', 'profile', '-n', 'fixture', '-i', 'eth0',
        '-k', 'fixture', '--postinstall', '/work/postinstall', '--rootimgdir', '/work/image', 'explicit-image');
    is($rc, 1, 'standalone command reaches the explicit postinstall failure') or diag($output, $error);
    is(-f "$box->{root}/work/selected" ? $box->read('work/selected') : '', "explicit\n",
        'an explicit image definition runs without installed xCAT modules');
    like($output, qr/postinstall script \/work\/postinstall failed/, 'failure comes from the explicit postinstall');
};

done_testing();
