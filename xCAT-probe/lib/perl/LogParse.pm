package LogParse;

# IBM(c) 2016 EPL license http://www.eclipse.org/legal/epl-v10.html

BEGIN { $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr'; }
use lib "$::XCATROOT/probe/lib/perl";
use probe_global_constant;
use probe_utils;
use xCAT::NetworkUtils;

use strict;
use Data::Dumper;
use File::Path;
use File::Copy;
use Time::Local;
use File::Basename;

#------------------------------------------

=head3
    Description:
        The constructor of class 'LogParse'
    Arguments:
        Public attributes:
            $self->{verbose}:scalar, Offer verbose information, used for handling feature logic
        private attributes:
            $self->{log_open_info}: reference of a hash, used to save the log file operating information. 
            $self->{current_ref_year}: scalar, the year information of current time. such as 2016. Used for log time parsing
            $self->{current_ref_time}:  scalar, the epoch format of current time, such as 1472437250. Used for log time parsing

            $self->{debug}: Scalar, offer debug information, used for hanlde code logic, used by developer to debug function running 
            $self->{debuglogpath}: Scalar, the path of debug log files
            $self->{debuglogfd}: File descriptor of debug log files

            The structure of "log_open_info" hash is:
            $self->{log_open_info}->{<logfileshortname>}{openfd}  : The file descriptor of sepecific openning log file       
            $self->{log_open_info}->{<logfileshortname>}{rotate_file_list} : Array, all rotate file about related log file
            $self->{log_open_info}->{<logfileshortname>}{openning_file_index} : scalar, the index of openning file in rotate_file_list 
            $self->{log_open_info}->{<logfileshortname>}{next_read_point} : scalar, the read point of one log file, used by 'seek' function
            $self->{log_open_info}->{<logfileshortname>}{filetype} : scalar, the type of current log file, $::LOGTYPE_RSYSLOG or $::LOGTYPE_HTTP 
            $self->{log_open_info}->{<logfileshortname>}{next_start_time} : scalar, the next read time

    Returns:
       The instance of class
=cut

#------------------------------------------
sub new {
    my @args  = @_;
    my $self  = {};
    my $class = shift;
    $self->{verbose} = shift;

    my %log_open_info;
    $self->{log_open_info} = \%log_open_info;

    my ($sec, $min, $hour, $day, $mon, $year, $wday, $yday, $isdst) = localtime(time());
    $self->{current_ref_year} = $year;
    $self->{current_ref_time} = time();

    $self->{debug} = 0;
    if ($self->{debug}) {
        my $logfiledir = "/tmp/xcatprobedebug/";
        mkpath("$logfiledir") unless (-d "$logfiledir");
        $self->{debuglogpath} = $logfiledir;
        $self->{debuglogfd} = undef;
    }

    bless($self, ref($class) || $class);
    return $self;
}

#------------------------------------------

=head3
    Description:
        Public functuon. Calculate the possible host name of current server in rsyslog files.
    Arguments:
        NULL
    Returns:
        A array which contains the possible host names of current server
        Such as ("xxxxxx", "xxxxx.domain",....)
=cut

#------------------------------------------
sub obtain_candidate_mn_hostname_in_log {
    my $self = shift;

    my $svr_hostname_short = `hostname -s`;
    chomp($svr_hostname_short);
    my $svr_hostname_domain = `hostname -d`;
    chomp($svr_hostname_domain);

    my @candidate_svr_hostname_inlog;
    push(@candidate_svr_hostname_inlog, $svr_hostname_short);
    push(@candidate_svr_hostname_inlog, "$svr_hostname_short.$svr_hostname_domain");
    if ($self->{debug}) {
        my $tmpstr = join(" ", @candidate_svr_hostname_inlog);
        probe_utils->send_msg("stdout", "d", "The candidate MN hostname(s) in log are $tmpstr");
    }
    return @candidate_svr_hostname_inlog;
}



#------------------------------------------

=head3
    Description:
        Public function. Specify the log files scope which will be scaned.
    Arguments:
        NULL
    Returns:
        A hash which save all candidate log file information
        $candidate_log{<label>}{file}
        $candidate_log{<label>}{type}
        <label> : The short name of log file 
        file:  The log file name, including full path
        type: The valid types are $::LOGTYPE_HTTP and $::LOGTYPE_RSYSLOG, refer to 'probe_global_constant' for more information.
=cut

#------------------------------------------
sub obtain_log_file_list {
    my $self = shift;
    my %candidate_log;

    my @candidate_log_set;
    push @candidate_log_set, "/var/log/messages" if (-e "/var/log/messages");
    push @candidate_log_set, "/var/log/xcat/cluster.log" if (-e "/var/log/xcat/cluster.log");
    push @candidate_log_set, "/var/log/xcat/computes.log" if (-e "/var/log/xcat/computes.log");

    my $filename;
    foreach my $log (@candidate_log_set) {
        $filename = basename($log);
        $filename =~ s/(\w+)\.(\w+)/$1/g;
        $candidate_log{$filename}{file} = $log;
        $candidate_log{$filename}{type} = $::LOGTYPE_RSYSLOG;
    }

    my $httplog;
    if (-e "/var/log/httpd/access_log") {
        $httplog = "/var/log/httpd/access_log";
    } elsif (-e "/var/log/apache2/access_log") {
        $httplog = "/var/log/apache2/access_log";
    } elsif (-e "/var/log/apache2/access.log") {
        $httplog = "/var/log/apache2/access.log";
    }

    $candidate_log{http}{file} = $httplog;
    $candidate_log{http}{type} = $::LOGTYPE_HTTP;

    if ($self->{debug}) {
        my $exist_log_file_list;
        $exist_log_file_list .= "$candidate_log{$_}{file} " foreach (keys %candidate_log);
        probe_utils->send_msg("stdout", "d", "The log files to be scaned are $exist_log_file_list");
    }
    return \%candidate_log;
}

#------------------------------------------

=head3
    Description:
        Public function. Obtian logs which belong to a specific second from candidate log files.
    Arguments:
        the_time_to_load:(input attribute) the specific second.
        valid_one_second_log_set_ref: (output attribute) the space which save the vaild logs. A array of reference of hash. 
                                      Refer to fucnction "obtain_log_content" for the hash structure of one log.
        
    Returns:
        1: success
        0: failed
=cut

#------------------------------------------
sub obtain_one_second_logs {
    my $self                         = shift;
    my $the_time_to_load             = shift;
    my $valid_one_second_log_set_ref = shift;

    if ($self->{debug}) {
        my $logfile = "$self->{debuglogpath}/obtain_one_second_logs.$the_time_to_load";
        open($self->{debuglogfd}, "> $logfile");
    }

    #read log for the first time
    #need to find vaild log files and load them
    if (!%{ $self->{log_open_info} }) {

        #obtain all exist log files in current server
        #such as "/var/log/message, /var/log/xcat/cluster.log......."
        my $candidate_log_ref = $self->obtain_log_file_list();
        foreach my $loglabel (keys %$candidate_log_ref) {

            #obtain all rotate log file for one kind of log
            #such as "/var/log/message, /var/log/message-20160506, /var/log/message-20160507......."
            my $rotate_file_list_ref = $self->obtain_rotate_log_list($candidate_log_ref->{$loglabel}{file});

            #depending on target log time, find out should read from which rotate log file and which point of this log file
            my $read_start_point_ref = $self->obtain_valid_log_start_point($the_time_to_load, $rotate_file_list_ref, $candidate_log_ref->{$loglabel}{type});

            $self->{log_open_info}->{$loglabel}{rotate_file_list} = $rotate_file_list_ref;
            $self->{log_open_info}->{$loglabel}{openning_file_index} = $read_start_point_ref->{log_index};
            $self->{log_open_info}->{$loglabel}{next_read_point} = $read_start_point_ref->{log_start_point};
            $self->{log_open_info}->{$loglabel}{filetype} = $candidate_log_ref->{$loglabel}{type};
        }
    }

    if ($self->{debug}) {
        $self->debuglogger("------------Dumper self->{log_open_info}---------------");
        foreach my $loglabel (keys %{ $self->{log_open_info} }) {
            $self->debuglogger("[$loglabel]");
            my $rotate_file_list = join(" ", @{ $self->{log_open_info}->{$loglabel}{rotate_file_list} });
            $self->debuglogger("rotate_file_list: $rotate_file_list");
            $self->debuglogger("openning_file_index: $self->{log_open_info}->{$loglabel}{openning_file_index}");
            $self->debuglogger("next_read_point: $self->{log_open_info}->{$loglabel}{next_read_point}");
            $self->debuglogger("filetype: $self->{log_open_info}->{$loglabel}{type}");
            $self->debuglogger("openfd: $self->{log_open_info}->{$loglabel}{openfd}");
        }
        $self->debuglogger("--------------------------------------------------------\n");
    }

    foreach my $loglabel (keys %{ $self->{log_open_info} }) {
        my $fd;
        if (!exists($self->{log_open_info}->{$loglabel}{openfd})) {
            if (!open($fd, "$self->{log_open_info}->{$loglabel}{rotate_file_list}->[$self->{log_open_info}->{$loglabel}{openning_file_index}]")) {
                print "[error] open $self->{log_open_info}->{$loglabel}{rotate_file_list}->[$self->{log_open_info}->{$loglabel}{openning_file_index}] failed\n";
                return 1;
            }
        } else {
            $fd = $self->{log_open_info}->{$loglabel}{openfd};
        }

        if ($fd) {
            $self->debuglogger("[read $self->{log_open_info}->{$loglabel}{rotate_file_list}->[$self->{log_open_info}->{$loglabel}{openning_file_index}]]");
            my $next_read_point = $self->{log_open_info}->{$loglabel}{next_read_point};
            my $next_start_time = 0;
            my $read_eof        = 1;

            my $i = 0;
            for ($i = $self->{log_open_info}->{$loglabel}{openning_file_index} ; $i < @{ $self->{log_open_info}->{$loglabel}{rotate_file_list} } ; $i++) {
                if ($i == $self->{log_open_info}->{$loglabel}{openning_file_index}) {
                    seek($fd, $next_read_point, 0);
                } else {
                    open($fd, $self->{log_open_info}->{$loglabel}{rotate_file_list}->[$i]);
                    $next_read_point = 0;
                }

                while (<$fd>) {
                    chomp;
                    $self->debuglogger("[$loglabel]read: $_");
                    my $log_content_ref = $self->obtain_log_content($self->{log_open_info}->{$loglabel}{filetype}, $_);

                    #if read the log whoes time bigger than target time, stop to read
                    $self->debuglogger("\t$log_content_ref->{time}   $the_time_to_load");
                    if ($log_content_ref->{time} > $the_time_to_load) {
                        $next_start_time = $log_content_ref->{time};
                        $read_eof        = 0;
                        $self->debuglogger("\tlast");
                        last;
                    } else {

                        #if read the log whoes time is equal the target time, save it
                        push @$valid_one_second_log_set_ref, $log_content_ref;

                        #adjust the next read point to next line
                        my $len = length($_) + 1;
                        $next_read_point += $len;
                        $self->debuglogger("\tnext_read_point + $len");
                    }
                }

                if ($read_eof) {

                    #reach the end of current openning file, maybe there are vaild log in next rotate file,
                    #prepare to search next rotate file
                    close($fd);
                    $self->debuglogger("\tread_eof");
                } else {

                    #have found all vaild log in current openning fd
                    $self->{log_open_info}->{$loglabel}{openfd} = $fd;
                    $self->{log_open_info}->{$loglabel}{openning_file_index} = $i;
                    $self->{log_open_info}->{$loglabel}{next_read_point} = $next_read_point;
                    $self->{log_open_info}->{$loglabel}{next_start_time} = $next_start_time;
                    $self->debuglogger("\tfound all vaild logs");
                    last;
                }
            }    #end ratate_files loop

            if ($i == @{ $self->{log_open_info}->{$loglabel}{rotate_file_list} } && $read_eof == 1) {
                $self->{log_open_info}->{$loglabel}{openfd} = 0;
                $self->{log_open_info}->{$loglabel}{next_start_time} = 9999999999;
                $self->debuglogger("read out all rotate files");
            }
        }    #end $fd
    }    #end log_open_info loop

    #delete duplicate logs
    $self->delete_duplicate_log($valid_one_second_log_set_ref);

    if ($self->{debug}) {
        close($self->{debuglogfd});
    }

    return 0;
}

#------------------------------------------

=head3
    Description:
        Private function. Depending on target log file name, obtain all related rotated log files.
        For example, if the target file is '/var/log/messages', the function should return all rotated '/var/log/messages' files.
        Such as '/var/log/messages-20160101', '/var/log/messages-20160102'.........
        The all related log files should save into a array in order, the latest log file should be in the tail and the oldest one is in the head of array.
        For example, the array should look like ("/var/log/messages-20160103", "/var/log/messages-20160104", "/var/log/messages-20160105", "/var/log/messages");
        Finally, this function return the reference of the array.

    Arguments:
        file_name: (input attribute) the target log file name, including full path.
        rotate_file_list_ref: (output attibute) the reference of the array which include all related log files name.
    Returns:
        0: success
        1: failed
=cut

#------------------------------------------
sub obtain_rotate_log_list {
    my $self      = shift;
    my $file_name = shift;

    my @files     = ();
    my $file_path = dirname($file_name);

    my @files_all = glob("$file_path/*");

    my @files_grep = grep /$file_name.+\d$/, @files_all;

    @files = sort { -M "$b" <=> -M "$a" } @files_grep;

    push @files, $file_name;

    return \@files;
}

#------------------------------------------

=head3
    Description:
       Private function. Depending on the reference start time. go through all rotate file list, find out where should start to read log.
       I.e. start from which point of which log file.

    Arguments:
        start_time: (input attribute) the target start time.
        rotate_file_list_ref: (input attibute) the reference of the array which include all related log files name.
        log_type: (input attribute) The type of log file

    Returns:
        start_point: a hash which include the index of start file and the start point of the file
                     %start_point{log_index}: the index of start file in the rotate file list
                     %start_point{log_start_point}: where start to read log from. this value will be used by "seek" function
=cut

#------------------------------------------
sub obtain_valid_log_start_point {
    my $self                 = shift;
    my $start_time           = shift;
    my $rotate_file_list_ref = shift;
    my $log_type             = shift;

    my %start_point;
    my @files      = @{$rotate_file_list_ref};
    my $list_index = @files - 1;

    my $fd;
    my $file;
    my $filetype;
    my $line;

    $start_point{log_index}       = 0;
    $start_point{log_start_point} = 0;
    while (@files) {
        $file     = pop(@files);
        $filetype = `file $file 2>&1`;
        chomp($filetype);
        if (!open($fd, "$file")) {
            print "open $file failed\n";
            $list_index--;
            next;
        }

        if ($line = <$fd>) {
            my %log_content = %{ $self->obtain_log_content($log_type, $line, 0) };
            if ($start_time <= $log_content{time}) {
                $list_index--;
                next;
            } else {
                $start_point{log_index} = $list_index;
                seek($fd, 0, 2);
                my $tail           = tell;
                my $head           = 0;
                my $lasttail       = $tail;
                my $file_tail      = $tail;
                my $tmp_start_time = $start_time - 1;
                my $historynum     = 0;

                while ($head <= $tail) {
                    my $middle = int(($tail - $head) / 2) + $head;
                    seek($fd, $middle, 0);
                    $line = <$fd>;
                    $middle += length($line);
                    last unless ($line = <$fd>);
                    my %log_content = %{ $self->obtain_log_content($log_type, $line, 0) };
                    if ($tmp_start_time == $log_content{time}) {
                        $historynum = $middle;
                        last;
                    } elsif ($tmp_start_time < $log_content{time}) {
                        $tail = $middle;
                        last if ($tail == $lasttail);
                        $lasttail = $tail;
                    } else {
                        $head = $middle;
                    }
                }

                $historynum = $head unless ($historynum);

                while ($historynum < $file_tail) {
                    seek($fd, $historynum, 0);
                    $line = <$fd>;
                    my %log_content = %{ $self->obtain_log_content($log_type, $line, 0) };
                    if ($start_time <= $log_content{time}) {
                        last;
                    } elsif ($start_time > $log_content{time}) {
                        $historynum += length($line);
                    }
                }
                $start_point{log_start_point} = $historynum;
                last;
            }
        }
    }
    return \%start_point;

}


#------------------------------------------

=head3
    Description:
        Convert one line original log which comes from log file to a hash. 

    Arguments:
        log_type     :(input attribute) valid log type are $::LOGTYPE_RSYSLOG and $::LOGTYPE_HTTP 
        original_log :(input attribute) one line log in real log file

    Returns:
        log_content_ref: (output attribute) the reference of a hash structure

        The hash structure which contain log message is
        %log_content
        $log_content{time}   : the timestamp of log, the format is epoch_seconds
        $log_content{sender} : the sender of log
        $log_content{label}  : the label of log, such as $::LOGLABEL_DHCPD, $::LOGLABEL_TFTP.... refer to "probe_global_constant" for all kinds vaild labels 
        $log_content{msg}    : the main message of log
=cut

#------------------------------------------
sub obtain_log_content {
    my $self         = shift;
    my $log_type     = shift;
    my $original_log = shift;

    my %log_content = ();
    my @split_line = split(/\s+/, $original_log);

    if ($log_type == $::LOGTYPE_RSYSLOG) {
        if ($split_line[0] =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(.+)-(.+)/) {
            $log_content{time} = $self->convert_to_epoch_seconds($split_line[0]);
            if (!xCAT::NetworkUtils->isIpaddr($split_line[1])) {
                my @sender_tmp = split(/\./, $split_line[1]);
                $log_content{sender} = $sender_tmp[0];
            } else {
                $log_content{sender} = $split_line[1];
            }
            if ($split_line[2] =~ /dhcpd/i) {
                $log_content{label} = $::LOGLABEL_DHCPD;
            } elsif ($split_line[2] =~ /in.tftpd/i) {
                $log_content{label} = $::LOGLABEL_TFTP;
            } elsif ($split_line[2] =~ /^xcat/i) {
                $log_content{label} = $::LOGLABEL_XCAT;
            } else {
                $log_content{label} = $::LOGLABEL_UNDEF;
            }
            $log_content{msg} = join(" ", @split_line[ 3 .. @split_line - 1 ]);
        } else {
            my $timestamp = join(" ", @split_line[ 0 .. 2 ]);
            $log_content{time}   = $self->convert_to_epoch_seconds($timestamp);
            if (!xCAT::NetworkUtils->isIpaddr($split_line[3])) {
                my @sender_tmp = split(/\./, $split_line[3]);
                $log_content{sender} = $sender_tmp[0];
            } else {
                $log_content{sender} = $split_line[3];
            }
            if ($split_line[4] =~ /dhcpd/i) {
                $log_content{label} = $::LOGLABEL_DHCPD;
            } elsif ($split_line[4] =~ /in.tftpd/i) {
                $log_content{label} = $::LOGLABEL_TFTP;
            } elsif ($split_line[4] =~ /^xcat/i) {
                $log_content{label} = $::LOGLABEL_XCAT;
            } else {
                $log_content{label} = $::LOGLABEL_UNDEF;
            }
            $log_content{msg} = join(" ", @split_line[ 5 .. @split_line - 1 ]);
        }
    } elsif ($log_type == $::LOGTYPE_HTTP) {
        $split_line[3] =~ s/^\[(.+)/$1/g;
        $log_content{time}   = $self->convert_to_epoch_seconds($split_line[3]);
        if (!xCAT::NetworkUtils->isIpaddr($split_line[0])) {
            my @sender_tmp = split(/\./, $split_line[0]);
            $log_content{sender} = $sender_tmp[0];
        } else {
            $log_content{sender} = $split_line[0];
        }
        $log_content{label}  = $::LOGLABEL_HTTP;
        $log_content{msg}    = join(" ", @split_line[ 5 .. @split_line - 1 ]);
    }
    return \%log_content;
}

#------------------------------------------

=head3
    Description:
        Convert input time format to the number of non-leap seconds since whatever time the system considers to be the epoch
    Arguments:
        timestr: the time format need to be converted
    Returns:
        the number of non-leap seconds since whatever time the system considers to be the epoch
=cut

#------------------------------------------
sub convert_to_epoch_seconds {
    my $self    = shift;
    my $timestr = shift;

    my $yday;
    my $mday;
    my $dday;
    my $h;
    my $m;
    my $s;
    my $epoch_seconds = -1;
    my %monthsmap = ("Jan" => 0, "Feb" => 1, "Mar" => 2, "Apr" => 3, "May" => 4, "Jun" => 5, "Jul" => 6, "Aug" => 7, "Sep" => 8, "Oct" => 9, "Nov" => 10, "Dec" => 11);

    # The time format looks like "2016-08-29T03:30:18.259287-04:00"
    if ($timestr =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(.+)-(.+)/) {
        ($yday, $mday, $dday, $h, $m, $s) = ($1 + 0, $2 - 1, $3 + 0, $4 + 0, $5 + 0, $6 + 0);
        $epoch_seconds = timelocal($s, $m, $h, $dday, $mday, $yday);

        # The time format looks like "Aug 15 02:43:31"
    } elsif ($timestr =~ /(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)/) {
        ($mday, $dday, $h, $m, $s) = ($1, $2, $3, $4, $5);
        $yday = $self->{current_ref_year};
        $epoch_seconds = timelocal($s, $m, $h, $dday, $monthsmap{$mday}, $yday);
        if ($epoch_seconds > $self->{current_ref_time}) {
            --$yday;
            $epoch_seconds = timelocal($s, $m, $h, $dday, $monthsmap{$mday}, $yday);
        }

        # The time format looks like "15/Aug/2016:01:10:24"
    } elsif ($timestr =~ /(\d+)\/(\w+)\/(\d+):(\d+):(\d+):(\d+)/) {
        $epoch_seconds = timelocal($6, $5, $4, $1, $monthsmap{$2}, $3);
    }
    return $epoch_seconds;
}


#------------------------------------------

=head3
    Description:
        Private function. After obtain one second logs. deleted these duplicate logs.
    Arguments:
        vaild_log_set_ref:(input/output attribute) The reference of the log set which will be scaned to delete duplicate log
    Returns:
        NULL
=cut

#------------------------------------------
sub delete_duplicate_log {
    my $self              = shift;
    my $vaild_log_set_ref = shift;

    my $log_index = @$vaild_log_set_ref - 1;
    my @delete_index;
    for (my $i = $log_index ; $i > 0 ; $i--) {
        for (my $j = 0 ; $j < $i ; $j++) {
            if (($vaild_log_set_ref->[$i]->{time} == $vaild_log_set_ref->[$j]->{time}) &&
                ($vaild_log_set_ref->[$i]->{label} == $vaild_log_set_ref->[$j]->{label}) &&
                ($vaild_log_set_ref->[$i]->{sender} eq $vaild_log_set_ref->[$j]->{sender}) &&
                ($vaild_log_set_ref->[$i]->{msg} eq $vaild_log_set_ref->[$j]->{msg})) {
                if (!grep { $_ eq $i } @delete_index) {
                    push @delete_index, $i;
                    last;
                }
            }
        }
    }

    foreach (@delete_index) {
        my @new_list = ();
        splice(@$vaild_log_set_ref, $_, 1, @new_list);
    }

    if ($self->{debug}) {
        $self->debuglogger("------------After delete duplicate logs---------------");
        foreach my $log_ref (@{$vaild_log_set_ref}) {
            $self->debuglogger("$log_ref->{msg}");
        }
    }
}

#------------------------------------------

=head3
    Description:
        Public function. Obtain the next second when should get logs from
    Arguments:
        NULL
    Returns:
        The second when should get logs from
=cut

#------------------------------------------
sub obtain_next_second {
    my $self = shift;

    my $next_start_time = 9999999999;
    foreach my $loglabel (keys %{ $self->{log_open_info} }) {
        if ($self->{log_open_info}->{$loglabel}{next_start_time} < $next_start_time) {
            $next_start_time = $self->{log_open_info}->{$loglabel}{next_start_time};
        }
    }
    return $next_start_time;
}

#------------------------------------------

=head3
    Description:
        The destructor of class 'LogParse'
    Arguments:
        NULL
    Returns:
        NULL
=cut

#------------------------------------------
sub destory {
    my $self = shift;
    foreach my $loglabel (keys %{ $self->{log_open_info} }) {
        if ($self->{log_open_info}->{$loglabel}{openfd}) {
            close($self->{log_open_info}->{$loglabel}{openfd});
        }
    }

    if ($self->{debuglogfd}) {
        close($self->{debuglogfd});
    }
}

#------------------------------------------

=head3
    Description:
        Private function. Used for log debug information to disk. 
    Arguments:
        $msg : The massage which will be logged into log file. 
    Returns:
        NULL
=cut

#------------------------------------------
sub debuglogger {
    my $self = shift;
    my $msg  = shift;
    if ($self->{debug}) {
        print {$self->{debuglogfd}} "$msg\n";
    }
}
1;

