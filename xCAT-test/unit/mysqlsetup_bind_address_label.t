#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

# mysqlsetup exits on an error, so the CLI load below needs a trap.
BEGIN {
    *CORE::GLOBAL::exit = sub {
        die bless { status => $_[0] || 0 }, 'MysqlSetupTestExit';
    };
}

my $script = $ENV{XCAT_MYSQLSETUP_SOURCE} || repo_path('xCAT-client/bin/mysqlsetup');
my ($help, $load_error);
{
    local @ARGV = ('--help');
    open(my $output, '>', \$help) or die $!;
    local *STDOUT = $output;
    do $script;
    $load_error = $@;
}
die("Unable to load mysqlsetup: $load_error")
  unless ref($load_error) eq 'MysqlSetupTestExit' && $load_error->{status} == 0;

my $CONF = <<'CONF';
[mysqld]
datadir=/var/lib/mysql
bind-address = 127.0.0.1
port=3306
CONF

# Writes $CONF to each named path under a fresh scratch tree and points
# mysqlsetup's candidate list at those paths.
sub scratch {
    my (@present) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my @candidates = map { "$dir/$_" } qw(
        etc/mysql/mariadb.conf.d/50-server.cnf
        etc/mysql/my.cnf
        etc/my.cnf
    );
    foreach my $index (@present) {
        my $path = $candidates[$index];
        (my $parent = $path) =~ s{/[^/]+$}{};
        make_path($parent);
        write_text($path, $CONF);
    }
    return ($dir, \@candidates);
}

# The first candidate that exists is the one it rewrites.
{
    my ($dir, $candidates) = scratch(0, 2);
    local @main::BIND_FILES = @{$candidates};
    my ($rc, $file) = main::comment_bind_address();
    is($rc, 0, 'the rewrite succeeds');
    is($file, $candidates->[0], 'the first candidate that exists is the one it rewrites');
    like(read_text($candidates->[0]), qr/^#bind-address/m, '... and its bind line is commented');
    unlike(read_text($candidates->[2]), qr/^#bind/m, '... and a later candidate is untouched');
}

# With no candidate present it falls back to the last one, which is /etc/my.cnf.
{
    my ($dir, $candidates) = scratch(1);
    local @main::BIND_FILES = @{$candidates};
    my ($rc, $file) = main::comment_bind_address();
    is($rc, 0, 'the second candidate is rewritten when the first is absent');
    is($file, $candidates->[1], '... and it is the file that exists');
}

# THE DEFECT. A temporary file written somewhere else takes the SELinux type of
# that place, and a rename over the configuration keeps it. mysqld is then
# denied read of its own configuration. The inode is what carries the label, so
# an in-place rewrite is measured by the inode surviving.
{
    my ($dir, $candidates) = scratch(2);
    local @main::BIND_FILES = @{$candidates};
    my $target = $candidates->[2];
    my $before = (stat($target))[1];
    my ($rc, $file) = main::comment_bind_address();
    is($rc, 0, 'the fallback candidate is rewritten');
    my $after = (stat($target))[1];
    is($after, $before, 'the rewrite keeps the inode of the configuration file');

    # A leftover temporary file beside the target is the other half of the
    # anti-pattern: it says a rename was used.
    opendir(my $dh, "$dir/etc") or die $!;
    my @left = sort grep { !/^\.\.?$/ } readdir($dh);
    closedir($dh);
    is_deeply(\@left, ['my.cnf'], 'no temporary file is left beside the configuration');
}

# The content is rewritten, and only the bind line changes.
{
    my ($dir, $candidates) = scratch(2);
    local @main::BIND_FILES = @{$candidates};
    main::comment_bind_address();
    my $after = read_text($candidates->[2]);
    is($after, "[mysqld]\ndatadir=/var/lib/mysql\n#bind-address = 127.0.0.1\nport=3306\n",
        'only the bind-address line is commented');
}

# A line that merely contains "bind" is not a bind-address line.
{
    my ($dir, $candidates) = scratch(2);
    local @main::BIND_FILES = @{$candidates};
    write_text($candidates->[2], "skip-name-resolve\n# bind-address = 1.2.3.4\nbind-address=0.0.0.0\n");
    main::comment_bind_address();
    is(read_text($candidates->[2]),
        "skip-name-resolve\n# bind-address = 1.2.3.4\n#bind-address=0.0.0.0\n",
        'a line that does not start with bind is left alone');
}

# An unreadable file is reported rather than ignored.
{
    my ($dir, $candidates) = scratch();
    local @main::BIND_FILES = @{$candidates};
    my ($rc, $message) = main::comment_bind_address();
    is($rc, 1, 'an absent configuration file is an error');
    like($message, qr/\Q$candidates->[2]\E/, '... and the message names the file');
}

done_testing();
