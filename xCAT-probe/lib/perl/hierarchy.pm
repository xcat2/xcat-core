package hierarchy;

# IBM(c) 2016 EPL license http://www.eclipse.org/legal/epl-v10.html

BEGIN { $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr'; }
use lib "$::XCATROOT/probe/lib/perl";
use probe_utils;
use xCAT::ServiceNodeUtils;

use strict;
use Data::Dumper;
use IO::Select;
use File::Basename;
use POSIX ":sys_wait_h";

sub new {
    my $self  = {};
    my $class = shift;

    $self->{program_name} = basename("$0");

    my %dispatchcmd;
    $self->{dispatchcmd} = \%dispatchcmd;

    my @subjobpids = ();
    my @subjobfds  = ();
    my %subjobstates;
    my %fdnodemap;
    $self->{subjobpids}    = \@subjobpids;
    $self->{subjobfds}     = \@subjobfds;
    $self->{subjobstates}  = \%subjobstates;
    $self->{allsubjobdone} = 0;
    $self->{fdnodemap}     = \%fdnodemap;
    $self->{select}        = new IO::Select;

    bless($self, ref($class) || $class);
    return $self;
}

sub calculate_dispatch_cmd {
    my $self      = shift;
    my $noderange = shift;
    my $argv_ref  = shift;
    my $error_ref = shift;

    @{$error_ref} = ();

    my @snlist = xCAT::ServiceNodeUtils->getAllSN();
    if ($noderange) {
        my @nodes = probe_utils->parse_node_range($noderange);

        #if there is error in noderange
        if ($?) {
            my $error = join(" ", @nodes);
            if ($error =~ /Error: Invalid nodes and\/or groups in noderange: (.+)/) {
                push @{$error_ref}, "There are invaild nodes ($1) in command line attribute node range";
            } else {
                push @{$error_ref}, "There is error in command line attribute node range, please using nodels to check";
            }
            return 1;
        } else {

            #calculate the mapping between SN and the nodes which belong to it.
            chomp foreach (@nodes);
            my $snnodemap = xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes, "xcat", "MN");

            my %newsnnodemap;
            my $rst = 0;
            foreach my $sn (keys %$snnodemap) {
                if (grep(/^$sn$/, @snlist)) {   # the node just belong to one SN
                    push(@{ $newsnnodemap{$sn} }, @{ $snnodemap->{$sn} });
                } elsif ($sn =~ /(\w+),.+/) { # the node belong to more than one SN, count it into first SN
                    if (grep(/^$1$/, @snlist)) {
                        push(@{ $newsnnodemap{$1} }, @{ $snnodemap->{$sn} });
                    } else {
                        push @{$error_ref}, "The value $1  of 'servicenode' isn't a service node";
                        $rst = 1;
                    }
                } else { # the nodes don't belong to any SN will be handled by MN
                    push(@{ $newsnnodemap{mn} }, @{ $snnodemap->{$sn} });
                }
            }

            return 1 if ($rst);

            #print Dumper \%newsnnodemap;
            #generate new command for each SN, replace noderange
            foreach my $sn (keys %newsnnodemap) {
                my $nodes = join(",", @{ $newsnnodemap{$sn} });
                for (my $i = 0 ; $i <= @$argv_ref ; $i++) {
                    if ($argv_ref->[$i] eq "-n") {
                        $argv_ref->[ $i + 1 ] = $nodes;
                        last;
                    }
                }
                my $args = join(" ", @$argv_ref);
                $self->{dispatchcmd}->{$sn} = "$::XCATROOT/probe/subcmds/$self->{program_name} $args -H 2>&1";
            }
        }
    } else {

        #there isn't noderange input from STDIN, dispatch command to all SN if there are SN defined in MN
        #if there isn't SN defined in MN, just dispatch command to MN itself
        my $args = join(" ", @$argv_ref);
        $self->{dispatchcmd}->{mn} = "$::XCATROOT/probe/subcmds/$self->{program_name} $args -H 2>&1";
        if (@snlist) {
            my $sns  = join(",", @snlist);
            $self->{dispatchcmd}->{$sns} = "$::XCATROOT/probe/subcmds/$self->{program_name} $args -H 2>&1";
        }
    }

    return 0;
}

sub dispatch_cmd {
    my $self      = shift;
    my $noderange = shift;
    my $argv_ref  = shift;
    my $error_ref = shift;

    @$error_ref = ();
    my $rst = 0;

    $rst = $self->calculate_dispatch_cmd($noderange, $argv_ref, $error_ref);
    return $rst if ($rst);

    foreach my $target_server (keys %{ $self->{dispatchcmd} }) {
        my $subjobcmd = undef;
        if ($target_server eq "mn") {
            $subjobcmd = $self->{dispatchcmd}->{$target_server};
        } else {
            $subjobcmd = "xdsh $target_server -s \"$self->{dispatchcmd}->{$target_server}\" 2>&1";
        }

        #print "$subjobcmd\n";

        my $subjobfd;
        my $subjobpid;
        if (!($subjobpid = open($subjobfd, "$subjobcmd |"))) {
            push @{$error_ref}, "Fork process to dispatch cmd $subjobcmd to $target_server failed: $!";
            $rst = 1;
            last;
        }
        push(@{ $self->{subjobpids} }, $subjobpid);
        push(@{ $self->{subjobfds} },  $subjobfd);
        $self->{fdnodemap}->{$subjobfd} = $target_server;
    }

    if (@{ $self->{subjobpids} })
    {
        $self->{select}->add(\*$_) foreach (@{ $self->{subjobfds} });
        $| = 1;

        foreach (@{ $self->{subjobfds} }) {
            $self->{subjobstates}->{$_} = 0;
        }
    }

    return $rst;
}

sub read_reply {
    my $self            = shift;
    my $reply_cache_ref = shift;

    %$reply_cache_ref = ();

    my @hdls;
    while (!$self->{allsubjobdone} && !%$reply_cache_ref) {
        if (@hdls = $self->{select}->can_read(0)) {
            foreach my $hdl (@hdls) {
                foreach my $fd (@{ $self->{subjobfds} }) {
                    if (!$self->{subjobstates}->{$_} && $hdl == \*$fd) {
                        if (eof($fd)) {
                            $self->{subjobstates}->{$fd} = 1;
                        } else {
                            my $line;
                            chomp($line = <$fd>);

                            #print ">>>$line\n";
                            $line = "mn:$line" if ($self->{fdnodemap}->{$fd} eq "mn");
                            push @{ $reply_cache_ref->{ $self->{fdnodemap}->{$fd} } }, $line;
                        }
                    }
                }
            }
        }
        sleep 0.1;

        #check if all sub job have done
        $self->{allsubjobdone} = 1;
        $self->{allsubjobdone} &= $self->{subjobstates}->{$_} foreach (keys %{ $self->{subjobstates} });
    }

    if (%$reply_cache_ref) {
        return 1;
    } else {
        return 0;
    }
}

sub destory {
    my $self      = shift;
    my $error_ref = shift;

    my $rst = 0;
    @$error_ref = ();

    close($_) foreach (@{ $self->{subjobfds} });

    my %runningpid;
    $runningpid{$_} = 1 foreach (@{ $self->{subjobpids} });
    my $existrunningpid = 0;
    $existrunningpid = 1 if (%runningpid);

    my $try = 0;
    while ($existrunningpid) {

        #send terminal signal to all running process at same time
        #try INT 5 up to 5 times
        if ($try < 5) {
            foreach my $pid (keys %runningpid) {
                kill 'INT', $pid if ($runningpid{$pid});
            }

            #try TERM 5 up to 5 times
        } elsif ($try < 10) {
            foreach my $pid (keys %runningpid) {
                kill 'TERM', $pid if ($runningpid{$pid});
            }

            #try KILL 1 time
        } else {
            foreach my $pid (keys %runningpid) {
                kill 'KILL', $pid if ($runningpid{$pid});
            }
        }
        ++$try;

        sleep 1;

        #To check how many process exit, set the flag of exited process to 0
        foreach my $pid (keys %runningpid) {
            $runningpid{$pid} = 0 if (waitpid($pid, WNOHANG));
        }

        #To check if there are processes still running, if there are, try kill again in next loop
        $existrunningpid = 0;
        $existrunningpid |= $runningpid{$_} foreach (keys %runningpid);

        #just try 10 times, if still can't kill some process, give up
        if ($try > 10) {
            my $leftpid;
            foreach my $pid (keys %runningpid) {
                $leftpid .= "$pid " if ($runningpid{$pid});
            }
            push @{$error_ref}, "Can't stop process $leftpid, please handle manually.";
            $rst = 1;
            last;
        }
    }
    return $rst;
}




1;
