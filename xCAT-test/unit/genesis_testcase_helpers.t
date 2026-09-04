#!/usr/bin/env perl
# Drive the genesis test case helpers. genesistest.pl needs a management node, so lift the
# routines out and run them with rpm, dpkg and cat shadowed.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $helper = repo_path('xCAT-test/autotest/testcase/genesis/genesistest.pl');
my $shell  = repo_path('xCAT-test/autotest/testcase/genesis/test.sh');
plan skip_all => 'genesis testcase helpers not found' unless -f $helper && -f $shell;
plan tests => 11;

my $tmpdir = tempdir(CLEANUP => 1);
my $source = read_text($helper);

eval_subs($source, qw(get_os get_arch check_genesis_file));

# get_os drives every later branch. AlmaLinux and Rocky release files say neither "Red Hat"
# nor "suse" nor "ubuntu", so the management node read as unknown and the check was skipped.
is(os_for("AlmaLinux release 9.8 (Olive Jaguar)\n"), 'redhat', 'AlmaLinux is a redhat family node');
is(os_for("Rocky Linux release 9.5 (Blue Onyx)\n"),  'redhat', 'Rocky is a redhat family node');
is(os_for("Red Hat Enterprise Linux release 9.5\n"), 'redhat', 'RHEL is still a redhat family node');
is(os_for("SUSE Linux Enterprise Server 15 SP6\n"),  'sles',   'SLES is still detected');
is(os_for("NAME=\"Ubuntu\"\nID=ubuntu\n"),           'ubuntu', 'Ubuntu is still detected');

# check_genesis_file answers with a return value. The caller used to read $? instead, so a
# management node with no genesis packages reported success.
{
    no warnings 'once';
    local $GenesisTest::os = 'redhat';
    is(rpm_check("xCAT-genesis-base-x86_64-2.19.0-snap1.noarch\nxCAT-genesis-scripts-x86_64-2.19.0-snap1.noarch\n"),
        0, 'both genesis packages installed reports success');
    is(rpm_check("xCAT-genesis-scripts-x86_64-2.19.0-snap1.noarch\n"),
        1, 'a missing genesis-base reports failure');
    eval_subs($source, qw(report_genesis_files));
    is(report_files("xCAT-genesis-scripts-x86_64-2.19.0-snap1.noarch\n"),
        1, 'report_genesis_files propagates the failure to its caller');
}

# Genesis generates new host keys at every boot and each case boots the node several times, so
# the second boot met "REMOTE HOST IDENTIFICATION HAS CHANGED" and xdsh could not reach it.
{
    no warnings 'once';
    eval_subs($source, qw(forget_host_keys testxdsh));
    local $GenesisTest::noderange = 'xcat71-cn';
    my $run = run_testxdsh(3, genesis_prompt => 1, cmdline => 'destiny=shell');
    is($run->{status}, 0, 'testxdsh succeeds when the node answers in the Genesis shell');
    like($run->{makeknownhosts}, qr/\bxcat71-cn\b/, 'the node host keys are forgotten first');
    like($run->{makeknownhosts}, qr/-r/, 'makeknownhosts is asked to remove them');
}

#---
# run_testxdsh: drive testxdsh with makeknownhosts and xdsh shadowed. xdsh is asked twice --
# once for the prompt, once for the file -- and the stub answers both from its arguments.
#---
sub run_testxdsh {
    my ($value, %opt) = @_;
    my $dir = tempdir(DIR => $tmpdir, CLEANUP => 1);
    my $log = "$dir/makeknownhosts.log";
    write_text("$dir/makeknownhosts", "#!/bin/sh\necho \"\$@\" >> '$log'\n");
    my $prompt = $opt{genesis_prompt} ? '[xCAT Genesis running on node]' : 'sh-5.1';
    write_text("$dir/xdsh", "#!/bin/sh\nfor a in \"\$@\"; do\n  case \"\$a\" in\n    */cmdline|/proc/cmdline) printf '%s\\n' '$opt{cmdline}'; exit 0;;\n  esac\ndone\nprintf '%s\\n' '$prompt'\n");
    chmod 0755, "$dir/makeknownhosts", "$dir/xdsh";
    local $ENV{PATH} = "$dir:$ENV{PATH}";
    my $status = GenesisTest::testxdsh($value);
    return { status => $status, makeknownhosts => (-f $log ? read_text($log) : '') };
}

#---
# eval_subs: lift named subs out of the script and compile them into a scratch package, so
# they can be run without a management node. Bails out when a sub stops being extractable.
#---
sub eval_subs {
    my ($text, @names) = @_;
    my $code = "package GenesisTest;\nno strict;\nno warnings;\nour \$os;\nour \$check_genesis_file;\nour \$noderange;\n";
    $code .= "sub send_msg { push \@GenesisTest::MSG, \$_[1]; return 0; }\n";
    foreach my $name (@names) {
        my ($body) = $text =~ /^(sub \Q$name\E \{.*?^\})$/ms;
        BAIL_OUT("sub $name() not found in $helper") unless defined $body;
        $code .= "$body\n";
    }
    $code .= "1;\n";
    eval $code or BAIL_OUT("cannot compile the extracted helpers: $@");
}

#---
# os_for: run get_os with `cat` shadowed so it reads the release text under test.
#---
sub os_for {
    my ($release) = @_;
    local $ENV{PATH} = stub_bin(cat => "#!/bin/sh\nprintf '%s' " . shell_quote($release)) . ":$ENV{PATH}";
    return GenesisTest::get_os();
}

#---
# rpm_check: run check_genesis_file with `rpm` shadowed so `rpm -qa` lists the given packages.
#---
sub rpm_check {
    my ($installed) = @_;
    local $ENV{PATH} = stub_bin(rpm => "#!/bin/sh\nprintf '%s' " . shell_quote($installed)) . ":$ENV{PATH}";
    return GenesisTest::check_genesis_file('x86_64');
}

sub report_files {
    my ($installed) = @_;
    local $ENV{PATH} = stub_bin(rpm => "#!/bin/sh\nprintf '%s' " . shell_quote($installed)) . ":$ENV{PATH}";
    return GenesisTest::report_genesis_files('x86_64');
}

#---
# shell_quote: single-quote a string for /bin/sh.
#---
sub shell_quote {
    my ($v) = @_;
    $v =~ s/'/'\\''/g;
    return "'$v'";
}

#---
# stub_bin: a directory holding one shadow command, ahead of the real one on PATH.
#---
sub stub_bin {
    my (%cmd) = @_;
    my $dir = tempdir(DIR => $tmpdir, CLEANUP => 1);
    while (my ($name, $body) = each %cmd) {
        write_text("$dir/$name", $body);
        chmod 0755, "$dir/$name";
    }
    return $dir;
}
