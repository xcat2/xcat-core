#!/usr/bin/env perl
use strict;
use warnings;
use Errno qw(EACCES EIO);
use File::Copy ();
use File::Basename qw(dirname);
use FindBin;
use File::Slurper qw(write_text);
use Storable qw(nstore);
our (@commands, $dracut_calls, $lock_calls);
BEGIN {
    *CORE::GLOBAL::readpipe = sub {
        return "4.18.2\n" if $_[0] =~ /rpm --version/;
        return "059\n" if $_[0] =~ /^rpm --root .* -qi dracut /;
        return '' if $_[0] =~ /type -p pigz/;
        die "Unexpected command: $_[0]";
    };
    *CORE::GLOBAL::system = sub {
        my $command = join(' ', @_);
        push @commands, $command;
        if ($command =~ /^chroot (\S+) dracut .* -f (\S+) /) {
            $dracut_calls++;
            write_text("$1$2", "new initrd\n");
            return 29 << 8 if $ENV{GENIMAGE_FAILURE} eq 'dracut';
        }
        if ($command =~ m{^sed -i -e '[^']+' \Q$ENV{GENIMAGE_DEST}\E/rootimg/etc/yum\.repos\.d/[A-Za-z0-9.-]+\.repo$}) {
            return CORE::system($command);
        }
        return 0;
    };
    *CORE::GLOBAL::rename = sub {
        my $failure = $ENV{GENIMAGE_FAILURE};
        if ($failure eq 'publish-initrd'
            && $_[1] eq "$ENV{GENIMAGE_DEST}/initrd-stateless.gz") {
            $! = EACCES;
            return 0;
        }
        return CORE::rename($_[0], $_[1]);
    };
}
my $move = \&File::Copy::move;
{
    no warnings 'redefine';
    *File::Copy::move = sub {
        if ($ENV{GENIMAGE_FAILURE} eq 'move-initrd' && $_[0] =~ m{/tmp/initrd\.\d+\.gz$}) {
            $! = EIO;
            return 0;
        }
        return $move->(@_);
    };
}
END {
    nstore({ commands => \@commands, dracut_calls => $dracut_calls || 0, lock_calls => $lock_calls || 0 },
        "$ENV{GENIMAGE_CASE}/result") if defined($ENV{GENIMAGE_CASE});
}
require xCAT::Utils;
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub {
        $lock_calls++;
        return ($ENV{GENIMAGE_FAILURE} eq 'lock' ? 1 : 0, undef);
    };
}
$0 = $ENV{GENIMAGE_SCRIPT};
$FindBin::Bin = dirname($0);
do $0;
die $@ if $@;
