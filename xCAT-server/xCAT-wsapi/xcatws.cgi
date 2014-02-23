#!/usr/bin/perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
use strict;
use CGI qw/:standard/;      #todo: remove :standard when the code only uses object oriented interface
use JSON;		#todo: require this dynamically later on so that installations that do not use xcatws.cgi do not need perl-JSON
use Data::Dumper;

#talk to the server
use Socket;
use IO::Socket::INET;
use IO::Socket::SSL;
use lib "/opt/xcat/lib/perl";
use xCAT::Table;

# Development notes:
# - added this line to /etc/httpd/conf/httpd.conf to hide the cgi-bin and .cgi extension in the uri:
#  ScriptAlias /xcatws /var/www/cgi-bin/xcatws.cgi
# - also upgraded CGI to 3.52
# - If "Internal Server Error" is returned, look at /var/log/httpd/ssl_error_log
# - can run your cgi script from the cli:  http://perldoc.perl.org/CGI.html#DEBUGGING

# This is how the parameters come in:
# GET: url parameters come $q->url_param.  There is no put/post data.
# PUT: url parameters come $q->url_param.  Put data comes in q->param(PUTDATA).
# POST: url parameters come $q->url_param.  Post data comes in q->param(POSTDATA).
# DELETE: ??

# Notes from http://perldoc.perl.org/CGI.html:
# %params = $q->Vars;       # same as $q->param() except put it in a hash
# @foo = split("\0",$params{'foo'});
# my $error = $q->cgi_error;        #todo: check for errors that occurred while processing user input
# print $q->end_html;       #todo: add the </body></html> tags
# $q->url_param()      # gets url options, even when there is put/post data (unlike q->param)

my $VERSION   = "2.8";

my $q           = CGI->new;
#my $url         = $q->url;      # the 1st part of the url, https, hostname, port num, and /xcatws
my $pathInfo    = $q->path_info;        # the resource specification, i.e. everything in the url after xcatws
#my $requestType = $ENV{'REQUEST_METHOD'};
my $requestType = $q->request_method();     # GET, PUT, POST, PATCH, DELETE
my $queryString = $ENV{'QUERY_STRING'};     #todo: remove this when not used any more
#my $userAgent = $ENV{'HTTP_USER_AGENT'};        # curl, etc.
my $userAgent = $q->user_agent();        # the client program: curl, etc.
my %queryhash;          # the queryString will get put into this
my @path = split(/\//, $pathInfo);
shift(@path);       # get rid of the initial /
my $resource    = $path[0];
my $pageContent = '';       # global var containing the ouptut back to the rest client
my $request     = {clienttype => 'ws'};     # global var that holds the request to send to xcatd

my $userName = $q->url_param('userName');
my $password = $q->url_param('password');

#error status codes
my $STATUS_BAD_REQUEST         = "400 Bad Request";
my $STATUS_UNAUTH              = "401 Unauthorized";
my $STATUS_FORBIDDEN           = "403 Forbidden";
my $STATUS_NOT_FOUND           = "404 Not Found";
my $STATUS_NOT_ALLOWED         = "405 Method Not Allowed";
my $STATUS_NOT_ACCEPTABLE      = "406 Not Acceptable";
my $STATUS_TIMEOUT             = "408 Request Timeout";
my $STATUS_EXPECT_FAILED       = "417 Expectation Failed";
my $STATUS_TEAPOT              = "418 I'm a teapot";
my $STATUS_SERVICE_UNAVAILABLE = "503 Service Unavailable";

#good status codes
my $STATUS_OK      = "200 OK";
my $STATUS_CREATED = "201 Created";

my $XCAT_PATH = '/opt/xcat/bin';

my $pdata;     # global var holding either the put data or the post data
if (isPut()) { $pdata = $q->param('PUTDATA'); }
elsif (isPost()) { $pdata = $q->param('POSTDATA'); }

my $DEBUGGING = $q->url_param('debug');      # turn on or off the debugging output by setting debug=1 (or 2) in the url string
if ($DEBUGGING) {
    #if (defined($q->param('PUTDATA')) || defined($q->param('POSTDATA'))) {
    #    addPageContent("put data 1 " . $q->p($q->param('PUTDATA') . "\n"));
    #} elsif (isPut()) {
    #    my $entries = $JSON->decode($q->param('PUTDATA'));
    #    if (scalar(@$entries) >= 1) {
    #        addPageContent("put data 2 \n");
    #        foreach (@$entries) {
    #            addPageContent("$_\n");
    #        }
    #    }
    #}

    #addPageContent($q->p("DEBUG: q->param:\n"));
    #my @params = $q->param;
    #foreach (@params) {
    #    addPageContent($q->p("DEBUG: $_ = " . join(',', $q->param($_)) . "\n"));
    #}
    #addPageContent($q->p("DEBUG: queryString: $queryString\n"));
    #addPageContent($q->p("DEBUG: queryhash (from queryString):" . Dumper(\%queryhash) . "\n"));
    #my %paramshash = $q->Vars;
    #addPageContent($q->p("DEBUG: paramshash (from q->Vars):" . Dumper(\%paramshash) . "\n"));
    #my @urlparams = $q->url_param;
    addPageContent($q->p("DEBUG: q->url_param:\n"));
    foreach ($q->url_param) {
        addPageContent($q->p("DEBUG: $_ = " . join(',', $q->url_param($_)) . "\n"));
    }
    addPageContent($q->p("DEBUG: q->request_method: $requestType\n"));
    addPageContent($q->p("DEBUG: q->user_agent: $userAgent\n"));
    addPageContent($q->p("DEBUG: pathInfo: $pathInfo\n"));
    #addPageContent($q->p("DEBUG: path " . Dumper(@path) . "\n"));
    #foreach (keys(%ENV)) { addPageContent($q->p("DEBUG: ENV{$_}: $ENV{$_}\n")); }
    addPageContent($q->p("DEBUG: resource: $resource\n"));
    addPageContent($q->p("DEBUG: userName=$userName, password=$password\n"));
    #addPageContent($q->p("DEBUG: http() values:\n" . http() . "\n"));
    if ($pdata) { addPageContent($q->p("DEBUG: pdata: $pdata\n")); }
    addPageContent("\n");
    if ($DEBUGGING == 2) {
        sendResponseMsg($STATUS_OK);     # this will also exit
    }
}

# Process the format requested
my $format = $q->url_param('format');
if (!$format) { $format = 'html'; }    # this is the default format

# supported formats
my %formatters = (
    'html' => \&wrapHtml,
    'json' => \&wrapJson,
    'xml'  => \&wrapXml
    );


# puts $queryString into %queryHash
fetchParameter($queryString);       #todo:  stop using and then remove when not used anymore

if (!exists $formatters{$format}) {
    addPageContent("The format '$format' is not supported");
    sendResponseMsg($STATUS_BAD_REQUEST);
}

my $JSON;       # global ptr to the json object
if ($format eq 'json' || isPut() || isPost()) {
	# require JSON dynamically and let them know if it is not installed
	my $jsoninstalled = eval { require JSON; };
	unless ($jsoninstalled) {
        error("JSON perl module missing.  Install perl-JSON before using the xCAT REST web services API.", $STATUS_SERVICE_UNAVAILABLE);
	}
    $JSON = JSON->new();
    if ($q->url_param('pretty')) { $JSON->indent(1); }
}

# require XML dynamically and let them know if it is not installed
# we need XML all the time to send request to xcat, even if thats not the return format requested by the user
my $xmlinstalled = eval { require XML::Simple; };
unless ($xmlinstalled) {
    addPageContent('The XML::Simple perl module is missing.  Install perl-XML-Simple before using the xCAT REST web services API with this format."}');
    sendResponseMsg($STATUS_SERVICE_UNAVAILABLE);
}
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
#debugandexit('here');

#resource handlers
my %resources = (
    groups        => \&groupsHandler,
    images        => \&imagesHandler,
    logs          => \&logsHandler,
    monitors      => \&monitorsHandler,
    networks      => \&networksHandler,
    nodes         => \&nodesHandler,
    notifications => \&notificationsHandler,
    policies      => \&policiesHandler,
    site          => \&siteHandler,
    tables        => \&tablesHandler,
    accounts      => \&accountsHandler,
    objects       => \&objectsHandler,
    vms           => \&vmsHandler,
    debug         => \&debugHandler,
    hypervisor    => \&hypervisorHandler,
    version       => \&versionHandler);

#if no resource was specified
if ($pathInfo =~ /^\/$/ || $pathInfo =~ /^$/) {
    addPageContent($q->p("This is the root page for the xCAT Rest Web Service.  Available resources are:"));
    foreach (sort keys %resources) {
        addPageContent($q->p($_));
    }
    sendResponseMsg($STATUS_OK);     # this will also exit
}

#my @imageFields = (
#    'imagename', 'profile', 'imagetype', 'provmethod', 'osname', 'osvers',
#    'osdistro',  'osarch',  'synclists', 'comments',   'disable');

my $formatType;     # global var for tablesHandler to pass the splitCommas option to wrapHtml

#general tests for valid requests and responses with HTTP codes here
if (!exists($resources{$resource})) {
    addPageContent("Resource '$resource' does not exist");
    sendResponseMsg($STATUS_NOT_FOUND);     # this will also exit
}

# Main function - process user request
handleRequest();        
# end of main

# The flow of functions is:
# handleRequest() - do the whole api call
# *Handler() - the specific handler routine for this resource
# genRequest() - convert xcat request to xml to prepare it for sending to xcatd
# sendRequest() - send the request to xcatd and read the xml response and convert it to a perl structure
# wrapData() - convert the output to the format requested by the user
# wrap*() - the specific formatter the user requested
# sendResponseMsg() - form/send the output header, and then exit

# Call one of the handler routines to process the api call, and then return the output
sub handleRequest {
    if ($userName && $password) {
        $request->{becomeuser}->[0]->{username}->[0] = $userName;
        $request->{becomeuser}->[0]->{password}->[0] = $password;
    }
    # this calls one of the handler routines that are stored in the resources hash
    my @data = $resources{$resource}->();
    wrapData(\@data);
}

# handle all the api calls for listing nodes, modifying nodes, querying nodes, running cmds on nodes, etc.
sub nodesHandler {
    my @responses;
    my @args;
    my $noderange;
    my @envs;

    if (defined $path[1]) {
        $noderange = $path[1];
    }

    if (isGet()) {
        my $subResource;
        if (defined $path[2]) {
            $subResource = $path[2];
            unless (defined($noderange)) {
                error("Invalid nodes and/or groups in noderange",$STATUS_BAD_REQUEST);
            }
            $request->{noderange} = $noderange;

            #use the corresponding command by the subresource name
            if ($subResource eq "power") {
                $request->{command} = 'rpower';
                push @args, 'stat';
            }
            elsif ($subResource eq "energy") {
                $request->{command} = 'renergy';

                #no fields will default to 'all'
                if (defined $q->url_param('field')) {
                    push @args, $q->url_param('field');
                }
                else {
                    push @args, 'all';
                }
            }
            elsif ($subResource eq "status") {
                $request->{command} = 'nodestat';
            }
            elsif ($subResource eq "inventory") {
                $request->{command} = 'rinv';
                if (defined $q->url_param('field')) {
                    push @args, $q->url_param('field');
                }
                else {
                    push @args, 'all';
                }
            }
            elsif ($subResource eq "vitals") {
                $request->{command} = 'rvitals';
                if (defined $q->url_param('field')) {
                    push @args, $q->url_param('field');
                }
                else {
                    push @args, 'all';
                }
            }
            elsif ($subResource eq "scan") {
                $request->{command} = 'rscan';
                if (defined $q->url_param('field')) {
                    push @args, $q->url_param('field');
                }
            }
            else {
                error("Unspported operation on nodes object.",$STATUS_BAD_REQUEST);
            }
        }
        else {
            $request->{command} = 'lsdef';
            push @args, "-t", "node";

            #add the nodegroup into args
            if (defined($noderange)) {
                push @args, "-o", $noderange;
            }

            #maybe it's specified in the parameters
            my @temparray = $q->url_param('field');
            if (scalar(@temparray) > 0) {
                push @args, "-i";
                push @args, join(',', @temparray);
            }
        }
    }
    elsif (isPut()) {       # this could be change node attributes, power state, etc.
        my $subResource;
        my $entries;
        my $entrydata;
        
        unless (defined($noderange)) {
            error("Invalid nodes and/or groups in noderange",$STATUS_BAD_REQUEST);
        }
        $request->{noderange} = $noderange;
        
        unless ($q->param('PUTDATA')) {
                error("No set attribute was supplied.",$STATUS_BAD_REQUEST);
        }
        else {
            # decode_json returns a reference to an array or hash
            $entries = eval { $JSON->decode($q->param('PUTDATA')); };
            if ($@) { error("$@",$STATUS_BAD_REQUEST); }
            debug("entries=" . Dumper($entries));
            #if (scalar(@entries) < 1) {
            #    addPageContent("No set attribute was supplied.");
            #    sendResponseMsg($STATUS_BAD_REQUEST);
            #}
        }
        
        if (defined $path[2]) {
            $subResource = $path[2];

            if (($subResource ne "dsh") && ($subResource ne "dcp")) {
                # For any function other than "dsh" or "dcp",
                # move all operands to the argument list.
                foreach (@$entries) {
                    if (ref($_) eq 'ARRAY') {
                        foreach (@$_) {
                            push @args, $_;
                        }
                    } else {
                        push @args, $_;
                    }
                }
            }
            if ($subResource eq "power") {
                $request->{command} = "rpower";
                my %elements;
                extractData(\%elements, @$entries);
                
                unless (scalar(%elements)) {
                    error("No power operands were supplied.",$STATUS_BAD_REQUEST);
                }
            }
            elsif ($subResource eq "energy") {
                $request->{command} = "renergy";
            }
            elsif ($subResource eq "bootstat" or $subResource eq "bootstate") {
                $request->{command} = "nodeset";
            }
            elsif ($subResource eq "bootseq") {
                $request->{command} = "rbootseq";
            }
            elsif ($subResource eq "setboot") {
                $request->{command} = "rsetboot";
            }
            elsif ($subResource eq "migrate") {
                $request->{command} = "rmigrate";
            }
            elsif ($subResource eq "dsh") {
                $request->{command} = "xdsh";
                my %elements;
                extractData(\%elements, @$entries);
                if (defined($elements{'devicetype'})) {
                    push @args, '--devicetype';
                    push @args, $elements{'devicetype'};
                }
                if (defined($elements{'execute'})) {
                    push @args, '-e';
                }
                if (defined($elements{'environment'})) {
                    push @args, '-E';
                    push @args, $elements{'environment'};
                }
                if (defined($elements{'fanout'})) {
                    push @args, '-f';
                    push @args, $elements{'fanout'};
                }
                if (defined($elements{'nolocale'})) {
                    push @args, '-L';
                }
                if (defined($elements{'userid'})) {
                    push @args, '-l';
                    push @args, $elements{'userid'};
                }
                if (defined($elements{'monitor'})) {
                    push @args, '-m';
                }
                if (defined($elements{'options'})) {
                    push @args, '-o';
                    push @args, $elements{'options'};
                }
                if (defined($elements{'showconfig'})) {
                    push @args, '-q';
                }
                if (defined($elements{'silent'})) {
                    push @args, '-Q';
                }
                if (defined($elements{'remoteshell'})) {
                    push @args, '-r';
                    push @args, $elements{'remoteshell'};
                }
                if (defined($elements{'syntax'})) {
                    push @args, '-S';
                    push @args, $elements{'syntax'};
                }
                if (defined($elements{'timeout'})) {
                    push @args, '-t';
                    push @args, $elements{'timeout'};
                }
                if (defined($elements{'envlist'})) {
                    push @args, '-X';
                    push @args, $elements{'envlist'};
                }
                if (defined($elements{'sshsetup'})) {
                    push @args, '-K';
                    push @args, $elements{'sshsetup'};
                }
                if (defined($elements{'rootimg'})) {
                    push @args, '-i';
                    push @args, $elements{'rootimg'};
                }
                if (defined($elements{'command'})) {
                    push @args, $elements{'command'};
                }
                if (defined($elements{'remotepasswd'})) {
                    push @envs, 'DSH_REMOTE_PASSWORD=' . $elements{'remotepasswd'};
                    push @envs, 'DSH_FROM_USERID=root';
                    push @envs, 'DSH_TO_USERID=root';
                }
            }
            elsif ($subResource eq "dcp") {
                $request->{command} = "xdcp";
                my %elements;
                extractData(\%elements, @$entries);
                if (defined($elements{'fanout'})) {
                    push @args, '-f';
                    push @args, $elements{'fanout'};
                }
                if (defined($elements{'rootimg'})) {
                    push @args, '-i';
                    push @args, $elements{'rootimg'};
                }
                if (defined($elements{'options'})) {
                    push @args, '-o';
                    push @args, $elements{'options'};
                }
                if (defined($elements{'rsyncfile'})) {
                    push @args, '-F';
                    push @args, $elements{'rsyncfile'};
                }
                if (defined($elements{'preserve'})) {
                    push @args, '-p';
                }
                if (defined($elements{'pull'})) {
                    push @args, '-P';
                }
                if (defined($elements{'showconfig'})) {
                    push @args, '-q';
                }
                if (defined($elements{'remotecopy'})) {
                    push @args, '-r';
                    push @args, $elements{'remotecopy'};
                }
                if (defined($elements{'recursive'})) {
                    push @args, '-R';
                }
                if (defined($elements{'timeout'})) {
                    push @args, '-t';
                    push @args, $elements{'timeout'};
                }
                if (defined($elements{'source'})) {
                    push @args, $elements{'source'};
                }
                if (defined($elements{'target'})) {
                    push @args, $elements{'target'};
                }
            }
            else { error("unsupported node resource $subResource.", $STATUS_BAD_REQUEST); }
        }
        else {      # setting node attributes in the db
            #todo: change this to use lissa's routines
            $request->{command} = "chdef";
            push @args, "-t", "node";
            push @args, "-o", $request->{noderange};

            # input is a json object with key/value pairs
            while (my ($name, $val) = each (%$entries)) {
                push @args, $name . "=" . $val;
            }
        }
    }
    elsif (isPost()) {
        $request->{command} = 'mkdef';
        push @args, "-t", "node";

        unless (defined($noderange)) {
            error("No nodename was supplied.",$STATUS_BAD_REQUEST);
        }

        push @args, "-o", $noderange;

        if ($q->param('POSTDATA')) {
            # decode_json returns a reference to an array or hash
            my $entries = eval { $JSON->decode($q->param('POSTDATA')); };
            if ($@) { error("$@",$STATUS_BAD_REQUEST); }
            debug("entries=" . Dumper($entries));
            while (my ($name, $val) = each (%$entries)) {
                push @args, $name . "=" . $val;
            }
        }
        else { error('no post data given.', $STATUS_BAD_REQUEST); }
    }
    elsif (isDelete()) {

        #F the nodeRange for delete is specified in the URI
        $request->{command} = 'rmdef';
        push @args, "-t", "node";
        unless (defined($noderange)) {
            error("No nodename was supplied.",$STATUS_BAD_REQUEST);
        }
        push @args, "-o", $noderange;
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    if (@envs) {
        push @{$request->{env}}, @envs;
    }
    debug("request: " . Dumper($request));
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

#get is done
#post and delete are done but not tested
#groupfiles4dsh is done but not tested
sub groupsHandler {
    my @responses;
    my @args;
    my $groupName;

    my @groupFields = ('groupname', 'grouptype', 'members', 'wherevals', 'comments', 'disable');

    #is the group name in the URI?
    if (defined $path[1]) {
        $groupName = $path[1];
    }

    #in the query string?
    else {
        $groupName = $q->param('groupName');
    }

    if (isGet()) {
        if (defined $groupName) {
            $request->{command} = 'tabget';
            push @args, "groupname=$groupName";
            if (defined $q->param('field')) {
                foreach ($q->param('field')) {
                    push @args, "nodegroup.$_";
                }
            }
            else {
                foreach (@groupFields) {
                    push @args, "nodegroup.$_";
                }
            }
        }
        else {
            $request->{command} = 'tabdump';
            push @args, 'nodegroup';
        }
    }

    #does it make sense to even have this?
    elsif (isPost()) {
        my $nodeRange = $q->param('nodeRange');
        if ((defined $groupName) && (defined $nodeRange)) {
            $request->{command} = 'mkdef';
            push @args, '-t';
            push @args, 'group';
            push @args, '-o';
            push @args, $groupName;
            push @args, "members=$nodeRange";
        }
        else {
            addPageContent("A node range and group name must be specified for creating a group");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    elsif (isPut()) {

        #handle groupfiles4dsh -p /tmp/nodegroupfiles
        if ($q->param('command') eq "4dsh") {
            if ($q->param('path')) {
                $request->{command} = 'groupfiles4dsh';
                push @args, "p=$q->param('path')";
            }
            else {
                addPageContent("The path must be specified for creating directories for dsh");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
        else {
            if (defined $groupName && defined $q->param('fields')) {
                $request->{command} = 'nodegrpch';
                push @args, $groupName;
                push @args, $q->param('field');
            }
            else {
                addPageContent("The group and fields must be specified to update groups");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
    }
    elsif (isDelete()) {
        if (defined $groupName) {
            $request->{command} = 'rmdef';
            push @args, '-d';
            push @args, 'group';
            push @args, '-o';
            push @args, $groupName;
        }
        else {
            addPageContent("The group must be specified to delete a group");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

#get is done, nothing else
sub imagesHandler {
    my @responses;
    my @args;
    my $image;
    my $subResource;

    if (defined($path[1])) {
        $image = $path[1];
    }

    if (isGet()) {
        $request->{command} = 'lsdef';
        push @args, '-t', 'osimage';
        if (defined $image) {
            push @args, '-o', $image;
        }
        if (defined($q->param('field'))) {
            push @args, '-i';
            push @args, join(',', $q->param('field'));
        }
        if (defined($q->param('criteria'))) {
            foreach ($q->param('criteria')) {
                push @args, '-w', "$_";
            }
        }
    }
    elsif (isPost()) {
        my $operationname = $image;
        my $entries;
        my %entryhash;

        #check the post data
        unless (defined($q->param('POSTDATA'))) {
            addPageContent("Invalid Parameters");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
        $entries = $JSON->decode($q->param('POSTDATA'));
        if (scalar(@$entries) < 1) {
            addPageContent("No set attribute was supplied.");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }

        extractData(\%entryhash, $entries);

        #for image capture
        if ($operationname eq 'capture') {
            $request->{command} = 'imgcapture';
            if (defined($entryhash{'nodename'})) {
                $request->{noderange} = $entryhash{'nodename'};
            }
            else {
                addPageContent('No node range.');
                sendResponseMsg($STATUS_BAD_REQUEST);
            }

            if (defined($entryhash{'profile'})) {
                push @args, '-p';
                push @args, $entryhash{'profile'};
            }
            if (defined($entryhash{'osimage'})) {
                push @args, '-o';
                push @args, $entryhash{'osimage'};
            }
            if (defined($entryhash{'bootinterface'})) {
                push @args, '-i';
                push @args, $entryhash{'bootinterface'};
            }
            if (defined($entryhash{'netdriver'})) {
                push @args, '-n';
                push @args, $entryhash{'netdriver'};
            }
            if (defined($entryhash{'device'})) {
                push @args, '-d';
                push @args, $entryhash{'device'};
            }
        }
        elsif ($operationname eq 'export') {             
            $request->{command} = 'imgexport';           
            if (defined($entryhash{'osimage'})) {        
                push @args, $entryhash{'osimage'};       
            }                                            
            else {                                       
                addPageContent('No image specified');   
                sendResponseMsg($STATUS_BAD_REQUEST);    
            }
                                                          
            if (defined($entryhash{'destination'})) {   
                push @args, $entryhash{'destination'};  
            }
            if (defined($entryhash{'postscripts'})) {    
                push @args, '-p';                        
                push @args, $entryhash{'postscripts'};   
            }
            if (defined($entryhash{'extra'})) {         
                push @args, '-e';                       
                push @args, $entryhash{'extra'};        
            }
            if (defined($entryhash{'remotehost'})) {        
                push @args, '-R';                        
                push @args, $entryhash{'remotehost'};       
            }
            if (defined($entryhash{'verbose'})) {   
                push @args, '-v';                        
            }  
        }                                            
        elsif ($operationname eq 'import') {            
            $request->{command} = 'imgimport';          
            if (defined($entryhash{'osimage'})) {       
                push @args, $entryhash{'osimage'};      
            }                                           
            else {                                      
                addPageContent('No image specified');  
                sendResponseMsg($STATUS_BAD_REQUEST);   
            }
                                                     
            if (defined($entryhash{'profile'})) {        
                push @args, '-f';                        
                push @args, $entryhash{'profile'};       
            }
            if (defined($entryhash{'remotehost'})) {        
                push @args, '-R';                        
                push @args, $entryhash{'remotehost'};       
            }
            if (defined($entryhash{'postscripts'})) {   
                push @args, '-p';                       
                push @args, $entryhash{'postscripts'};  
            }
            
            if (defined($entryhash{'verbose'})) {   
                push @args, '-v';                        
            }                                           
        }            
    }
    elsif (isPut()) {

        #check the operation type
        unless (defined $path[2]) {
            addPageContent("The subResource $subResource does not exist");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }

        $subResource = $path[2];

        #check the image name
        unless (defined $image) {
            addPageContent("The image name is required to clean an os image");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }

        if ($subResource eq 'check') {
            $request->{command} = 'chkosimage';
            if (defined($q->param('PUTDATA'))) {
                push @args, '-c';
            }
            push @args, $image;
        }
        else {
            addPageContent("The subResource $subResource does not exist");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    elsif (isDelete()) {
        if (defined $image) {
            $request->{command} = 'rmimage';
            if (defined $q->param('verbose')) {
                push @args, '-v';
            }
            push @args, $image;
        }
        elsif (defined $q->param('os') && defined $q->param('arch') && defined $q->param('profile')) {
            push @args, '-o';
            push @args, $q->param('os');
            push @args, '-a';
            push @args, $q->param('arch');
            push @args, '-p';
            push @args, $q->param('profile');
        }
        else {
            addPageContent(
                "Either the image name or the os, architecture and profile must be specified to remove an image");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

#complete
sub logsHandler {
    my @responses;
    my @args;
    my $logType;

    if (defined $path[1]) {
        $logType = $path[1];
    }

    #in the query string?
    else {
        $logType = $q->param('logType');
    }
    my $nodeRange = $q->param('nodeRange');

    #no real output unless the log type is defined
    if (!defined $logType) {
        addPageContent("Current logs available are auditlog and eventlog");
        sendResponseMsg($STATUS_BAD_REQUEST);
        exit(0);
    }

    if (isGet()) {
        if ($logType eq "reventLog") {
            if (defined $nodeRange) {
                $request->{command} = 'reventlog';
                push @args, $nodeRange;
                if (defined $q->param('count')) {
                    push @args, $q->param('count');
                }
            }
            else {
                addPageContent("nodeRange must be specified to GET remote event logs");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
        else {
            $request->{command} = 'tabdump';
            push @args, $logType;
        }
    }

    #this clears the log
    elsif (isPut()) {
        if ($logType eq "reventlog") {
            if (defined $nodeRange) {
                $request->{command} = 'reventlog';
                push @args, $nodeRange;
                push @args, 'clear';
            }
            else {
                addPageContent("nodeRange must be specified to clean remote event logs");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
        else {

            #should it return the removed entries?
            if (defined $q->param('showRemoved')) {
                push @args, '-V';
            }
            if (defined $q->param('count') || defined $q->param('percent') || defined $q->param('lastRecord')) {

                #remove some of the entries
                $request->{command} = 'tabprune';

                #remove a certain number of records
                if (defined $q->param('count')) {
                    push @args, ('-n', $q->param('count'));
                }

                #remove a percentage of the records
                if (defined $q->param('percent')) {
                    push @args, ('-p', $q->param('percent'));
                }

                #remove all records before this record
                if (defined $q->param('lastRecord')) {
                    push @args, ('-i', $q->param('lastRecord'));
                }
            }
            else {
                $request->{command} = 'tabprune';

                #-a removes all
                push @args, '-a';
            }
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

#complete
#todo: delete this handler.  We are de-emphasizing the monitoring plugins in xcat, so don't need a rest api for them.
sub monitorsHandler {
    my @responses;
    my @args;
    my $monitor;

    if (defined $path[1]) {
        $monitor = $path[1];
    }

    #in the query string?
    elsif (defined $q->param('monitor')) {
        push @args, $q->param('monitor');
    }
    if (defined $monitor) {
        push @args, $monitor;
    }

    if (isGet()) {
        $request->{command} = 'monls';
    }
    elsif (isPost()) {
        $request->{command} = 'monadd';
        if ($q->param('nodeStatMon')) {
            push @args, '-n';
        }

        #get the plug-in specific settings array
        foreach ($q->param('pluginSetting')) {
            push @args, '-s';
            push @args, $_;
        }
    }
    elsif (isDelete()) {
        $request->{command} = 'monrm';
    }
    elsif (isPut() || isPatch()) {
        my $action = $q->param('action');
        if ($action eq "start") {
            $request->{command} = 'monstart';
        }
        elsif ($action eq "stop") {
            $request->{command} = 'monstop';
        }
        elsif ($action eq "config") {
            $request->{command} = 'moncfg';
        }
        elsif ($action eq "deconfig") {
            $request->{command} = 'mondeconfig';
        }
        else {
            unsupportedRequestType();
        }
        if (!defined $q->param('nodeRange')) {

            #error
        }
        else {
            push @args, $q->param('nodeRange');
        }
        if (defined $q->param('remote')) {
            push @args, '-r';
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

sub networksHandler {
    my @responses;
    my @args;
    my $netname = '';

    if (isGet()) {
        $request->{command} = 'lsdef';
        push @{$request->{arg}}, '-t', 'network';
        if (defined($path[1])) {
            push @{$request->{arg}}, '-o', $path[1];
        }
        my @temparray = $q->param('field');

        #add the field name to get
        if (scalar(@temparray) > 0) {
            push @{$request->{arg}}, '-i';
            push @{$request->{arg}}, join(',', @temparray),;
        }
    }
    elsif (isPut() || isPost()) {
        my $entries;
        my $iscommand = 0;
        if (isPut()) {
            $request->{command} = 'chdef';
            if (defined($path[1])) {
                if ($path[1] eq "makehosts" || $path[1] eq "makedns") {
                    # Issue makehost/makedns directly
                    $request->{command} = $path[1];
                    $iscommand = 1;
                }
            }
        }
        else {
            $request->{command} = 'mkdef';
        }

        if (!$iscommand) {
            if (defined $path[1]) {
                $netname = $path[1];
            }

            if ($netname eq '') {
                addPageContent('A network name must be specified.');
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        
            push @{$request->{arg}}, '-t', 'network', '-o', $netname;
        
            if (defined($q->param('PUTDATA'))) {
                $entries = $JSON->decode($q->param('PUTDATA'));
            }
            elsif (defined($q->param('POSTDATA'))) {
                $entries = $JSON->decode($q->param('POSTDATA'));
            }
            else {
                addPageContent("No Field and Value map was supplied.");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }

            if (scalar($entries) < 1) {
                addPageContent("No Field and Value map was supplied.");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
            foreach (@$entries) {
                push @{$request->{arg}}, $_;
            }
        }
    }
    elsif (isDelete()) {
        $request->{command} = 'rmdef';

        if (defined $path[1]) {
            $netname = $path[1];
        }
        if ($netname eq '') {
            addPageContent('A network name must be specified.');
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
        push @{$request->{arg}}, '-t', 'network', '-o', $netname;
    }
    else {
        unsupportedRequestType();
    }
    @responses = sendRequest(genRequest());

    return @responses;
}

#complete, unless there is some way to alter existing notifications
sub notificationsHandler {
    my @responses;
    my @args;

    my @notificationFields = ('filename', 'tables', 'tableops', 'comments', 'disable');

    #does not support using the notification fileName in the URI

    if (isGet()) {
        if (defined $q->param('fileName')) {
            $request->{command} = 'gettab';
            push @args, "filename" . $q->param('fileName');

            #if they specified the fields, just get those
            if (defined $q->param('field')) {
                foreach ($q->param('field')) {
                    push @args, $_;
                }
            }

            #else show all of the fields
            else {
                foreach (@notificationFields) {
                    push @args, "notification.$_";
                }
            }
        }
        else {
            $request->{command} = 'tabdump';
            push @args, "notification";
        }
    }
    elsif (isPost()) {
        $request->{command} = 'regnotif';
        if (!defined $q->param('fileName') || !defined $q->param('table') || !defined $q->param('operation')) {
            addPageContent("fileName, table and operation must be specified for a POST on /notifications");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
        else {
            push @args, $q->param('fileName');
            my $tables;
            foreach ($q->param('table')) {
                $tables .= "$_,";
            }

            #get rid of the extra comma
            chop($tables);
            push @args, $tables;
            push @args, '-o';
            my $operations;
            foreach ($q->param('operation')) {
                $operations .= "$_,";
            }

            #get rid of the extra comma
            chop($operations);
            push @args, $q->param('operation');
        }
    }
    elsif (isDelete()) {
        $request->{command} = 'unregnotif';
        if (defined $q->param('fileName')) {
            push @args, $q->param('fileName');
        }
        else {
            addPageContent("fileName must be specified for a DELETE on /notifications");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    addPageContent("request is " . Dumper($request));
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

#complete
sub policiesHandler {
    my @responses;
    my @args;
    my $priority;

    my @policyFields =
        ('priority', 'name', 'host', 'commands', 'noderange', 'parameters', 'time', 'rule', 'comments', 'disable');

    #does it specify the prioirty in the URI?
    if (defined $path[1]) {
        $priority = $path[1];
    }

    #in the query string?
    elsif (defined $q->param('priority')) {
        $priority = $q->param('priority');
    }

    if (isGet()) {
        if (defined $priority) {
            $request->{command} = 'gettab';
            push @args, "priority=$priority";
            my @fields = $q->param('field');

            #if they specified fields to retrieve
            if (@fields) {
                push @args, @fields;
            }

            #give them everything if nothing is specified
            else {
                foreach (@policyFields) {
                    push @args, "policy.$_";
                }
            }
        }
        else {
            $request->{command} = 'tabdump';
            push @args, 'policy';
        }
    }
    elsif (isPost()) {
        if (defined $priority) {
            $request->{command} = 'tabch';
            push @args, "priority=$priority";
            for ($q->param) {
                if ($_ ne /priority/) {
                    push @args, "policy.$_=" . $q->param($_);
                }
            }
        }

        #some response about the priority being required
        else {
            addPageContent("The priority must be specified when creating a policy");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    elsif (isDelete()) {

        #just allowing a delete by priority at the moment, could expand this to anything
        if (defined $priority) {
            $request->{command} = 'tabch';
            push @args, '-d';
            push @args, "priority=$priority";
            push @args, "policy";
        }
    }
    elsif (isPut() || isPatch()) {
        if (defined $priority) {
            $request->{command} = 'tabch';
            push @args, "priority=$priority";
            for ($q->param) {
                if ($_ ne /priority/) {
                    push @args, "policy.$_=" . $q->param($_);
                }
            }
        }

        #some response about the priority being required
        else {
            addPageContent("The priority must be specified when updating a policy");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    addPageContent("request is " . Dumper($request));
    my $req = genRequest();
    @responses = sendRequest($req);

    return @responses;
}

#complete
sub siteHandler {
    my @data;
    my @responses;
    my @args;

    if (isGet()) {
        $request->{command} = 'lsdef';
        push @{$request->{arg}}, '-t', 'site', '-o', 'clustersite';
        my @temparray = $q->param('field');

        #add the field name to get
        if (scalar(@temparray) > 0) {
            push @{$request->{arg}}, '-i';
            push @{$request->{arg}}, join(',', @temparray);
        }
    }
    elsif (isPut()) {
        $request->{command} = 'chdef';
        push @{$request->{arg}}, '-t', 'site', '-o', 'clustersite';
		unless ($q->param('PUTDATA')) {
			#temporary allowance for the put data to be contained in the queryString
			unless ($queryhash{'putData'}) {
				addPageContent("No set attribute was supplied.");
				sendResponseMsg($STATUS_BAD_REQUEST);
			}
			else {
                    foreach my $put (@{$queryhash{'putData'}}) {
                        my ($key, $value) = split(/=/, $put, 2);
                        if ($key eq 'field' && $value) {
                            push @{$request->{arg}}, $value;
                        }
                    }
                }
		} else {
			if ($q->param('PUTDATA')) {
				my $entries = $JSON->decode($q->param('PUTDATA'));
				foreach (@$entries) {
					push @{$request->{arg}}, $_;
				}
			}
			else {
				addPageContent("No Field and Value map was supplied.");
				sendResponseMsg($STATUS_BAD_REQUEST);
			}
		}
    }
    else {
        unsupportedRequestType();
    }

    my $req = genRequest();
    @responses = sendRequest($req);
    return @responses;
}

#provide direct table access
#complete and tested on the site table
#use of the actual DELETE doesn't seem to fit here, since a resource would not be deleted
#using PUT or PATCH instead, though it doesn't feel all that correct either
sub tablesHandler {
    my @responses;
    my $table;
    my @args;

    #is the table name specified in the URI?
    if (defined $path[1]) {
        $table = $path[1];
    }

    #handle all gets
    if (isGet()) {

        #table was specified
        if (defined $table) {
            if (defined($q->param('col'))) {
                $request->{command} = 'gettab';
                push @args, $q->param('col') . '=' . $q->param('value');
                my @temparray = $q->param('attribute');
                foreach (@temparray) {
                    push @args, $table . '.' . $_;
                }
            }
            else {
                $request->{command} = 'tabdump';
                push @args, $table;
                if (!defined $q->param('desc')) {
                    $formatType = 'splitCommas';
                }
            }
        }
        else {
            $request->{command} = 'tabdump';
        }
    }
    elsif (isPut() || isPatch()) {
        my $condition = $q->param('condition');
        my @vals;
        my $entries;
        if (!defined $condition) {
            unless ($q->param('PUTDATA')) {
                foreach my $put (@{$queryhash{'putData'}}) {
                    my ($key, $value) = split(/=/, $put, 2);
                    if ($key eq 'condition' && $value) {
                        $condition = $value;
                    }
                }
                foreach my $put (@{$queryhash{'putData'}}) {
                    my ($key, $value) = split(/=/, $put, 2);
                    if ($key eq 'value') {
                        push(@vals, $value);
                    }
	            }
            }
            else {
                $entries = $JSON->decode($q->param('PUTDATA'));
                if (scalar(@$entries) < 1) {
                    addPageContent("No set attribute was supplied.");
                    sendResponseMsg($STATUS_BAD_REQUEST);
                }
            }
        }

        if (!defined $table || !defined $condition) {
            if (scalar(@$entries) < 1) {
                addPageContent("The table and condition must be specified when adding, changing or deleting an entry");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
        $request->{command} = 'tabch';
        my $del;
        if (!defined $q->param('delete')) {
            foreach my $put (@{$queryhash{'putData'}}) {
                my ($key, $value) = split(/=/, $put, 2);
                if ($key eq 'delete') {
                    $del = 1;
                }
            }
        }

        if (defined $q->param('delete') || defined $del) {
            push @args, '-d';
            push @args, $condition;
            push @args, $table;
        }
        elsif (defined $condition) {
            push @args, $condition;
            if ($q->param('value')) {
                for ($q->param('value')) {
                    push @args, "$table.$_";
                }
            }
            else {
                @args = (@args, @vals);
            }
        }
        else {
            foreach (@$entries) {
                push @args, split(/ /,$_);
            }
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);
    return @responses;
}

#done aside from being able to change cluster users, which xcat can't do yet
sub accountsHandler {
    my @responses;
    my @args;
    my $key = $q->param('key');

    my @accountFields = ('key', 'username', 'password', 'cryptmethod', 'comments', 'disable');

    if (isGet()) {

        #passwd table
        if (!defined $q->param('clusterUser')) {
            if (defined $key) {
                $request->{command} = 'tabget';
                push @args, "key=$key";
                if (defined $q->param('field')) {
                    foreach ($q->param('field')) {
                        push @args, "passwd.$_";
                    }
                }
                else {
                    foreach (@accountFields) {
                        push @args, "passwd.$_";
                    }
                }
            }
            else {
                $request->{command} = 'tabdump';
                push @args, 'passwd';
            }
        }

        #cluster user list
        else {
            $request->{command} = 'xcatclientnnr';
            push @args, 'clusteruserlist';
            push @args, '-p';
        }
    }
    elsif (isPost()) {
        if (!defined $q->param('clusterUser')) {
            if (defined $key) {
                $request->{command} = 'tabch';
                push @args, "key=$key";
                for ($q->param) {
                    if ($_ !~ /key/) {
                        push @args, "passwd.$_=" . $q->param($_);
                    }
                }
            }
            else {
                addPageContent("The key must be specified when creating a non-cluster user");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }

        #active directory user
        else {
            if (defined $q->param('userName') && defined $q->param('userPass')) {
                $request->{command} = 'xcatclientnnr';
                push @args, 'clusteruseradd';
                push @args, $q->param('userName');
                push @{$request->{arg}}, @args;
                $request->{environment} = {XCAT_USERPASS => $q->param('userPass')};
            }
            else {
                addPageContent("The key must be specified when creating a cluster user");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
    }
    elsif (isDelete()) {
        if (!defined $q->param('clusterUser')) {

            #just allowing a delete by key at the moment, could expand this to anything
            if (defined $key) {
                $request->{command} = 'tabch';
                push @args, '-d';
                push @args, "key=$key";
                push @args, "passwd";
            }
            else {
                addPageContent("The key must be specified when deleting a non-cluster user");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
        else {
            if (defined $q->param('userName')) {
                $request->{command} = 'xcatclientnnr';
                push @args, 'clusteruserdel';
                push @args, $q->param('userName');
            }
            else {
                addPageContent("The userName must be specified when deleting a cluster user");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }
    }
    elsif (isPut() || isPatch()) {
        if (!defined $q->param('clusterUser')) {
            if (defined $key) {
                $request->{command} = 'tabch';
                push @args, "key=$key";
                for ($q->param) {
                    if ($_ !~ /key/) {
                        push @args, "passwd.$_=" . $q->param($_);
                    }
                }
            }
            else {
                addPageContent("The key must be specified when updating a non-cluster user");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
        }

        #TODO:  there isn't currently a way to update cluster users
        else {

        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);
    return @responses;
}

sub objectsHandler {
    my @responses;
    my @args;
    my @objectTypeList = (
        "auditlog", "boottarget", "eventlog",     "firmware", "group",  "monitoring",
        "network",  "node",       "notification", "osimage",  "policy", "route",
        "site");

    #my %objectTypes;
    #foreach my $item (@objectTypeList) { $objectTypes{$item} = 1 }
    my @objectTypes;
    my @objects;
    if (defined $path[1]) {
        $objectTypes[0] = $path[1];
        if (defined $path[2]) {
            $objects[0] = $path[2];
        }
    }
    if (defined $q->param('objectType')) {
        @objectTypes = $q->param('objectType');
    }
    if (defined $q->param('object')) {
        @objects = $q->param('object');
    }

    if ($q->param('verbose')) {
        push @args, '-v';
    }

    if (isGet()) {
        if (defined $objectTypes[0]) {
            $request->{command} = 'lsdef';
            push @args, '-l';
            push @args, '-t';
            push @args, join(',', @objectTypes);
            if (defined $objects[0]) {
                push @args, '-o';
                push @args, join(',', @objects);
            }
            if ($q->param('info')) {
                push @args, '-h';
            }
        }
        else {
            if ($q->param('info')) {
                push @args, '-h';
            }
            else {

                #couldn't find a way to do this through xcatd, so shortcutting the request
                my %resp = (data => \@objectTypeList);
                return (\%resp);
            }
        }
    }
    elsif (isPut()) {
        $request->{command} = 'chdef';
        if ($q->param('verbose')) {
            push @args, '-v';
        }
        if (!defined $q->param('objectType')) {
            addPageContent("The object must be specified.");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
        else {
            push @args, '-t';
            push @args, join(',', $q->param('objectType'));
        }
        if ($q->param('objectName')) {
            push @args, join(',', $q->param('objectName'));
        }
        if ($q->param('dynamic')) {
            push @args, '-d';
        }
        if ($q->param('minus')) {
            push @args, '-m';
        }
        if ($q->param('plus')) {
            push @args, '-p';
        }
        if (defined $q->param('field')) {
            foreach ($q->param('field')) {

                #if it has ==, !=. =~ or !~ operators in the field, use the -w option
                if (/==|!=|=~|!~/) {
                    push @args, '-w';
                }
                push @args, $_;
            }
        }
        if ($q->param('nodeRange')) {
            push @args, $q->param('nodeRange');
        }

    }
    elsif (isPost()) {
        $request->{command} = 'mkdef';
        if ($q->param('verbose')) {
            push @args, '-v';
        }
        if (!defined $q->param('objectType')) {
            addPageContent("The object must be specified.");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
        else {
            push @args, '-t';
            push @args, join(',', $q->param('objectType'));
        }
        if ($q->param('objectName')) {
            push @args, join(',', $q->param('objectName'));
        }
        if ($q->param('dynamic')) {
            push @args, '-d';
        }
        if ($q->param('force')) {
            push @args, '-f';
        }
        if (defined $q->param('field')) {
            foreach ($q->param('field')) {

                #if it has ==, !=. =~ or !~ operators in the field, use the -w option
                if (/==|!=|=~|!~/) {
                    push @args, '-w';
                }
                push @args, $_;
            }
        }
        if ($q->param('nodeRange')) {
            push @args, $q->param('nodeRange');
        }

    }
    elsif (isDelete()) {
        $request->{command} = 'rmdef';
        if (defined $q->param('info')) {
            push @args, '-h';
        }
        elsif (defined $q->param('all')) {
            push @args, '-a';
        }
        elsif (defined $objectTypes[0]) {
            push @args, '-t';
            push @args, join(',', @objectTypes);
            if (defined $objects[0]) {
                push @args, '-o';
                push @args, join(',', @objects);
            }
        }
        else {
            addPageContent(
"Either the help info must be requested or the object must be specified or the flag that indicates everything should be removed."
            );
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
        if (defined $q->param('nodeRange')) {
            push @args, $q->param('nodeRange');
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    @responses = sendRequest($req);
    return @responses;
}

#complete i think, tho chvm could handle args better
sub vmsHandler {
    my @args;
    my $noderange;
    my $subResource;
    if (defined $path[1]) {
        $noderange = $path[1];
        $request->{noderange} = $noderange;
    }
    else {
        addPageContent("Invalid nodes and/or groups in noderange");
        sendResponseMsg($STATUS_BAD_REQUEST);
    }

    if (isGet()) {
        $request->{command} = 'lsvm';
        if (defined $q->param('all')) {
            push @args, '-a';
        }
        
        # for z/VM
        if (defined $q->param('networknames')) {
            push @args, '--getnetworknames';
        }
	        
        if (defined $q->param('network')) {
            push @args, '--getnetwork';
            push @args, $q->param('getnetwork');
        }
	        
        if (defined $q->param('diskpoolnames')) {
            push @args, '--diskpoolnames';
        }
	        
        if (defined $q->param('diskpool')) {
            push @args, '--diskpool';
            push @args, $q->param('diskpool');
        }
    }
    elsif (isPost()) {
        my $entries;
        my %entryhash;
        my $position;
        $request->{command} = 'mkvm';
        unless ($q->param('POSTDATA')) {
            addPageContent("Invalid Parameters");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }

        #collect all parameters from the postdata
        my $entries = $JSON->decode($q->param('POSTDATA'));
        if (scalar(@$entries) < 1) {
            addPageContent("No set attribute was supplied.");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }

        extractData(\%entryhash, $entries);

        #for system p
        if (defined $entryhash{'cec'}) {
            push @args, '-c';
            push @args, $entryhash{'cec'};
        }

        if (defined $entryhash{'startId'}) {
            push @args, '-i';
            push @args, $entryhash{'startId'};
        }

        if (defined $entryhash{'source'}) {
            push @args, '-l';
            push @args, $entryhash{'source'};
        }

        if (defined $entryhash{'profile'}) {
            push @args, '-p';
            push @args, $entryhash{'profile'};
        }

        if (defined $entryhash{'full'}) {
            push @args, '--full';
        }

        #for KVM & Vmware
        if (defined $entryhash{'master'}) {
            push @args, '-m';
            push @args, $entryhash{'master'};
        }

        if (defined $entryhash{'disksize'}) {
            push @args, '-s';
            push @args, $entryhash{'disksize'};
        }

        if (defined $entryhash{'memory'}) {
            push @args, '--mem';
            push @args, $entryhash{'memory'};
        }

        if (defined $entryhash{'cpu'}) {
            push @args, '--cpus';
            push @args, $entryhash{'cpu'};
        }

        if (defined $entryhash{'force'}) {
            push @args, '-f';
        }
        
        # for z/VM
        if (defined $entryhash{'userid'}) {
            push @args, '--userid';
            push @args, $entryhash{'userid'};
        }
	
        if (defined $entryhash{'size'}) {
            push @args, '--size';
            push @args, $entryhash{'size'};
        }
	        
        if (defined $entryhash{'password'}) {
            push @args, '--password';
            push @args, $entryhash{'password'};
        }
	        
        if (defined $entryhash{'privilege'}) {
            push @args, '--privilege';
            push @args, $entryhash{'privilege'};
        }
	        
        if (defined $entryhash{'diskpool'}) {
            push @args, '--diskpool';
            push @args, $entryhash{'diskpool'};
        }
	        
        if (defined $entryhash{'diskvdev'}) {
            push @args, '--diskVdev';
            push @args, $entryhash{'diskvdev'};
        }
    }
    elsif (isPut()) {
        $request->{command} = 'chvm';
        if ($q->param('PUTDATA')) {
            my $entries = $JSON->decode($q->param('PUTDATA'));
            if (scalar(@$entries) < 1) {
                addPageContent("No Field and Value map was supplied.");
                sendResponseMsg($STATUS_BAD_REQUEST);
            }
            foreach (@$entries) {
                # Handle blank delimited parameters
                push @args, split(/ /,$_);
            }
        }
        else {
            addPageContent("No Field and Value map was supplied.");
            sendResponseMsg($STATUS_BAD_REQUEST);
        }
    }
    elsif (isDelete()) {
        $request->{command} = 'rmvm';
        if (defined $q->param('retain')) {
            push @args, '-r';
        }
        if (defined $q->param('service')) {
            push @args, '--service';
        }
    }
    else {
        unsupportedRequestType();
    }

    push @{$request->{arg}}, @args;
    my $req       = genRequest();
    my @responses = sendRequest($req);
    return @responses;
}

sub versionHandler {
    addPageContent($q->p("API version is $VERSION"));
    sendResponseMsg($STATUS_OK);
    exit(0);
}

sub hypervisorHandler {                                                
    my @responses;                                             
    my @args;                                                  
    if (isPut()) {                                             
        my %entryhash;                                         
        if (defined $path[1]) {                                
            $request->{noderange} = $path[1];                  
        }                                                      
        else {                                                 
            addPageContent("Invalid nodes and/or groups in node in noderange");
            sendResponseMsg($STATUS_BAD_REQUEST);              
        }                                                      
                                                               
        if (defined $path[2]) {                                
            $request->{command} = $path[2];                    
        }                                                      
        else {                                                 
            $request->{command} = 'chhypervisor';              
        }                                                      
        my $entries = $JSON->decode( $q->param('PUTDATA') );
        if (scalar(@$entries) < 1) {                           
            addPageContent("No set attribute was supplied.");  
            sendResponseMsg($STATUS_BAD_REQUEST);              
        }                                                      
                                                               
        foreach (@$entries) {
            push @args, split(/ /,$_);
        }                  
                                                               
        push @{$request->{arg}}, @args;                        
        my $req = genRequest();                                
        @responses = sendRequest($req);                        
        return @responses;                                     
    }                                                          
}

#for operations that take a 'long' time to finish, this will provide the interface to check their status
#todo: this is not supported in xcatd yet, so not sure what to do about this one
sub jobsHandler {
}

sub debugHandler {                                             
    my @responses;                                             
    my @args;                                                  
    if (isPut()) {                                             
        my %entryhash;                                         
        $request->{command} = 'xcatclientnnr xcatdebug';       
                                                               
        #push @args, 'xcatdebug';                              
        my $entries = $JSON->decode( $q->param('PUTDATA') );
        if (scalar(@$entries) < 1) {                           
            addPageContent("No set attribute was supplied.");  
            sendResponseMsg($STATUS_BAD_REQUEST);              
        }                                                      
                                                               
        foreach (@$entries) {
            push @{$request->{arg}}, $_;
        }                                                      
                                                               
        push @{$request->{arg}}, @args;                        
        my $req = genRequest();                                
        @responses = sendRequest($req);                        
        return @responses;                                     
    }                                                          
}                   

# if debugging, output the given string
sub debug {
    if (!$DEBUGGING) { return; }
    addPageContent($q->p("DEBUG: $_[0]\n"));
}

# when having bugs that cause this cgi to not produce any output, output something and then exit.
sub debugandexit {
    addPageContent("$_[0]\n");
    sendResponseMsg($STATUS_OK);
}

# add a error msg to the output in the correct format and end this request
#todo: replace all addPageContent/sendResponseMsg pairs to call this function instead
sub error {
    my ($msg, $errorcode) = @_;
    my $severity = 'error';
    my $m;
    if ($format eq 'xml') { $m = "<$severity>$msg</$severity>\n"; }
    elsif ($format eq 'json') { $m = qq({"$severity":"$msg"}\n); }
    else { $m = "<p>$severity: $msg</p>\n"; }
    addPageContent($m);
    sendResponseMsg($errorcode);
}

# Append content to the global var holding the output to go back to the rest client
sub addPageContent {
    my $newcontent = shift;
    $pageContent .= $newcontent;
}

# send the response to client side, then exit
# with http there is only one return for each request, so all content should be in pageContent global variable when you call this
# create the response header by status code and format
sub sendResponseMsg {
    my $code       = shift;
    my $tempFormat = '';
    if ('json' eq $format) { $tempFormat = 'application/json'; }
    elsif ('xml' eq $format) { $tempFormat = 'text/xml'; }
    else { $tempFormat = 'text/html'; }
    print $q->header(-status => $code, -type => $tempFormat);
    print $pageContent;
    exit(0);
}

sub unsupportedRequestType {
    addPageContent("request method '$requestType' is not supported on resource '$resource'");
    sendResponseMsg($STATUS_NOT_ALLOWED);
}

# Convert xcat request to xml for sending to xcatd
sub genRequest {
    if ($DEBUGGING) {
        #addPageContent($q->p("DEBUG: request to xcatd: " . Dumper($request) . "\n"));
    }
    my $xml = XML::Simple::XMLout($request, RootName => 'xcatrequest', NoAttr => 1, KeyAttr => []);
}

# when use put and post, can not fetch the url-parameter, so add this sub to support all kinds of methods
#todo: stop using this.  Can always get parms thru $q->url_param, regardless of the request type
sub fetchParameter {
    my $parstr = shift;
    unless ($parstr) {
        return;
    }

    my @pairs = split(/&/, $parstr);
    foreach my $pair (@pairs) {
        my ($key, $value) = split(/=/, $pair, 2);
        $value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/chr(hex($1))/eg;
        push @{$queryhash{$key}}, $value;
    }
}

# Extract the put data or post data into the hash that is passed in by reference.
# The data (2nd parameter) comes from $JSON->decode()
#todo: remove when not used any more
sub extractData {
    my $returnhash = shift;
    my $parArray = shift;
    my $key;
    my $value;
    my $position;

    #traversal all element in the array
    foreach (@$parArray) {
        $position = index($_, '=');
        if ($position < 0) {
            $key   = $_;
            $value = 1;
        }
        else {
            $key = substr $_, 0, $position;
            $value = substr $_, $position + 1;
        }
        $returnhash->{$key} = $value;

        if ($DEBUGGING) {
            addPageContent($q->p("DEBUG: parameters extracted from put/post data: " . Dumper($returnhash) . "\n"));
        }
    }
}

# Format the output data the way the user requested.  All data wrapping and writing is funneled through here.
# This will call one of the other wrap*() functions.
sub wrapData {
    my $data             = shift;
    my $errorInformation = '';

    #trim the serverdone message off
    if (exists $data->[0]->{serverdone} && exists $data->[0]->{error}) {
        $errorInformation = $data->[0]->{error}->[0];
        addPageContent($q->p($errorInformation));       #todo: put this in the requested format?
        if (($errorInformation =~ /Permission denied/) || ($errorInformation =~ /Authentication failure/)) {
            sendResponseMsg($STATUS_UNAUTH);
        }
        else {
            sendResponseMsg($STATUS_FORBIDDEN);
        }
    }
    else {
        pop @{$data};       #todo: are we sure this is the serverdone entry?
    }

    # Call the appropriate formatting function stored in the formatters hash
    if (exists $formatters{$format}) {
        $formatters{$format}->($data);
    }

    # all output has been added into the global varibale pageContent, now complete the response to the user
    if (exists $data->[0]->{info} && $data->[0]->{info}->[0] =~ /Could not find an object/) {
        sendResponseMsg($STATUS_NOT_FOUND);
    }
    elsif (isPost()) {
        sendResponseMsg($STATUS_CREATED);
    }
    else {
        sendResponseMsg($STATUS_OK);
    }
}


# Structure the response perl data structure into well-formed json.  Since the structure of the
# xml output that comes from xcatd is inconsistent and not very structured, we have a lot of work to do.
sub wrapJson {
    # this is an array of responses from xcatd.  Often all the output comes back in 1 response, but not always.
    my $data = shift;

    # put, post, and delete usually just give a short msg, if anything
    if (isPut() || isPost() || isDelete() || isPatch()) {
        addPageContent($JSON->encode($data));
        return;
    }

    # Divide the processing into several groups of requests, according to how they return the output
    # At this point, these are all gets
    my $json;
    if ($resource eq 'nodes') {
        if (!defined $path[2]) {        # querying node attributes
            # The data structure is: array of hashes that have a single key 'info'.  The value for that key
            # is an array of lines of lsdef output (all nodes in the same array).
            # Create a json array of node objects. Each node object contains the attributes/values (including
            # the nodename) of that object.
            $json = [];
            foreach my $d (@$data) {
                my $jsonnode;
                my $lines = $d->{info};
                foreach my $l (@$lines) {
                    if ($l =~ /^Object name: /) {    # start new node
                        if (defined($jsonnode)) { push @$json, $jsonnode; }     # push previous object onto array
                        my ($nodename) = $l =~ /^Object name:\s+(\S+)/;
                        $jsonnode = { nodename => $nodename };
                    }
                    else {      # just an attribute of the current node
                        if (!defined($jsonnode)) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                        my ($attr, $val) = $l =~ /^\s*(\S+)=(.*)$/;
                        if (!defined($attr)) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                        $jsonnode->{$attr} = $val;
                    }
                }
                if (defined($jsonnode)) { push @$json, $jsonnode;  $jsonnode=undef; }     # push last object onto array
            }
            addPageContent($JSON->encode($json));
        }
        elsif (grep(/^$path[2]$/, qw(power inventory vitals energy))) {        # querying other node info
            # The data structure is: array of hashes that have a single key 'node'.  The value for that key
            # is a 1-element array that has a hash with keys 'name' and 'data'.  The 'name' value is a 1-element
            # array that has the nodename.  The 'data' value is a 1-element array of a hash that has keys 'desc'
            # and 'content' (sometimes desc is ommited).
            # Create a json array of node objects. Each node object contains the attributes/values (including
            # the nodename) of that object.
            $json = {};     # its keys are nodenames
            foreach my $d (@$data) {
                # each element is a complex structure that contains 1 attr and value for a node
                my $node = $d->{node}->[0];
                my $nodename = $node->{name}->[0];
                my $nodedata = $node->{data}->[0];
                my $contents = $nodedata->{contents}->[0];
                my $desc = 'power';         # rpower doesn't output a desc tag
                if (defined($nodedata->{desc})) { $desc = $nodedata->{desc}->[0]; }

                # add this desc and content into this node's hash
                $json->{$nodename}->{$desc} = $contents;
            }
            # convert this hash of hashes into an array of hashes
            my @jsonarray;
            foreach my $n (sort(keys(%$json))) {
                $json->{$n}->{nodename} = $n;       # add the key (nodename) inside of the node's hash
                push @jsonarray, $json->{$n};
            }
            addPageContent($JSON->encode(\@jsonarray));
        }
        else {      # querying a node subresource (rpower, rvitals, rinv, etc.)
            addPageContent($JSON->encode($data));
        }       # end else path[2] defined
    }       # end if nodes
}

sub wrapHtml {
    my $item;
    my $response = shift;

    foreach my $element (@$response) {

        if ($element->{node}) {
            addPageContent("<table border=1>");
            foreach $item (@{$element->{node}}) {

                #my $url = $baseUri.$item->{name}[0];
                addPageContent("<tr><td>$item->{name}[0]</td>");
                if (exists $item->{data} && exists $item->{data}[0]) {
                    if (ref($item->{data}[0]) eq 'HASH') {
                        if (exists $item->{data}[0]->{desc} && exists $item->{data}[0]->{desc}[0]) {
                            addPageContent("<td>$item->{data}[0]->{desc}[0]</td>");
                        }
                        if (ref($item->{data}[0]) eq 'HASH' && exists $item->{data}[0]->{contents}[0]) {
                            addPageContent("<td>$item->{data}[0]->{contents}[0]</td>");
                        }
                    }
                    else {
                        addPageContent("<td>$item->{data}[0]</td>");
                    }
                }
                elsif (exists $item->{error}) {
                    addPageContent("<td>$item->{error}[0]</td>");
                }
                addPageContent("</tr>");
            }
            addPageContent("</table>");
        }
        if ($element->{data}) {
            addPageContent("<table border=1>");
            foreach $item (@{$element->{data}}) {
                my @values = split(/:/, $item, 2);
                addPageContent("<tr>");
                foreach (@values) {
                    if ($formatType =~ /splitCommas/) {
                        my @fields = split(/,/, $_, -1);
                        foreach (@fields) {
                            addPageContent("<td>$_</td>");
                        }
                    }
                    else {
                        addPageContent("<td>$_</td>");
                    }
                }
                addPageContent("</tr>\n");
            }
            addPageContent("</table>");
        }
        if ($element->{info}) {
            addPageContent("<table border=1>");
            foreach $item (@{$element->{info}}) {
                addPageContent("<tr>");
                my $fieldname  = '';
                my $fieldvalue = '';

                #strip whitespace in the string
                $item =~ s/^\s+//;
                $item =~ s/\s+$//;
                if ($item =~ /Object/) {
                    ($fieldname, $fieldvalue) = split(/:/, $item);
                }
                elsif ($item =~ /.*=.*/) {
                    my $position = index $item, '=';
                    $fieldname = substr $item, 0, $position;
                    $fieldvalue = substr $item, $position + 1;
                }
                else {
                    $fieldname = $item;
                }
                addPageContent("<td>" . $fieldname . "</td>");
                if ($fieldvalue ne '') {
                    addPageContent("<td>" . $fieldvalue . "</td>");
                }
                addPageContent("</tr>\n");
            }
            addPageContent("</table>");
        }
        if ($element->{error}) {
            addPageContent("<table border=1>");
            foreach $item (@{$element->{error}}) {
                addPageContent("<tr><td>" . $item . "</td></tr>");
            }
            addPageContent("</table>");
        }
    }
}

sub wrapXml {
    my @data = shift;
    foreach (@data) {
        foreach (@$_) {
            addPageContent(XML::Simple::XMLout($_, RootName => '', NoAttr => 1, KeyAttr => []));
        }
    }
}

# Send the request to xcatd and read the response.  The request passed in has already been converted to xml.
# The response returned to the caller of this function has already been converted from xml to perl structure.
sub sendRequest {
    my $request = shift;
    my $sitetab;
    my $retries = 0;

    if ($DEBUGGING) {
        #my $preXml = $request;
        #$preXml =~ s/</<br>&lt /g;
        #$preXml =~ s/>/&gt<br>/g;
        #addPageContent($q->p("DEBUG: request XML: " . $request . "\n"));
    }

    #hardcoded port for now
    my $port     = 3001;
    my $xcatHost = "localhost:$port";

    #temporary, will be using username and password
    my $homedir  = "/root";
    my $keyfile  = $homedir . "/.xcat/client-cred.pem";
    my $certfile = $homedir . "/.xcat/client-cred.pem";
    my $cafile   = $homedir . "/.xcat/ca.pem";

    my $client;
    if (-r $keyfile and -r $certfile and -r $cafile) {
        $client = IO::Socket::SSL->new(
            PeerAddr      => $xcatHost,
            SSL_key_file  => $keyfile,
            SSL_cert_file => $certfile,
            SSL_ca_file   => $cafile,
            SSL_use_cert  => 1,
            Timeout       => 15,);
    }
    else {
        $client = IO::Socket::SSL->new(
            PeerAddr => $xcatHost,
            Timeout  => 15,);
    }
    unless ($client) {
        if ($@ =~ /SSL Timeout/) {
            error("Connection failure: SSL Timeout or incorrect certificates in ~/.xcat",$STATUS_TIMEOUT);
        }
        else {
            error("Connection failurexx: $@",$STATUS_SERVICE_UNAVAILABLE);
        }
    }

    print $client $request;

    my $response;
    my $rsp;
    my @fullResponse;
    my $cleanexit = 0;
    while (<$client>) {
        $response .= $_;
        if (m/<\/xcatresponse>/) {

            #replace ESC with xxxxESCxxx because XMLin cannot handle it
            if ($DEBUGGING) {
                #addPageContent("DEBUG: response from xcatd: " . $response . "\n");
            }
            $response =~ s/\e/xxxxESCxxxx/g;

            #print "responseXML is ".$response;
            $rsp = XML::Simple::XMLin($response, SuppressEmpty => undef, ForceArray => 1);

            #add ESC back
            foreach my $key (keys %$rsp) {
                if (ref($rsp->{$key}) eq 'ARRAY') {
                    foreach my $text (@{$rsp->{$key}}) {
                        next unless defined $text;
                        $text =~ s/xxxxESCxxxx/\e/g;
                    }
                }
                else {
                    $rsp->{$key} =~ s/xxxxESCxxxx/\e/g;
                }
            }

            $response = '';
            push(@fullResponse, $rsp);
            if ($rsp->{serverdone}) {
                $cleanexit = 1;
                last;
            }
        }
    }
    unless ($cleanexit) {
        error("communication with the xCAT server seems to have been ended prematurely",$STATUS_SERVICE_UNAVAILABLE);
    }

    if ($DEBUGGING) {
        #addPageContent($q->p("DEBUG: full response from xcatd: " . Dumper(@fullResponse) . "\n"));
    }
    return @fullResponse;
}

# Functions to test the http request type
sub isGet { return uc($requestType) eq "GET"; }

sub isPut { return uc($requestType) eq "PUT"; }

sub isPost { return uc($requestType) eq "POST"; }

sub isPatch { return uc($requestType) eq "PATCH"; }

sub isDelete { return uc($requestType) eq "DELETE"; }

# check to see if this is a valid user.  userName and password are already set
# this function is not currently used.
sub isAuthenticUser {
    $request->{command} = 'authcheck';
    my $req       = genRequest();
    my @responses = sendRequest($req);
    if ($responses[0]->{data}[0] eq "Authenticated") {

        #user is authenticated
        return 1;
    }

    #authentication failure
    error($responses[0]->{error}[0], $STATUS_UNAUTH);
}
