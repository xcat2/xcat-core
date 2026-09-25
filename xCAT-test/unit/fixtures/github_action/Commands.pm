package Commands;

use strict;
use warnings;
use JSON::PP qw(encode_json);

sub record_command {
    my ($command) = @_;
    open(my $log, '>>', $ENV{XCAT_TEST_CI_COMMANDS}) or die "open command log: $!";
    print {$log} encode_json($command), "\n";
    close($log) or die "close command log: $!";
    return;
}

BEGIN {
    *CORE::GLOBAL::readpipe = sub {
        my ($command) = @_;
        record_command($command);
        my @output = ("ok\n");
        my $status = 0;
        if ($command eq $ENV{XCAT_TEST_CI_FAIL_COMMAND}) {
            @output = ("command failed\n");
            $status = 1;
        } elsif ($command =~ /^ip -o link /) {
            @output = ();
        } elsif ($command =~ /^file (.+) 2>&1$/) {
            my $file = $1;
            @output = ($file . ': ' . ($file =~ /\.txt$/ ? "ASCII text\n" : "Perl script text\n"));
        } elsif ($command eq 'hostname') {
            @output = ("ci-node\n");
        } elsif ($command =~ /xcattest -s /) {
            @output = ("example_case\n");
        } elsif ($command =~ /xcattest -f /) {
            my $result = $ENV{XCAT_TEST_CI_FAIL_CASE} ? 'Failed' : 'Passed';
            @output = ("------END::example_case::$result\n");
        }
        $? = $status << 8;
        return wantarray ? @output : join('', @output);
    };
    *CORE::GLOBAL::system = sub {
        record_command(join(' ', @_));
        return 0;
    };
}

# Install the filesystem fixture after the driver compiles, before its main code runs.
INIT {
    no warnings qw(redefine once);
    *main::get_files_recursive = sub {
        my ($directory, $files) = @_;
        if ($directory eq '/opt/xcat') {
            push @$files,
              '/opt/xcat/share/xcat/netboot/genesis/bin/init',
              '/opt/xcat/probe/lib/example.pm',
              '/opt/xcat/share/xcat/tools/autotest/unit/example.t',
              '/opt/xcat/lib/perl/xCAT/Example.pm',
              '/opt/xcat/share/xcat/tools/autotest/unit-extra/example.pl',
              '/opt/xcat/probe-extra/example.pl',
              '/opt/xcat/share/xcat/netboot/genesis-extra/example.pl',
              '/opt/xcat/share/readme.txt';
        } elsif ($directory eq '/install') {
            push @$files, '/install/postscripts/example';
        } else {
            die "unexpected scan directory: $directory";
        }
        return 0;
    };
}

1;
