#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Storable qw(retrieve);
use Test::More;

plan skip_all => 'requires native Linux DNF and trusted RPM keys'
  unless $^O eq 'linux' && -x '/usr/bin/dnf' && -x '/usr/bin/rpm';
my $repo = File::Spec->rel2abs("$FindBin::Bin/../..");
my $dir = tempdir(CLEANUP => 1);
my $driver = "$dir/driver.pl";
write_file($driver, <<'PERL');
use strict;
use warnings;
use Storable qw(nstore);
use Text::ParseWords qw(shellwords);
our (@commands, $reached, $config, $restored);
BEGIN {
    *CORE::GLOBAL::readpipe = sub {
        return "x86_64\n" if $_[0] eq 'uname -m';
        return "ext4\n" if $_[0] =~ /^df -T -P /;
        die "Unexpected command: $_[0]";
    };
    *CORE::GLOBAL::system = sub {
        my $command = join(' ', @_);
        push @commands, $command;
        if ($command =~ /^\s*(?:dnf|yum) /) {
            my @args = shellwords($command);
            my ($index) = grep { $args[$_] eq '-c' } 0 .. $#args - 1;
            die 'Package command omitted its configuration' unless defined($index);
            open(my $file, '<', $args[$index + 1]) or die $!;
            $config = do { local $/; <$file> };
            close($file);
            my $phase = $command =~ / erase .*pre-remove/ ? 'pre-remove'
              : $command =~ / erase .*post-remove/ ? 'post-remove'
              : $command =~ / install .*native-extra/ ? 'extra-install'
              : $command =~ / install / ? 'os-install'
              : $command =~ / update / ? 'update' : 'clean';
            return 29 << 8 if $phase eq $ENV{GENIMAGE_FAILURE};
            return 0;
        }
        if ($command eq "rm -fr $ENV{GENIMAGE_ROOT}/bin/uname") {
            $restored = 1;
            return CORE::system(@_);
        }
        if ($restored && $command eq "mknod $ENV{GENIMAGE_ROOT}/dev/null c 1 3") {
            $reached = 1;
            exit 23;
        }
        return 0;
    };
}
END {
    my $uname = '';
    if (open(my $file, '<', "$ENV{GENIMAGE_ROOT}/bin/uname")) {
        $uname = do { local $/; <$file> };
        close($file);
    }
    nstore({ commands => \@commands, reached => $reached, config => $config, uname => $uname },
        "$ENV{GENIMAGE_CASE}/result");
    unlink("/tmp/genimage.$$.yum.conf");
}
require xCAT::Utils;
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub { return (0, undef); };
}
$0 = $ENV{GENIMAGE_SCRIPT};
do $0;
die $@ if $@;
die "Image builder returned before the package boundary";
PERL

for my $os (qw(openeuler20.03sp4 openeuler24.03sp3 rhels9.6)) {
    for my $failure (qw(os-install pre-remove extra-install post-remove update none)) {
        my ($rc, $state, $output) = run_case($os, $failure, 'https://packages.example/native');
        my $fatal = $failure ne 'none' && ($os =~ /^openeuler/ || $failure =~ /install$/);
        my $label = "$os $failure";
        if ($fatal) {
            isnt($rc, 23, "$label stops before postscripts");
            ok(!$state->{reached}, "$label does not continue into image finalization");
            like($output, qr/RPM package manager invocation failed/, "$label reports the failed transaction");
            ok(grep({ /^findmnt .*\/dev\// } @{$state->{commands}}),
                "$label invokes the image mount cleanup owner");
        } else {
            is($rc, 23, "$label reaches the controlled end of the package phase") or diag($output);
            ok($state->{reached}, "$label proceeds to postscripts");
        }
        is($state->{uname}, "original uname\n", "$label restores the image uname");
        if ($os =~ /^openeuler/ && $failure ne 'os-install') {
            like($state->{config}, qr{baseurl=https://packages\.example/native\n},
                "$label retains the explicit package URL");
            unlike($state->{config}, qr{baseurl=file://}, "$label does not create an unavailable local repository");
        }
    }
}
my ($rc, $state) = run_case('openeuler24.03sp3', 'none', '/var/tmp/native-packages');
is($rc, 23, 'a native local package directory reaches postscripts');
like($state->{config}, qr{baseurl=file:///var/tmp/native-packages/vendor\n},
    'native local package repositories retain their package-list subdirectory');

done_testing();

sub run_case {
    my ($os, $failure, $otherdir) = @_;
    my $case = tempdir(DIR => $dir, CLEANUP => 1);
    my $root = "$case/image/rootimg";
    make_path("$root/bin", "$root/etc", "$root/dev", "$root/run", "$root/sbin");
    write_file("$root/bin/uname", "original uname\n");
    chmod 0755, "$root/bin/uname";
    write_file("$case/os.pkglist", "native-os\n");
    write_file("$case/extra.pkglist", "-pre-remove\nvendor/native-extra\n--post-remove\n");
    local %ENV = %ENV;
    @ENV{qw(GENIMAGE_SCRIPT GENIMAGE_ROOT GENIMAGE_CASE GENIMAGE_FAILURE XCATROOT)} =
      ("$repo/xCAT-server/share/xcat/netboot/rh/genimage", $root, $case, $failure, "$repo/xCAT-server");
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        open(STDOUT, '>', "$case/output") or die $!;
        open(STDERR, '>&', STDOUT) or die $!;
        exec $^X, "-I$repo/perl-xCAT", "-I$repo/xCAT-server/lib/perl",
          "-I$repo/xCAT-server/share/xcat/netboot/imgutils", $driver,
          '-o', $os, '-a', 'x86_64', '-p', 'compute', '--srcdir', 'https://os.example/native',
          '--pkglist', "$case/os.pkglist", '--otherpkgdir', $otherdir,
          '--otherpkglist', "$case/extra.pkglist", '--rootimgdir', "$case/image", 'native-fixture';
        die "exec: $!";
    }
    waitpid($pid, 0);
    my $status = (($? & 127) ? 128 + ($? & 127) : $? >> 8);
    open(my $file, '<', "$case/output") or die $!;
    my $output = do { local $/; <$file> };
    close($file);
    return ($status, retrieve("$case/result"), $output);
}

sub write_file {
    my ($path, $contents) = @_;
    open(my $file, '>', $path) or die "write $path: $!";
    print {$file} $contents or die $!;
    close($file) or die $!;
}
