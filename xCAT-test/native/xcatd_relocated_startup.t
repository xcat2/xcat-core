#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Text::ParseWords qw(shellwords);
use XCAT::Test::RPM;

plan skip_all => 'Native RPM distribution and Linux namespaces are required'
    unless $^O eq 'linux' && -f '/etc/redhat-release';

my $rpm = XCAT::Test::RPM->build('xCAT-server', 1);

#---

=head3 service_settings

    Descriptions: Read the [Service] section of a unit file, in order.
    Arguments:    The text of the unit file.
    Returns:      A list of [directive, value] pairs.

=cut

#---
sub service_settings {
    my ($text) = @_;
    my ($section, @settings);
    foreach my $line (split /\n/, $text) {
        if ($line =~ /^\s*\[([^]]+)\]\s*$/) { $section = $1; next; }
        next unless ($section // '') eq 'Service';
        push @settings, [ $1, $2 ] if $line =~ /^\s*(\w+)\s*=\s*(.*)$/;
    }
    return @settings;
}

#---

=head3 unit_environment

    Descriptions: Compose the environment systemd gives ExecStart. Environment
                  and EnvironmentFile apply in the order the unit lists them,
                  and a later setting replaces an earlier one. A leading - on
                  an EnvironmentFile path makes a missing file not an error.
    Arguments:    The scratch root, and the unit path inside it.
    Returns:      A hash reference of the composed variables.

=cut

#---
sub unit_environment {
    my ($root, $unit) = @_;
    my %env;
    foreach my $setting (service_settings($root->read($unit))) {
        my ($directive, $value) = @{$setting};
        if ($directive eq 'Environment') {
            foreach my $word (shellwords($value)) {
                $env{$1} = $2 if $word =~ /^(\w+)=(.*)$/;
            }
        } elsif ($directive eq 'EnvironmentFile') {
            (my $path = $value) =~ s/^-//;
            next unless -f $root->path($path);
            foreach my $line (split /\n/, $root->read($path)) {
                next if $line =~ /^\s*(?:#|$)/;
                next unless $line =~ /^\s*(\w+)\s*=\s*(.*?)\s*$/;
                my ($name, $word) = ($1, $2);
                $word =~ s/^"(.*)"$/$1/ or $word =~ s/^'(.*)'$/$1/;
                $env{$name} = $word;
            }
        }
    }
    return \%env;
}

#---

=head3 exec_start

    Descriptions: Give the start command of a unit, as systemd would run it.
    Arguments:    The scratch root, and the unit path inside it.
    Returns:      The command and its arguments.

=cut

#---
sub exec_start {
    my ($root, $unit) = @_;
    my @commands = map { $_->[1] }
      grep { $_->[0] eq 'ExecStart' && length $_->[1] } service_settings($root->read($unit));
    die 'Expected one service start command' unless @commands == 1;
    return shellwords($commands[0]);
}

my $unit = '/usr/lib/systemd/system/xcatd.service';

# One subtest per prefix. The daemon runs from the prefix rpm relocated the
# package to, so XCATROOT and the command directories on PATH must name that
# prefix and not the one the unit file was written with.
foreach my $prefix ('/opt/xcat', '/srv/xcat') {
    subtest "a package installed under $prefix starts the daemon of $prefix" => sub {
        my $root = XCAT::Test::RPM->new;
        $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"10.0\"\n");
        my ($status, $out, $err) = $root->install($rpm, '--prefix', $prefix);
        is($status, 0, "install under $prefix") or diag "$out$err";

        ok(-e $root->path("$prefix/sbin/xcatd"), "the daemon is installed in $prefix");
        is(readlink($root->path('/usr/sbin/xcatd')), "$prefix/sbin/xcatd",
            'the daemon symlink names the installed prefix');

        my $env = unit_environment($root, $unit);
        is($env->{XCATROOT}, $prefix, "XCATROOT of the unit is $prefix");

        my @xcat = grep { m{/xcat(/|$)} } split /:/, ($env->{PATH} // '');
        ok(scalar(@xcat) >= 3, 'PATH carries the xCAT command directories')
            or diag($env->{PATH} // '(no PATH)');
        my @wrong = grep { !m{^\Q$prefix\E/} } @xcat;
        is_deeply(\@wrong, [], "every xCAT directory on PATH is under $prefix");

        # Run the start command with the environment the unit composes, and read
        # back what the daemon received.
        my @start = exec_start($root, $unit);
        is($start[0], '/usr/sbin/xcatd', 'the unit starts the daemon without a shell');
        $root->write("$prefix/sbin/xcatd",
            "#!/bin/sh\nprintf 'xcatd XCATROOT=%s\\n' \"\$XCATROOT\" >> /calls\n", 0755);
        ($status, $out, $err) = $root->run('env', "XCATROOT=$env->{XCATROOT}",
            "PATH=$env->{PATH}", @start);
        is($status, 0, 'the start command runs') or diag "$out$err";
        is($root->read('/calls'), "xcatd XCATROOT=$prefix\n",
            "the daemon receives XCATROOT=$prefix");

        ($status, $out, $err) = $root->run('rpm', '--nodeps', '-e', 'xCAT-server');
        is($status, 0, 'erase transaction') or diag "$out$err";
        ok(!-e $root->path('/etc/xcat/xcatroot.env'),
            'erase removes the generated environment file');
    };
}

# %post writes the environment file and %preun takes it away, so it is absent
# on rpm --justdb, before %post runs, and after an interrupted install. The
# unit must still start: each EnvironmentFile carries a leading -, which makes
# a missing file not an error, and the unit keeps a default XCATROOT.
subtest 'the unit starts when the recorded prefix file is absent' => sub {
    my $root = XCAT::Test::RPM->new;
    $root->write('/etc/os-release', "ID=rhel\nVERSION_ID=\"10.0\"\n");
    my ($status, $out, $err) = $root->install($rpm, '--prefix', '/srv/xcat');
    is($status, 0, 'install under /srv/xcat') or diag "$out$err";

    foreach my $setting (service_settings($root->read($unit))) {
        next unless $setting->[0] eq 'EnvironmentFile';
        like($setting->[1], qr{^-},
            "a missing $setting->[1] does not stop the unit");
    }

    unlink($root->path('/etc/xcat/xcatroot.env'))
        or die 'removing the recorded prefix: ' . $!;
    # The default in the unit is the only source left, so name it. An empty
    # value would satisfy a check that only compared the composed value with
    # itself.
    my $env = unit_environment($root, $unit);
    is($env->{XCATROOT}, '/opt/xcat', 'XCATROOT is the default of the unit');
    like($env->{PATH} // '', qr{\Q/opt/xcat/sbin\E},
        'PATH is the default of the unit');

    # The daemon symlink still names /srv/xcat, and XCATROOT falls back to the
    # default in the unit, so the daemon starts and reads the modules of the
    # other prefix. That is the state before this change, and it is what the
    # recorded prefix file removes. Record at the path the symlink names, so
    # the test writes nothing outside its scratch tree.
    my @start = exec_start($root, $unit);
    my $target = readlink($root->path('/usr/sbin/xcatd'));
    $root->write($target,
        "#!/bin/sh\nprintf 'xcatd XCATROOT=%s\\n' \"\$XCATROOT\" >> /calls\n", 0755);
    ($status, $out, $err) = $root->run('env', "XCATROOT=$env->{XCATROOT}",
        "PATH=$env->{PATH}", @start);
    is($status, 0, 'the start command runs without the recorded prefix') or diag "$out$err";
    is($root->read('/calls'), "xcatd XCATROOT=/opt/xcat\n",
        'the daemon starts with the default prefix, not the installed one');
};

done_testing();
