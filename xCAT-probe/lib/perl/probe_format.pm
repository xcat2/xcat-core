# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package probe_format;

use strict;
use warnings;

my $DESIRED_WIDTH = 120;
my $DEFAULT_WIDTH = 80;
my $FLAG_WIDTH    = 6;

#-----------------------------------

=head3 screen_width

    Descriptions:
        Return the number of columns to format a message in.
    Arguments:
        raw: the output of 'tput cols', or undef when there is no terminal
    Returns:
        the column count

=cut

#-----------------------------------
sub screen_width {
    my ($raw) = @_;

    return $DEFAULT_WIDTH unless (defined($raw));
    return $raw =~ /(\d+)/ ? $1 + 0 : 0;
}

#-----------------------------------

=head3 render

    Descriptions:
        Lay out one message line of a probe subcommand.
    Arguments:
        line:        the line the subcommand printed, "[<flag>]:<message>"
        fullmsg:     true to wrap a long message, false to truncate it
        screenwidth: the column count from screen_width()
    Returns:
        (lines, mark). lines is an array reference. Print every line but the
        last with a newline. mark is what follows the last line: undef when
        the line carries no flag, and otherwise the mark to print, which
        already holds its newline.

=cut

#-----------------------------------
sub render {
    my ($line, $fullmsg, $screenwidth) = @_;

    my $msg = $line;
    my $flag;
    if ($line =~ /\[(\w+)\]\s*:(.+)/) {
        $flag = $1;
        $msg  = $2;
    }

    $msg =~ s/\t/        /g;
    my $maxlen = ($screenwidth > $DESIRED_WIDTH ? $DESIRED_WIDTH : $screenwidth);

    my @finalmsg = ();
    my $msglen   = length($msg);
    if ($msglen <= $maxlen) {
        if (!$fullmsg && $flag) {
            my $leftspace = $maxlen - length($msg);
            if ($leftspace < $FLAG_WIDTH) {
                $msg = substr($msg, 0, $maxlen - $FLAG_WIDTH);
                $msg =~ s/(.*).../$1\.\.\./g;
            }
        }
        push @finalmsg, $msg;
    } else {
        my $head = 0;
        my $tail = $maxlen;
        while ($head < $msglen) {
            push @finalmsg, substr($msg, $head, ($tail - $head));
            if (!$fullmsg) {
                if ($flag) {
                    $finalmsg[0] =~ s/(.*).........$/$1\.\.\./g;
                } else {
                    $finalmsg[0] =~ s/(.*)...$/$1\.\.\./g;
                }
                last;
            }
            $head = $tail;
            $tail = $head + ($maxlen <= ($msglen - $tail) ? $maxlen : ($msglen - $tail));
        }
    }

    return (\@finalmsg, undef) unless ($flag);

    my $last      = $finalmsg[-1];
    my $leftspace = $maxlen - length($last);
    my $debug     = ($flag =~ /debug/i) ? 1 : 0;
    my $mark      = '';
    if ($flag =~ /failed/i) {
        $mark = "[FAIL]\n";
    } elsif ($flag =~ /warning/i) {
        $mark = "[WARN]\n";
    } elsif ($flag =~ /ok/i) {
        $mark = "[ OK ]\n";
    } elsif ($debug) {
        $mark = "\n";
    } elsif ($flag =~ /info/i) {
        $mark = "[INFO]\n";
    }

    my $spacenum = 0;
    if (!$debug) {
        $spacenum = (($leftspace >= $FLAG_WIDTH) ? ($leftspace - $FLAG_WIDTH) : ($screenwidth - length($last) + $maxlen - $FLAG_WIDTH));
    }
    $finalmsg[-1] = $last . (" " x $spacenum);

    return (\@finalmsg, $mark);
}

1;
