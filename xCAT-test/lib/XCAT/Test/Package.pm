package XCAT::Test::Package;

use strict;
use warnings;
use Cwd qw(getcwd);
use Exporter qw(import);
use XCAT::Test::Lifecycle ();

our @EXPORT_OK = qw(run_in);

sub run_in {
    my ($directory, @command) = @_;
    my $previous = getcwd();
    chdir($directory) or die "chdir $directory: $!";
    my ($stdout, $stderr, $status);
    my $ok = eval {
        ($status, $stdout, $stderr) = XCAT::Test::Lifecycle::command(@command);
        1;
    };
    my $error = $@;
    chdir($previous) or die "chdir $previous: $!";
    die $error unless $ok;
    return ($status, $stdout, $stderr);
}

1;
