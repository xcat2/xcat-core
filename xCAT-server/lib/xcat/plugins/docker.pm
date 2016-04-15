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

#use strict;
use POSIX qw(WNOHANG nice);
use POSIX qw(WNOHANG setsid :errno_h);
use Errno;
use MIME::Base64 qw(encode_base64);
require IO::Socket::SSL; IO::Socket::SSL->import('inet4');
use Time::HiRes qw(gettimeofday sleep);
use Fcntl qw/:DEFAULT :flock/;
use File::Path;
use File::Copy;
use File::Basename;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use HTTP::Headers;
use HTTP::Request;
use xCAT::Utils;
use xCAT::MsgUtils;
use Cwd;
use xCAT::Usage;
use JSON;

my $verbose;
my $global_callback;
my $subreq;

my $async;

#-------------------------------------------------------
=head3  The hash variable to store node related http request id 

 The structure is like this
 %http_session_variable = (
     $session_id => $node,
 );

=cut
#-------------------------------------------------------

my %http_session_variable = ();

#-------------------------------------------------------
=head3  The hash variable to store node parameters to access docker container

 The structure is like this
 %node_hash_variable = (
     $node => {
         image=>$nodetype.provmethod,
         cmd=>$nodetype.provmethod,
         ip=>$host.ip,    
         nics=>$vm.vmnics,
         mac=>$mac.mac,
         cpu=>$vm.cpus
         memory=>$vm.memory
         flag=>$vm.othersettings,
         hostinfo=>{
             name => $host,
             port => $port,
         },
         genreq_ptr => \&genreq;
         http_req_method => $init_method,
         http_req_url => $node_init_url,
         node_app_state => $init_state,
         state_machine_engine => $state_machine_engine,
     },
 );

=cut
#-------------------------------------------------------

my %node_hash_variable = ();

# The num of HTTP requests that is progressing
my $http_requests_in_progress = 0;


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
            lsdocker => 'nodehm:mgt=docker|ipmi|kvm',
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

# For rpower start/stop/restart/pause/unpause/state
#    return error_msg if failed or corresponding msg if success
    rpower => {
        start => {
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/start",
            init_state => "INIT_TO_WAIT_FOR_START_DONE",
        }, 
        stop => {
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/stop",
            init_state => "INIT_TO_WAIT_FOR_STOP_DONE",
        },        
        restart => {
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/restart",
        },        
        pause => {
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/pause",
        },
        unpause => {
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/containers/#NODE#/unpause",
        },
        state => {
            state_machine_engine => \&default_state_engine,
            init_method => "GET",
            init_url => "/containers/#NODE#/json",
            init_state => "INIT_TO_WAIT_FOR_QUERY_STATE_DONE",
        },
    },

# The state changing graphic for mkdocker
#                                                             error
#    init-----------> INIT_TO_WAIT_FOR_CREATE_DONE -----------------> error_msg
#              ^                   /         |
#              |       404 and    /          |
#           20x|  'No such image'/           |
#              |                v            |                error
#  CREATE_TO_WAIT_FOR_IMAGE_PULL_DONE ------------------------------> error_msg
#                                            |
#                                            |
#                                         20x|
#                                            v
#                                      create done
#
    mkdocker => {
        default => {
            genreq_ptr => \&genreq_for_mkdocker,
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/containers/create?name=#NODE#",
            init_state => "INIT_TO_WAIT_FOR_CREATE_DONE"
        },
        pullimage => {
            state_machine_engine => \&default_state_engine,
            init_method => "POST",
            init_url => "/images/create?fromImage=#DOCKER_IMAGE#",
            init_state => "CREATE_TO_WAIT_FOR_IMAGE_PULL_DONE",
        },
    },

# For rmdocker
#    return error_msg if failed or success if done
    rmdocker => {
        force => {
            state_machine_engine => \&default_state_engine,
            init_method => "DELETE",
            init_url => "/containers/#NODE#?force=1",
        },
        default => {
            state_machine_engine => \&default_state_engine,
            init_method => "DELETE",
            init_url => "/containers/#NODE#",
        },
    },

# For lsdocker [-l|--logs]
#    return error_msg if failed or corresponding msg if success
    lsdocker => {
        default => {
            state_machine_engine => \&default_state_engine,
            init_method => "GET",
            init_url => "/containers/#NODE#/json?",
            init_state => "INIT_TO_WAIT_FOR_QUERY_DOCKER_DONE",
        },
        log => {
            state_machine_engine => \&default_state_engine,
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
        http_state_code_info('304', "INIT_TO_WAIT_FOR_STOP_DONE") -> "Already stopped"
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
                return [0, "container already stopped"];
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

=head3 modify_node_state_hash
  To change node state to the state specified.
  Input:
        $node: the node to change state
        $to_state_hash: the hash which store the destination state info
  Return:
  Usage example:
        modify_node_state_hash($node, $command_states{$command}{$option});
=cut

#-------------------------------------------------------

sub modify_node_state_hash {
    my $node = shift;
    my $to_state_hash = shift;
    my $node_hash = $node_hash_variable{$node};
    $node_hash->{http_req_method} = $to_state_hash->{init_method};
    $node_hash->{http_req_url} = $to_state_hash->{init_url};
    $node_hash->{node_app_state} = $to_state_hash->{init_state};
    $node_hash->{state_machine_engine} = $to_state_hash->{state_machine_engine};
    $node_hash->{genreq_ptr} = $to_state_hash->{genreq_ptr};
    if (!defined($node_hash->{genreq_ptr})) {
        $node_hash->{genreq_ptr} = \&genreq;
    }
    if ($node_hash->{image} =~ /:/) {
        $node_hash->{http_req_url} =~ s/#DOCKER_IMAGE#/$node_hash->{image}/;
    } else {
        $node_hash->{http_req_url} =~ s/#DOCKER_IMAGE#/$node_hash->{image}:latest/;
    }
    $node_hash->{http_req_url} =~ s/#NETNAME#/$node_hash->{nics}/;
    $node_hash->{http_req_url} =~ s/#NODE#/$node/;
    return;
}

#-------------------------------------------------------

=head3 change_node_state
  To change node state to the state specified, and then send out the HTTP request.
  Input:
        $node: the node to change state
        $to_state_hash: the hash which store the destination state info
  Return:
  Usage example:
        change_node_state($node, $command_states{$command}{$option});
=cut

#-------------------------------------------------------

sub change_node_state {
    my ($node, $to_state_hash) = @_;
    modify_node_state_hash(@_);
    sendreq($node, $node_hash_variable{$node});
    return;
}

#-------------------------------------------------------

=head3 default_state_engine

  The state_machine_engine to deal with http response
  Input:
        $id: The http session id when adding HTTP request into HTTP::Async object
        $data: The http response 
  Return:
        If there are any errors or msg, they will be outputed directly.
        Else, nothing returned.
  Usage example:
        default_state_engine($id, HTTP Response data);

=cut  

#-------------------------------------------------------

sub default_state_engine {
    my $id = shift;
    my $data = shift;
    my $node = $http_session_variable{$id};
    if (!defined($node)) {
        return;
    }
    my $node_hash = $node_hash_variable{$node};
    my $curr_state = $node_hash->{node_app_state};
    my $info_flag = 'data';

    if ($data->is_error or (defined($data->header("connection")) and $data->header("connection") =~ /close/)) { 
        $http_requests_in_progress--;
        delete($http_session_variable{$id}); 
    }

    my $content = $data->decoded_content;
    my @msg = ();
    $msg[0] = &http_state_code_info($data->code, $curr_state);
    if ($data->is_error) {
        if ($content ne '') {
            $msg[0]->[1] = "$content";
        }
        elsif ($data->message ne '') {
            $msg[0]->[1] = $data->message;
        }
    }
    my $content_type = $data->header("content-type"); 
    my $content_hash = undef;
    if (defined($content_type) and $content_type =~ /json/i) {
        if ($curr_state ne "CREATE_TO_WAIT_FOR_IMAGE_PULL_DONE") {
            $content_hash = decode_json $content;
        }
        else {
            if ($content =~ /Status: Downloaded newer image/) {

            }
            elsif ($content =~ /\"error\":\"([^\"]*)\"/) {
                @msg = ();
                $msg[0] = [1, $1];
            }
        }
    }
    elsif (!defined($content_type)) {
        $content_type = "undefined";
    }

    if ($curr_state eq "INIT_TO_WAIT_FOR_QUERY_STATE_DONE")  {
        if ($data->is_success) {
            if ($content_type =~ /json/i) {
                my $node_state = $content_hash->{'State'}->{'Status'};
                if (defined($node_state)) {
                    $msg[0] = [0, $node_state];
                }
                else {
                    $msg[0] = [1, "Can not get status"];
                }
            } 
            else {
                $msg[0] = [1, "The content type: $content_type is unable to be parsed."];
            }
        }
    } 
    elsif ($curr_state eq "INIT_TO_WAIT_FOR_QUERY_LOG_DONE") {
        if ($data->is_success) {
            $info_flag = "base64_data";
            @msg = ();
            if ($content_type =~ /text\/plain/i) {
                $msg[0] = [0,encode_base64($content)];
            }
            else {
                $msg[0] = [1, "The content type: $content_type is unable to be parsed."];
            }
        }
    }
    elsif ($curr_state eq "INIT_TO_WAIT_FOR_QUERY_DOCKER_DONE") {
        if ($data->is_success) {
            @msg = ();
            if ($content_type =~ /json/i) {
                if (ref($content_hash) eq 'ARRAY') {
                    foreach (@$content_hash) {
                        push @msg, [0, parse_docker_list_info($_, 1)];
                    }
                }
                else {
                    push @msg, [0, parse_docker_list_info($content_hash, 0)];
                }
            }
            if (!scalar(@msg)) {
                @msg = [0, "No running docker"];
            }
        }
    }
    elsif ($curr_state eq 'INIT_TO_WAIT_FOR_CREATE_DONE') {
        if ($data->code eq '404' and $msg[0]->[1] =~ /image:/i) {
            # To avoid pulling image loop
            if (defined($node_hash->{have_pulled_image})) {
                return;
            }
            $global_callback->({node=>[{name=>[$node],"$info_flag"=>["Pull image $node_hash->{image} start"]}]});
            change_node_state($node, $command_states{mkdocker}{pullimage});
            return;
        }
    }
    elsif ($curr_state eq 'CREATE_TO_WAIT_FOR_IMAGE_PULL_DONE') {
        if ($data->is_success and !$msg[0]->[0]) {
            $global_callback->({node=>[{name=>[$node],"$info_flag"=>["Pull image $node_hash->{image} done"]}]});
            $node_hash->{have_pulled_image} = 1;
            change_node_state($node, $command_states{mkdocker}{default});
            return;
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
        my @cmd = ();
        push @cmd, $docker_info_hash->{Path};
        if (defined($docker_info_hash->{Args})) {
            push @cmd, @{$docker_info_hash->{Args}};
        }
        $command = deal_with_space_in_array_entry(\@cmd);
        $names = $docker_info_hash->{'Name'};
        $created = $docker_info_hash->{'Created'};
        $status = $docker_info_hash->{'State'}->{'Status'};
        $created =~ s/\..*$//;
    }
    my $cmd = sprintf("\"%.20s\"", $command);
    my $string = sprintf("%-12s   %-30.30s %-22s %-20s %-10s %s", $id, $image, $cmd, $created, $status, $names);
    return($string);
}

#-------------------------------------------------------

=head3  deal_with_rsp

  The function to deal with SELECT
  Input:
        %args: a hash which currently only key 'timeout' is using
  Return:
        The number of response have received
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
    my $deal_num = 0;
    while (my ($response, $id) = $async->wait_for_next_response($timeout)) {
        my $node = $http_session_variable{$id};
        if (defined($node)) {
            $deal_num++;
            $node_hash_variable{$node}->{state_machine_engine}->($id, $response);
        }
    }

    return $deal_num;
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
        if ($cmd eq "rpower") {
            return ([1, "No option specified for rpower"]);
        }
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
            $request->{mapping_option} = $ARGV[0];
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
        $request->{mapping_option} = "force";
    }
    elsif ($cmd eq 'lsdocker') {
        foreach my $op (@ARGV) {
            if ($op ne '-l' and $op ne '--logs') {
                return ( [1, "Option $op is not supported for $cmd"]);
            }
        }
        $request->{mapping_option} = "log";
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
    $subreq      = shift;
    my $noderange = $req->{node};
    my $command = $req->{command}->[0];
    my $args = $req->{arg};
    $global_callback = $callback;

    # For docker create, the attributes needed are
    #    vm.host,cpus,memory,othersettings 
    #    nodetype.provmethod     -- the image and command the docker will use
    #    mac.mac 
    # For other command, get docker host is enough to do operation

    my $mapping_hash = undef;
    if (defined($req->{mapping_option})) {
        $mapping_hash = $command_states{$command}{$req->{mapping_option}};
    }
    else {
        $mapping_hash = $command_states{$command}{default};
    }
    my $max_concur_session_allow = 20; # A variable can be set by caculated in the future
    if ($command eq 'lsdocker') {
        my @new_noderange = ();
        my $nodehm = xCAT::Table->new('nodehm');
        if ($nodehm) {
            my $nodehmhash = $nodehm->getNodesAttribs($noderange, ['mgt']);
            foreach my $node (@$noderange) {
                if (defined($nodehmhash->{$node}->[0]->{mgt}) and $nodehmhash->{$node}->[0]->{mgt} =~ /ipmi|kvm/) {
                     
                    if (defined($args) and $args->[0] ne '') {
                        $callback->({error=>[" $args->[0] is not support for $node"], errorcode=>1});
                        return;
                    }
                    ${$node_hash_variable{$node}}{hostinfo} = {name=>$node,port=>'2375'};
                    $mapping_hash->{init_url} =~ s/#NODE#\///;
                    modify_node_state_hash($node, $mapping_hash);
                } 
                else {
                    push @new_noderange, $node;
                }
            }
        }
        $noderange = \@new_noderange;
    }  

    # The dockerhost is mapped to vm.host, so open vm table here
    my $vmtab = xCAT::Table->new('vm');
    if ($vmtab) {
        my $vmhashs = $vmtab->getNodesAttribs($noderange, ['host','nics']);
        if ($vmhashs) {
            my @errornodes = ();
            foreach my $node (@$noderange) {
                my $vmhash = $vmhashs->{$node}->[0];
                if (!defined($vmhash) or !defined($vmhash->{host})) {
                    delete $node_hash_variable{$node};
                    push @errornodes, $node;
                    next; 
                }
                my ($host, $port) = split /:/,$vmhash->{host};
                if (!defined($host)) {
                    delete $node_hash_variable{$node};
                    push @errornodes, $node;
                    next;
                }
                if (!defined($port)) {
                    $port = 2375;
                }
                ${$node_hash_variable{$node}}{hostinfo} = {name=>$host,port=>$port};
                if (defined($vmhash->{nics})) {
                    $node_hash_variable{$node}->{nics} = $vmhash->{nics};
                } else {
                    $node_hash_variable{$node}->{nics} = "mynet0";
                }
                if ($command eq 'rmdocker') {
                    if (defined($args->[0])) {
                        $node_hash_variable{$node}->{opt} = "force";
                    } 
                    else {
                        $node_hash_variable{$node}->{opt} = "default";
                    }
                }
                modify_node_state_hash($node, $mapping_hash);
            }
            if (scalar(@errornodes)) {
                $callback->({error=>["Docker host not set correct for @errornodes"], errorcode=>1});
                return;
            }
        }
    } 
    else {
        $callback->({error=>["Open table 'vm' failed"], errorcode=>1});
        return;
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
        my $nodetypetab = xCAT::Table->new('nodetype');
        if (!defined($nodetypetab)) {
            $callback->({error=>["Open table 'nodetype' failed"], errorcode=>1});
            return;
        }
        my $mactab = xCAT::Table->new('mac');
        if (!defined($mactab)) { 
            $callback->({error=>["Open table 'mac' failed"], errorcode=>1});
            return;
        }
        my ($ret, $netcfg_hash) = xCAT::NetworkUtils->getNodesNetworkCfg($noderange);
        if ($ret)  {
            $callback->({error=>[$netcfg_hash], errorcode=>1});
            return;
        }
        my $nodetypehash = $nodetypetab->getNodesAttribs($noderange, ['provmethod']);
        my $machash = $mactab->getNodesAttribs($noderange, ['mac']);
        my $vmhash = $vmtab->getNodesAttribs($noderange, ['cpus', 'memory', 'othersettings']);
 
        my %errornodes = ();
        foreach my $node (@$noderange)  {
            if ($imagearg) {
                $node_hash_variable{$node}->{image} = $imagearg;
                if ($cmdarg) {
                    $node_hash_variable{$node}->{cmd} = $cmdarg;
                    $nodetypetab->setNodeAttribs($node,{provmethod=>"$imagearg!$cmdarg"});
                }
                else {
                    $nodetypetab->setNodeAttribs($node,{provmethod=>"$imagearg"});
                }
            }
            else {
                if (!defined($nodetypehash->{$node}->[0]->{provmethod})) {
                    delete $node_hash_variable{$node};
                    push @{$errornodes{Image}}, $node;
                    next;
                }
                else {
                    my ($tmp_img,$tmp_cmd) = split /!/, $nodetypehash->{$node}->[0]->{provmethod};
                    if (!defined($tmp_img)) {
                        delete $node_hash_variable{$node};
                        push @{$errornodes{Image}}, $node;
                        next;
                    }
                    $node_hash_variable{$node}->{image} = $tmp_img;
                    $node_hash_variable{$node}->{cmd} = $tmp_cmd;
                }
            } 
            if ($flagarg) {
                $node_hash_variable{$node}->{flag} = $flagarg;
                $vmtab->setNodeAttribs($node,{othersettings=>$flagarg});
            }
            if (defined($machash->{$node}->[0]->{mac})) {
                $node_hash_variable{$node}->{mac} = $machash->{$node}->[0]->{mac};
            }
            my $vmnodehash = $vmhash->{$node}->[0];
            if (defined($vmnodehash)) {
                if (defined($vmnodehash->{cpus})) {
                    $node_hash_variable{$node}->{cpus} = $vmnodehash->{cpus};
                }
                if (defined($vmnodehash->{memory})) {
                    $node_hash_variable{$node}->{memory} = $vmnodehash->{memory};
                }
                if (!defined($flagarg) and defined($vmnodehash->{othersettings})) {
                    $node_hash_variable{$node}->{flag} = $vmnodehash->{othersettings};
                }
            }
            my $netcfg_info = $netcfg_hash->{$node};
            if (!defined($netcfg_info) or !defined($netcfg_info->{'ip'})) {
                delete $node_hash_variable{$node};
                push @{$errornodes{Network}}, $node;
                next;
            }
            else {
                $node_hash_variable{$node}->{ip} = $netcfg_info->{ip};
            }
        }
        $nodetypetab->close;
        $mactab->close;
        foreach (keys %errornodes) {
            $callback->({error=>["$_ not set correct for @{$errornodes{$_}}"], errorcode=>1});
        }
    }
    $vmtab->close;

    if (my $res = init_async(slots=>$max_concur_session_allow)) {
        $callback->({error=>[$res], errorcode=>1});
        return;
    }
    my @nodeargs = keys(%node_hash_variable);

    while (1)  {
        while ((scalar @nodeargs) and $http_requests_in_progress < $max_concur_session_allow) {
            deal_with_rsp();
            my $node = shift @nodeargs;
            sendreq($node, $node_hash_variable{$node});
        }
        if ($async->empty)  {
            last;
        }
        deal_with_rsp();
    }
    return;
}

#-------------------------------------------------------

=head3  init_async

  Creates a new HTTP::Async object and sets it up.
  Input:
        %args: the hash stores params to create the HTTP::Async object
            slots: maximum number of parallel requests to make
  Usage example:
        init_async(slots=><num>)

=cut

#-------------------------------------------------------

sub init_async {
    my %args = @_;
    eval {require HTTP::Async};
    if ($@) {
        return ("Can't find HTTP/Async.pm, please make sure the package have been installed");  
    }
    my @user = getpwuid($>);
    my $homedir = $user[7];
    my $ssl_ca_file = $homedir . "/.xcat/ca.pem";
    my $ssl_cert_file = $homedir . "/.xcat/client-cred.pem";
    my $key_file = $homedir . "/.xcat/client-cred.pem";
    $async = HTTP::Async->new(
        slots => $args{slots},
        ssl_options => {
            SSL_verify_mode => SSL_VERIFY_PEER,
            SSL_ca_file => $ssl_ca_file,
            SSL_cert_file => $ssl_cert_file,
            SSL_key_file => $key_file,
        },
    );
    return undef;
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

  return: The http request;

  Usage example:
          my $res = genreq_for_mkdocker($node,\%dockerhost,'GET','/containers/$node/json');

=cut

#-------------------------------------------------------

sub genreq_for_mkdocker {
    my ($node, $dockerhost, $method, $api) = @_; 
    my $dockerinfo = $node_hash_variable{$node};
    my %info_hash = ();
    if (defined($dockerinfo->{flag})) {
        my $flag_hash = decode_json($dockerinfo->{flag});
        %info_hash = %$flag_hash;
    }
    #$info_hash{name} = '/'.$node;
    #$info_hash{Hostname} = '';
    #$info_hash{Domainname} = '';
    $info_hash{Image} = "$dockerinfo->{image}";
    @{$info_hash{Cmd}} = split/,/, $dockerinfo->{cmd};
    $info_hash{Memory} = $dockerinfo->{mem};
    $info_hash{MacAddress} = $dockerinfo->{mac};
    $info_hash{CpusetCpus} = $dockerinfo->{cpus};
    $info_hash{HostConfig}->{NetworkMode} = $dockerinfo->{nics};
    $info_hash{NetworkDisabled} = JSON::false;
    $info_hash{NetworkingConfig}->{EndpointsConfig}->{"$dockerinfo->{nics}"}->{IPAMConfig}->{IPv4Address} = $dockerinfo->{ip};
    my $content = encode_json \%info_hash;
    return genreq($node, $dockerhost, $method, $api, $content);
}

#-------------------------------------------------------

=head3  sendreq

  Based on the method, url create a http request and send out on the given SSL connection

  Input:
         $node: the docker container name
         $node_hash: the hash that store information for the $node
  return: 0-undefine If no error
          1-return generate http request failed;
          2-return http request error message;
  Usage example:
          my $res = sendreq($node, $node_hash);

=cut

#-------------------------------------------------------

sub sendreq {
    my ($node, $node_hash) = @_;
    my $http_req = $node_hash->{genreq_ptr}->($node, $node_hash->{hostinfo}, $node_hash->{http_req_method}, $node_hash->{http_req_url});
    # Need to Dumper to log file later
    # print Dumper($http_req);
    my $http_session_id = $async->add_with_opts($http_req, {});
    $http_session_variable{$http_session_id} = $node;
    $http_requests_in_progress++;
    return undef;
}
1;
