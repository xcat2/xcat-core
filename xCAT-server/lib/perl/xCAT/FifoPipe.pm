#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::FifoPipe;

BEGIN {
    $::XCATROOT =
      $ENV{'XCATROOT'} ? $ENV{'XCATROOT'}
      : -d '/opt/xcat' ? '/opt/xcat'
      :                  '/usr';
}

use lib "$::XCATROOT/lib/perl";

use strict;
use xCAT::Table;
use xCAT::MsgUtils;
use Data::Dumper;
use POSIX;


use constant PIPE_SIZE => 4096;    # use ulimit -a to check

#-------------------------------------------------------

=head3  _create_pipe
  Create the pipe file if not exists. This function is a
  private method in FifoPipe.
  Input:
        $pipe_file: the file path of the pipe file
  Return:
        -1: Unexpected error
        0: Create success
  Usage example:
        my $fifo_path = '/tmp/fifopipe/pipe1;
        _create_pipe($pipe_file);
=cut

#-------------------------------------------------------
sub _create_pipe {
    my $pipe_file = shift;
    unless (-p $pipe_file) {
        if (-e _) {
            xCAT::MsgUtils->message("S", "$pipe_file is not a pipe file.");
            return -1;
        } else {
            unless (POSIX::mkfifo($pipe_file, 0660)) {
                xCAT::MsgUtils->message("S", "Can not create fifo pipe: $pipe_file");
                return -1;
            }
            xCAT::MsgUtils->message("I", "Create $pipe_file as a pipe file.");
        }
    }
    return 0;
}

#-------------------------------------------------------

=head3  recv_message
  Use fifo pipe to receive the message
  Input:
        $class: FifoPipe class
        $pipe_file: the file path of the pipe file
        $buf_ptr: A pointer to the message buffer array
  Return:
        -1: Unexpected error
        count: Number of message getting from fifo pipe
  Usage example:
         my $fifo_path = '/tmp/fifopipe/pipe1;
         my @buf = ();
         xCAT::FifoPipe->recv_message($fifo_path, \@buf);
=cut

#-------------------------------------------------------
sub recv_message {
    my $class         = shift;
    my $pipe_file     = shift;
    my $buf_array_ptr = shift;
    my ($len, $pipe, $tmp);
    my $count = 0;
    my $rt    = -1;

    my $read_pipe_func = sub {
        my $pipe     = shift;
        my $buf_ptr  = shift;
        my $len      = shift;
        my $read_len = $len;
        my ($rt, $tmp);


        while (($rt = read($pipe, $tmp, $read_len)) > 0) {
            $read_len -= $rt;
            ${$buf_ptr} .= $tmp;
            if ($read_len == 0) {
                return $len;
            }
        }
        if (!defined($rt)) {
            xCAT::MsgUtils->message("S", "Read pipe $pipe_file error return code=$rt.");
            return -1;
        }
        return 0;
    };    # end of read_pipe_func

    if (_create_pipe($pipe_file)) {
        return -1;
    }

    # NOTE(chenglch) if multiple process are writing the fifo pipe
    # at the same time, the open call of reader will be blocked only
    # once, but multiple messages should be retrived.
    $rt = open($pipe, '<', $pipe_file);
    unless ($rt) {
        xCAT::MsgUtils->message("S", "open $pipe_file error");
        return -1;
    }

    while (&$read_pipe_func($pipe, \$len, 8) > 0) {
        $len = unpack("A8", $len);
        if (($rt = &$read_pipe_func($pipe, \$tmp, $len)) < 0) {
            return -1;
        }
        if ($rt != $len) {
            xCAT::MsgUtils->message("S", "Read pipe $pipe_file error, uncomplete.");
            return -1;
        }
        ${$buf_array_ptr}[$count] = $tmp;
        $count++;
    }
    close($pipe);
    return $count;
}

#-------------------------------------------------------

=head3  send_message
  Send message to fifo pipe
  Input:
        $class: FifoPipe class
        $pipe_file: the file path of the pipe file
        $buf: A buf string
  Return:
        -1: Unexpected error
        0: send success
  Usage example:
         my $fifo_path = '/tmp/fifopipe/pipe1;
         my $buf = "hellow fifo pipe";
         xCAT::FifoPipe->send_message($fifo_path, $buf);
=cut

#-------------------------------------------------------
sub send_message {
    my $class     = shift;
    my $pipe_file = shift;
    my $buf       = shift;
    my $pipe;

    # WARNING: the lenth of the buf should not be larger than PIPE_BUF,
    # otherwise the write opration for fifo pipe can not be
    # looked as a atomic opration.
    my $len = length($buf);
    if ($len > PIPE_SIZE - 8) {
        xCAT::MsgUtils->message("W", "The size of message is larger than 4088 bytes.");
    }
    my $tmp = pack("A8", $len);
    $buf = $tmp . $buf;
    $len += 8;
    if (_create_pipe($pipe_file)) {
        return -1;
    }
    my $rt = sysopen(PIPEHANDLE, $pipe_file, O_WRONLY);
    unless ($rt) {
        xCAT::MsgUtils->message("S", "open $pipe_file error");
        return -1;
    }
    while (($rt = syswrite(PIPEHANDLE, $buf, $len)) > 0) {
        $len -= $rt;
        if ($len == 0) {
            last;
        }
    }
    if (!defined($rt)) {
        xCAT::MsgUtils->message("S", "Write $pipe_file error");
        return -1;
    }
    if ($len != 0) {
        xCAT::MsgUtils->message("S", "Write $pipe_file error");
        return -1;
    }

    #print {$pipe} $buf;
    close(PIPEHANDLE);
    return 0;
}

#-------------------------------------------------------

=head3  remove_pipe
  Remove the fifo pipe file if pipe file exists.
  Input:
        $class: FifoPipe class
        $pipe_file: the file path of the pipe file

  Usage example:
         my $fifo_path = '/tmp/fifopipe/pipe1;
         xCAT::FifoPipe->remove_pipe($fifo_path);
=cut

#-------------------------------------------------------
sub remove_pipe {
    my $class     = shift;
    my $pipe_file = shift;
    xCAT::MsgUtils->message("I", "Remove fifo pipe file $pipe_file");
    if (-p $pipe_file) {
        unlink($pipe_file);
    }
}


1;
