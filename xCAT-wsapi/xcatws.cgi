#!/usr/bin/perl
use strict;
use CGI qw/:standard/;
use JSON;
use Data::Dumper;

#added the line:
#ScriptAlias /xcatws /var/www/cgi-bin/xcatws.cgi
#to /etc/httpd/conf/httpd.conf to hid the cgi-bin and .cgi extension in the uri
#
# also upgraded CGI to 3.52

#take the JSON or XML and put it into a data structure
#all data input will be done from the common structure

#turn on or off the debugging output
my $DEBUGGING = 1;

my $q = CGI->new;
my $url = $q->url;
my $pathInfo = $q->path_info;
my $requestType = $ENV{'REQUEST_METHOD'};
my $queryString = $ENV{'QUERY_STRING'};
my @path = split(/\//, $pathInfo);
shift(@path);
my $resource = $path[0];
print $q->header('text/html');
my $request = {clienttype =>'ws'};

#error status codes
my $STATUS_BAD_REQUEST = "400 Bad Request";
my $STATUS_UNAUTH = "401 Unauthorized";
my $STATUS_FORBIDDEN = "403 Forbidden";
my $STATUS_NOT_FOUND= "404 Not Found";
my $STATUS_NOT_ALLOWED = "405 Method Not Allowed";
my $STATUS_NOT_ACCEPTABLE = "406 Not Acceptable";
my $STATUS_TIMEOUT = "408 Request Timeout";
my $STATUS_EXPECT_FAILED = "417 Expectation Failed";
my $STATUS_TEAPOT = "418 I'm a teapot";
my $STATUS_SERVICE_UNAVAILABLE = "503 Service Unavailable";

#good status codes
my $STATUS_OK = "200 OK";
my $STATUS_CREATED = "201 Created";

sub sendStatusMsg{
  my $code = shift;
  my $message = shift;
  print $q->header(-status => $code);
  print $message;
}

sub unsupportedRequestType{
  sendStatusMsg($STATUS_NOT_ALLOWED, "request method '$requestType' is not supported on resource '$resource'");
}

use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';

sub genRequest{
  if($DEBUGGING){
    print $q->p("request ".Dumper($request));
  }
  my $xml = XMLout($request, RootName=>'xcatrequest',NoAttr=>1,KeyAttr=>[]);
}

my $format = 'html';
if($q->param('format'))
{
  $format = $q->param('format');
}

#if no resource was specified
if($pathInfo =~ /^\/$/ || $pathInfo =~ /^$/){
  print $q->p('Some general xCAT WS page will be served or forwarded to when there is no resource specified');
  exit(0);
}


my $XCAT_PATH = '/opt/xcat/bin';

my %resources = (groups           => \&groupsHandler,
                 images           => \&imagesHandler,
                 logs             => \&logsHandler,
                 monitors         => \&monitorsHandler,
                 networks         => \&networksHandler,
                 nodes            => \&nodesHandler,
                 notifications    => \&notificationsHandler,
                 policies         => \&policiesHandler,
                 site             => \&siteHandler,
                 tables           => \&tablesHandler,
                 accounts         => \&accountsHandler,
                 objects          => \&objectsHandler,
                 vms              => \&vmsHandler);

sub doesResourceExist
{
  my $res = shift;
  return exists $resources{$res};
}

if($DEBUGGING){
  if(defined $q->param('PUTDATA')){
    print "put data ".$q->p($q->param('PUTDATA')."\n");
  }
  if(defined $q->param('POSTDATA')){
    print "post data ".$q->p($q->param('POSTDATA')."\n");
  }
  print $q->p("Parameters ");
  my @params = $q->param;
  foreach (@params)
  {
    print "$_ = ".$q->param($_)."\n";
  }
  print $q->p("Query String $queryString"."\n");
  print $q->p("HTTP Method $requestType"."\n");
  print $q->p("URI $url"."\n");
  print $q->p("path ".Dumper(@path)."\n");
}

my $userName;
my $password;

sub handleRequest{
  if(defined $q->param('userName')){
    $userName = $q->param('userName')
  }
  if(defined $q->param('password')){
    $password = $q->param('password')
  }
  if($userName && $password){
    $request->{becomeuser}->[0]->{username}->[0] = $userName;
    $request->{becomeuser}->[0]->{password}->[0] = $password;
  }
  my @data = $resources{$resource}->();
  wrapData(\@data);
}

my @groupFields = ('groupname', 'grouptype', 'members', 'wherevals', 'comments', 'disable');

#resource handlers

#get is done
#post and delete are done but not tested
#groupfiles4dsh is done but not tested
sub groupsHandler{
  my @responses;
  my @args;
  my $groupName;

  #is the group name in the URI?
  if(defined $path[1]){
    $groupName = $path[1];
  }
  #in the query string?
  else{
    $groupName = $q->param('groupName');
  }

  if(isGet()){
    if(defined $groupName){
      $request->{command} = 'tabget';
      push @args, "groupname=$groupName";
      if(defined $q->param('field')){
        foreach ($q->param('field')){
          push @args, "nodegroup.$_";
        }
      }
      else{
        foreach (@groupFields){
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
  elsif(isPost()){
    my $nodeRange = $q->param('nodeRange');
    if(defined $groupName && defined $nodeRange){
      $request->{command} = 'mkdef';
      push @args, '-t';
      push @args, 'group';
      push @args, '-o';
      push @args, $groupName;
      push @args, "members=$nodeRange";
    }
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "A node range and group name must be specified for creating a group");
      exit(0);
    }
  }
  elsif(isPut()){
    #handle groupfiles4dsh -p /tmp/nodegroupfiles
    if($q->param('command') eq /4dsh/){
      if($q->param('path')){
        $request->{command} = 'groupfiles4dsh';
        push @args, "p=$q->param('path')";
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The path must be specified for creating directories for dsh");
        exit(0);
      }
    }
    else{
      if(defined $groupName && defined $q->param('fields')){
         $request->{command} = 'nodegrpch';
         push @args, $groupName;
         push @args, $q->param('field');
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The group and fields must be specified to update groups");
        exit(0);
      }
    }
  }
  elsif(isDelete()){
    if(defined $groupName){
      $request->{command} = 'rmdef';
      push @args, '-d';
      push @args, 'group';
      push @args, '-o';
      push @args, $groupName;
    }
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "The group must be specified to delete a group");
      exit(0);
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);

  return @responses;
}

my @imageFields = ('imagename','profile','imagetype','provmethod','osname','osvers','osdistro','osarch','synclists','comments','disable');

#get is done, nothing else
sub imagesHandler{
  my @responses;
  my @args;
  my $image;

  if(defined($path[1])){
    $image = $path[1];
  }
  else{
    $image = $q->param('imageName');
  }

  if(isGet()){
    if(defined $image){
      #call chkosimage, but should only be used for AIX images
      if($q->param('check')){
        $request->{command} = 'chkosimage';
        push @args, $image;
      }
      else{
        $request->{command} = 'tabget';
        push @args, "imagename=$image";
        if(defined $q->param('field')){
          foreach ($q->param('field')){
            push @args, "osimage.$_";
          }
        }
        else{
          foreach (@groupFields){
            push @args, "osimage.$_";
          }
        }
      }
    }
    #no image indicated, so list all
    else{
      $request->{command} = 'tabdump';
      push @args, 'osimage';
    }
  }
  elsif(isPost()){
####genimage and related commands do not go through xcatd....
####not supported at the moment
    #if($q->param('type') eq /stateless/){
      #if(!defined $image){
        #sendStatusMsg($STATUS_BAD_REQUEST, "The image name is required to create a stateless image");
        #exit(0);
      #}
      #$request->{command} = 'genimage';
      #foreach(param->{'field'}){
      #}
    #}
    #else{
      #if(defined $q->param('path')){
        #$request->{command} = 'copycds';
        #push @args, $q->param('path');
      #}
    #}
  }
  elsif(isPut() || isPatch()){
    #use chkosimage to remove any older versions of the rpms.  should only be used for AIX
    if($q->param('clean')){
      if(defined $image){
        $request->{command} = 'chkosimage';
        push @args, '-c';
        push @args, $image;
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The image name is required to clean an os image");
      }
    }
  }
  elsif(isDelete()){
    if(defined $image){
      $request->{command} = 'rmimage';
      if(defined $q->param('verbose')){
        push @args, '-v';
      }
      push @args, $image;
    }
    elsif(defined $q->param('os') && defined $q->param('arch') && defined $q->param('profile')){
      push @args, '-o';
      push @args, $q->param('os');
      push @args, '-a';
      push @args, $q->param('arch');
      push @args, '-p';
      push @args, $q->param('profile');
    }
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "Either the image name or the os, architecture and profile must be specified to remove an image");
      exit(0);
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);

  return @responses;
}

#complete
sub logsHandler{
  my @responses;
  my @args;
  my $logType;

  if(defined $path[1]){
    $logType = $path[1];
  }
  #in the query string?
  else{
   $logType = $q->param('logType');
  }
  my $nodeRange = $q->param('nodeRange');;

  #no real output unless the log type is defined
  if(!defined $logType){
    print $q->p("Current logs available are auditlog and eventlog");
    exit(0);
  }

  if(isGet()){
    if($logType eq /reventLog/){
      if(defined $nodeRange){
        $request->{command} = 'reventlog';
        push @args, $nodeRange;
        if(defined $q->param('count')){
          push @args, $q->param('count');
        }
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "nodeRange must be specified to GET remote event logs");
      }
    }
    else{
      $request->{command} = 'tabdump';
      push @args, $logType;
    }
  }
  #this clears the log
  elsif(isPut()){
    if($logType eq /reventlog/){
      if(defined $nodeRange){
        $request->{command} = 'reventlog';
        push @args, $nodeRange;
        push @args, 'clear';
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "nodeRange must be specified to GET remote event logs");
      }
    }
    else{
      $request->{command} = 'tabprune';
      #-a removes all
      push @args, '-a';
      #should it return the removed entries?
      if(defined $q->param('showRemoved'))
      {
        push @args, '-V';
      }
    }
  }
  #remove some of the entries
  elsif(isPatch()){
    $request->{command} = 'tabprune';
    #should it return the removed entries?
    if(defined $q->param('showRemoved'))
    {
      push @args, '-V';
    }
    #remove a certain number of records
    if(defined $q->param('count')){
      push @args, ('-n', $q->param('count'));
    }
    #remove a percentage of the records
    if(defined $q->param('percent')){
      push @args, ('-p', $q->param('percent'));
    }
    #remove all records before this record
    if(defined $q->param('lastRecord')){
      push @args, ('-i', $q->param('lastRecord'));
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);

  return @responses;
}

#complete
sub monitorsHandler{
  my @responses;
  my @args;
  my $monitor;

  if(defined $path[1]){
    $monitor = $path[1];
  }
  #in the query string?
  elsif(defined $q->param('monitor')){
    push @args, $q->param('monitor');
  }
  if(defined $monitor)
  {
    push @args, $monitor;
  }

  if(isGet()){
    $request->{command} = 'monls';
  }
  elsif(isPost()){
    $request->{command} = 'monadd';
    push @args, $q->param('name');
    if($q->param('nodeStatMon')){
      push @args, '-n';
    }
    #get the plug-in specific settings array
    for ($q->param){
      if($_ ne /name/ && $_ ne /nodeStatMon/){
        push @args, '-s';
        push @args, "$_=".$q->param($_);
      }
    }
  }
  elsif(isDelete()){
    $request->{command} = 'monrm'
  }
  elsif(isPut() || isPatch()){
    my $action = $q->param('action');
    if($action eq /start/){
      $request->{command} = 'monstart';
    }
    elsif($action eq /stop/){
      $request->{command} = 'monstop';
    }
    elsif($action eq /config/){
      $request->{command} = 'moncfg';
    }
    elsif($action eq /deconfig/){
      $request->{command} = 'mondeconfig';
    }
    else{
      unsupportedRequestType();
    }
    if(!defined $q->param('nodeRange')){
      #error
    }
    else{
      push @args, $q->param('nodeRange');
    }
    if(defined $q->param('remote')){
      push @args, '-r';
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);

  return @responses;
}

sub networksHandler{
  my @responses;
  my @args;

  if(isGet()){

  }
  elsif(isPut() or isPatch()){
    my $subResource;
    if(defined $path[2]){
      $subResource = $path[2];
    }
    if($subResource eq /hosts/){
      $request->{command} = 'makehosts';
      #is this needed?
      push @args, 'all';
    }
    elsif($subResource eq /dhcp/){
      #allow restarting of the dhcp service.  scary?
      if($q->param('command') eq /restart/){
        system.exec('service dhcp restart');
      }
      else{
        $request->{command} = 'makedhcp';
        foreach($q->param('field')){
          push @args, $_;
        }
      }
    }
    elsif($subResource eq /dns/){
      #allow restarting of the named service.  scary?
      if($q->param('command') eq /restart/){
        system.exec('service named restart');
      }
      else{
        $request->{command} = 'makedhcp';
        foreach($q->param('field')){
          push @args, $_;
        }
      }
    }
  }
  elsif(isPost()){

  }
  elsif(isDelete()){

  }
  else{
    unsupportedRequestType();
    exit(0);
  }

  return @responses;
}

sub nodesHandler{
  my @responses;
  my @args;

  #does it specify nodes in the URI?
  if(defined $path[1]){
    $request->{noderange} = $path[1];
  }
  #in the query string?
  elsif(defined $q->param('nodeRange')){
    $request->{noderange} = $q->param('nodeRange');
  }
  
  if(isGet()){
    my $subResource;
    if(defined $path[2]){
      $subResource = $path[2];
    }

    if($subResource =~ "power"){
      $request->{command} = 'rpower';
      push @args, 'stat';
    }
    elsif($subResource =~ "bootState"){
      $request->{command} = 'nodeset';
      push @args,'stat';
    }
    elsif($subResource =~ "energy"){
      $request->{command} = 'renergy';

      #no fields will default to 'all'
      if(defined $q->param('field')){
        foreach ($q->param('field')){
          push @args, $_;
        }
      }
    }
    elsif($subResource =~ "osimage"){
      
    }
    elsif($subResource =~ "status"){
      $request->{command} = 'nodestat';
    }
    elsif($subResource =~ "inventory"){
      $request->{command} = 'rinv';
      if(defined $q->param('field')){
        push @args, $q->param('field');
      }
      else{
        push @args, 'all';
      }
    }
    elsif($subResource =~ "location"){
      $request->{command} = 'nodels';
      push @args, 'nodepos';
    }
    else{
      $request->{command} = 'nodels';
      #if the table or field is specified in the URI
      if(defined $subResource){
        push @args, $subResource;
      }
      #maybe it's specified in the parameters
      else{
        push @args, $q->param('field');
      }
    }
  }
  #PUT will remove and readd the nodes
  #is that true?
  elsif(isPut()){
    my $subResource;
    if(defined $path[2]){
      $subResource = $path[2];
    }
    if($subResource =~ "bootState"){
      $request->{command} = 'nodeset';
      if(defined $q->param('boot')){
        push @args, 'boot';
      }
      if(defined $q->param('install')){
        if($q->param('install')){
          push @args, "install=".$q->param('install');
        }
        else{
          push @args, 'install';
        }
      }
      if(defined $q->param('netboot')){
        if($q->param('netboot')){
          push @args, "netboot=".$q->param('netboot');
        }
        else{
          push @args, 'netboot';
        }
      }
      if(defined $q->param('statelite')){
        if($q->param('statelite')){
          push @args, "statelite=".$q->param('statelite');
        }
        else{
          push @args, 'statelite';
        }
      }
      if(defined $q->param('bmcsetup')){
        push @args, "runcmd=bmcsetup";
      }
      if(defined $q->param('shell')){
        push @args, 'shell';
      }
    }
    else{
      sendErrorMessage($STATUS_BAD_REQUEST, "The subResource \'$request->{subResource}\' does not exist");
    }
  }
  elsif(isPost()){
    $request->{command} = 'nodeadd';
    if(defined $q->param('groups')){
      $request->{groups} = $q->param('groups');
    }

    #since we can't predict which table fields will be passed
    #we just pass everything else
    for my $arg ($q->param){
      if($arg !~ "nodeRange" && $arg !~ "groups"){
        push @args, $arg;
      }
    }
  }
  elsif(isPatch()){
    $request->{command} = 'nodech';
  }
  elsif(isDelete()){
    #FYI:  the nodeRange for delete has to be specified in the URI
    $request->{command} = 'noderm';
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);

  #if($element->{node}){
    #print "<table>";
    #foreach my $item (@{$element->{node}}){
      #print "<tr><td>$item->{name}[0]</td>";
      #if(exists $item->{data}[0]->{desc}[0]){
        #print "<td>$item->{data}[0]->{desc}[0]</td>";
      #}
      #if(exists $item->{data}[0]->{contents}[0]){
        #print "<td>$item->{data}[0]->{contents}[0]</td>";
      #}
      #print "</tr>";
    #}
    #print "</table>";
  #}
  return @responses;
}

my @notificationFields = ('filename', 'tables', 'tableops', 'comments', 'disable');

#complete, unless there is some way to alter existing notifications
sub notificationsHandler{
  my @responses;
  my @args;

  #does not support using the notification fileName in the URI

  if(isGet()){
    if(defined $q->param('fileName')){
      $request->{command} = 'gettab';
      push @args, "filename".$q->param('fileName');

      #if they specified the fields, just get those
      if(defined $q->param('field')){
        foreach ($q->param('field')){
          push @args, $_;
        }
      }
      #else show all of the fields
      else{
        foreach (@notificationFields){
          push @args, "notification.$_";
        }
      }
    }
    else{
      $request->{command} = 'tabdump';
      push @args, "notification";
    }
  }
  elsif(isPost()){
    $request->{command} = 'regnotif';
    if(!defined $q->param('fileName') || !defined $q->param('table') || !defined $q->param('operation')){
      sendStatusMsg($STATUS_BAD_REQUEST, "fileName, table and operation must be specified for a POST on /notifications");
    }
    else{
      push @args, $q->param('fileName');
      my $tables;
      foreach ($q->param('table')){
        $tables .= "$_,";
      }
      #get rid of the extra comma
      chop($tables);
      push @args, $tables;
      push @args, '-o';
      my $operations;
      foreach ($q->param('operation')){
        $operations .= "$_,";
      }
      #get rid of the extra comma
      chop($operations);
      push @args, $q->param('operation');
    }
  }
  elsif(isDelete()){
    $request->{command} = 'unregnotif';
    if(defined $q->param('fileName')){
      push @args, $q->param('fileName');
    }
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "fileName must be specified for a DELETE on /notifications");
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }
  
  push @{$request->{arg}}, @args;
  print "request is ".Dumper($request);
  my $req = genRequest();
  @responses = sendRequest($req);

  return @responses;
}

my @policyFields = ('priority','name','host','commands','noderange','parameters','time','rule','comments','disable');

#complete
sub policiesHandler{
  my @responses;
  my @args;
  my $priority;

  #does it specify the prioirty in the URI?
  if(defined $path[1]){
    $priority = $path[1];
  }
  #in the query string?
  elsif(defined $q->param('priority')){
    $priority = $q->param('priority');
  }

  if(isGet()){
    if(defined $priority){
      $request->{command} = 'gettab';
      push @args, "priority=$priority";
      my @fields = $q->param('field');

      #if they specified fields to retrieve
      if(@fields){
        push @args, @fields;
      }
      #give them everything if nothing is specified
      else{
        foreach (@policyFields){
          push @args, "policy.$_";
        }
      }
    }
    else{
      $request->{command} = 'tabdump';
      push @args, 'policy';
    }
  }
  elsif(isPost()){
    if(defined $priority){
      $request->{command} = 'tabch';
      push @args, "priority=$priority";
      for ($q->param){
        if($_ ne /priority/){
          push @args, "policy.$_=".$q->param($_);
        }
      }
    }
    #some response about the priority being required
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "The priority must be specified when creating a policy");
      exit(0);
    }
  }
  elsif(isDelete()){
    #just allowing a delete by priority at the moment, could expand this to anything
    if(defined $priority){
      $request->{command} = 'tabch';
      push @args, '-d';
      push @args, "priority=$priority";
      push @args, "policy";
    }
  }
  elsif(isPut() || isPatch()){
    if(defined $priority){
      $request->{command} = 'tabch';
      push @args, "priority=$priority";
      for ($q->param){
        if($_ ne /priority/){
          push @args, "policy.$_=".$q->param($_);
        }
      }
    }
    #some response about the priority being required
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "The priority must be specified when updating a policy");
      exit(0);
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  print "request is ".Dumper($request);
  my $req = genRequest();
  @responses = sendRequest($req);

  return @responses;
}

#complete
sub siteHandler{
  my @data;
  my @responses;
  my @args;

  if(isGet()){
    $request->{command} = 'tabdump';
    push @{$request->{arg}}, 'site';
    my $req = genRequest();
    @responses = sendRequest($req);
  }
  elsif(isPut() || isPatch()){
    $request->{command} = 'tabch';
    if(defined $q->param('PUTDATA')){
      my $entries = decode_json $q->param('PUTDATA');;
      foreach (values %$entries){
        my %fields = %$_;
        foreach my $key (keys %fields){
          if($key =~ /key/){
            #the key needs to be first
            unshift @args, "key=$fields{$key}";
          }
          else{
            push @args, "site.$key=$fields{$key}";
          }
        }
        push @{$request->{arg}}, @args;
        my $req = genRequest();
        my @subResponses = sendRequest($req);
        #TODO:  look at the reponses and see if there are errors
        push @responses, @subResponses;
      }
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  #change response formatting
  foreach my $response (@responses){
    foreach my $item (@{$response->{data}}){
      if($item !~ /^#/)
      {
        my @values = split(/,/, $item);
        my %item = (
          entry => $values[0],
          value => $values[1],
          comments => $values[2],
          disable => $values[3]);
        push @data, \%item;
      }
    }
  }
  return @responses;
}

  my $formatType;

#provide direct table access
#complete and tested on the site table
#use of the actual DELETE doesn't seem to fit here, since a resource would not be deleted
#using PUT or PATCH instead, though it doesn't feel all that correct either
sub tablesHandler{
  my @responses;
  my $table;
  my @args;

  #is the table name specified in the URI?
  if(defined $path[1]){
    $table = $path[1];
  }

  #handle all gets
  if(isGet()){
    $request->{command} = 'tabdump';
    if(defined $q->param('desc')){
      push @args, '-d';
    }

    #table was specified
    if (defined $table){
      push @args, $table;
      if(!defined $q->param('desc')){
        $formatType = 'splitCommas';
      }
    }
  }
  elsif(isPut() || isPatch()){
    my $condition = $q->param('condition');
    if(!defined $table || !defined $condition){
      sendStatusMsg($STATUS_BAD_REQUEST, "The table and condition must be specified when adding, changing or deleting an entry");
      exit(0);
    }
    $request->{command} = 'tabch';
    if(defined $q->param('delete')){
      push @args, '-d';
      push @args, $condition;
      push @args, $table;
    }
    else{
      push @args, $condition;
      for($q->param('value')){
        push @args, "$table.$_";
      }
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);
  return @responses;
}

my @accountFields = ('key', 'username', 'password', 'cryptmethod', 'comments', 'disable');

#done aside from being able to change cluster users, which xcat can't do yet
sub accountsHandler{
  my @responses;
  my @args;
  my $key = $q->param('key');

  if(isGet()){

    #passwd table
    if(!defined $q->param('clusterUser')){
      if(defined $key){
        $request->{command} = 'tabget';
        push @args, "key=$key";
        if(defined $q->param('field')){
          foreach ($q->param('field')){
            push @args, "passwd.$_";
          }
        }
        else{
          foreach (@accountFields){
            push @args, "passwd.$_";
          }
        }
      }
    }
    #cluster user list
    else{
      $request->{command} = 'xcatclientnnr';
      push @args, 'clusteruserlist';
      push @args, '-p';
    }
  }
  elsif(isPost()){
    if(!defined $q->param('clusterUser')){
      if(defined $key){
        $request->{command} = 'tabch';
        push @args, "key=$key";
        for ($q->param){
          if($_ !~ /key/){
            push @args, "passwd.$_=".$q->param($_);
          }
        }
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The key must be specified when creating a non-cluster user");
        exit(0);
      }
    }
    #active directory user
    else{
      if(defined $q->param('userName') && defined $q->param('userPass')){
        $request->{command} = 'xcatclientnnr';
        push @args, 'clusteruseradd';
        push @args, $q->param('userName');
        push @{$request->{arg}}, @args;
        $request->{environment} = {XCAT_USERPASS => $q->param('userPass')};
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The key must be specified when creating a cluster user");
        exit(0);
      }
    }
  }
  elsif(isDelete()){
    if(!defined $q->param('clusterUser')){
      #just allowing a delete by key at the moment, could expand this to anything
      if(defined $key){
        $request->{command} = 'tabch';
        push @args, '-d';
        push @args, "key=$key";
        push @args, "passwd";
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The key must be specified when deleting a non-cluster user");
        exit(0);
      }
    }
    else{
      if(defined $q->param('userName')){
        $request->{command} = 'xcatclientnnr';
        push @args, 'clusteruserdel';
        push @args, $q->param('userName');
      } 
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The userName must be specified when deleting a cluster user");
        exit(0);
      }
    }
  }
  elsif(isPut() || isPatch()){
    if(!defined $q->param('clusterUser')){
      if(defined $key){
        $request->{command} = 'tabch';
        push @args, "key=$key";
        for ($q->param){
          if($_ !~ /key/){
            push @args, "passwd.$_=".$q->param($_);
          }
        }
      }
      else{
        sendStatusMsg($STATUS_BAD_REQUEST, "The key must be specified when updating a non-cluster user");
        exit(0);
      }
    }
    #TODO:  there isn't currently a way to update cluster users
    else{

    }
  }
  else{
    unsupportedRequestType();
    exit(0);
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);
  return @responses;
}

sub objectsHandler{
  my @responses;
  my @args;
  my @objectList = ("auditlog","boottarget","eventlog","firmware","group","monitoring","network","node","notification","osimage","policy","route","site");
  my %objects;
  foreach my $item (@objectList) { $objects{$item} = 1 }
  my $object;
  if(defined $path[1]){
    $object = $path[1];
  }

  if(isGet()){
    if(defined $object){
      $request->{command} = 'lsdef';
      push @args, '-t';
      push @args, $object;
      if($q->param('info')){
        push @args, '-h';
      }
    }
    else{
      #couldn't find a way to do this through xcatd, so shortcutting the request
      my %resp = (data => \@objectList);
      return (\%resp);
    }
  }
  elsif(isPut() || isDelete()){

  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  @responses = sendRequest($req);
  return @responses;
}

#complete i think, tho chvm could handle args better
sub vmsHandler{
  my @args;
  if(defined $q->param('nodeRange')){
    $request->{noderange} = $q->param('nodeRange');
  }
  if(defined $q->param('verbose')){
    push @args, '-V';
  }

  if(isGet()){
    $request->{command} = 'lsvm';
    if(defined $q->param('all')){
      push @args, '-a';
    }
  }
  elsif(isPost()){
    if(defined $q->param('clone')){
      $request->{command} = 'clonevm';
      if(defined $q->param('target')){
        push @args, '-t';
        push @args, $q->param('target');
      }
      if(defined $q->param('source')){
        push @args, '-b';
        push @args, $q->param('source');
      }
      if(defined $q->param('detached')){
        push @args, '-d';
      }
      if(defined $q->param('force')){
        push @args, '-f';
      }
    }
    else{
#man page for mkvm needs updating for options
      $request->{command} = 'mkvm';
      if(defined $q->param('cec')){
        push @args, '-c';
        push @args, $q->param('cec');
      }
      if(defined $q->param('startId')){
        push @args, '-i';
        push @args, $q->param('startId');
      }
      if(defined $q->param('source')){
        push @args, '-l';
        push @args, $q->param('source');
      }
      if(defined $q->param('profile')){
        push @args, '-p';
        push @args, $q->param('profile');
      }
      if(defined $q->param('full')){
        push @args, '--full';
      }
      if(defined $q->param('master')){
        push @args, '-m';
        push @args, $q->param('master');
      }
      if(defined $q->param('size')){
        push @args, '-s';
        push @args, $q->param('size');
      }
      if(defined $q->param('force')){
        push @args, '-f';
      }
    }
  }
  elsif(isPut() || isPatch()){
    $request->{command} = 'chvm';
    if(defined $q->param('field')){
      foreach ($q->param('field'){
        push @args, $_;
      }
    }
    
  }
  elsif(isDelete()){
    if(defined $request->{nodeRange})){
      if(defined $q->param('retain')){
        push @args, '-r';
      }
      if(defined $q->param('service')){
        push @args, '--service';
      }
    }
    else{
      sendStatusMsg($STATUS_BAD_REQUEST, "The node range must be specified when deleting vms");
      exit(0);
    }
  }
  else{
    unsupportedRequestType();
    exit();
  }

  push @{$request->{arg}}, @args;
  my $req = genRequest();
  my @responses = sendRequest($req);
  return @responses;
}

#for operations that take a 'long' time to finish, this will provide the interface to check their status
sub jobsHandler{

}


#data formatters.  To add one simple copy the format of an existing one
# and add it to this hash
my %formatters = ('html' => \&wrapHtml,
                  'json' => \&wrapJson,
                  'xml'  => \&wrapXml,
                 );

#all data wrapping and writing is funneled through here
sub wrapData{
  my @data = shift;
  if(exists $formatters{$format}){
    $formatters{$format}->(@data);
  }
}

sub wrapJson
{
  my @data = shift;
  print header('application/json');
  my $json;
  $json->{'data'} = \@data;
  print to_json($json);
}

sub wrapHtml
{
  my @response = shift;
  my $baseUri = $url.$pathInfo;
  if($baseUri !~ /\/^/)
  {
    $baseUri .= "/";
  }
  #print $q->p("dumping in wrapHtml ".Dumper(@response));
  foreach my $data (@response){
    if(@$data[0]->{error}){
      #not sure if we can be more specific with status codes or if this is the right choice
      sendStatusMsg($STATUS_NOT_ACCEPTABLE, @$data[0]->{error}[0]);
      exit(0);
    }
    else{
      if(isPost()){
        sendStatusMsg($STATUS_CREATED);
      }
      else{
        sendStatusMsg($STATUS_OK);
      }
    }
    foreach my $element (@$data){
      #if($element->{error}){
      if($element->{node}){
        print "<table border=1>";
        foreach my $item (@{$element->{node}}){
          #my $url = $baseUri.$item->{name}[0];
          #print "<tr><td><a href=$url>$item->{name}[0]</td></tr>";
          print "<tr><td>$item->{name}[0]</td>";
          if(exists $item->{data} && exists $item->{data}[0]){
            if(ref($item->{data}[0]) eq 'HASH'){
              if(exists $item->{data}[0]->{desc} && exists $item->{data}[0]->{desc}[0]){
                print "<td>$item->{data}[0]->{desc}[0]</td>";
              }
              if(ref($item->{data}[0]) eq 'HASH' && exists $item->{data}[0]->{contents}[0]){
                print "<td>$item->{data}[0]->{contents}[0]</td>";
              }
            }
            else{
              print "<td>$item->{data}[0]</td>";
            }
          }
          print "</tr>";
        }
        print "</table>";
      }
      elsif($element->{data}){
        print "<table border=1>";
        foreach my $item (@{$element->{data}}){
          my @values = split(/:/, $item, 2);
          #print "<tr><td><a href=$url$pathInfo$key>$key</a></td><td>$value</td></tr>";
          print "<tr>";
          foreach (@values){
            if($formatType =~ /splitCommas/){
              my @fields = split(/,/, $_,-1);
              foreach (@fields){
                print "<td>$_</td>";
              }
            }
            else{
              print "<td>$_</td>";
            }
          }
          print "</tr>\n";
        }
        print "</table>";
      }
      elsif($element->{info}){
        foreach my $item (@{$element->{info}}){

          print $item;
        }
      }
    }
  }
}

sub wrapXml
{
  my @data = shift;

}

#general tests for valid requests and responses with HTTP codes here
if(!doesResourceExist($resource)){
  sendStatusMsg($STATUS_NOT_FOUND, "Resource '$resource' does not exist");
  exit(0);
}
else{
  if($DEBUGGING){
    print $q->p("resource is $resource");
  }
  handleRequest();
}

#talk to the server
use Socket;
use IO::Socket::INET;
use IO::Socket::SSL;
use lib "/opt/xcat/lib/perl";
use xCAT::Table;

# The database initialization may take some time in the system boot scenario
# wait for a while for the database initialization
#do we really need to do this for the web service?
sub sendRequest{
  my $request = shift;
  my $sitetab;
  my $retries = 0;

  if($DEBUGGING){
    my $preXml = $request;
    #$preXml =~ s/</<br>&lt /g;
    #$preXml =~ s/>/&gt<br>/g;
    print $q->p("request XML<br>$preXml");
  }
  #while (!($sitetab=xCAT::Table->new('site')) && $retries < 200)
  #{
    #print ("Can not open basic site table for configuration, waiting the database to be initialized.\n");
    #sleep 1;
    #$retries++;
  #}
  #unless ($sitetab) {
    #xCAT::MsgUtils->message("S","ERROR: Unable to open basic site table for configuration");
    #die;
  #}
#
  #my ($tmp) = $sitetab->getAttribs({'key'=>'xcatdport'},'value');
  #unless ($tmp) {
    #xCAT::MsgUtils->message("S","ERROR:Need xcatdport defined in site table, try chtab key=xcatdport site.value=3001");
    #die;
  #}
  my $port = 3001;#$tmp->{value};
  my $xcatHost = "localhost:$port";

  #temporary, will be using username and password
  my $homedir = "/root";
  my $keyfile = $homedir."/.xcat/client-cred.pem";
  my $certfile = $homedir."/.xcat/client-cred.pem";
  my $cafile  = $homedir."/.xcat/ca.pem";

  my $client;
  if (-r $keyfile and -r $certfile and -r $cafile) {
    $client = IO::Socket::SSL->new(
    PeerAddr => $xcatHost,
    SSL_key_file => $keyfile,
    SSL_cert_file => $certfile,
    SSL_ca_file => $cafile,
    SSL_use_cert => 1,
    Timeout => 15,
    );
  } else {
    $client = IO::Socket::SSL->new(
      PeerAddr => $xcatHost,
      Timeout => 15,
    );
  }
  unless ($client) {
    if ($@ =~ /SSL Timeout/) {
      sendStatusMsg($STATUS_TIMEOUT, "Connection failure: SSL Timeout or incorrect certificates in ~/.xcat");
      exit(0);
    }
    else{
      sendStatusMsg($STATUS_SERVICE_UNAVAILABLE, "Connection failure: $@");
      exit(0);
    }
  }

  print $client $request;

  my $response;
  my $rsp;
  my @fullResponse;
  my $cleanexit=0;
  while (<$client>) {
    $response .= $_;
    if (m/<\/xcatresponse>/) {
      #replace ESC with xxxxESCxxx because XMLin cannot handle it
      $response =~ s/\e/xxxxESCxxxx/g;
#print "responseXML is ".$response;
      $rsp = XMLin($response,SuppressEmpty=>undef,ForceArray=>1);

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

      $response='';
      push (@fullResponse, $rsp);
      if ($rsp->{serverdone}) {
        $cleanexit=1;
        last;
      }
    }
  }
  unless ($cleanexit) {
    sendStatusMsg($STATUS_SERVICE_UNAVAILABLE, "ERROR/WARNING: communication with the xCAT server seems to have been ended prematurely");
    exit(0);
  }
  
  if($DEBUGGING){
    print $q->p("response ".Dumper(@fullResponse));
  }
  return @fullResponse;
}

sub isGet{
  return uc($requestType) eq "GET";
}

sub isPut{
  return uc($requestType) eq "PUT";
}

sub isPost{
  return uc($requestType) eq "POST";
}

sub isPatch{
  return uc($requestType) eq "PATCH";
}

sub isDelete{
  return uc($requestType) eq "DELETE";
}
