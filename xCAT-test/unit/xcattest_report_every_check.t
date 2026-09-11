#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

my $program = "$FindBin::Bin/../xcattest";
BAIL_OUT("xcattest is not at $program") unless -f $program;

#---
=head3 run_harness

    Descriptions: Run xcattest over one fixture case file and return its log lines.
    Arguments:
        $case_text - the content of the fixture case file
        @names     - the case names to run
    Returns: a reference to the array of log lines, and the failed-cases report lines
=cut

#---
sub run_harness {
    my ($case_text, @names) = @_;

    # xcattest derives its result directory from the location of the program, so the copy
    # under the scratch tree keeps every file the run writes inside that tree.
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/bin", "$root/cases");
    copy($program, "$root/bin/xcattest") or BAIL_OUT("copy xcattest: $!");
    chmod 0755, "$root/bin/xcattest";

    open(my $case_fh, '>', "$root/cases/fixture") or BAIL_OUT("write the fixture case: $!");
    print $case_fh $case_text;
    close($case_fh) or BAIL_OUT("close the fixture case: $!");

    local $ENV{XCATTEST_CASEDIR} = "$root/cases";
    system($^X, "$root/bin/xcattest", '-q', '-t', join(',', @names));

    my $slurp = sub {
        my ($path) = @_;
        open(my $fh, '<', $path) or BAIL_OUT("open $path: $!");
        my @lines = <$fh>;
        close($fh) or BAIL_OUT("close $path: $!");
        chomp(@lines);
        return @lines;
    };

    my ($log) = glob("$root/share/xcat/tools/autotest/result/xcattest.log.*");
    BAIL_OUT("the harness wrote no running log under $root") unless $log;
    my ($failed) = glob("$root/share/xcat/tools/autotest/result/failedcases.*");
    BAIL_OUT("the harness wrote no failed-cases report under $root") unless $failed;

    return ([ $slurp->($log) ], [ $slurp->($failed) ]);
}

#---
=head3 reported_checks

    Descriptions: Select the check results the harness reported.
    Arguments:
        $lines - a reference to the array of log lines
    Returns: a reference to the array of CHECK lines, in the order they were reported
=cut

#---
sub reported_checks {
    my ($lines) = @_;
    return [ grep { /^CHECK:/ } @{$lines} ];
}

# The second command fails its first check. The check after it on the same command, and the
# checks of every command after it, describe the same run and must report their own result.
my $mixed = <<'CASE';
start:mixedchecks
description:a failed check between checks that pass
cmd:echo alpha
check:rc==0
cmd:echo beta
check:rc!=0
check:output=~beta
cmd:echo gamma
check:output=~gamma
end
CASE

my ($log, $failed) = run_harness($mixed, 'mixedchecks');

is_deeply(reported_checks($log),
    [ "CHECK:rc == 0\t[Pass]",
        "CHECK:rc != 0\t[Failed]",
        "CHECK:output =~ beta\t[Pass]",
        "CHECK:output =~ gamma\t[Pass]" ],
    'every check reports its own result, and a failed check does not silence the checks after it');

is_deeply(reported_checks($failed), reported_checks($log),
    'the failed-cases report carries the same check results as the running log');

ok(scalar(grep { /^------END::mixedchecks::Failed::/ } @{$log}),
    'a check that passes after a failed check does not make the case pass');

# A case that fails more than one check names every one of them.
my $twofails = <<'CASE';
start:twofailedchecks
description:two commands, each with a check that fails
cmd:echo one
check:rc!=0
cmd:echo two
check:rc!=0
end
CASE

($log, $failed) = run_harness($twofails, 'twofailedchecks');

is_deeply(reported_checks($log),
    [ "CHECK:rc != 0\t[Failed]", "CHECK:rc != 0\t[Failed]" ],
    'both failed checks are reported, not just the first');

# A case where every check passes is unchanged.
my $allpass = <<'CASE';
start:allcheckspass
description:every check passes
cmd:echo alpha
check:rc==0
check:output=~alpha
cmd:echo beta
check:output=~beta
end
CASE

($log, $failed) = run_harness($allpass, 'allcheckspass');

is_deeply(reported_checks($log),
    [ "CHECK:rc == 0\t[Pass]", "CHECK:output =~ alpha\t[Pass]", "CHECK:output =~ beta\t[Pass]" ],
    'a case whose checks all pass reports every check');

ok(scalar(grep { /^------END::allcheckspass::Passed::/ } @{$log}),
    'a case whose checks all pass still reports Passed');

done_testing();
