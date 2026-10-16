# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::SELinux;

use strict;
use warnings;

# selinuxfs is at /sys/fs/selinux. /selinux is the path a kernel before 2.6.37 uses.
our @ENFORCE_FILES = ('/sys/fs/selinux/enforce', '/selinux/enforce');
our $CONFIG_FILE = '/etc/selinux/config';

#-----------------------------------------------------------------------------

=head3 runtime_mode

    Descriptions:
        Reports the SELinux mode of the running system.
    Arguments:
        root - a prefix for the paths this module reads. The default is the
               empty string, which reads the real system.
    Returns:
        'enforcing'  - selinuxfs reports enforcing
        'permissive' - selinuxfs reports permissive
        'enabled'    - selinuxfs is there and the mode is not readable
        'disabled'   - selinuxfs is not there, so SELinux is off
    Example:
        my $mode = xCAT::SELinux->runtime_mode();

=cut

#-----------------------------------------------------------------------------
sub runtime_mode {
    my ($class, %args) = @_;
    my $root = defined $args{root} ? $args{root} : '';

    foreach my $path (@ENFORCE_FILES) {
        my $value = _first_line("$root$path");
        next unless defined $value;
        $value =~ s/\s+//g;
        return 'enforcing'  if $value eq '1';
        return 'permissive' if $value eq '0';
        return 'enabled';
    }

    return 'disabled';
}

#-----------------------------------------------------------------------------

=head3 config_mode

    Descriptions:
        Reports the mode that /etc/selinux/config selects for the next boot.
    Arguments:
        root - a prefix for the paths this module reads.
    Returns:
        The lower case value of the last SELINUX= line, or undef when the file
        has no such line and when the file is not there.
    Example:
        my $mode = xCAT::SELinux->config_mode();

=cut

#-----------------------------------------------------------------------------
sub config_mode {
    my ($class, %args) = @_;
    my $root = defined $args{root} ? $args{root} : '';

    my $mode;
    open(my $fh, '<', "$root$CONFIG_FILE") or return undef;
    while (my $line = <$fh>) {
        next if $line =~ /^\s*#/;
        $mode = lc($1) if $line =~ /^\s*SELINUX\s*=\s*(\S+)/;
    }
    close($fh);

    return $mode;
}

#-----------------------------------------------------------------------------

=head3 xcatconfig_action

    Descriptions:
        Decides what xcatconfig does about SELinux on this node. The answer
        asks for no change, because the SELinux policy belongs to the site.
        The caller reports the warning.
    Arguments:
        root - a prefix for the paths this module reads.
    Returns:
        A hash reference:
            mode        - the mode runtime_mode reports
            config_mode - the mode config_mode reports
            warning     - a message for the admin, or undef when SELinux is off
    Example:
        my $answer = xCAT::SELinux->xcatconfig_action();

=cut

#-----------------------------------------------------------------------------
sub xcatconfig_action {
    my ($class, %args) = @_;
    my $root = defined $args{root} ? $args{root} : '';

    my $mode = $class->runtime_mode(root => $root);
    my %answer = (
        mode        => $mode,
        config_mode => $class->config_mode(root => $root),
        warning     => undef,
    );

    return \%answer if $mode eq 'disabled';

    $answer{warning} =
      "SELINUX is $mode. xCAT does not change the SELinux mode or $CONFIG_FILE.";

    return \%answer;
}

sub _first_line {
    my ($path) = @_;

    open(my $fh, '<', $path) or return undef;
    my $line = <$fh>;
    close($fh);

    return $line;
}

1;
