#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $program = "$FindBin::Bin/../xcattest";
my $casedir = "$FindBin::Bin/../autotest/testcase";
BAIL_OUT("xcattest is not at $program")     unless -f $program;
BAIL_OUT("no test cases under $casedir")    unless -d $casedir;

# A check line xcattest does not understand costs the case the assertion it describes, and the
# case says nothing about it: an unknown operator reports "Unrecognized testcase syntax", and a
# line whose content does not start with a word character is dropped while the case is loaded.
# Read the shipped check lines and let the harness report on them.
my @files;
find({ wanted => sub { push(@files, $File::Find::name) if -f $File::Find::name }, no_chdir => 1 }, $casedir);
BAIL_OUT("no case files under $casedir") unless @files;

my (%checks, %vars);
for my $file (sort @files) {
    open(my $fh, '<', $file) or BAIL_OUT("open $file: $!");
    while (my $line = <$fh>) {
        chomp($line);
        next unless $line =~ /^check\s*:\s*(\S.*)$/;
        my $check = $1;

        # __GETNODEATTR(...)__ and its siblings read the xCAT database, one lsdef for each
        # check. The shape of the line is what this test reads, so a fixed value stands in.
        $check =~ s/__\w+\([^)]*\)__/placeholder/g;
        $vars{$1} = 1 while ($check =~ /\$\$(\w+)/g);
        push(@{ $checks{$file} }, $check);
    }
    close($fh) or BAIL_OUT("close $file: $!");
}
BAIL_OUT("no check lines under $casedir") unless keys %checks;

# One case per shipped file, so a check that reports nothing is attributed to its own file.
my %case_of_file = map { $_ => 'syntax_' . do { my $n = $_; $n =~ s{^\Q$casedir\E/?}{}; $n =~ s/[^A-Za-z0-9_-]/_/g; $n } } keys %checks;

my $fixture = '';
for my $file (sort keys %checks) {
    $fixture .= "start:$case_of_file{$file}\n";
    $fixture .= "cmd:true\n";
    $fixture .= "check:$_\n" for @{ $checks{$file} };
    $fixture .= "end\n";
}

# xcattest derives its result directory from the location of the program, so the copy under the
# scratch tree keeps every file the run writes inside that tree.
my $root = tempdir(CLEANUP => 1);
make_path("$root/bin", "$root/cases");
copy($program, "$root/bin/xcattest") or BAIL_OUT("copy xcattest: $!");
chmod 0755, "$root/bin/xcattest";
open(my $fixture_fh, '>', "$root/cases/fixture") or BAIL_OUT("write the fixture case: $!");
print $fixture_fh $fixture;
close($fixture_fh) or BAIL_OUT("close the fixture case: $!");

# Every variable a check line names has to resolve, or xcattest drops the whole case.
# A "local" here would be undone at the end of its own statement, before the run.
$ENV{"XCATTEST_$_"} = 'placeholder' for keys %vars;
$ENV{XCATTEST_CASEDIR} = "$root/cases";
# Some shipped patterns warn when perl compiles them, and the warnings say nothing about the
# operator. The log file carries what this test reads, so the warnings go to the scratch tree.
open(my $stderr_save, '>&', \*STDERR) or BAIL_OUT("save STDERR: $!");
open(STDERR, '>', "$root/stderr") or BAIL_OUT("redirect STDERR: $!");
system($^X, "$root/bin/xcattest", '-q', '-t', join(',', sort values %case_of_file));
open(STDERR, '>&', $stderr_save) or BAIL_OUT("restore STDERR: $!");

my ($logname) = glob("$root/share/xcat/tools/autotest/result/xcattest.log.*");
BAIL_OUT("the harness wrote no log under $root") unless $logname;
open(my $log_fh, '<', $logname) or BAIL_OUT("open $logname: $!");
my @log = <$log_fh>;
close($log_fh) or BAIL_OUT("close $logname: $!");
chomp(@log);

# Count what the harness reported for each case, and keep the lines it did not understand.
my (%reported, @unrecognized, $current);
for my $line (@log) {
    $current = $1 if ($line =~ /^------START::(\S+)::/);
    next unless defined $current;
    $reported{$current}++ if ($line =~ /^CHECK:/ or $line =~ /^Unrecognized testcase syntax:/);
    push(@unrecognized, "$current: $line") if ($line =~ /^Unrecognized testcase syntax:/);
    $current = undef if ($line =~ /^------END::/);
}

is(join("\n", @unrecognized), '',
    'every check line in the shipped cases uses an operator xcattest understands');

my @silent;
for my $file (sort keys %checks) {
    my $case = $case_of_file{$file};
    my $fed  = scalar @{ $checks{$file} };
    my $got  = $reported{$case} || 0;
    push(@silent, "$file: $fed check lines, $got reported") if ($got != $fed);
}
is(join("\n", @silent), '',
    'every check line in the shipped cases reports a result, so none is dropped while the case loads');

done_testing();
