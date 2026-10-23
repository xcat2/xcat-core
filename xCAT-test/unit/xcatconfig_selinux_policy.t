#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Find;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

use xCAT::SELinux;

# An xCAT installation must not change the SELinux policy of the node. xcatconfig
# used to set the running system permissive and write SELINUX=disabled into
# /etc/selinux/config, so every CI cell that declared SELINUX=enforcing ran its
# test cases permissive.

like($INC{'xCAT/SELinux.pm'}, qr/\Q$FindBin::Bin\E/,
    'the module under test comes from this checkout, not from /opt/xcat');

# Builds a scratch root that holds the files the module reads.
sub selinux_root {
    my (%args) = @_;

    my $root = tempdir(CLEANUP => 1);
    if (defined $args{enforce}) {
        my $path = defined $args{enforce_path} ? $args{enforce_path} : '/sys/fs/selinux/enforce';
        my ($dir) = $path =~ m{^(.*)/[^/]+$};
        make_path("$root$dir");
        write_text("$root$path", $args{enforce});
    }
    if (defined $args{config}) {
        make_path("$root/etc/selinux");
        write_text("$root/etc/selinux/config", $args{config});
    }

    return $root;
}

# Every file under $root, with its contents, so a caller can prove the module
# wrote nothing.
sub tree_contents {
    my ($root) = @_;

    my %contents;
    find({
            no_chdir => 1,
            wanted   => sub {
                return unless -f $File::Find::name;
                my $relative = substr($File::Find::name, length($root));
                $contents{$relative} = read_text($File::Find::name);
            },
        }, $root);

    return \%contents;
}

my $CONFIG = "SELINUX=enforcing\nSELINUXTYPE=targeted\n";

# An enforcing node keeps enforcing.
{
    my $root   = selinux_root(enforce => "1\n", config => $CONFIG);
    my $before = tree_contents($root);
    my $answer = xCAT::SELinux->xcatconfig_action(root => $root);

    is($answer->{mode}, 'enforcing', 'an enforcing node is reported as enforcing');
    is($answer->{config_mode}, 'enforcing', '... and the config mode is enforcing');
    is_deeply([ sort keys %{$answer} ], [ qw(config_mode mode warning) ],
        '... and the answer asks for no change, so it carries only the state and a warning');
    like($answer->{warning}, qr/^SELINUX is enforcing\./,
        '... and the warning names the mode the node is in');
    like($answer->{warning}, qr/\Qdoes not change the SELinux mode\E/,
        '... and the warning says xCAT leaves the mode alone');
    unlike($answer->{warning}, qr/disabl/i,
        '... and the warning does not announce a disable');
    is_deeply(tree_contents($root), $before,
        '... and /etc/selinux/config and the enforce file are not rewritten');
}

# A permissive node stays permissive. xcatconfig must not write the enforce file.
{
    my $root   = selinux_root(enforce => "0\n", config => "SELINUX=permissive\n");
    my $before = tree_contents($root);
    my $answer = xCAT::SELinux->xcatconfig_action(root => $root);

    is($answer->{mode}, 'permissive', 'a permissive node is reported as permissive');
    is($answer->{config_mode}, 'permissive', '... and the config mode is permissive');
    is_deeply([ sort keys %{$answer} ], [ qw(config_mode mode warning) ],
        '... and the answer asks for no change');
    like($answer->{warning}, qr/^SELINUX is permissive\./,
        '... and the warning names the permissive mode');
    unlike($answer->{warning}, qr/disabl/i,
        '... and the warning does not announce a disable');
    is_deeply(tree_contents($root), $before,
        '... and nothing under the scratch root is rewritten');
}

# A node that already has SELinux off behaves as it did: no warning, no change.
{
    my $root   = selinux_root(config => "SELINUX=disabled\n");
    my $before = tree_contents($root);
    my $answer = xCAT::SELinux->xcatconfig_action(root => $root);

    is($answer->{mode}, 'disabled', 'a node without selinuxfs is reported as disabled');
    is($answer->{config_mode}, 'disabled', '... and the config mode is disabled');
    is($answer->{warning}, undef, '... and a disabled node gets no warning');
    is_deeply([ sort keys %{$answer} ], [ qw(config_mode mode warning) ],
        '... and the answer asks for no change');
    is_deeply(tree_contents($root), $before,
        '... and /etc/selinux/config is not rewritten');
}

# selinuxfs with a value that is neither 0 nor 1 still means SELinux is on.
{
    my $root   = selinux_root(enforce => "unknown\n", config => $CONFIG);
    my $answer = xCAT::SELinux->xcatconfig_action(root => $root);

    is($answer->{mode}, 'enabled', 'an unreadable enforce value is reported as enabled');
    like($answer->{warning}, qr/^SELINUX is enabled\./, '... and the warning names that state');
    is_deeply([ sort keys %{$answer} ], [ qw(config_mode mode warning) ],
        '... and the answer asks for no change');
}

# The pre-2.6.37 selinuxfs mount point is read as well.
{
    my $root = selinux_root(
        enforce      => "1\n",
        enforce_path => '/selinux/enforce',
        config       => $CONFIG,
    );
    my $answer = xCAT::SELinux->xcatconfig_action(root => $root);

    is($answer->{mode}, 'enforcing', 'the legacy /selinux/enforce path reports enforcing');
}

# A node with no /etc/selinux/config reports no config mode, and the file stays absent.
{
    my $root   = selinux_root(enforce => "1\n");
    my $answer = xCAT::SELinux->xcatconfig_action(root => $root);

    is($answer->{mode}, 'enforcing', 'the runtime mode is read without /etc/selinux/config');
    is($answer->{config_mode}, undef, '... and a missing config file has no mode');
    ok(!-e "$root/etc/selinux/config", '... and the missing config file is not created');
}

# A commented SELINUX line is not the setting.
{
    my $root = selinux_root(
        enforce => "0\n",
        config  => "# SELINUX=enforcing\nSELINUX=permissive\n",
    );

    is(xCAT::SELinux->config_mode(root => $root), 'permissive',
        'a commented SELINUX line is ignored');
}

# At the first install, site.selinux records enforcing only for an enforcing
# management node. An existing value is never replaced.
{
    my %expected = (
        enforcing  => 'enforcing',
        permissive => 'disabled',
        disabled   => 'disabled',
        enabled    => 'disabled',
    );
    foreach my $mode (sort keys %expected) {
        is(xCAT::SELinux->install_default($mode, undef), $expected{$mode},
            "a $mode management node with no site.selinux records $expected{$mode}");
        is(xCAT::SELinux->install_default($mode, ''), $expected{$mode},
            "a $mode management node with an empty site.selinux records $expected{$mode}");
        foreach my $existing (qw(enforcing permissive disabled)) {
            is(xCAT::SELinux->install_default($mode, $existing), undef,
                "a $mode management node keeps site.selinux=$existing");
        }
    }
}

# install_default only decides. It writes nothing under the root it reads.
{
    my $root   = selinux_root(enforce => "1\n", config => $CONFIG);
    my $before = tree_contents($root);
    my $mode   = xCAT::SELinux->runtime_mode(root => $root);

    is(xCAT::SELinux->install_default($mode, undef), 'enforcing',
        'the runtime mode of an enforcing root gives enforcing');
    is_deeply(tree_contents($root), $before,
        '... and the enforce file and /etc/selinux/config are not rewritten');
}

done_testing();
