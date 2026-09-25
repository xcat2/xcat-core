package XCAT::GenesisPayload;

# verify-genesis-payload runs this module in the rpm %install of xCAT-genesis-base and inside
# the Ubuntu build root, where only perl-base is installed. Use core modules only.
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(module_commands missing_paths check_payload main);

my $ME = 'verify-genesis-payload';

#-------------------------------------------------------------------------------

=head3 module_commands

    Descriptions: read back the names a dracut module installs.
        Only the top level of install() counts. A name under a condition is
        release-dependent, so the caller names it as a required path instead.
        An option to dracut_install (a word that starts with "-") is not a name.
    Arguments:
        $module_setup: the path of the module-setup.sh
    Returns:
        the names, sorted, each one once. A name that starts with "/" is an
        absolute path; any other name is a command.
        Dies with "verify-genesis-payload: cannot read <file>" when the file
        cannot be read, and with "verify-genesis-payload: no command name read
        from <file>" when install() names nothing.

=cut

#-------------------------------------------------------------------------------
sub module_commands {
    my ($module_setup) = @_;
    open(my $fh, '<', $module_setup)
      or die "$ME: cannot read $module_setup\n";

    my ($in_install, %names);
    while (my $line = <$fh>) {
        if ($line =~ /^install\(\)/) { $in_install = 1; next }
        $in_install = 0 if $in_install && $line =~ /^}/;
        next unless $in_install && $line =~ s/^    dracut_install //;
        $line =~ s/#.*//s;
        $names{$_} = 1 for grep { length && !/^-/ } split /\s+/, $line;
    }
    close($fh);

    die "$ME: no command name read from $module_setup\n" unless %names;
    return sort keys %names;
}

#-------------------------------------------------------------------------------

=head3 missing_paths

    Descriptions: list what a Genesis payload lacks.
        dracut_install reports a missing binary and returns, so the image can
        ship without it. This check runs on the extracted payload before it is
        packaged.
    Arguments:
        $have: code ref. It takes a path relative to the payload root and
               returns true when the payload carries it.
        %opt:
            required: paths relative to the payload root that the caller needs
            commands: names from module_commands. A bare command is looked
                      for in bin, sbin, usr/bin and usr/sbin; an absolute
                      path is looked for under the payload root.
            source:   the module the commands came from, for the message
            sshd:     the content of usr/sbin/sshd, or undef without one
    Returns:
        one "<path> (<reason>)" string per missing item, in the order checked.
        An empty list means the payload is complete.

=cut

#-------------------------------------------------------------------------------
sub missing_paths {
    my ($have, %opt) = @_;
    my @missing;

    for my $path (@{ $opt{required} || [] }) {
        push @missing, "$path (required by the build)" unless $have->($path);
    }

    for my $want (@{ $opt{commands} || [] }) {
        my $found =
            $want =~ m{^/(.*)}
          ? $have->($1)
          : scalar(grep { $have->("$_/$want") } qw(bin sbin usr/bin usr/sbin));
        push @missing, "$want (installed by $opt{source})" unless $found;
    }

    push @missing, "usr/sbin/sshd (Genesis is reached over ssh)"
      unless $have->('usr/sbin/sshd');
    push @missing, "usr/bin/mktemp (getdestiny makes its request file with it)"
      unless $have->('usr/bin/mktemp');

    # OpenSSH 9.8 split the per-connection work into sshd-session, which sshd execs by
    # absolute path. EL9 carries OpenSSH 9.9, so an image with sshd alone refuses every
    # connection.
    if (index($opt{sshd} // '', 'sshd-session') >= 0
        && !$have->('usr/libexec/openssh/sshd-session')
        && !$have->('usr/lib/openssh/sshd-session'))
    {
        push @missing,
          "usr/libexec/openssh/sshd-session (this sshd execs it for every connection)";
    }

    # tmux exits under the C locale. The hook then runs doxcat directly, but a Genesis
    # shell without tmux loses the console attach.
    if ($have->('usr/bin/tmux') && !$have->('usr/lib/locale/C.utf8/LC_CTYPE')) {
        push @missing,
          "usr/lib/locale/C.utf8/LC_CTYPE (tmux refuses to start without a UTF-8 locale)";
    }
    return @missing;
}

#-------------------------------------------------------------------------------

=head3 check_payload

    Descriptions: the command line of verify-genesis-payload, without the output:
        [--commands-from <module-setup.sh>] <payload-root> [required-path ...]
    Arguments:
        @args: the command line
    Returns:
        ($status, $message). $status is the exit status: 0 when the payload is
        complete, 1 when it lacks something, 2 on a usage error. $message is
        the text to print, one line or a list of missing items.

=cut

#-------------------------------------------------------------------------------
sub check_payload {
    my @args = @_;
    my $commands_from = '';
    while (@args) {
        if ($args[0] eq '--commands-from') {
            shift @args;
            $commands_from = shift(@args) // '';
        } elsif ($args[0] =~ /^--commands-from=(.*)/s) {
            $commands_from = $1;
            shift @args;
        } else {
            last;
        }
    }

    my $payload = shift(@args) // '';
    if ($payload eq '' || !-d $payload) {
        return (2, "$ME: not a payload directory: " . ($payload eq '' ? '<empty>' : $payload) . "\n");
    }

    my @commands;
    if ($commands_from ne '') {
        @commands = eval { module_commands($commands_from) };
        return (2, $@) if $@;
    }

    my $sshd;
    if (open(my $fh, '<:raw', "$payload/usr/sbin/sshd")) {
        local $/;
        $sshd = <$fh> // '';
        close($fh);
    }
    my @missing = missing_paths(sub { -e "$payload/$_[0]" },
        required => \@args,
        commands => \@commands,
        source   => $commands_from,
        sshd     => $sshd);
    return (1, "$ME: $payload is incomplete:" . join('', map { "\n  $_" } @missing) . "\n")
      if @missing;
    return (0, "$ME: $payload is complete\n");
}

#-------------------------------------------------------------------------------

=head3 main

    Descriptions: run check_payload and print its message: on STDOUT when the
        payload is complete, on STDERR otherwise.
    Arguments:
        @args: the command line
    Returns:
        the exit status from check_payload

=cut

#-------------------------------------------------------------------------------
sub main {
    my ($status, $message) = check_payload(@_);
    print { $status ? *STDERR : *STDOUT } $message;
    return $status;
}

1;
