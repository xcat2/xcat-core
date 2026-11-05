#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

plan skip_all => 'bash is not installed' unless -x '/bin/bash';

# The script runs in the image, which lists its kernels in /lib/modules. This ls lists two of them.
my $bin = tempdir(CLEANUP => 1);
write_text("$bin/ls", "#!/bin/sh\n[ \"\$1\" = /lib/modules ] && printf '6.8.0-99-generic\\n6.8.0-100-generic\\n'\n");
chmod(0755, "$bin/ls") or die "chmod: $!";

sub uname {
    my ($kernelver, @options) = @_;
    my $script = tempdir(CLEANUP => 1) . '/uname';
    write_text($script, imgutils::uname_script($kernelver));
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    my $output = `/bin/bash $script @options`;
    chomp($output);
    return $output;
}

is(uname('', '-r'), '6.8.0-100-generic', 'uname -r names the newest kernel of the image');
is(uname('6.8.0-99-generic', '-r'), '6.8.0-99-generic', 'uname -r names an explicit kernelver');
is(uname('', '-s'), 'Linux', 'uname -s names Linux');
is(uname(''), 'Linux', 'uname without an option names Linux');

done_testing();
