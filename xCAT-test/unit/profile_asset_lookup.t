use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT",
  "$FindBin::Bin/../../xCAT-server/lib/perl",
  "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Cwd qw(getcwd realpath);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use imgutils;

my $root = tempdir(CLEANUP => 1);
my $original_dir = getcwd();
chdir($root) or die "chdir $root: $!";
make_path('assets');
symlink('assets', 'alias') or die "symlink: $!";

sub lookup {
    my ($owner, $version, $arch, $base, $extension) = @_;
    return imgutils::get_profile_def_filename($version, 'compute', $arch, $base, $extension)
      if $owner eq 'imgutils';
    local $ENV{PERL5LIB} = '';
    local $ENV{XCATROOT} = '/nonexistent';
    my ($rc, $output) = run_command($^X,
        repo_path('xCAT-test/unit/fixtures/debian_profile_lookup.pl'),
        repo_path('xCAT-server/share/xcat/netboot/debian/genimage'),
        $version, 'compute', $arch, $base, $extension);
    die "Debian lookup failed ($rc): $output" if $rc;
    return decode_json($output)->[0];
}

for my $owner (qw(debian imgutils)) {
    for my $arch (qw(x86_64 ppc64le s390x)) {
        for my $extension (qw(pkglist otherpkgs.pkglist postinstall)) {
            subtest "$owner $arch $extension priority" => sub {
                my @names = (
                    "compute.debian12.5.$arch.$extension",
                    "compute.debian12.$arch.$extension",
                    "compute.$arch.$extension",
                    "compute.debian12.5.$extension",
                    "compute.debian12.$extension",
                    "compute.$extension",
                );
                write_text("assets/$_", "fixture\n") for @names;
                for my $name (@names) {
                    for my $base ('assets', './alias', realpath('assets')) {
                        my $expected_base = $owner eq 'debian' ? $base : realpath($base);
                        is(lookup($owner, 'debian12.5', $arch, $base, $extension),
                            "$expected_base/$name", "selects $name through $base");
                    }
                    unlink("assets/$name") or die "unlink $name: $!";
                }
                is(lookup($owner, 'debian12.5', $arch, 'assets', $extension), '', 'miss returns an empty string');
                is(lookup($owner, 'debian12.5', $arch, 'missing', $extension), '', 'missing directory returns an empty string');
                SKIP: {
                    skip 'root can read mode-0000 files', 1 unless $>;
                    write_text("assets/$names[0]", 'unreadable');
                    chmod(0000, "assets/$names[0]") or die "chmod: $!";
                    write_text("assets/$names[-1]", 'readable');
                    is(lookup($owner, 'debian12.5', $arch, 'assets', $extension),
                        ($owner eq 'debian' ? 'assets' : realpath('assets')) . "/$names[-1]",
                        'an unreadable exact match does not hide the generic asset');
                    unlink(map { "assets/$_" } @names[0, -1]) == 2 or die "unlink: $!";
                }
            };
        }
    }
}

for my $case (
    ['debian', 'debian12.5', 'compute.debian12.x86_64.pkglist', 'compute.debian12.4.x86_64.pkglist'],
    ['debian', 'debian12.5.1', 'compute.debian12.5.x86_64.pkglist', 'compute.debian12.x86_64.pkglist'],
    ['imgutils', 'rocky9.6', 'compute.rocky9.5.x86_64.pkglist', 'compute.rocky9.x86_64.pkglist'],
    ['imgutils', 'ubuntu24.04', 'compute.pkglist', 'compute.ubuntu24.x86_64.pkglist'],
    ['imgutils', 'sles11sp1', 'compute.sles11.x86_64.pkglist', 'compute.pkglist'],
    ['imgutils', 'leap15.6', 'compute.sle15.x86_64.pkglist', 'compute.x86_64.pkglist'],
    ['imgutils', 'leap15.6', 'compute.sle15.pkglist', 'compute.pkglist'],
    ['debian', 'debian12', 'compute.debian12.x86_64.pkglist', 'compute.pkglist'],
) {
    my ($owner, $version, $wanted, $other) = @$case;
    write_text("assets/$_", "fixture\n") for ($wanted, $other);
    is(lookup($owner, $version, 'x86_64', 'assets', 'pkglist'),
        ($owner eq 'debian' ? 'assets' : realpath('assets')) . "/$wanted",
        "$owner retains its $version fallback policy");
    unlink("assets/$wanted", "assets/$other") == 2 or die "unlink: $!";
}

chdir($original_dir) or die "chdir $original_dir: $!";
done_testing();
