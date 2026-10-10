package XCAT::Test::Package;

use strict;
use warnings;
use Capture::Tiny qw(capture);
use Cwd qw(getcwd);
use Exporter qw(import);

our @EXPORT_OK = qw(run_in);

sub run_in {
    my ($directory, @command) = @_;
    my $previous = getcwd();
    chdir($directory) or die "chdir $directory: $!";
    my ($stdout, $stderr, $status);
    my $ok = eval {
        ($stdout, $stderr, $status) = capture { system(@command) };
        1;
    };
    my $error = $@;
    chdir($previous) or die "chdir $previous: $!";
    die $error unless $ok;
    $status = $status == -1 ? 255 : ($status & 127) ? 128 + ($status & 127) : $status >> 8;
    return ($status, $stdout, $stderr);
}

1;
