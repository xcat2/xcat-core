#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_PKG_MODULE_DIR};
use Cwd qw(abs_path);
use Errno qw(EACCES EPERM);
use POSIX qw(setpgid);
use Symbol qw(gensym);
use Test::More;
use xCAT::FreeBSDPkg;

my $parent = $$;
my $native_setpgid = \&POSIX::setpgid;
my $perl = abs_path($^X);

sub rejects {
    my ($action, $pattern, $description) = @_;
    my $ok = eval { $action->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    like($error, $pattern, "$description diagnostic");
    return;
}

sub run_case {
    my ($side, $errno) = @_;
    local $! = 0;
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    {
        local *POSIX::setpgid = gensym();
        *POSIX::setpgid = sub {
            my @arguments = @_;
            if (($side eq 'parent' && $$ == $parent) || ($side eq 'child' && $$ != $parent)) {
                $native_setpgid->(@arguments) if $errno == EACCES;
                $! = $errno; ## no critic (Variables::RequireLocalizedPunctuationVars) -- Preserve errno across the system-call double.
                return;
            }
            return $native_setpgid->(@arguments);
        };
        my $action = sub { xCAT::FreeBSDPkg::run_command([$perl, '-e', 'print "executed";'], timeout => 3) };
        if ($errno == EACCES) {
            is_deeply($action->(), { stdout => 'executed', stderr => '', signal => 0, exitcode => 0 },
                'parent EACCES after child group establishment permits the command');
        } else {
            my $pattern = $side eq 'parent' ? qr/Cannot establish command process group/ : qr/Cannot create command process group/;
            rejects($action, $pattern, "$side process-group failure prevents a successful command result");
        }
    }
    is_deeply(\@warnings, [], "$side setpgid failure is not compared numerically as undef");
    is(\&POSIX::setpgid, $native_setpgid, 'native system-call boundary is restored');
    is(xCAT::FreeBSDPkg::run_command([$perl, '-e', 'exit 7;'])->{exitcode}, 7,
        'another command runs after process-group handling');
    return;
}

run_case('parent', EACCES);
run_case('parent', EPERM);
run_case('child', EPERM);
done_testing();
