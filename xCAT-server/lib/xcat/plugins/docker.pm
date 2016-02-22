# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle docker
=cut

#-------------------------------------------------------

package xCAT_plugin::docker;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use POSIX qw(WNOHANG nice);
use POSIX qw(WNOHANG setsid :errno_h);
use Errno;
use IO::Select;
use MIME::Base64 qw(encode_base64);
require IO::Socket::SSL; IO::Socket::SSL->import('inet4');
use Time::HiRes qw(gettimeofday sleep);
use Fcntl qw/:DEFAULT :flock/;
use File::Path;
use File::Copy;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use HTTP::Headers;
use HTTP::Request;
use HTTP::Response; 
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
use File::Basename;
use Cwd;
use xCAT::Usage;
use JSON;
#use Data::Dumper;

my $verbose;
my $global_callback;

my $select = IO::Select->new();

#-------------------------------------------------------
=head3  The hash variable to store node related SSL connection and state information 

 The structure is like this
 %node_hash_variable = (
     $SSL_connection => {
         node => $node,
         state => $current_state,
         state_machine_engine => $state_machine_for_the_node,
         total_len => $total_len,
         get_len => $get_len,
         data_buf => $data,
     },
 );

=cut
#-------------------------------------------------------

my %node_hash_variable = ();

#-------------------------------------------------------
=head3  The hash variable to store node parameters to create docker container

 The structure is like this
 %node_create_variable = (
     $node => {
         image=>$nodetype.provmethod,
         cmd=>$nodetype.provmethod,
         ip=>$host.ip,    
         mac=>$mac.mac,
         cpu=>$vm.cpus
         memory=>$vm.memory
         flag=>$vm.othersettings
     },
 );

=cut
#-------------------------------------------------------

my %node_create_variable = ();

# The counter to record how many request have been send and responses are expected.
my $pending_res = 0;

# The counter to record concurrent openting SSL connection numbers
my $concurrent_ssl_sessions = 0;

# The function point used for mkdocker to generate http request, for other cmd it will point to &genreq;
my $genreq_ptr = \&genreq;

# The vairables below are used to update attributes
my $vmtab; # vm.othersettings
my $nodelisttab; # nodelist.status
my $nodetypetab; #nodetype.provmethod

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return( {docker=>"docker",
            rpower => 'nodehm:mgt',
            mkdocker => 'nodehm:mgt',
            rmdocker => 'nodehm:mgt',
            lsdocker => 'nodehm:mgt=docker|ipmi',
           } );
}



#-------------------------------------------------------

=head3 The hash table to store mapping of commands and its state_machine_engine
    The structure is like this:
        command => {
            option1 => {
                state_machine_engine => \&state_machine_engine,
                init_method => GET/POST/PUT/DELETE,
                init_url => url,
            },
        },

=cut

#-------------------------------------------------------

my %command_states = (
    rpower => {
        start => {
            state_machine_engine => \&single_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/start",
            init_state => "INIT_TO_WAIT_FOR_START_DONE",
        }, 
        stop => {
            state_machine_engine => \&single_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/stop",
            init_state => "INIT_TO_WAIT_FOR_STOP_DONE",
        },        
        restart => {
            state_machine_engine => \&single_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/restart",
        },        
        pause => {
            state_machine_engine => \&single_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/pause",
        },
        unpause => {
            state_machine_engine => \&single_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/unpause",
        },
        state => {
            state_machine_engine => \&single_state_engine,
            init_method => "GET",
            init_url => "/containers/#NODE#/json",
            init_state => "INIT_TO_WAIT_FOR_QUERY_STATE_DONE",
        },
    },
    mkdocker => {
        all => {
            state_machine_engine => \&single_state_engine,
            init_method => "POST",
            init_url => "/containers/create?name=#NODE#",
            init_state => "INIT_TO_WAIT_FOR_CREATE_DONE"
        },
    },
    rmdocker => {
        force => {
            state_machine_engine => \&single_state_engine,
            init_method => "DELETE",
            init_url => "/containers/#NODE#?force=1",
        },
        all => {
            state_machine_engine => \&single_state_engine,
            init_method => "DELETE",
            init_url => "/containers/#NODE#",
        },
    },
    lsdocker => {
        all => {
            state_machine_engine => \&single_state_engine,
            init_method => "GET",
            init_url => "/containers/#NODE#/json?",
            init_state => "INIT_TO_WAIT_FOR_QUERY_DOCKER_DONE",
        },
        log => {
            state_machine_engine => \&single_state_engine,
            init_method => "GET",
            init_url => "/containers/#NODE#/logs?stderr=1&stdout=1",
            init_state => "INIT_TO_WAIT_FOR_QUERY_LOG_DONE",
        },
    },
);

#-------------------------------------------------------

=head3 http_state_code_info 
  The function to deal with http response code
  Input:
        $state_code: the http response code
        $curr_status: the current status for the SSL connection that receive the http response
                      It is used for rpower start/stop since they use the same state_code 304 to indicate no modification.
  Return:
        A string to explain the http response code
  Usage example:
        http_state_code_info('304', "INIT_TO_WAIT_FOR_START_DONE") -> "Already started"
        http_state_code_info('304', "INIT_TO_WAIT_FOR_STOP_DONE") -> "Already stoped"
=cut  

#-------------------------------------------------------

sub http_state_code_info {
    my $state_code = shift;
    my $curr_status = shift;
    if ($state_code =~ /20\d/) {
        return [0, "success"];
    }
    elsif ($state_code eq '304')  {
        if (defined $curr_status)  {
            if ($curr_status eq "INIT_TO_WAIT_FOR_START_DONE") {
                return [0, "container already started"];
            }
            else {
                return [0, "container already stoped"];
            }
        }
        else {
            return [1, "unknown http status code $state_code"];
        }
    }
    elsif ($state_code eq '404') {
        return [1, "no such container"];
    }
    elsif ($state_code eq '406') {
        return [1, "impossible to attach (container not running)"];
    }
    elsif ($state_code eq '500') {
        return [1, "server error"];
    }
    return [1, "unknown http status code $state_code"];
}

#-------------------------------------------------------

=head3 single_state_engine

  The state_machine_engine to deal with http response
  Input:
        $sockfd: The SSL connection from which the http response is returned
        $data: The http response 
  Return:
        If there are any errors or msg, they will be outputed directly.
        Else, nothing returned.
  Usage example:
        single_state_engine($sockfd, HTTP Response data);

=cut  

#-------------------------------------------------------

sub single_state_engine {
    my $sockfd = shift;
    my $data = shift;
    if (!defined $node_hash_variable{$sockfd}) {
        return;
    }
    my $info_flag = 'data';
    my $get_another_pkg = 0;
    my $node = $node_hash_variable{$sockfd}->{node};
    my $curr_state = $node_hash_variable{$sockfd}->{state};
    my $data_buf = $node_hash_variable{$sockfd}->{data_buf};
    my $data_total_len = $node_hash_variable{$sockfd}->{total_len};
    my $data_get_len = $node_hash_variable{$sockfd}->{get_len};
    my $data_chunked = $node_hash_variable{$sockfd}->{chunked};
    my @chunked_array = ();
    # The code logic to deal with http response and state machine
    #Need to Dumper to log file later
    my $res = HTTP::Response->parse($data);
    #print Dumper($res);
    my $content = undef;
    # Deal with the scenario that a http response is splited into multiple pkgs
    unless ($res->code and $res->code =~ /\d{3}/) {
        my $len = length($data);
        if (defined($data_chunked)) {
            $content = $data;
            $res = HTTP::Response->parse($data_buf);
        }
        elsif (!defined($data_buf) or !defined($data_total_len) or !defined($data_get_len) or ($data_get_len + $len > $data_total_len)) {
            $global_callback->({node=>[{name=>[$node],error=>["Incorrect data received"],errorcode=>[1]}]});
            $concurrent_ssl_sessions--;
            $select->remove($sockfd);
            close($sockfd);
            delete($node_hash_variable{$sockfd}); 
            return;
        }
        else {
            my $len = length($data);
            if ($data_get_len + $len < $data_total_len) {
                $node_hash_variable{$sockfd}->{get_len} += $len;
                $node_hash_variable{$sockfd}->{data_buf} .= $data;
                $pending_res++;
                return;
            }
            else { # Exactly all the data are received
                $res = HTTP::Response->parse($data_buf.$data);
                delete $node_hash_variable{$sockfd}->{data_buf};
                delete $node_hash_variable{$sockfd}->{total_len};
                delete $node_hash_variable{$sockfd}->{get_len};
            }
        }
    }

    if (!defined($content) and $res->content()) {
        $content = $res->content();
    }
    my $get_content_len = length($content);
    my $content_length = $res->header('content-length');
    if (defined($content_length) and $get_content_len < $content_length) {
        $node_hash_variable{$sockfd}->{data_buf} = $data;
        $node_hash_variable{$sockfd}->{total_len} = $content_length;
        $node_hash_variable{$sockfd}->{get_len} = $get_content_len;
        $pending_res++;
        return;
    }

    my $encoding_flag = $res->header('transfer-encoding');
    if (defined($encoding_flag) and $encoding_flag eq 'chunked') {
        $node_hash_variable{$sockfd}->{chunked} = 1;
        $data_chunked = 1;
        if ($get_content_len < 3) {
            $node_hash_variable{$sockfd}->{data_buf} = $data;
            $pending_res++;
            return;
        }
    }  
    if (defined($data_chunked)) {
        while (length($content)) {
            my $split_pos = index($content, "\r\n");
            my $length_string = substr($content, 0, $split_pos);
            my $data_length = hex($length_string);
            if ($data_length lt 2) {
                if ($data_length eq 0)  {
                    push @chunked_array, '0';
                }
                last; 
            }
            push @chunked_array, $length_string;
            push @chunked_array, substr($content, $split_pos + 2, $data_length);
            $content = substr($content, $split_pos + 4 + $data_length); 
        }
    }
    my @msg = ();
    $msg[0] = &http_state_code_info($res->code, $curr_state);
    unless ($res->is_success) {
        if ($content ne '') {
            $msg[0]->[1] = "$content";
        }
    }
    if ($curr_state eq "INIT_TO_WAIT_FOR_QUERY_STATE_DONE")  {
        if ($res->is_success) {
            my $node_state = undef;
            if ($data_chunked) {
                my $length = shift @chunked_array;
                while ($length) {
                    my $content_hash = decode_json (shift @chunked_array);
                    if (defined($content_hash->{'State'}->{'Status'})) {
                        $node_state = $content_hash->{'State'}->{'Status'};
                        last;
                    }
                    $length = shift @chunked_array;
                }
                if (!defined($node_state) and $length) {
                    $get_another_pkg = 1;
                }
            }
            else {
                my $content_hash = decode_json $content;
                $node_state = $content_hash->{'State'}->{'Status'};
            }
            if (defined($node_state)) {
                if ($nodelisttab) {
                    $nodelisttab->setNodeAttribs($node, {status=>$node_state});
                }
                $msg[0] = [0, $node_state];
            }
            elsif (!$get_another_pkg) {
                $msg[0] = [1, "Can not get status"];
            }
        }
        elsif ($res->code eq '404') {
            if ($nodelisttab) {
                $nodelisttab->setNodeAttribs($node, {status=>''});
            }
        }
    } 
    elsif ($curr_state eq "INIT_TO_WAIT_FOR_QUERY_LOG_DONE") {
        if (!$msg[0]->[0]) {
            $info_flag = "base64_data";
            @msg = ();
            if (defined($data_chunked)) {
                my @data_array = ();
                my $tmp_len = shift(@chunked_array);
                while ($tmp_len and scalar(@chunked_array)) {
                    push @data_array, shift(@chunked_array);
                    $tmp_len = shift(@chunked_array);
                }
                if ($tmp_len ne 0) {
                    $get_another_pkg = 1;
                }
                if (scalar(@data_array)) {
                    my $string = join('', @data_array);
                    $msg[0] = [0, encode_base64($string)];
                }
                else {
                    $msg[0] = [0, encode_base64("No logs")];
                }
            }
            else {
                $msg[0] = [0, encode_base64($content)];
            }
        }
    }
    elsif ($curr_state eq "INIT_TO_WAIT_FOR_QUERY_DOCKER_DONE") {
        if ($res->is_success) {
            @msg = ();
            if (!defined($content_length) or ($content_length > 3)) {
                if (defined($data_chunked)) {
                    my $tmp_entry = shift @chunked_array;
                    while ($tmp_entry and scalar(@chunked_array)) {
                        my $content_hash = decode_json (shift @chunked_array);
                        if (ref($content_hash) eq 'ARRAY') {
                            foreach (@$content_hash) {
                                push @msg, [0, parse_docker_list_info($_, 1)];
                            }
                        }
                        else {
                            push @msg, [0, parse_docker_list_info($content_hash, 0)];
                        }
                        $tmp_entry = shift @chunked_array;
                    }
                    if ($tmp_entry ne '0') {
                        $get_another_pkg = 1;
                    }
                }
                else {
                    my $content_hash = decode_json $content;
                    if (ref($content_hash) eq 'ARRAY') {
                        foreach (@$content_hash) {
                            push @msg, [0, parse_docker_list_info($_, 1)];
                        }
                    }
                    else {
                        push @msg, [0, parse_docker_list_info($content_hash, 0)];
                    }
                }
            }
            else {
                @msg = [0, "No running docker"];
            }
        }
    }
    elsif ($curr_state eq 'INIT_TO_WAIT_FOR_CREATE_DONE') {
        if ($nodetypetab) {
            $nodetypetab->setNodeAttribs($node,{provmethod=>"$node_create_variable{$node}->{image}:$node_create_variable{$node}->{cmd}"});
        }
        if ($vmtab) {
            $vmtab->setNodeAttribs($node,{othersettings=>$node_create_variable{$node}->{flag}});
        }
    }
 
    foreach my $tmp (@msg) {
        if ($tmp->[0]) {
            $global_callback->({node=>[{name=>[$node],error=>["$tmp->[1]"],errorcode=>["$tmp->[0]"]}]});
        } 
        else {
            $global_callback->({node=>[{name=>[$node],"$info_flag"=>["$tmp->[1]"]}]});
        }
    } 
    if ($get_another_pkg) {
        $pending_res++;
        return;
    }
    $concurrent_ssl_sessions--;
    $select->remove($sockfd);
    close($sockfd);
    delete($node_hash_variable{$sockfd}); 
    return;
}

#-------------------------------------------------------

=head3 deal_with_space_in_array_entry

  The function to add '' for entries that have spaces
  Input:
        $array: The string array whose entires may have spaces
  Return:
        A string that join the entries in input $array with space, 
        for entries have spaces, they will be put in "'"
  Usage example:

=cut  

#-------------------------------------------------------

sub deal_with_space_in_array_entry {
    my $array = shift;
    my @ret_array = ();
    push @ret_array, shift @$array;
    foreach (@$array) {
        if (/\s/) {
            push @ret_array, "'$_'";
        }
        else {
            push @ret_array, $_;
        }
    }
    return join(' ', @ret_array);
}

#-------------------------------------------------------

=head3 parse_docker_list_info

  The function to parse the content returned by the lsdocker command
  Input:
        $docker_info_hash: The hash variable which include docker infos
                           The variable is decoded from JSON string
        $flag: To show the info is get from dockerhost (1) or a speciifed docker (0)
  Return:
        docker_info_string in the format: $id $image $command $created $status $names;
  Usage example:

=cut  

#-------------------------------------------------------

sub parse_docker_list_info {
    my $docker_info_hash = shift;
    my $flag = shift; # Use the flag to check whether need to cut command
    my ($id,$image,$command,$created,$status,$names);
    $id = substr($docker_info_hash->{'Id'}, 0, 12);
    if ($flag) {
        $image = $docker_info_hash->{'Image'};
        $command = $docker_info_hash->{'Command'};
        $created = $docker_info_hash->{'Created'};
        $status = $docker_info_hash->{'Status'};

        $names = $docker_info_hash->{'Names'}->[0];
        my ($sec,$min,$hour,$day,$mon,$year) = localtime($created);
        $mon += 1;
        $year += 1900;
        $created = "$year-$mon-$day - $hour:$min:$sec";
    }
    else {
        $image = $docker_info_hash->{Config}->{'Image'};
        $command = deal_with_space_in_array_entry($docker_info_hash->{Config}->{'Cmd'});
        if (defined($docker_info_hash->{Config}->{'Entrypoint'})) {
            $command = deal_with_space_in_array_entry($docker_info_hash->{Config}->{'Entrypoint'});
        }
        $names = $docker_info_hash->{'Name'};
        $created = $docker_info_hash->{'Created'};
        $status = $docker_info_hash->{'State'}->{'Status'};
        $created =~ s/\..*$//;
    }
    my $cmd = sprintf("\"%.20s\"", $command);
    my $string = sprintf("%-12s %-30.30s %-22s %-20s %-10s %s", $id, $image, $cmd, $created, $status, $names);
    return($string);
}

#-------------------------------------------------------

=head3  deal_with_rsp

  The function to deal with SELECT
  Input:
        %args: a hash which currently only key 'timeout' is using
  Return:
        The expected number of response which havn't been received
  Usage example:

=cut  

#-------------------------------------------------------

sub deal_with_rsp
{
    my %args = @_;
    my $timeout = 0;
    if (defined($args{timeout})) {
        $timeout = $args{timeout};
    } 
    my @data = ();
    if ($select->can_read($timeout)) {
        my @ready_fds = $select->can_read(0);
        foreach my $sockfd (@ready_fds) {
            my $res = "";
            my $node_hash = $node_hash_variable{$sockfd};
            if (defined($node_hash)) {
                while (1) {
                    my $readbytes = undef;
                    $readbytes = sysread($sockfd, $res, 65535, length($res));
                    if (!defined($readbytes)) {
                        if ($!{EAGAIN} or $!{EWOULDBLOCK}) {
                            $pending_res--;
                            last;
                        }
                        elsif ($!{EINTR} or $!{ENOTTY}) {
                            next;
                        }
                        else {
                            die "read failed: $!";
                        }
                    }
                    elsif ($readbytes == 0) {
                        $pending_res--;
                        last;
                    }
                }
                # readbytes UNDEF means a reading error, so print out a msg and parse the next SSL connection
                push @data, [$node_hash->{state_machine_engine}, $sockfd, $res];
            }
        }
    }
    foreach (@data) {
        $_->[0]->($_->[1], $_->[2]);
    }
    return $pending_res;
}

#-------------------------------------------------------

=head3  parse_args

  Parse the command line options and operands

=cut

#-------------------------------------------------------
sub parse_args {

    my $request  = shift;
    my $args     = $request->{arg};
    my $cmd      = $request->{command}->[0];
    my %opt;
    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [$_[0], $usage_string] );
    };
    #############################################
    # No command-line arguments - use defaults
    #############################################
    if ( !defined( $args )) {
        return(0);
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    #############################################
    # Process command-line flags
    #############################################
    if (!GetOptions( \%opt,
            qw(h|help V|Verbose v|version))) {
        return( usage() );
    }

    #############################################
    # Option -V for verbose output
    #############################################
    if ( exists( $opt{V} )) {
        $verbose = 1;
    }
    if ($cmd eq "rpower") {
        if (scalar (@ARGV) > 1) {
            return ( [1, "Only one option is supportted at the same time"]);
        }
        elsif (!defined ($command_states{$cmd}{$ARGV[0]})) {
            return ( [1, "The option $ARGV[0] not support for $cmd"]);
        }
        else {
            @ARGV = ();
        }
    } 
    elsif ($cmd eq 'mkdocker') {
        my ($image, $command);
        foreach my $op (@ARGV) {
            my ($key,$value) = split /=/,$op;
            if ($key !~ /image|command|dockerflag/) {
                return ( [1, "Option $key is not supported for $cmd"]);
            }
            elsif (!defined($value)) {
                return ( [1, "Must set value for $key"]);
            }  
            else {
                if ($key eq 'image') {
                    $image = $value;
                }
                elsif ($key eq 'command') {
                    $command = $value;
                }
            }
        }
        if (!defined($image) and defined($command)) {
            return ( [1, "Must set 'image' if use 'command'"]);
        }
    }
    elsif ($cmd eq 'rmdocker') {
        foreach my $op (@ARGV) {
            if ($op ne '-f' and $op ne '--force') {
                return ( [1, "Option $op is not supported for $cmd"]);
            }
        }
        $request->{arg}->[0] = "force";
    }
    elsif ($cmd eq 'lsdocker') {
        foreach my $op (@ARGV) {
            if ($op ne '-l' and $op ne '--logs') {
                return ( [1, "Option $op is not supported for $cmd"]);
            }
        }
        $request->{arg}->[0] = "log";
    }


    return;
}


#-------------------------------------------------------

=head3  preprocess_request

  preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my $command = $req->{command}->[0];
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }
    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }
    ####################################
    # Process command-specific options
    ####################################
    my $parse_result = parse_args( $req );
    ####################################
    # Return error
    ####################################
    if ( ref($parse_result) eq 'ARRAY' ) {
        $callback->({error=>$parse_result->[1], errorcode=>$parse_result->[0]});
        $req = {};
        return ;
    }

    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    return \@result;
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request {
    my $req      = shift;
    my $callback = shift;

    my $noderange = $req->{node};
    my $command = $req->{command}->[0];
    my $args = $req->{arg};
    $global_callback = $callback;

    # For docker create, the attributes needed are
    #    vm.host,cpus,memory,othersettings 
    #    nodetype.provmethod     -- the image and command the docker will use
    #    mac.mac 
    # For other command, get docker host is enough to do operation

    my $init_method = undef;
    my $init_url = undef;
    my $init_state = undef;
    my $state_machine_engine = undef;
    my @nodeargs = ();
    my @errornodes = ();
    my $mapping_hash = undef;
    my $max_concur_ssl_session_allow = 10; # A variable can be set by caculated in the future
    $mapping_hash = $command_states{$command}{$args->[0]};
    unless($mapping_hash) {
        $mapping_hash = $command_states{$command}{all};
    }
    unless ($mapping_hash) {
        my $option = '';
        if (defined($args->[0])) {
            $option = $args->[0];
        }
        $callback->({error=>["Not support $command $option"], errorcode=>1});
        return;
    }
    $init_method = $mapping_hash->{init_method};
    $init_url = $mapping_hash->{init_url};
    $state_machine_engine = $mapping_hash->{state_machine_engine};
    $init_state = $mapping_hash->{init_state};
    if (!defined($init_state)) {
        $init_state = "INIT_TO_WAIT_FOR_RSP";
    }
    if ($command eq 'rpower' and defined($args->[0]) and ($args->[0] eq 'state')) {
        $nodelisttab = xCAT::Table->new('nodelist');
    }
    if ($command eq 'lsdocker') {
        my @new_noderange = ();
        my $nodehm = xCAT::Table->new('nodehm');
        if ($nodehm) {
            my $nodehmhash = $nodehm->getNodesAttribs($noderange, ['mgt']);
            foreach my $node (@$noderange) {
                if (defined($nodehmhash->{$node}->[0]->{mgt}) and $nodehmhash->{$node}->[0]->{mgt} eq 'ipmi') {
                     
                    if (defined($args) and $args->[0] ne '') {
                        $callback->({error=>[" -l|--log is not support for $node"], errorcode=>1});
                        return;
                    }
                    my $node_init_url = $init_url;
                    $node_init_url =~ s/#NODE#\///;
                    push @nodeargs, [$node, {name=>$node,port=>'2375'}, $init_method, $node_init_url, $init_state, $state_machine_engine]; 
                } 
                else {
                    push @new_noderange, $node;
                }
            }
        }
        $noderange = \@new_noderange;
    }  

    # The dockerhost is mapped to vm.host, so open vm table here
    $vmtab = xCAT::Table->new('vm');
    if ($vmtab) {
        my $vmhashs = $vmtab->getNodesAttribs($noderange, ['host']);
        if ($vmhashs) {
            foreach my $node (@$noderange) {
                my $vmhash = $vmhashs->{$node}->[0];
                if (!defined($vmhash) or !defined($vmhash->{host})) {
                    push @errornodes, $node;
                    next; 
                }
                my ($host, $port) = split /:/,$vmhash->{host};
                if (!defined($host)) {
                    push @errornodes, $node;
                    next;
                }
                if (!defined($port)) {
                    $port = 2375;
                }
                my $node_init_url = $init_url;
                $node_init_url =~ s/#NODE#/$node/;
                push @nodeargs, [$node, {name=>$host,port=>$port}, $init_method, $node_init_url, $init_state, $state_machine_engine];
            }
        }
    } 
    #parse parameters for mkdocker
    if ($command eq 'mkdocker') {
        my ($imagearg, $cmdarg, $flagarg);
        foreach (@$args) {
            if (/image=(.*)$/) {
                $imagearg = $1;
            }            
            elsif (/command=(.*)$/) {
                $cmdarg = $1;
            }
            elsif (/dockerflag=(.*)$/) {
                $flagarg = $1;
            }
        }     
        $genreq_ptr = \&genreq_for_mkdocker;
        $nodetypetab = xCAT::Table->new('nodetype');
        my $hosttab = xCAT::Table->new('hosts');
        my $mactab = xCAT::Table->new('mac');
        if (!defined($hosttab) or !defined($nodetypetab) or !defined($mactab) or !defined($vmtab)) { 
            $callback->({error=>["Open table 'nodetype', 'hosts' or 'mac' failed"], errorcode=>1});
            return;
        } 
        my $nodetypehash = $nodetypetab->getNodesAttribs($noderange, ['provmethod']);
        my $hosthash = $hosttab->getNodesAttribs($noderange, ['ip']);
        my $machash = $mactab->getNodesAttribs($noderange, ['mac']);
        my $vmhash = $vmtab->getNodesAttribs($noderange, ['cpus', 'memory', 'othersettings']);
        my @errornodes = ();
        foreach my $node (@$noderange)  {
            if ($imagearg) {
                $node_create_variable{$node}->{image} = $imagearg;
                if ($cmdarg) {
                    $node_create_variable{$node}->{cmd} = $cmdarg;
                }
            }
            else {
                if (!defined($nodetypehash->{$node}->[0]->{provmethod})) {
                    push @errornodes, $node;
                    next;
                }
                else {
                    my ($tmp_img,$tmp_cmd) = split /:/, $nodetypehash->{$node}->[0]->{provmethod};
                    if (!defined($tmp_img)) {
                        push @errornodes, $node;
                        next;
                    }
                    $node_create_variable{$node}->{image} = $tmp_img;
                    $node_create_variable{$node}->{cmd} = $tmp_cmd;
                }
            } 
            if ($flagarg) {
                $node_create_variable{$node}->{flag} = $flagarg;
            }
            if (defined($hosthash->{$node}->[0]->{ip})) {
                $node_create_variable{$node}->{ip} = $hosthash->{$node}->[0]->{ip};
            }
            if (defined($machash->{$node}->[0]->{mac})) {
                $node_create_variable{$node}->{mac} = $machash->{$node}->[0]->{mac};
            }
            my $vmnodehash = $vmhash->{$node}->[0];
            if (defined($vmnodehash)) {
                if (defined($vmnodehash->{cpus})) {
                    $node_create_variable{$node}->{cpus} = $vmnodehash->{cpus};
                }
                if (defined($vmnodehash->{memory})) {
                    $node_create_variable{$node}->{memory} = $vmnodehash->{memory};
                }       
                if (!defined($flagarg) and defined($vmnodehash->{othersettings})) {
                    $node_create_variable{$node}->{flag} = $vmnodehash->{othersettings};
                }         
            }
        }
    }



    if (scalar(@errornodes)) {
        $callback->({error=>["Docker host not set correct for @errornodes"], errorcode=>1});
        return;
    }
    my $timeout = 0;
    my $pre_pending_res = undef;
    my $no_res_times = 0;
    while (1)  {
        my $pending_nodes = scalar(@nodeargs);
        if ($pending_nodes eq 0) {
            if ($pending_res eq 0) { # No more nodes needed to be process, no more response is expected, end the loop
                last;
            }
            # The steps below is used to judge whether there is no response
            # In the 1st round, just record the pending response num
            # Then, check whether the pending num have changed. 
            #           If NO changes, increase NO-change times counter and waiting time
            #           If changed, clear counter, waiting time
            elsif (!defined($pre_pending_res)) {
                $pre_pending_res = $pending_res;
            }
            elsif ($pre_pending_res eq $pending_res) {
                $no_res_times++;
                $timeout += $pending_res;
            }
            else {
                $pre_pending_res = undef;
                $no_res_times = 0;
                $timeout = 0;
            }
            # Wait for 10 * num_of_sessions 
            if ($no_res_times > 5) {
                last;
            }
        }        


        if (($pending_nodes eq 0) and ($pending_res eq 0)) { # No more nodes needed to be process, no more response is expected, end the loop
            last;
        }
        if (($pending_nodes) and ($concurrent_ssl_sessions lt $max_concur_ssl_session_allow)) {
            my $node = shift @nodeargs;
            my $ssl_connect = init_ssl_connection($node->[1]);
            if (!defined($ssl_connect)) {
                $callback->({error=>["Create SSL connection failed for docker $node->[0] on host $node->[1]->{host}"], errorcode=>1});
            } 
            elsif (not ref($ssl_connect)) {
                $callback->({error=>["$ssl_connect"], errorcode=>1});
            }
            else {
                my $res = sendreq($ssl_connect, @$node);
                if (defined($res)) {
                    $callback->({node=>[{name=>[$node->[0]], error=>[$res], errorcode=>[1]}]});
                    close($ssl_connect);
                    $concurrent_ssl_sessions--;
                }
            }
        } 
        deal_with_rsp(timeout=>$timeout);
    }
    my @failed_handler_array = $select->handles;
    if (scalar(@failed_handler_array)) {
        my @err_msg = ();
        foreach my $sockfd (@failed_handler_array) {
            if (defined($node_hash_variable{$sockfd})) {
                push @err_msg, {name=>[$node_hash_variable{$sockfd}->{node}], error=>["Timeout to wait for response"], errorcode=>[1]};
            }
        }
        $callback->({node=>\@err_msg});
    }
    if ($nodelisttab) { $nodelisttab->commit;}
    if ($nodetypetab) { $nodetypetab->commit;}
    if ($vmtab) {$vmtab->commit;}
    return;
}

#-------------------------------------------------------

=head3  genreq

  Generate the docker REST API http request
  Input:
        $node: the docker container name
        $dockerhost: hash, keys: name, port, user, pw, user, pw
        $method: GET, PUT, POST, DELETE
        $api: the url of rest api
        $content: an xml section which including the data to perform the rest api
  Return:
        The REST API http request
  Usage example:
         my $api = "/images/json";
         my $method = "GET";
         my %dockerhost = ( name => "bybc0604", port => "2375", );
         my $request = genreq($node, \%dockerhost, $method,$api, "");

=cut

#-------------------------------------------------------
sub genreq {
    my $node = shift;
    my $dockerhost = shift;
    my $method = shift;
    my $api = shift;
    my $content = shift;

    if (! defined($content)) { $content = ""; }
    my $header = HTTP::Headers->new('content-type' => 'application/json',
                             'Accept' => 'application/json',
                             #'Connection' => 'keep-alive',
                             'Host' => $dockerhost->{name}.":".$dockerhost->{port});
    $header->authorization_basic($dockerhost->{user}.'@internal', $dockerhost->{pw});

    my $ctlen = length($content);
    $header->push_header('Content-Length' => $ctlen);

    my $url = "https://".$dockerhost->{name}.":".$dockerhost->{port}.$api;
    my $request = HTTP::Request->new($method, $url, $header, $content);
    $request->protocol('HTTP/1.1');
    return $request;
}

#-------------------------------------------------------

=head3  genreq_for_mkdocker

  Generate HTTP request for mkdocker

  Input: $node: The docker container name
         $dockerhost: hash, keys: name, port, user, pw, user, pw, user, pw
         $method: the http method to generate the http request
         $api: the url to generate the http request

  return: 1-No image defined;
          2-http response error;
  Usage example:
          my $res = genreq_for_mkdocker($node,\%dockerhost,'GET','/containers/$node/json');

=cut

#-------------------------------------------------------

sub genreq_for_mkdocker {
    my ($node, $dockerhost, $method, $api) = @_; 
    my $dockerinfo = $node_create_variable{$node};
    if (!defined($dockerinfo) or !defined($dockerinfo->{image})) {
        return "No image defined";
    }
    my %info_hash = ();
    #$info_hash{name} = '/'.$node;
    #$info_hash{Hostname} = '';
    #$info_hash{Domainname} = '';
    $info_hash{Image} = "$dockerinfo->{image}";
    @{$info_hash{Cmd}} = split/,/, $dockerinfo->{cmd};
    $info_hash{Memory} = $dockerinfo->{mem};
    $info_hash{MacAddress} = $dockerinfo->{mac};
    $info_hash{CpusetCpus} = $dockerinfo->{cpus};
    if (defined($dockerinfo->{flag})) {
        my $flag_hash = decode_json($dockerinfo->{flag});
        %info_hash = (%info_hash, %$flag_hash);  
    }
    my $content = encode_json \%info_hash;
    return genreq($node, $dockerhost, $method, $api, $content);
}

#-------------------------------------------------------

=head3  sendreq

  Based on the method, url create a http request and send out on the given SSL connection
  
  Input: $ssl_connection: the SSL connection for this request
         $node: the docker container name
         $dockerhost: hash, keys: name, port, user, pw, user, pw
         $method: the http method to generate a http request
         $url: the http url to generate a http request
         $state: the state for the action
         $state_machine_engine: the function to deal with the http response for the request generate by $method and $url

  return: 0-undefine If no error
          1-return generate http request failed;
          2-return http request error message;
  Usage example:
          my $res = send_req($ssl_connetion, $node, \%dockerhost, 'GET', '/containers/$node/json', "INIT_TO_WAIT_FOR_RSP", \&single_state_engine);

=cut

#-------------------------------------------------------

sub sendreq {
    my ($ssl_connection, $node, $dockerhost, $init_method, $init_url, $init_state, $state_machine_engine) = @_;
    my $http_req = $genreq_ptr->($node, $dockerhost, $init_method, $init_url);
    # Need to Dumper to log file later
    #print Dumper($http_req);
    if (!defined($http_req)) {
        return "Generate http request failed";
    }
    elsif (not ref($http_req)) {
        return $http_req;
    }
    $select->add($ssl_connection);
    print $ssl_connection $http_req->as_string();
    $node_hash_variable{$ssl_connection}->{node} = $node;
    $node_hash_variable{$ssl_connection}->{state} = $init_state;
    $node_hash_variable{$ssl_connection}->{state_machine_engine} = $state_machine_engine;
    $pending_res++;
    return undef;
}
#-------------------------------------------------------

=head3  init_ssl_connection

  This function is used to create a SSL connection to the docker host

  Input: $dockerhost: hash, keys: name, port, user, pw, user, pw

  return: A SSL connection handler if success.
          An error msg if failed.
  Usage example:
          my $ssl_connect = init_ssl_connection(\%dockerhost);

=cut

#-------------------------------------------------------

sub init_ssl_connection {
    my $dockerhost = shift;
    my $hostname = $dockerhost->{name};
    my $port = $dockerhost->{port};
    my @user = getpwuid($>); 
    my $homedir = $user[7];
    my $ssl_ca_file = $homedir . "/.xcat/ca.pem";
    my $ssl_cert_file = $homedir . "/.xcat/client-cred.pem";
    my $key_file = $homedir . "/.xcat/client-cred.pem";
    my $rc = 0;
    my $response;
    my $connect;
    my $socket = IO::Socket::INET->new( PeerHost => $hostname,
                                        PeerPort => $port,
                                        Timeout => 2);
    if ($socket) {
        $connect = IO::Socket::SSL->start_SSL( $socket,
                                                   SSL_verify_mode => "SSL_VERIFY_PEER",
                                                   SSL_ca_file => $ssl_ca_file,
                                                   SSL_cert_file =>$ssl_cert_file,
                                                   SSL_key_file => $key_file,
                                                   Timeout => 2
                                      );
        if ($connect) {
            my $flags=fcntl($connect,F_GETFL,0);
            $flags |= O_NONBLOCK;
            fcntl($connect,F_SETFL,$flags);
        } else {
            $rc = 1;
            $response = "Could not make ssl connection to $hostname:$port.";
        }
    } else {
        $rc = 1;
        $response = "Could not create socket to $hostname:$port.";
    }

    if ($rc) {
        return $response;
    } else {
        $concurrent_ssl_sessions++;
        return $connect;
    }
}

1;

