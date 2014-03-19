#!/usr/bin/perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
use strict;
use CGI qw/:standard/;      #todo: remove :standard when the code only uses object oriented interface
#use JSON;              #todo: require this dynamically later on so that installations that do not use xcatws.cgi do not need perl-JSON
use Data::Dumper;

#talk to the server
use Socket;
use IO::Socket::INET;
use IO::Socket::SSL;
use lib "/opt/xcat/lib/perl";
use xCAT::Table;

#bmp: you need more comments in most of the file, especially in the handler routines

#URIdef{node|network}->{allnode|nodeattr}

my %URIdef = (
    #### definition for node resources
    node => {
        allnode => {
            desc => "[URI:/node] - The node list resource.",
            matcher => '^\/node$',
            GET => {
                desc => "Get all the nodes in xCAT.",
                usage => "||An array of node names.|",
                example => "|Get all the node names from xCAT database.|GET|/node|[\n   all,\n   node1,\n   node2,\n   node3,\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            }
        },
        nodeallattr => {
            desc => "[URI:/node/{nodename}] - The node resource",
            matcher => '^\/node\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for the node {nodename}.",
                usage => "||An array of node objects.|",
                example => "|Get all the attibutes for node \'node1\'.|GET|/node/node1|[\n   {\n      netboot:xnba,\n      mgt:1,\n      groups:22,\n      name:node1,\n      postbootscripts:otherpkgs,\n      postscripts:syslog,remoteshell,syncfiles\n   }\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the node {nodename}.",
                usage => "||An array of node objects.|",
                example => "|Change the attributes mgt=dfm and netboot=yaboot.|PUT|/node/node1 {mgt:dfm,netboot:yaboot}|{\n   \"info\":[\n      \"1 object definitions have been created or modified.\"\n   ]\n}|",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
            POST => {
                desc => "Create the node {nodename}. DataBody: {attr1:v1,att2:v2...}.",
                usage => "||An array of node objects.|",
                example => "|Create a node with attributes groups=all, mgt=dfm and netboot=yaboot|POST|/node/node1 {groups:all,mgt:dfm,netboot:yaboot}|{\n   \"info\":[\n      \"1 object definitions have been created or modified.\"\n   ]\n}|",
                cmd => "mkdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
            DELETE => {
                desc => "Remove the node {nodename}.",
                usage => "||An array of node objects.|",
                example => "|Delete the node node1|DELETE|/node/node1|{\n   \"info\":[\n      \"1 object definitions have been removed.\"\n   ]\n}|",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
        },
        nodeattr => {
            desc => "[URI:/node/{nodename}/attr/attr1;attr2;attr3 ...] - The attributes resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the node {nodename}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change attributes for the node {nodename}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            }
        },
        power => {
            desc => "[URI:/node/{nodename}/power] - The power resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/power$',
            GET => {
                desc => "Get the power status for the node {nodename}.",
                cmd => "rpower",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change power status for the node {nodename}. DataBody: {action:on|off|reset ...}.",
                cmd => "rpower",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            }
        },
        energy => {
            desc => "[URI:/node/{nodename}/energy] - The energy resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/energy$',
            GET => {
                desc => "Get the energy status for the node {nodename}.",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change energy attributes for the node {nodename}. DataBody: {cappingstatus:on ...}.",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            }
        },
        energyattr => {
            disable => 1,
            desc => "[URI:/node/{nodename}/energy/cappingmaxmin;cappingstatus;cappingvalue ...] - The specific energy attributes for the node {nodename}",
            matcher => '^\/node\/[^\/]*/energy/\S+$',
            GET => {
                desc => "Get the specific energy attributes cappingmaxmin,cappingstatus,cappingvalue for the node {nodename}.",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change energy attributes for the node {nodename}. DataBody: {cappingstatus:on ...}.",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            }
        },
        serviceprocessor => {
            disable => 1,
            desc => "[URI:/node/{nodename}/sp/{ip;netmask...}] - The specific attributes of service processor for the node {nodename}",
            matcher => '^\/node\/[^\/]*/sp/\S+$',
            GET => {
                desc => "Get the specific attributes for service processor resource.",
                cmd => "rspconfig",
                fhandler => \&sphdl,
            },
            PUT => {
                desc => "Change the specific attributes for the service processor resource. DataBody: {ip:xx.xx.xx.xx.xx.xx,netmask:xx.xx.xx.xx ...}.",
                cmd => "rspconfig",
                fhandler => \&sphdl,
            }
        },
        macaddress => {
            disable => 1,
            desc => "[URI:/node/{nodename}/mac] - The mac address resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/mac$',
            GET => {
                desc => "Get the mac address for the node {nodename}. Generally, it also updates the mac attribute of the node.",
                cmd => "getmacs",
                fhandler => \&common,
            },
        },
        nextboot => {
            desc => "[URI:/node/{nodename}/nextboot] - The boot order in next boot for the node {nodename}",
            matcher => '^\/node\/[^\/]*/nextboot$',
            GET => {
                desc => "Get the next boot order.",
                cmd => "rsetboot",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change the next boot order. DataBody: {order:net}.",
                cmd => "rsetboot",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            }
        },
        bootorder => {
            desc => "[URI:/node/{nodename}/bootorder] - The boot order for the node {nodename}",
            matcher => '^\/node\/[^\/]*/bootorder$',
            GET => {
                desc => "Get the boot order.",
                cmd => "rbootseq",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change the boot order. DataBody: {\"order\":\"net,hd\"}.",
                cmd => "rbootseq",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            }
        },
        vitals => {
            desc => "[URI:/node/{nodename}/vitals] - The vitals attributes for the node {nodename}",
            matcher => '^\/node\/[^\/]*/vitals$',
            GET => {
                desc => "Get all the vitals attibutes.",
                cmd => "rvitals",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        vitalsattr => {
            disable => 1,
            desc => "[URI:/node/{nodename}/vitals/{temp|voltage|wattage|fanspeed|power|leds...}] - The specific vital attributes for the node {nodename}",
            matcher => '^\/node\/[^\/]*/vitals/\S+$',
            GET => {
                desc => "Get the specific vital attibutes.",
                cmd => "rvitals",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        inventory => {
            desc => "[URI:/node/{nodename}/inventory] - The inventory attributes for the node {nodename}",
            matcher => '^\/node\/[^\/]*/inventory$',
            GET => {
                desc => "Get all the inventory attibutes.",
                cmd => "rinv",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        inventoryattr => {
            desc => "[URI:/node/{nodename}/inventory/{pci;model...}] - The specific inventory attributes for the node {nodename}",
            matcher => '^\/node\/[^\/]*/inventory/\S+$',
            GET => {
                desc => "Get the specific inventory attibutes.",
                cmd => "rinv",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        eventlog => {
            desc => "[URI:/node/{nodename}/eventlog] - The eventlog resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/eventlog$',
            GET => {
                desc => "Get all the eventlog for the node {nodename}.",
                cmd => "reventlog",
                fhandler => \&common,
            },
            DELETE => {
                desc => "Clean up the event log for the node {nodename}.",
                cmd => "reventlog",
                fhandler => \&common,
            },
        },
        beacon => {
            desc => "[URI:/node/{nodename}/beacon] - The beacon resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/beacon$',
            GET => {
                desc => "Get the beacon status for the node {nodename}.",
                cmd => "rbeacon",
                fhandler => \&common,
            },
            PUT => {
                desc => "Change the beacon status for the node {nodename}. DataBody: {on|off|blink}.",
                cmd => "rbeacon",
                fhandler => \&common,
            },
        },
        virtualization => {
            desc => "[URI:/node/{nodename}/virtualization] - The virtualization resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/virtualization$',
            GET => {
                desc => "Get the vm status for the node {nodename}.",
                cmd => "lsvm",
                fhandler => \&common,
            },
            PUT => {
                desc => "Change the vm status for the node {nodename}. DataBody: {new:1|clone:1|migrate:1 ...}. new=1 means to run mkvm; clone=1 means to run rclone; migrate=1 means to run rmigrate.",
                cmd => "",
                fhandler => \&common,
            },
            DELETE => {
                desc => "Remove the vm node {nodename}.",
                cmd => "rmvm",
                fhandler => \&common,
            },
        },
        updating => {
            desc => "[URI:/node/{nodename}/updating] - The updating resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/updating$',
            PUT => {
                desc => "Update the node with file syncing, software maintenance and rerun postscripts.",
                cmd => "updatenode",
                fhandler => \&common,
            },
        },
        filesyncing => {
            desc => "[URI:/node/{nodename}/filesyncing] - The filesyncing resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/filesyncing$',
            PUT => {
                desc => "Sync files for the node {nodename}. DataBody: {location of syncfile}",
                cmd => "updatenode",
                fhandler => \&common,
            },
        },
        software_maintenance => {
            desc => "[URI:/node/{nodename}/sw] - The software maintenance for the node {nodename}",
            matcher => '^\/node\/[^\/]*/sw$',
            PUT => {
                desc => "Perform the software maintenance process for the node {nodename}.",
                cmd => "updatenode",
                fhandler => \&common,
            },
        },
        postscript => {
            desc => "[URI:/node/{nodename}/postscript] - The postscript resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/postscript$',
            PUT => {
                desc => "Run the postscripts for the node {nodename}. DataBody: {p1,p2,p3...}",
                cmd => "updatenode",
                fhandler => \&common,
            },
        },
        nodeshell => {
            desc => "[URI:/node/{nodename}/nodeshell] - The nodeshell resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/nodeshell$',
            PUT => {
                desc => "Run the command in the nodeshell of the node {nodename}. DataBody: { ... }",
                cmd => "xdsh",
                fhandler => \&common,
            },
        },
        nodecopy => {
            desc => "[URI:/node/{nodename}/nodecopy] - The nodecopy resource for the node {nodename}",
            matcher => '^\/node\/[^\/]*/nodecopy$',
            PUT => {
                desc => "Copy files to the node {nodename}. DataBody: { ... }",
                cmd => "xcp",
                fhandler => \&common,
            },
        },
        subnode => {
            desc => "[URI:/node/{nodename}/subnode] - The sub nodes for the node {nodename}",
            matcher => '^\/node\/[^\/]*/subnode$',
            GET => {
                desc => "Return the Children node for the node {nodename}.",
                cmd => "rscan",
                fhandler => \&common,
            },
            PUT => {
                desc => "Update the Children node for the node {nodename}.",
                cmd => "rscan",
                fhandler => \&common,
            },
        },
        # for slpnode, we need use the query attribute to specify the network parameter for lsslp command
        slpnode => {
            desc => "[URI:/slpnode?network=xx] - The slp nodes in the xCAT cluster",
            matcher => '^\/slpnode\?.*$',
            GET => {
                desc => "Get all the nodes which support slp protocol in the network.",
                cmd => "lsslp",
                fhandler => \&common,
            },
            PUT => {
                desc => "Update the discovered nodes to database.",
                cmd => "lsslp",
                fhandler => \&common,
            },
        },
        specific_slpnode => {
            desc => "[URI:/slpnode/{IMM;CMM;CEC;FSP...}?network=xx] - The slp nodes with specific service type in the xCAT cluster",
            matcher => '^\/slpnode/[^\/]*/\?.*$',
            GET => {
                desc => "Get all the nodes with specific slp service type in the network.",
                cmd => "lsslp",
                fhandler => \&common,
            },
            PUT => {
                desc => "Update the discovered nodes to database.",
                cmd => "lsslp",
                fhandler => \&common,
            },
        },
        bootstat => {
            desc => "[URI:/node/{nodename}/bootstat] - The boot state resource for node {nodename}.",
            matcher => '^\/node\/[^\/]*/bootstat$',
            GET => {
                desc => "Get boot state.",
                cmd => "nodeset",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Set the boot state. DataBody: {osimage:xxx}",
                cmd => "nodeset",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },


        # TODO: rflash
    },

    #### definition for group resources
    group => {
    },
    
    #### definition for network resources
    network => {
        network => {
            desc => "[URI:/network] - The network resource.",
            matcher => '^\/network$',
            GET => {
                desc => "Get all the networks in xCAT.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
            POST => {
                desc => "Create the network resources base on the network configuration on xCAT MN.",
                cmd => "makenetworks",
                fhandler => \&defhdl,
            },
        },
        network_allattr => {
            desc => "[URI:/network/{netname}] - The network resource",
            matcher => '^\/network\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for the network {netname}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the network {netname}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            },
            POST => {
                desc => "Create the network {netname}. DataBody: {attr1:v1,att2:v2...}.",
                cmd => "mkdef",
                fhandler => \&defhdl,
            },
            DELETE => {
                desc => "Remove the network {netname}.",
                cmd => "rmdef",
                fhandler => \&defhdl,
            },
        },
        network_attr => {
            desc => "[URI:/network/{netname}/attr/attr1;attr2;attr3 ...] - The attributes resource for the network {netname}",
            matcher => '^\/network\/[^\/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the network {netname}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change attributes for the network {netname}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            }
        },

    },

    #### definition for osimage resources
    osimage => {
        osimage => {
            desc => "[URI:/osimage] - The osimage resource.",
            matcher => '^\/osimage$',
            GET => {
                desc => "Get all the osimage in xCAT.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
            POST => {
                desc => "Create the osimage resources base on the iso specified in the Data body. DataBody: {isopath: path}",
                cmd => "copycds",
                fhandler => \&defhdl,
            },
        },
        osimage_allattr => {
            desc => "[URI:/osimage/{osname}] - The osimage resource",
            matcher => '^\/osimage\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for the osimage {osname}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the osimage {osname}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            },
            POST => {
                desc => "Create the osimage {osname}. DataBody: {attr1:v1,att2:v2...}.",
                cmd => "mkdef",
                fhandler => \&defhdl,
            },
            DELETE => {
                desc => "Remove the osimage {osname}.",
                cmd => "rmdef",
                fhandler => \&defhdl,
            },
        },
        osimage_attr => {
            desc => "[URI:/osimage/{osname}/attr/attr1;attr2;attr3 ...] - The attributes resource for the osimage {osname}",
            matcher => '^\/osimage\/[^\/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the osimage {osname}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change attributes for the osimage {osname}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            }
        },

        # todo: genimage, packimage, imagecapture, imgexport, imgimport
    },

    #### definition for global setting resources
    site => {
        site => {
            desc => "[URI:/globalconf] - The global configuration resource.",
            matcher => '^\/globalconf$',
            GET => {
                desc => "Get all the configuration in global.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
        },
        site => {
            desc => "[URI:/globalconf/attr/{attr1;attr2 ...}] - The specific global configuration resource.",
            matcher => '^\/globalconf/attr/\S+$',
            GET => {
                desc => "Get the specific configuration in global.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
            PUT => {
            },
        },
    },
    
    #### definition for database/table resources

    #### definition for database/table resources
    table => {
        table_nodes => {
            desc => "[URI:/table/{tablelist}/node/{noderange}/{attrlist}] - The node table resource",
            matcher => '^/table/[^/]+/node(/[^/]+){0,2}$',
            GET => {
                desc => "Get attibutes for noderange {noderange} of the table {table}.",
                cmd => "getTablesNodesAttribs",     # not used
                fhandler => \&tablenodehdl,
                outhdler => \&tableout,
            },
            PUT => {
                desc => "Change the attibutes for the table {table}.",
                cmd => "chdef",
                fhandler => \&defhdl,
                #outhdler => \&defout,
            },
            POST => {
                desc => "Create the table {table}. DataBody: {attr1:v1,att2:v2...}.",
                cmd => "mkdef",
                fhandler => \&defhdl,
            },
            DELETE => {
                desc => "Remove the table {table}.",
                cmd => "rmdef",
                fhandler => \&defhdl,
            },
        },
        table_rows => {
            desc => "[URI:/table/{tablelist}/row/{keys}/{attrlist}] - The non-node table resource",
            matcher => '^/table/[^/]+/row(/[^/]+){0,2}$',
            GET => {
                desc => "Get attibutes for rows of the table {table}.",
                cmd => "getTablesAllRowAttribs",        # not used
                fhandler => \&tablerowhdl,
                outhdler => \&tableout,
            },
            PUT => {
                desc => "Change the attibutes for the table {table}.",
                cmd => "chdef",
                fhandler => \&defhdl,
                #outhdler => \&defout,
            },
            POST => {
                desc => "Create the table {table}. DataBody: {attr1:v1,att2:v2...}.",
                cmd => "mkdef",
                fhandler => \&defhdl,
            },
            DELETE => {
                desc => "Remove the table {table}.",
                cmd => "rmdef",
                fhandler => \&defhdl,
            },
        },
    },

);

# supported formats
my %formatters = (
    'json' => \&wrapJson,
    #'html' => \&wrapHtml,
    #'xml'  => \&wrapXml
);

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
my $VERSION   = "2.8";


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

#### Main procedure to handle the REST request

my $q           = CGI->new;
#my $url         = $q->url;      # the 1st part of the url, https, hostname, port num, and /xcatws
my $pathInfo    = $q->path_info;        # the resource specification, i.e. everything in the url after xcatws
#my $requestType = $ENV{'REQUEST_METHOD'};
my $requestType = $q->request_method();     # GET, PUT, POST, PATCH, DELETE
#my $queryString = $ENV{'QUERY_STRING'};     #todo: remove this when not used any more
#my $userAgent = $ENV{'HTTP_USER_AGENT'};        # curl, etc.
my $userAgent = $q->user_agent();        # the client program: curl, etc.
#my %queryhash;          # the queryString will get put into this
my @path = split(/\//, $pathInfo);
#shift(@path);       # get rid of the initial /
#my $resource    = $path[0];
my $pageContent = '';       # global var containing the ouptut back to the rest client
my $request     = {clienttype => 'ws'};     # global var that holds the request to send to xcatd
my $format = 'json';
my $pretty;
my $xmlinstalled;

# Handle the command parameter for debugging and generating doc
my $dbgdata;
sub dbgusage { print "Usage:\n    $0 -h\n    $0 -d\n    $0 {GET|PUT|POST|DELETE} URI user:password data\n"; }

if ($ARGV[0] eq "-h") {
    dbgusage();    
    exit 0;
} elsif ($ARGV[0] eq "-g") {
    require genrestapidoc;
    genrestapidoc::gendoc(\%URIdef);
    exit 0;
} elsif ($ARGV[0] eq "-d") {
    displayUsage();
    exit 0;
} elsif ($ARGV[0] =~ /(GET|PUT|POST|DELETE)/) {
    $requestType = $ARGV[0];
    $pathInfo= $ARGV[1];

    unless ($pathInfo) { dbgusage(); exit 1; }
    
    if ($ARGV[2] =~ /(.*):(.*)/) {
        $ENV{userName} = $1;
        $ENV{password} = $2;
    } else {
        dbgusage();    
        exit 0;
    }
    $dbgdata = $ARGV[3] if defined ($ARGV[3]);
} elsif (defined ($ARGV[0])) {
    dbgusage();    
    exit 1;
}

my $JSON;       # global ptr to the json object.  Its set by loadJSON()
#if (isPut() || isPost()) {
    loadJSON();        # need to do this early, so we can fetch the params
#}

# the input parameters from both the url and put/post data will combined and then
# separated into the general params (not specific to the api call) and params specific to the call
# Note: some of the values of the params in the hash can be arrays
my ($generalparams, $paramhash) = fetchParameters();

my $DEBUGGING = $generalparams->{debug};      # turn on or off the debugging output by setting debug=1 (or 2) in the url string
if ($DEBUGGING) {
    displaydebugmsg();
}

# Process the format requested
$format = $generalparams->{format} if (defined ($generalparams->{format}));

# Remove the last '/' in the pathInfo
$pathInfo =~ s/\/$//;

# Get the payload format from the end of URI
#if ($pathInfo =~ /\.json$/) {
#    $format = "json";
#    $pathInfo =~ s/\.json$//;
#} elsif ($pathInfo =~ /\.json.pretty$/) {
#    $format = "json";
#    $pretty = 1;
#    $pathInfo =~ s/\.json.pretty$//;
#} elsif ($pathInfo =~ /\.xml$/) {
#    $format = "xml";
#    $pathInfo =~ s/\.xml$//;
#} elsif ($pathInfo =~ /\.html$/) {
#    $format = "html";
#    $pathInfo =~ s/\.html$//;
#}

#if (!exists $formatters{$format}) {
#    error("The format '$format' is not supported",$STATUS_BAD_REQUEST);
#}

if ($format eq 'json') {
#    loadJSON();         # in case it was not loaded before
    if ($generalparams->{pretty}) { $JSON->indent(1); }
}

# require XML dynamically and let them know if it is not installed
# we need XML all the time to send request to xcat, even if thats not the return format requested by the user
loadXML();

# Match the first layer of resource URI
my $uriLayer1;

#bmp: why can't you just split on "/" like xcatws.cgi did?
# Get all the layers in the URI
my @layers;
my $portion = index($pathInfo, '/');
while (1) {
    my $endportion = index($pathInfo, '/', $portion+1);
    if ($endportion >= 0) {
        my $layer = substr($pathInfo, $portion+1, ($endportion - $portion - 1));
        push @layers, $layer if ($layer);
        $portion = $endportion;
    } else { # the last layer
        my $layer = substr($pathInfo, $portion+1);
        push @layers, $layer if ($layer);
        last;
    }
}

if ($#layers < 0) {
    # If no resource was specified
    addPageContent($q->p("This is the root page for the xCAT Rest Web Service.  Available resources are:"));
    foreach (sort keys %URIdef) {
        addPageContent($q->p($_));
    }
    sendResponseMsg($STATUS_OK);     # this will also exit
} else {
    $uriLayer1 = $layers[0];
}

# set the user and password to access xcatd
#todo: replace with using certificates or an api key
$request->{becomeuser}->[0]->{username}->[0] = $ENV{userName} if (defined($ENV{userName}));
$request->{becomeuser}->[0]->{username}->[0] = $generalparams->{userName} if (defined($generalparams->{userName}));
$request->{becomeuser}->[0]->{password}->[0] = $ENV{password} if (defined($ENV{password}));
$request->{becomeuser}->[0]->{password}->[0] = $generalparams->{password} if (defined($generalparams->{password}));

# find and invoke the correct handler and output handler functions
my $outputdata;
my $handled;
if (defined ($URIdef{$uriLayer1})) {
    # Make sure the resource has been defined
    foreach my $res (keys %{$URIdef{$uriLayer1}}) {
        my $matcher = $URIdef{$uriLayer1}->{$res}->{matcher};
        #bmp: if you use m|$matcher| here instead then you won't need to escape all of the /'s ?
        if ($pathInfo =~ m|$matcher|) {
            # matched to a resource
            if (defined ($URIdef{$uriLayer1}->{$res}->{$requestType}->{fhandler})) {    #bmp: if there isn't a handler, shouldn't we error out?
                 my $params;
                 unless (defined ($URIdef{$uriLayer1}->{$res}->{$requestType})) {       #bmp: how can this not be defined if we got here?
                     error("request method '$requestType' is not supported on resource '$pathInfo'",$STATUS_NOT_ALLOWED);
                 }
                 $params->{'cmd'} = $URIdef{$uriLayer1}->{$res}->{$requestType}->{cmd} if (defined ($URIdef{$uriLayer1}->{$res}->{$requestType}->{cmd}));
                 $params->{'outputhdler'} = $URIdef{$uriLayer1}->{$res}->{$requestType}->{outhdler} if (defined ($URIdef{$uriLayer1}->{$res}->{$requestType}->{outhdler}));
                 $params->{'layers'} = \@layers;
                 $params->{'resourcegroup'} = $uriLayer1;
                 $params->{'resourcename'} = $res;
                 # Call the hanldle subroutine to send request to xcatd and format the output
                 #@outputdata = $URIdef{$uriLayer1}->{$res}->{$requestType}->{fhandler}->($params);
                 # get the response from xcatd
                 $outputdata = $URIdef{$uriLayer1}->{$res}->{$requestType}->{fhandler}->($params);
                 # Filter the output data from the response
                 $outputdata = filterData ($outputdata);
                 # Restructure the output data
                 if (defined ($URIdef{$uriLayer1}->{$res}->{$requestType}->{outhdler})) {
                     $outputdata = $URIdef{$uriLayer1}->{$res}->{$requestType}->{outhdler}->($outputdata, $params);
                 } else {
                     # Call the appropriate formatting function stored in the formatters hash
                     if (exists $formatters{$format}) {
                         $formatters{$format}->($outputdata);
                     }
                 }
                 
                 $handled = 1;
                 last;
            }
        }
    }
} else {
    error("Unspported resource.",$STATUS_NOT_FOUND);
}

unless ($handled) {
    error("Unspported resource.",$STATUS_NOT_FOUND);
}


# all output has been added into the global varibale pageContent, call the response funcion
#if (exists $data->[0]->{info} && $data->[0]->{info}->[0] =~ /Could not find an object/) {
#    sendResponseMsg($STATUS_NOT_FOUND);
#}
if (isPost()) {
    sendResponseMsg($STATUS_CREATED);
}
else {
    sendResponseMsg($STATUS_OK);
}

#### End of the Main Program

#===========================================================
# Subrutines 
sub isGET { return uc($requestType) eq "GET"; }
sub isPost { return uc($requestType) eq "POST"; }
sub isPut { return uc($requestType) eq "PUT"; }
sub isPost { return uc($requestType) eq "POST"; }
sub isPatch { return uc($requestType) eq "PATCH"; }
sub isDelete { return uc($requestType) eq "DELETE"; }


# handle the input like  
# Object name: <objname>
#   attr=value
# ---
# TO
# ---
# nodename : value
# attr : value
sub defout {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        my $jsonnode;
        my $lines = $d->{info};
        foreach my $l (@$lines) {
            if ($l =~ /^Object name: /) {    # start new node
                if (defined($jsonnode)) { push @$json, $jsonnode; }     # push previous object onto array
                my ($nodename) = $l =~ /^Object name:\s+(\S+)/;
                $jsonnode = { name => $nodename };
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
# handle the input like
# all  (node)
# node1  (node)
# node2  (node)
# ---
# TO
# ---
# all
# node1
# node2

sub defout_remove_appended_type {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        my $jsonnode;
        my $lines = $d->{info};
        foreach my $l (@$lines) {
            if ($l =~ /^(\S*)\s+\(.*\)$/) {    # start new node
                push @{$json}, $1;
            }
        }
        #if (defined($jsonnode)) { push @$json, $jsonnode;  $jsonnode=undef; }     # push last object onto array
    }
    if ($json) {
        addPageContent($JSON->encode($json));
    }
}

sub infoout {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        if (defined ($d->{info})) {
            push @{$json->{info}}, @{$d->{info}};
        }
    }
    if ($json) {
        addPageContent($JSON->encode($json));
    }
}

sub actionout {
    my $data = shift;
    my $param =shift;

    my $json;
    my $jsonnode;
    foreach my $d (@$data) {
        if (defined ($d->{node}->[0]->{name})) {
            $jsonnode->{$d->{node}->[0]->{name}->[0]}->{'name'} = $d->{node}->[0]->{name}->[0];
        } else {
            next;
        }
        if (defined ($d->{node}->[0]->{data}) && ! defined($d->{node}->[0]->{data}->[0]->{contents})) {
            $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}} = $d->{node}->[0]->{data}->[0];
        } elsif (defined ($d->{node}->[0]->{data}->[0]->{contents})) {
            if (defined($d->{node}->[0]->{data}->[0]->{desc})) {
                $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$d->{node}->[0]->{data}->[0]->{desc}->[0]} = $d->{node}->[0]->{data}->[0]->{contents}->[0];
            } else {
                $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}} = $d->{node}->[0]->{data}->[0]->{contents}->[0];
            }
        } 
    }

    foreach (keys %{$jsonnode}) {
        push @$json, $jsonnode->{$_};
    }

    addPageContent($JSON->encode($json)) if ($json);
}

sub defout_1 {
    my $msg = shift;
   
    my @output;
    my $hn; 
    my $node;
    foreach (@{$msg}) {
        if (defined ($_->{info})) {
            foreach my $line (@{$_->{info}}) {
                if ($line =~ /Object name: (.*)/) {
                    #if ($node) {
                    #    push @output, $hn;
                    #}
                    $node = $1;
                } elsif ($line =~ /(.*)=(.*)/) {
                    my $n = $1;
                    my $v = $2;
                    $n =~ s/^\s*//;
                    $n =~ s/\s*$//;
                    $v =~ s/^\s*//;
                    $v =~ s/\s*$//;
                    $hn->{$node}->{$n} = $v;
                }
            }
            push @output, $hn;
        } else {
            push @output, $_;
        }
    }
    return \@output;
}


# invoke one of the def cmds
sub defhdl {
    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};

    # set the command name
    $request->{command} = $params->{'cmd'};

    # push the -t args
    push @args, ('-t', $params->{'resourcegroup'});

    # push the object name - node/noderange
    if (defined ($urilayers[1])) {
        push @args, ('-o', $urilayers[1]);
    }

    foreach my $k (keys(%$paramhash)) {
        push @args, "$k=$paramhash->{$k}" if ($k);
    } 
    
    if ($params->{'resourcename'} eq "allnode") {
        push @args, '-s';
    } elsif ($params->{'resourcename'} eq "nodeattr") {
        my $attrs = $urilayers[3];
        $attrs =~ s/;/,/g;

        if (isGET()) {
            push @args, ('-i', $attrs);
        } 
    }

    push @{$request->{arg}}, @args;  
    my $req = genRequest();
    my $responses = sendRequest($req);

    return $responses;
}

sub actionhdl {
    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};

    # set the command name
    $request->{command} = $params->{'cmd'};

        # push the object name - node/noderange
    if (defined ($urilayers[1])) {
        $request->{noderange} = $urilayers[1];
    }

    if ($params->{'resourcename'} eq "power") {
        if (isGET()) {
            push @args, 'stat';
        } elsif ($paramhash->{'action'}) {
            #my @v = keys(%$paramhash);
            push @args, $paramhash->{'action'};
        } else {
            error("Missed Action.",$STATUS_NOT_FOUND);
        }
    } elsif  ($params->{'resourcename'} =~ /(energy|energyattr)/) {
        if (isGET()) {
            if ($params->{'resourcename'} eq "energy") {
                push @args, 'all';
            } elsif ($params->{'resourcename'} eq "energyattr") {
                my @attrs = split(';', $urilayers[3]);
                push @args, @attrs;
            }
        } elsif ($paramhash) {
            my @params = keys(%$paramhash);
            push @args, "$params[0]=$paramhash->{$params[0]}";
        } else {
            error("Missed Action.",$STATUS_NOT_FOUND);
        }
    } elsif  ($params->{'resourcename'}eq "bootstat") {
        if (isGET()) {
            push @args, 'stat';
        } elsif ($paramhash->{'action'}) {
            push @args, $paramhash->{'action'};
        } elsif ($paramhash) {
            my @params = keys(%$paramhash);
            push @args, "$params[0]=$paramhash->{$params[0]}";
        } else {
            error("Missed Action.",$STATUS_NOT_FOUND);
        }
    } elsif  ($params->{'resourcename'} eq "nextboot") {
        if (isGET()) {
            push @args, 'stat';
        } elsif ($paramhash->{'order'}) {
            push @args, $paramhash->{'order'};
        } else {
            error("Missed Action.",$STATUS_NOT_FOUND);
        }
    } elsif ($params->{'resourcename'} =~ /(vitals|vitalsattr|inventory|inventoryattr)/) {
        if (defined($urilayers[3])) {
            my @attrs = split(';', $urilayers[3]);
            push @args, @attrs;
        }
    }

    push @{$request->{arg}}, @args;  
    my $req = genRequest();
    my $responses = sendRequest($req);

    return $responses;
}


# get attrs of tables for a noderange
sub tablenodehdl {
    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};
    # the array elements for @urilayers are:
    # 0 - 'table'
    # 1 - <tablelist>
    # 2 - 'node'
    # 3 - <noderange>  (optional)
    # 4 - <attrlist>  (optional)

    # set the command name
    my @tables = split(/,/, $urilayers[1]);

    if (!defined($urilayers[3]) || $urilayers[3] eq 'ALLNODES') {
        $request->{command} = 'getTablesAllNodeAttribs';
    } else {
        $request->{command} = 'getTablesNodesAttribs';
        $request->{noderange} = $urilayers[3];
    }

    # if they specified attrs, sort/group them by table
    my $attrlist = $urilayers[4];
    if (!defined($attrlist)) { $attrlist = 'ALL'; }       # attr=ALL means get all non-blank attributes
    my @attrs = split(/,/, $attrlist);
    my %attrhash;
    foreach my $a (@attrs) {
        if ($a =~ /\./) {
            my ($table, $attr) = split(/\./, $a);
            push @{$attrhash{$table}}, $attr;
        }
        else {      # the attr doesn't have a table qualifier so apply to all tables
            foreach my $t (@tables) { push @{$attrhash{$t}}, $a; }
        }
    }

    # deal with all of the tables and the attrs for each table
    foreach my $tname (@tables) {
        my $table = { tablename => $tname };
        if (defined($attrhash{$tname})) { $table->{attr} = $attrhash{$tname}; }
        else { $table->{attr} = 'ALL'; }
        push @{$request->{table}}, $table;
    }


    my $req = genRequest();
    # disabling the KeyAttr option is important in this case, so xmlin doesn't pull the name attribute
    # out of the node hash and make it the key
    my $responses = sendRequest($req, {SuppressEmpty => undef, ForceArray => 0, KeyAttr => []});

    return $responses;
}


# get attrs of tables for keys
sub tablerowhdl {
    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};
    # the array elements for @urilayers are:
    # 0 - 'table'
    # 1 - <tablelist>
    # 2 - 'row'
    # 3 - <key-val-list>  (optional)
    # 4 - <attrlist>  (optional)

    # do stuff that is common between getAttribs and getTablesAllRowAttribs
    my @tables = split(/,/, $urilayers[1]);
    my $attrlist = $urilayers[4];
    if (!defined($attrlist)) { $attrlist = 'ALL'; }       # attr=ALL means get all non-blank attributes
    my @attrs = split(/,/, $attrlist);

    # get all rows for potentially multiple tables
    if (!defined($urilayers[3]) || $urilayers[3] eq 'ALLROWS') {
        $request->{command} = 'getTablesAllRowAttribs';

        # if they specified attrs, sort/group them by table
        my %attrhash;
        foreach my $a (@attrs) {
            if ($a =~ /\./) {
                my ($table, $attr) = split(/\./, $a);
                push @{$attrhash{$table}}, $attr;
            }
            else {      # the attr doesn't have a table qualifier so apply to all tables
                foreach my $t (@tables) { push @{$attrhash{$t}}, $a; }
            }
        }

        # deal with all of the tables and the attrs for each table
        foreach my $tname (@tables) {
            my $table = { tablename => $tname };
            if (defined($attrhash{$tname})) { $table->{attr} = $attrhash{$tname}; }
            else { $table->{attr} = 'ALL'; }
            push @{$request->{table}}, $table;
        }
    }

    # for 1 table, get just one row based on the keys given
    else {
        if (scalar(@tables) > 1) { error('currently you can only specify keys for a single table.', $STATUS_BAD_REQUEST); }
        $request->{command} = 'getAttribs';
        $request->{table} = $tables[0];
        if (defined($urilayers[3])) {
            my @keyvals = split(/,/, $urilayers[3]);
            foreach my $kv (@keyvals) {
                my ($key, $value) = split(/\s*=\s*/, $kv, 2);
                $request->{keys}->{$key} = $value; 
            }
        }
        foreach my $a (@attrs) { push @{$request->{attr}}, $a; }
    }

    my $req = genRequest();
    # disabling the KeyAttr option is important in this case, so xmlin doesn't pull the name attribute
    # out of the node hash and make it the key
    my $responses = sendRequest($req, {SuppressEmpty => undef, ForceArray => 0, KeyAttr => []});

    return $responses;
}

# parse the output of all attrs of tables.  This is used for both node-oriented tables
# and non-node-oriented tables.
#todo: investigate a converter straight from xml to json
sub tableout {
    my $data = shift;
    my $json = {};
    # For the table calls, we turned off ForceArray and KeyAttr for XMLin(), so the output is a little
    # different than usual.  Each element is a hash with key "table" that is either a hash or array of hashes.
    # Each element of that is a hash with 2 keys called "tablename" and "node". The latter has either: an array of node hashes,
    # or (if there is only 1 node returned) the node hash directly.
    # We are producing json that is a hash of table name keys that each have an array of node objects.
    foreach my $d (@$data) {
        my $table = $d->{table};
        if (!defined($table)) {     # special case for the getAttribs cmd
            $json = $d;
            last;
        }
        #debug(Dumper($d)); debug (Dumper($jsonnode));
        if (ref($table) eq 'HASH') { $table = [$table]; }       # if a single table, make it a 1 element array of tables
        foreach my $t (@$table) {
            my $jsonnodes = [];         # start an array of node objects for this table
            my $tabname = $t->{tablename};
            if (!defined($tabname)) { $tabname = 'unknown' . $::i++; }       #todo: have lissa fix this bug
            $json->{$tabname} = $jsonnodes;           # add it into the top level hash
            my $node = $t->{node};
            if (!defined($node)) { $node = $t->{row}; }
            #debug(Dumper($d)); debug (Dumper($jsonnode));
            if (ref($node) eq 'HASH') { $node = [$node]; }       # if a single node, make it a 1 element array of nodes
            foreach my $n (@$node) { push @$jsonnodes, $n; }
        }
    }
    addPageContent($JSON->encode($json));
}

sub displayUsage {
    foreach my $group (keys %URIdef) {
        print "Resource Group: $group\n";
        foreach my $res (keys %{$URIdef{$group}}) {
            print "    Resource: $res\n";
            print "        $URIdef{$group}->{$res}->{desc}\n";
            if (defined ($URIdef{$group}->{$res}->{GET})) {
                print "            GET: $URIdef{$group}->{$res}->{GET}->{desc}\n";
            }
            if (defined ($URIdef{$group}->{$res}->{PUT})) {
                print "            PUT: $URIdef{$group}->{$res}->{PUT}->{desc}\n";
            }
            if (defined ($URIdef{$group}->{$res}->{POST})) {
                print "            POST: $URIdef{$group}->{$res}->{POST}->{desc}\n";
            }
            if (defined ($URIdef{$group}->{$res}->{DELETE})) {
                print "            DELETE: $URIdef{$group}->{$res}->{DELETE}->{desc}\n";
            }
        }
    }
}


# This handles and removes serverdone and error tags in the perl data structure that is from the xml that xcatd returned
#bmp: is there a way to avoid make a copy of the whole response?  For big output that could be time consuming.
#       For the error tag, you don't have to bother copying the response, because you are going to exit anyway.
#       Maybe this function could just verify there is a serverdone and handle any error, and then
#       let each specific output handler ignore the serverdone tag?
sub filterData {
    my $data             = shift;
    my $errorInformation = '';
    #debugandexit(Dumper($data));

    my $outputdata;
    #trim the serverdone message off
    foreach (@{$data}) {
        if (exists($_->{serverdone}) || defined($_->{error})) {
            if (exists($_->{serverdone}) && defined($_->{error})) {
                if (ref($_->{error}) eq 'ARRAY') { $errorInformation = $_->{error}->[0]; }
                else { $errorInformation = $_->{error}; }
                addPageContent(qq({"error":"$errorInformation"}));
                if (($errorInformation =~ /Permission denied/) || ($errorInformation =~ /Authentication failure/)) {
                    sendResponseMsg($STATUS_UNAUTH);
                }
                else {
                    sendResponseMsg($STATUS_FORBIDDEN);
                }
                exit 1;
            }
            next;
        } else {
            push @{$outputdata}, $_;
        }
        
    }

    return $outputdata;
}

# Structure the response perl data structure into well-formed json.  Since the structure of the
# xml output that comes from xcatd is inconsistent and not very structured, we have a lot of work to do.
sub wrapJson {
    # this is an array of responses from xcatd.  Often all the output comes back in 1 response, but not always.
    my $data = shift;

    addPageContent($JSON->encode($data));
    return;


    # put, delete, and patch usually just give a short msg, if anything
    if (isPut() || isDelete() || isPatch()) {
        addPageContent($JSON->encode($data));
        return;
    }
}


#bmp: this isn't used anymore, just here for reference, right?
# structure the json output for node resource api calls
sub wrapJsonNodes {
    # this is an array of responses from xcatd.  Often all the output comes back in 1 response, but not always.
    my $data = shift;

    # Divide the processing into several groups of requests, according to how they return the output
    # At this point, these are all gets and posts.  The others were taken care of wrapJson()
    my $json;
    if (isGet()) {
        if (!defined $path[2] && !defined($paramhash->{field})) {        # querying node list
            # The data structure is: array of hashes that have a single key 'node'.  The value for that key
            # is an array of hashes with a single key 'name'.  The value for that key
            # is a 1-element array that contains the node name.
            # Create a json array of node name strings.
            $json = [];
            foreach my $d (@$data) {
                my $ar = $d->{node};
                foreach my $a (@$ar) {
                    my $nodename = $a->{name}->[0];
                    if (!defined($nodename)) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                    push @$json, $nodename;
                }
            }
            addPageContent($JSON->encode($json));
        }
        elsif (!defined $path[2] && defined($paramhash->{field})) {        # querying node attributes
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
        elsif (grep(/^$path[2]$/, qw(power inventory vitals energy status))) {        # querying other node info
            # The data structure is: array of hashes that have a single key 'node'.  The value for that key
            # is a 1-element array that has a hash with keys 'name' and 'data'.  The 'name' value is a 1-element
            # array that has the nodename.  The 'data' value is a 1-element array of a hash that has keys 'desc'
            # and 'content' (sometimes desc is ommited), or in the case of status it has the status directly in the array.
            # Create a json array of node objects. Each node object contains the attributes/values (including
            # the nodename) of that object.
            $json = {};     # its keys are nodenames
            foreach my $d (@$data) {
                # each element is a complex structure that contains 1 attr and value for a node
                my $node = $d->{node}->[0];
                my $nodename = $node->{name}->[0];
                my $nodedata = $node->{data}->[0];
                if ($path[2] eq 'status') {
                    $json->{$nodename} = $nodedata;
                }
                else {
                    my $contents = $nodedata->{contents}->[0];
                    my $desc = 'power';         # rpower doesn't output a desc tag
                    if (defined($nodedata->{desc})) { $desc = $nodedata->{desc}->[0]; }
                    # add this desc and content into this node's hash
                    $json->{$nodename}->{$desc} = $contents;
                }
            }
            if ($path[2] eq 'status') { addPageContent($JSON->encode($json)); }
            else {
                # convert this hash of hashes into an array of hashes
                my @jsonarray;
                foreach my $n (sort(keys(%$json))) {
                    $json->{$n}->{nodename} = $n;       # add the key (nodename) inside of the node's hash
                    push @jsonarray, $json->{$n};
                }
                addPageContent($JSON->encode(\@jsonarray));
            }
        }
        else {      # querying a node subresource (rpower, rvitals, rinv, etc.)
            addPageContent($JSON->encode($data));
        }       # end else path[2] defined
    }
    elsif (isPost()) {          # dsh or dcp
        if ($path[2] eq 'dsh') {
            # The data structure is: array of hashes with a single key, either 'data' or 'errorcode'.  The value
            # of 'errorcode' is a 1-element array containing the error code.  The value of 'data' is an array of
            # output lines prefixed by the node name.  Some of the lines can be null.
            # Create a hash with 2 keys: 'errorcode' and 'nodes'. The 'nodes' value is a hash of nodenames, each
            # value is an array of the output for that node.
            $json = {};     # its keys are nodenames
            foreach my $d (@$data) {
                # this is either an errorcode hash or data hash
                if (defined($d->{errorcode})) {
                    $json->{errorcode} = $d->{errorcode}->[0];
                }
                elsif (defined($d->{data})) {
                    foreach my $line (@{$d->{data}}) {
                        my ($nodename, $output) = $line =~ m/^(\S+): (.*)$/;
                        if (defined($nodename)) { push @{$json->{$nodename}}, $output; }
                    }
                }
                else { error('improperly formatted xdsh output from xcatd', $STATUS_TEAPOT); }
            }
            addPageContent($JSON->encode($json));
        }
        elsif ($path[2] eq 'dcp') {
            # The data structure is a 1-element array of a hash with 1 key 'errorcode'.  That has a 1-element
            # array with the code in it.  Let's simplify it.
            $json->{errorcode} = $data->[0]->{errorcode}->[0];
            addPageContent($JSON->encode($json));
        }
        else {
            addPageContent($JSON->encode($data));
        }
    }       # end if isPost
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
    if ('json' eq $format) {
        $tempFormat = 'application/json';
    }
    elsif ('xml' eq $format) {
        $tempFormat = 'text/xml';
    }
    else {
        $tempFormat = 'text/html';
    }
    print $q->header(-status => $code, -type => $tempFormat);
    if ($pageContent) { $pageContent .= "\n"; }     # if there is any content, append a newline
    print $pageContent;
    exit(0);
}

# Convert xcat request to xml for sending to xcatd
sub genRequest {
    my $xml = XML::Simple::XMLout($request, RootName => 'xcatrequest', NoAttr => 1, KeyAttr => []);
}

# Send the request to xcatd and read the response.  The request passed in has already been converted to xml.
# The response returned to the caller of this function has already been converted from xml to perl structure.
sub sendRequest {
    my $request = shift;
    my $xmlinoptions = shift;        # optional arg to not set ForceArray on the XMLin() call
    my $sitetab;
    my $retries = 0;

    if ($DEBUGGING == 2) {
        my $preXml = $request;
        $preXml =~ s/</<br>&lt /g;
        $preXml =~ s/>/&gt<br>/g;
        addPageContent($q->p("DEBUG: request XML: " . $request . "\n"));
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
    my $fullResponse = [];
    my $cleanexit = 0;
    while (<$client>) {
        $response .= $_;
        if (m/<\/xcatresponse>/) {

            #replace ESC with xxxxESCxxx because XMLin cannot handle it
            if ($DEBUGGING) {
                #addPageContent("DEBUG: response from xcatd: " . $response . "\n");
            }
            $response =~ s/\e/xxxxESCxxxx/g;
            debug("response xml=$response");

            #bmp: i added the $xmlinoptions var because for the table output it saved me processing if everything
            #       wasn't forced into arrays.  Consider if that could save you processing on other api calls too.
            if (!$xmlinoptions) { $xmlinoptions = {SuppressEmpty => undef, ForceArray => 1}; }
            $rsp = XML::Simple::XMLin($response, %$xmlinoptions);
            #debug(Dumper($rsp));

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
            push(@$fullResponse, $rsp);
            if (exists($rsp->{serverdone})) {
                $cleanexit = 1;
                last;
            }
        }
    }
    unless ($cleanexit) {
        error("communication with the xCAT server seems to have been ended prematurely",$STATUS_SERVICE_UNAVAILABLE);
    }

    if ($DEBUGGING == 2) {
        addPageContent($q->p("DEBUG: full response from xcatd: " . Dumper($fullResponse)));
    }
    return $fullResponse;
}

# Put input parameters from both $q->url_param and put/post data (if it exists) into generalparams and paramhash for all to use
sub fetchParameters {
    my @generalparamlist = qw(userName password pretty debug);
    # 1st check for put/post data and put that in the hash
    my $pdata;
    if (isPut()) { $pdata = $q->param('PUTDATA'); }
    elsif (isPost()) { $pdata = $q->param('POSTDATA'); }
    if ($dbgdata) {
        $pdata = $dbgdata;
    }
    my $genparms = {};
    my $phash;
    if ($pdata) {
        $phash = eval { $JSON->decode($pdata); };
        if ($@) { error("$@",$STATUS_BAD_REQUEST); }
        #debug("phash=" . Dumper($phash));
        if (ref($phash) ne 'HASH') { error("put or post data must be a json object (hash/dict).", $STATUS_BAD_REQUEST); }

        # if any general parms are in the put/post data, move them to genparms
        foreach my $k (keys %$phash) {
            if (grep(/^$k$/, @generalparamlist)) {
                $genparms->{$k} = $phash->{$k};
                delete($phash->{$k});
            }
        }
    }
    else { $phash = {}; }

    # now get params from the url (if any of the keys overlap, the url value will overwrite the put/post value)
    foreach my $p ($q->url_param) {
        my @a = $q->url_param($p);          # this could be a single value or an array, have to figure it out
        my $value;
        if (scalar(@a) > 1) { $value = [@a]; }      # convert it to a reference to an array
        else { $value = $a[0]; }
        if (grep(/^$p$/, @generalparamlist)) { $genparms->{$p} = $value; }
        else { $phash->{$p} = $value; }
    }

    return ($genparms, $phash);
}

# Load the XML::Simple module
sub loadXML {
    if ($xmlinstalled) { return; }
    
    $xmlinstalled = eval { require XML::Simple; };
    unless ($xmlinstalled) {
        error('The XML::Simple perl module is missing.  Install perl-XML-Simple before using the xCAT REST web services API with this format."}',$STATUS_SERVICE_UNAVAILABLE);
    }
    $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
}

# Load the JSON perl module, if not already loaded.  Sets the $JSON global var.
sub loadJSON {
    if ($JSON) { return; }      # already loaded
    # require JSON dynamically and let them know if it is not installed
    my $jsoninstalled = eval { require JSON; };
    unless ($jsoninstalled) {
        error("JSON perl module missing.  Install perl-JSON before using the xCAT REST web services API.", $STATUS_SERVICE_UNAVAILABLE);
    }
    $JSON = JSON->new();
}

# add a error msg to the output in the correct format and end this request
sub error {
    my ($msg, $errorcode) = @_;
    my $severity = 'error';
    my $m;
    #if ($format eq 'xml') { $m = "<$severity>$msg</$severity>\n"; }
    #elsif ($format eq 'json') {
        $m = qq({"$severity":"$msg"});
    #}
    #else { $m = "<p>$severity: $msg</p>\n"; }
    addPageContent($m);
    sendResponseMsg($errorcode);
}


# if debugging, output the given string
sub debug {
    if (!$DEBUGGING) { return; }
    addPageContent($q->p("DEBUG: $_[0]\n"));
}

# when having bugs that cause this cgi to not produce any output, output something and then exit.
sub debugandexit {
    debug("$_[0]\n");
    sendResponseMsg($STATUS_OK);
}

sub displaydebugmsg {
    addPageContent($q->p("DEBUG: generalparams:". Dumper($generalparams)));
    addPageContent($q->p("DEBUG: paramhash:". Dumper($paramhash)));
    addPageContent($q->p("DEBUG: q->request_method: $requestType\n"));
    #addPageContent($q->p("DEBUG: q->user_agent: $userAgent\n"));
    addPageContent($q->p("DEBUG: pathInfo: $pathInfo\n"));
    #addPageContent($q->p("DEBUG: path " . Dumper(@path) . "\n"));
    #foreach (keys(%ENV)) { addPageContent($q->p("DEBUG: ENV{$_}: $ENV{$_}\n")); }
    #addPageContent($q->p("DEBUG: userName=".$paramhash->{userName}.", password=".$paramhash->{password}."\n"));
    #addPageContent($q->p("DEBUG: http() values:\n" . http() . "\n"));
    #if ($pdata) { addPageContent($q->p("DEBUG: pdata: $pdata\n")); }
    addPageContent("\n");
    if ($DEBUGGING == 3) {
        sendResponseMsg($STATUS_OK);     # this will also exit
    }
}


# push flags (options) onto the xcatd request.  Arguments: request args array, flags array.
# Format of flags array: <urlparam-name> <xdsh-cli-flag> <if-there-is-associated-value>
# Use this function for cmds with a lot of flags like xdcp and xdsh
sub pushFlags {
    my ($args, $flags) = @_;
    foreach my $f (@$flags) {
        my ($key, $flag, $arg) = @$f;
        if (defined($paramhash->{$key})) {
            push @$args, $flag;
            if ($arg) { push @$args, $paramhash->{$key}; }
        }
    }
}
