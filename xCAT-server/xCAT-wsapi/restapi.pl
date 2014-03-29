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

# The hash %URIdef defines all the xCAT resources which can be access from Web Service.
# This script will be called when a https request with the URI started with /xcatws/ is sent to xCAT Web Service
# Inside this script:
#   1. The main body parses the URI and parameters
#   2. Base on the URI, go through the %URIdef to find the matched resource by the 'matcher' which is defined for each resource
#   3. Call the 'fhandler' which is defined in the resource to communicate with xcatd and get the xml response
#     3.1 The 'fhandler' generates the xml request base on the resource, parameters and http method 'GET|PUT|POST|DELETE', sends to xcatd and then get the xml response
#   4. Call the 'outhdler' which is defined in the resource to parse the xml response and translate it to JSON format
#   5. Output the http response to STDOUT
#
# Refer to the $URIdef{node}->{allnode} and $URIdef{node}->{nodeallattr} for your new created resource definition.
#
# |--node - Resource Group
# |  `--allnode - Resource Name
# |    `--desc - Description for the Resource
# |    `--desc[1..10] - Additional description for the Resource
# |    `--matcher - The matcher which is used to match the URI to the Resource
# |    `--GET - The info is used to handle the GET request
# |      `--desc - Description for the GET operation
# |      `--desc[1..10] - Additional description for the GET operation
# |      `--usage - Usage message. The format must be '|Parameters for the GET request|Returns for the GET request|'. The message in the '|' can be black, but the delimiter '|' must be kept.
# |      `--example - Example message. The format must be '|Description|GET|URI PUT/POST_data|Return Msg|'. The messages in the four sections must be completed.
# |      `--cmd - The xCAT command line coammnd which will be used to complete the request. It's not a must have attribute.
# |      `--fhandler - The call back subroutine which is used to handle the GET request. Generally, it parses the parameters from request and then call xCAT command. This subroutine can be exclusive or shared.
# |      `--outhdler - The call back subroutine which is used to handle the GET request. Generally, it parses the xml output from the 'fhandler' and then format the output to JSON. This subroutine can be exclusive or shared.
# |    `--PUT - The info is used to handle the PUT request
# |    `--POST - The info is used to handle the POST request
# |    `--DELETE - The info is used to handle the DELETE request

my %usagemsg = (
    objreturn => "Json format: An object which includes multiple \'<name> : {att:value, attr:value ...}\' pairs.",
    objchparam => "Json format: An object which includes multiple \'att:value\' pairs.",
    non_getreturn => "No output for succeeded execution. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}."
);

my %URIdef = (
    #### definition for node resources
    nodes => {
        allnode => {
            desc => "[URI:/nodes] - The node list resource.",
            desc1 => "This resource can be used to display all the nodes which have been defined in the xCAT database.",
            matcher => '^/nodes$',
            GET => {
                desc => "Get all the nodes in xCAT.",
                desc1 => "The attributes details for the node will not be displayed.",
                usage => "||Json format: An array of node names.|",
                example => "|Get all the node names from xCAT database.|GET|/nodes|[\n   \"node1\",\n   \"node2\",\n   \"node3\",\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            }
        },
        nodeallattr => {
            desc => "[URI:/nodes/{nodename}] - The node resource",
            matcher => '^/nodes/[^/]*$',
            GET => {
                desc => "Get all the attibutes for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the attibutes for node \'node1\'.|GET|/nodes/node1|{\n   \"node1\":{\n      \"profile\":\"compute\",\n      \"netboot\":\"xnba\",\n      \"arch\":\"x86_64\",\n      \"mgt\":\"ipmi\",\n      \"groups\":\"all\",\n      ...\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the node {nodename}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Change the attributes mgt=dfm and netboot=yaboot.|PUT|/nodes/node1 {\"mgt\":\"dfm\",\"netboot\":\"yaboot\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            POST => {
                desc => "Create the node {nodename}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Create a node with attributes groups=all, mgt=dfm and netboot=yaboot|POST|/nodes/node1 {\"groups\":\"all\",\"mgt\":\"dfm\",\"netboot\":\"yaboot\"}||",
                cmd => "mkdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the node {nodename}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the node node1|DELETE|/nodes/node1||",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
        },
        nodeattr => {
            desc => "[URI:/nodes/{nodename}/attr/{attr1,attr2,attr3 ...}] - The attributes resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the attributes {groups,mgt,netboot} for node node1|GET|/nodes/node1/attr/groups,mgt,netboot|{\n   \"node1\":{\n      \"netboot\":\"xnba\",\n      \"mgt\":\"ipmi\",\n      \"groups\":\"all\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT_backup => {
                desc => "Change attributes for the node {nodename}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                usage => "||An array of node objects.|",
                example => "|Get the attributes {groups,mgt,netboot} for node node1|GET|/nodes/node1/attr/groups;mgt;netboot||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            }
        },
        nodestat => {
            desc => "[URI:/nodes/{nodename}/nodestat}] - The attributes resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/nodestat$',
            GET => {
                desc => "Get the running status for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the running status for node node1|GET|/nodes/node1/nodestat|x|",
                cmd => "nodestat",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        nodehost => {
            desc => "[URI:/nodes/{nodename}/host] - The mapping of ip and hostname for the node {nodename}",
            matcher => '^/nodes/[^/]*/host$',
            POST => {
                desc => "Create the mapping of ip and hostname record for the node {nodename}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the mapping of ip and hostname record for node \'node1\'.|POST|/nodes/node1/host||",
                cmd => "makehosts",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        nodedns => {
            desc => "[URI:/nodes/{nodename}/dns] - The dns record resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/dns$',
            POST => {
                desc => "Create the dns record for the node {nodename}.",
                desc1 => "The prerequisite of the POST operation is the mapping of ip and nodename for the node has been added in the /etc/hosts.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the dns record for node \'node1\'.|POST|/nodes/node1/dns||",
                cmd => "makedns",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the dns record for the node {nodename}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the dns record for node node1|DELETE|/nodes/node1/dns||",
                cmd => "makedns",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        nodedhcp => {
            desc => "[URI:/nodes/{nodename}/dhcp] - The dhcp record resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/dhcp$',
            POST => {
                desc => "Create the dhcp record for the node {nodename}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the dhcp record for node \'node1\'.|POST|/nodes/node1/dhcp||",
                cmd => "makedhcp",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the dhcp record for the node {nodename}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the dhcp record for node node1|DELETE|/nodes/node1/dhcp||",
                cmd => "makedhcp",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        power => {
            desc => "[URI:/nodes/{nodename}/power] - The power resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/power$',
            GET => {
                desc => "Get the power status for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the power status.|GET|/nodes/node1/power|{\n   \"node1\":{\n      \"power\":\"on\"\n   }\n}|",
                cmd => "rpower",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change power status for the node {nodename}.",
                usage => "|Json Formatted DataBody: {action:on/off/reset ...}.|$usagemsg{non_getreturn}|",
                example => "|Change the power status to on|PUT|/nodes/node1/power {\"action\":\"on\"}||",
                cmd => "rpower",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        energy => {
            desc => "[URI:/nodes/{nodename}/energy] - The energy resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/energy$',
            GET => {
                desc => "Get all the energy status for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the energy attributes.|GET|/nodes/node1/energy|{\n   \"node1\":{\n      \"cappingmin\":\"272.3 W\",\n      \"cappingmax\":\"354.0 W\"\n      ...\n   }\n}|",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change energy attributes for the node {nodename}.",
                usage => "|$usagemsg{objchparam} DataBody: {powerattr:value}.|$usagemsg{non_getreturn}|",
                example => "|Turn on the cappingstatus to [on]|PUT|/nodes/node1/energy {\"cappingstatus\":\"on\"}||",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        energyattr => {
            disable => 1,
            desc => "[URI:/nodes/{nodename}/energy/{cappingmaxmin,cappingstatus,cappingvalue ...}] - The specific energy attributes resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/energy/\S+$',
            GET => {
                desc => "Get the specific energy attributes cappingmaxmin,cappingstatus,cappingvalue ... for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the energy attributes which are specified in the URI.|GET|/nodes/node1/energy/cappingmaxmin,cappingstatus|{\n   \"node1\":{\n      \"cappingmin\":\"272.3 W\",\n      \"cappingmax\":\"354.0 W\"\n   }\n}|",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change energy attributes for the node {nodename}. ",
                usage => "|$usagemsg{objchparam} DataBody: {powerattr:value}.|$usagemsg{non_getreturn}|",
                example => "|Turn on the cappingstatus to [on]|PUT|/nodes/node1/energy {\"cappingstatus\":\"on\"}||",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        serviceprocessor => {
            disable => 1,
            desc => "[URI:/nodes/{nodename}/sp/{community|ip|netmask|...}] - The attribute resource of service processor for the node {nodename}",
            matcher => '^/nodes/[^/]*/sp/\S+$',
            GET => {
                desc => "Get the specific attributes for service processor resource.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the snmp community for the service processor of node1.|GET|/nodes/node1/sp/community|{\n   \"node1\":{\n      \"SP SNMP Community\":\"public\"\n   }\n}|",
                cmd => "rspconfig",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change the specific attributes for the service processor resource. ",
                usage => "|$usagemsg{objchparam} DataBody: {community:public}.|$usagemsg{non_getreturn}|",
                example => "|Set the snmp community to [mycommunity].|PUT|/nodes/node1/sp/community {\"value\":\"mycommunity\"}||",
                cmd => "rspconfig",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        macaddress => {
            disable => 1,
            desc => "[URI:/nodes/{nodename}/mac] - The mac address resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/mac$',
            GET => {
                desc => "Get the mac address for the node {nodename}. Generally, it also updates the mac attribute of the node.",
                cmd => "getmacs",
                fhandler => \&common,
            },
        },
        nextboot => {
            desc => "[URI:/nodes/{nodename}/nextboot] - The temporary bootorder resource in next boot for the node {nodename}",
            matcher => '^/nodes/[^/]*/nextboot$',
            GET => {
                desc => "Get the next bootorder.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the bootorder for the next boot. (It's only valid after setting.)|GET|/nodes/node1/nextboot|{\n   \"node1\":{\n      \"nextboot\":\"Network\"\n   }\n}|",
                cmd => "rsetboot",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change the next boot order. ",
                usage => "|$usagemsg{objchparam} DataBody: {order:net/hd}.|$usagemsg{non_getreturn}|",
                example => "|Set the bootorder for the next boot.|PUT|/nodes/node1/nextboot {\"order\":\"net\"}||",
                cmd => "rsetboot",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        bootorder => {
            desc => "[URI:/nodes/{nodename}/bootorder] - The permanent bootorder resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/bootorder$',
            GET => {
                desc => "Get the permanent boot order.",
                usage => "|?|?|",
                example => "|Get the permanent bootorder for the node1.|GET|/nodes/node1/bootorder|?|",
                cmd => "rbootseq",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change the boot order. DataBody: {\"order\":\"net,hd\"}.",
                usage => "|Put data: Json formatted order:value pair.|?|",
                example => "|Set the permanent bootorder for the node1.|PUT|/nodes/node1/bootorder|?|",
                cmd => "rbootseq",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        vitals => {
            desc => "[URI:/nodes/{nodename}/vitals] - The vitals resources for the node {nodename}",
            matcher => '^/nodes/[^/]*/vitals$',
            GET => {
                desc => "Get all the vitals attibutes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the vitails attributes for the node1.|GET|/nodes/node1/vitals|{\n   \"node1\":{\n      \"SysBrd Fault\":\"0\",\n      \"CPUs\":\"0\",\n      \"Fan 4A Tach\":\"3330 RPM\",\n      \"Drive 15\":\"0\",\n      \"SysBrd Vol Fault\":\"0\",\n      \"nvDIMM Flash\":\"0\",\n      \"Progress\":\"0\"\n      ...\n   }\n}|",
                cmd => "rvitals",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        vitalsattr => {
            disable => 1,
            desc => "[URI:/nodes/{nodename}/vitals/{temp|voltage|wattage|fanspeed|power|leds...}] - The specific vital attributes for the node {nodename}",
            matcher => '^/nodes/[^/]*/vitals/\S+$',
            GET => {
                desc => "Get the specific vitals attibutes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the \'fanspeed\' vitals attribute.|GET|/nodes/node1/vitals/fanspeed|{\n   \"node1\":{\n      \"Fan 1A Tach\":\"3219 RPM\",\n      \"Fan 4B Tach\":\"2688 RPM\",\n      \"Fan 3B Tach\":\"2560 RPM\",\n      \"Fan 4A Tach\":\"3330 RPM\",\n      \"Fan 2A Tach\":\"3293 RPM\",\n      \"Fan 1B Tach\":\"2592 RPM\",\n      \"Fan 3A Tach\":\"3182 RPM\",\n      \"Fan 2B Tach\":\"2592 RPM\"\n   }\n}|",
                cmd => "rvitals",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        inventory => {
            desc => "[URI:/nodes/{nodename}/inventory] - The inventory attributes for the node {nodename}",
            matcher => '^/nodes/[^/]*/inventory$',
            GET => {
                desc => "Get all the inventory attibutes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the inventory attributes for node1.|GET|/nodes/node1/inventory|{\n   \"node1\":{\n      \"DIMM 21 \":\"8GB PC3-12800 (1600 MT/s) ECC RDIMM\",\n      \"DIMM 1 Manufacturer\":\"Hyundai Electronics\",\n      \"Power Supply 2 Board FRU Number\":\"94Y8105\",\n      \"DIMM 9 Model\":\"HMT31GR7EFR4C-PB\",\n      \"DIMM 8 Manufacture Location\":\"01\",\n      \"DIMM 13 Manufacturer\":\"Hyundai Electronics\",\n      \"DASD Backplane 4\":\"Not Present\",\n      ...\n   }\n}|",
                cmd => "rinv",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        inventoryattr => {
            desc => "[URI:/nodes/{nodename}/inventory/{pci;model...}] - The specific inventory attributes for the node {nodename}",
            matcher => '^/nodes/[^/]*/inventory/\S+$',
            GET => {
                desc => "Get the specific inventory attibutes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the \'model\' inventory attribute for node1.|GET|/nodes/node1/inventory/model|{\n   \"node1\":{\n      \"System Description\":\"System x3650 M4\",\n      \"System Model/MTM\":\"7915C2A\"\n   }\n}|",
                cmd => "rinv",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        eventlog => {
            desc => "[URI:/nodes/{nodename}/eventlog] - The eventlog resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/eventlog$',
            GET => {
                desc => "Get all the eventlog for the node {nodename}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the eventlog for node1.|GET|/nodes/node1/eventlog|{\n   \"node1\":{\n      \"eventlog\":[\n         \"03/19/2014 15:17:58 Event Logging Disabled, Log Area Reset/Cleared (SEL Fullness)\"\n      ]\n   }\n}|",
                cmd => "reventlog",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            DELETE => {
                desc => "Clean up the event log for the node {nodename}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete all the event log for node1.|DELETE|/nodes/node1/eventlog|[\n   {\n      \"eventlog\":[\n         \"SEL cleared\"\n      ],\n      \"name\":\"node1\"\n   }\n]|",
                cmd => "reventlog",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        beacon => {
            desc => "[URI:/nodes/{nodename}/beacon] - The beacon resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/beacon$',
            GET_backup => {
                desc => "Get the beacon status for the node {nodename}.",
                cmd => "rbeacon",
                fhandler => \&common,
            },
            PUT => {
                desc => "Change the beacon status for the node {nodename}.",
                usage => "|$usagemsg{objchparam} DataBody: {action:on/off/blink}.|$usagemsg{non_getreturn}|",
                example => "|Turn on the beacon.|PUT|/nodes/node1/beacon {\"action\":\"on\"}|[\n   {\n      \"name\":\"node1\",\n      \"beacon\":\"on\"\n   }\n]|",
                cmd => "rbeacon",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        virtualization => {
            desc => "[URI:/nodes/{nodename}/virtualization] - The virtualization resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/virtualization$',
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
            desc => "[URI:/nodes/{nodename}/updating] - The updating resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/updating$',
            POST => {
                desc => "Update the node with file syncing, software maintenance and rerun postscripts.",
                usage => "||An array of messages for performing the node updating.|",
                example => "|Initiate an updatenode process.|POST|/nodes/node2/updating|[\n   \"There were no syncfiles defined to process. File synchronization has completed.\",\n   \"Performing software maintenance operations. This could take a while, if there are packages to install.\n\",\n   \"node2: Wed Mar 20 15:01:43 CST 2013 Running postscript: ospkgs\",\n   \"node2: Running of postscripts has completed.\"\n]|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        filesyncing => {
            desc => "[URI:/nodes/{nodename}/filesyncing] - The filesyncing resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/filesyncing$',
            POST => {
                desc => "Sync files for the node {nodename}. DataBody: {location of syncfile}",
                usage => "||An array of messages for performing the file syncing for the node.|",
                example => "|Initiate an file syncing process.|POST|/nodes/node2/filesyncing|[\n   \"There were no syncfiles defined to process. File synchronization has completed.\"\n]|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        software_maintenance => {
            desc => "[URI:/nodes/{nodename}/sw] - The software maintenance for the node {nodename}",
            matcher => '^/nodes/[^/]*/sw$',
            POST => {
                desc => "Perform the software maintenance process for the node {nodename}.",
                usage => "||An array of messages for performing the software maintenance for the node.|",
                example => "|Initiate an software maintenance process.|POST|/nodes/node2/sw|[\n   \"Performing software maintenance operations. This could take a while, if there are packages to install.\n\",\n   \"node2: Wed Mar 20 15:40:27 CST 2013 Running postscript: ospkgs\",\n   \"node2: Unable to read consumer identity\",\n   \"node2: Postscript: ospkgs exited with code 0\",\n   \"node2: Wed Mar 20 15:40:29 CST 2013 Running postscript: otherpkgs\",\n   \"node2: ./otherpkgs: no extra rpms to install\",\n   \"node2: Postscript: otherpkgs exited with code 0\",\n   \"node2: Running of Software Maintenance has completed.\"\n]|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        postscript => {
            desc => "[URI:/nodes/{nodename}/postscript] - The postscript resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/postscript$',
            POST => {
                desc => "Run the postscripts for the node {nodename}. DataBody: {scripts:[p1,p2,p3,...]}",
                usage => "|Put data: Json formatted scripts:[scriptname list].|An array of messages for the running postscripts for the node.|",
                example => "|Initiate an updatenode process.|POST|/nodes/node2/postscript {\"scripts\":[\"syslog\",\"remoteshell\"]}|[\n   \"node2: Wed Mar 20 15:39:23 CST 2013 Running postscript: syslog\",\n   \"node2: Shutting down system logger: [  OK  ]\n\",\n   \"node2: Starting system logger: [  OK  ]\n\",\n   \"node2: Postscript: syslog exited with code 0\",\n   \"node2: Wed Mar 20 15:39:23 CST 2013 Running postscript: remoteshell\",\n   \"node2: \",\n   \"node2: Stopping sshd: [  OK  ]\n\",\n   \"node2: Starting sshd: [  OK  ]\n\",\n   \"node2: Postscript: remoteshell exited with code 0\",\n   \"node2: Running of postscripts has completed.\"\n]|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        nodeshell => {
            desc => "[URI:/nodes/{nodename}/nodeshell] - The nodeshell resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/nodeshell$',
            POST => {
                desc => "Run the command in the shell of the node {nodename}. DataBody: {command:[cmd1,cmd2]}",
                usage => "|Put data: Json formatted command:[cmd1,cmd2].|An arry of messages for running commands on the node.|",
                example => "|Run the \'data\' command on the node2.|POST|/nodes/node2/nodeshell {\"command\":[\"date\",\"ls\"]}|[\n   \"node2: Wed Mar 20 16:18:08 CST 2013\",\n   \"node2: anaconda-ks.cfg\nnode2: install.log\nnode2: install.log.syslog\nnode2: post.log\",\n   null\n]|",
                cmd => "xdsh",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        nodecopy => {
            desc => "[URI:/nodes/{nodename}/nodecopy] - The nodecopy resource for the node {nodename}",
            matcher => '^/nodes/[^/]*/nodecopy$',
            POST => {
                desc => "Copy files to the node {nodename}. DataBody: {src:[file1,file2],target:dir}",
                usage => "|Put data: Json formatted src file and target file or directory.|Error messages.|",
                example => "|Copy files to the node2.|POST|/nodes/node2/nodecopy {\"src\":[\"/tmp/f1\",\"/tmp/f2\"],\"target\":\"/tmp\"}|no output for succeeded copy.|",
                cmd => "xdcp",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        subnode => {
            desc => "[URI:/nodes/{nodename}/subnode] - The sub nodes for the node {nodename}",
            matcher => '^/nodes/[^/]*/subnode$',
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
            matcher => '^/slpnode\?.*$',
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
            matcher => '^/slpnode/[^/]*/\?.*$',
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
        bootstate => {
            desc => "[URI:/nodes/{nodename}/bootstate] - The boot state resource for node {nodename}.",
            matcher => '^/nodes/[^/]*/bootstate$',
            GET => {
                desc => "Get boot state.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the next boot state for the node1.|GET|/nodes/node1/bootstate|{\n   \"node1\":{\n      \"bootstat\":\"boot\"\n   }\n}|",
                cmd => "nodeset",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Set the boot state.",
                usage => "|$usagemsg{objchparam} DataBody: {osimage:xxx}/{state:offline}.|$usagemsg{non_getreturn}|",
                example => "|Set the next boot state for the node1.|PUT|/nodes/node1/bootstate {\"osimage\":\"rhels6.4-x86_64-install-compute\"}||",
                cmd => "nodeset",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },


        # TODO: rflash
    },

    #### definition for group resources
    groups => {
        all_groups => {
            desc => "[URI:/groups] - The group list resource.",
            desc1 => "This resource can be used to display all the groups which have been defined in the xCAT database.",
            matcher => '^/groups$',
            GET => {
                desc => "Get all the groups in xCAT.",
                desc1 => "The attributes details for the group will not be displayed.",
                usage => "||Json format: An array of group names.|",
                example => "|Get all the group names from xCAT database.|GET|/groups|[\n   \"__mgmtnode\",\n   \"all\",\n   \"compute\",\n   \"ipmi\",\n   \"kvm\",\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            }
        },
        group_allattr => {
            desc => "[URI:/groups/{groupname}] - The group resource",
            matcher => '^/groups/[^/]*$',
            GET => {
                desc => "Get all the attibutes for the group {groupname}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the attibutes for group \'all\'.|GET|/groups/all|{\n   \"all\":{\n      \"members\":\"zxnode2,nodexxx,node1,node4\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the group {groupname}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Change the attributes mgt=dfm and netboot=yaboot.|PUT|/groups/all {\"mgt\":\"dfm\",\"netboot\":\"yaboot\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
        },
        group_attr => {
            desc => "[URI:/groups/{groupname}/attr/{attr1,attr2,attr3 ...}] - The attributes resource for the group {groupname}",
            matcher => '^/groups/[^/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the group {groupname}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the attributes {mgt,netboot} for group all|GET|/groups/all/attr/mgt,netboot|{\n   \"all\":{\n      \"netboot\":\"yaboot\",\n      \"mgt\":\"dfm\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
        },
    },

    #### definition for services resources: dns, dhcp, hostname
    services => {
        host => {
            desc => "[URI:/services/host] - The hostname resource.",
            matcher => '^/services/host$',
            POST => {
                desc => "Create the ip/hostname records for all the nodes to /etc/hosts.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the ip/hostname records for all the nodes to /etc/hosts.|POST|/services/host||",
                cmd => "makehosts",
                fhandler => \&nonobjhdl,
                outhdler => \&noout,
            }
        },
        dns => {
            desc => "[URI:/services/dns] - The dns service resource.",
            matcher => '^/services/dns$',
            POST => {
                desc => "Initialize the dns service.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Initialize the dns service.|POST|/services/dns||",
                cmd => "makedns",
                fhandler => \&nonobjhdl,
                outhdler => \&noout,
            }
        },
        dhcp => {
            desc => "[URI:/services/dhcp] - The dhcp service resource.",
            matcher => '^/services/dhcp$',
            POST => {
                desc => "Create the dhcpd.conf for all the networks which are defined in the xCAT Management Node.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the dhcpd.conf and restart the dhcpd.|POST|/services/dhcp||",
                cmd => "makedhcp",
                fhandler => \&nonobjhdl,
                outhdler => \&noout,
            }
        },
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
                desc => "Create the osimage resources base on the parameters specified in the Data body. DataBody: {iso:isoname|file:filename|node:nodename,params:[{attr1:value,attr2:value2}]}",
                cmd => "copycds",
                fhandler => \&imgophdl,
            },
        },
        osimage_allattr => {
            desc => "[URI:/osimage/{imgname}] - The osimage resource",
            matcher => '^\/osimage\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for the osimage {imgname}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the osimage {imgname}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            },
            POST => {
                desc => "Create the osimage {imgname}. DataBody: {attr1:v1,att2:v2...}.",
                cmd => "mkdef",
                fhandler => \&defhdl,
            },
            DELETE => {
                desc => "Remove the osimage {imgname}.",
                cmd => "rmdef",
                fhandler => \&defhdl,
            },
        },
        osimage_attr => {
            desc => "[URI:/osimage/{imgname}/attr/attr1;attr2;attr3 ...] - The attributes resource for the osimage {imgname}",
            matcher => '^\/osimage\/[^\/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the osimage {imgname}.",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change attributes for the osimage {imgname}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                cmd => "chdef",
                fhandler => \&defhdl,
            }
        },
        osimage_op => {
            desc => "[URI:/osimage/{imgname}/instance] - The instance for the osimage {imgname}",
            matcher => '^\/osimage\/[^\/]*/instance$',
            POST => {
                desc => "Operate the instance of the osimage {imgname}. DataBody: {action:gen|pack|export,params:[{attr1:v1,attr2:v2}]}",
                cmd => "",
                fhandler => \&imgophdl,
            },
            DELETE => {
                desc => "Delete the instance for the osimage {imgname} from the file system",
                cmd => "rmimage",
                fhandler => \&imgophdl,
            },
        },

        # todo: genimage, packimage, imagecapture, imgexport, imgimport
    },

    #### definition for policy resources
    policy => {
        policy => {
            desc => "[URI:/policy] - The policy resource.",
            matcher => '^\/policy$',
            GET => {
                desc => "Get all the policies in xCAT.",
                usage => "||An array of policy list.|",
                example => "|Get all the policy objects.|GET|/policy|[\n   \"1\",\n   \"1.2\",\n   \"2\",\n   \"4.8\"\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
            POST_back => {
                desc => "Create a new policy on xCAT MN.",
                usage => "|?|?|",
                example => "|Create |?|?|?|",
                cmd => "chdef",
                fhandler => \&defhdl,
            },
        },
        policy_allattr => {
            desc => "[URI:/policy/{policy_priority}] - The policy resource",
            matcher => '^\/policy\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for a policy {policy_priority}.",
                usage => "||An array policy object, each object includes the values for each attribute.|",
                example => "|Get all the attribute for policy 1.|GET|/policy/1|[\n   {\n      \"name\":\"root\",\n      \"rule\":\"allow\"\n   }\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the policy {policy_priority}.",
                usage => "|Put data: Json formatted attribute:value pairs.|Message indicates the success or failure.|",
                example => "|Set the name attribute for policy 3.|PUT|/policy/3 {\"name\":\"root\"}|[\n   \"1 object definitions have been created or modified.\"\n]|",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
            POST => {
                desc => "Create the policy {policyname}. DataBody: {attr1:v1,att2:v2...}.",
                usage => "|POST data: Json formatted attribute:value pairs.|Message indicates the success or failure.|",
                example => "|Create a new policy 10.|POST|/policy/10 {\"name\":\"root\",\"commands\":\"rpower\"}|[\n   \"1 object definitions have been created or modified.\"\n]|",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
            DELETE => {
                desc => "Remove the policy {policy_priority}.",
                usage => "||Message indicates the success or failure.|",
                example => "|Delete the policy 10.|DELETE|/policy/10|[\n   \"1 object definitions have been removed.\"\n]|",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
        },
        policy_attr => {
            desc => "[URI:/policy/{policyname}/attr/{attr1;attr2;attr3,...}] - The attributes resource for the policy {policy_priority}",
            matcher => '^\/policy\/[^\/]*/attr/\S+$',
            GET => {
                desc => "Get the specific attributes for the policy {policy_priority}.",
                usage => "||An array policy object, each object includes the values for each attribute.|",
                example => "|Get the name and rule attributes for policy 1.|GET|/policy/1/attr/name;rule|[\n   {\n      \"name\":\"root\",\n      \"rule\":\"allow\"\n   }\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the policy {policy_priority}.",
                usage => "|Put data: Json formatted attribute:value pairs.|Message indicates the success or failure.|",
                example => "|Set the name attribute for policy 3.|PUT|/policy/3 {\"name\":\"root\"}|[\n   \"1 object definitions have been created or modified.\"\n]|",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&infoout,
            },
        },
    },
    #### definition for global setting resources
    globalconf => {
        all_site => {
            desc => "[URI:/globalconf] - The global configuration resource.",
            matcher => '^\/globalconf$',
            GET => {
                desc => "Get all the xCAT global configuration.",
                usage => "||An array of all the global configuration list.|",
                example => "|Get all the global configuration|GET|/globalconf|[\n   {\n      \"xcatconfdir\":\"/etc/xcat\",\n      \"tftpdir\":\"/tftpboot\",\n      ...\n   }\n]|",
                cmd => "lsdef",
                fhandler => \&sitehdl,
                outhdler => \&defout,
            },
            POST_backup => {
                desc => "Add the site attributes. DataBody: {attr1:v1,att2:v2...}.",
                usage => "|?|?|",
                example => "|?|?|?|?|",
                cmd => "chdef",
                fhandler => \&sitehdl,
            },
        },
        site => {
            desc => "[URI:/globalconf/attr/{attr1;attr2 ...}] - The specific global configuration resource.",
            matcher => '^\/globalconf/attr/\S+$',
            GET => {
                desc => "Get the specific configuration in global.",
                usage => "||?|",
                example => "|Get the \'master\' and \'domain\' configuration.|GET|/globalconf/attr/master;domain|?|",
                cmd => "lsdef",
                fhandler => \&sitehdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attributes for the site table. DataBody: {name:value}.",
                usage => "|Put data: Json formatted name:value pairs.|?|",
                example => "|Change the domain attribute.|PUT|/globalconf/attr/domain|?|",
                cmd => "chdef",
                fhandler => \&sitehdl,
            },
            POST => {
                desc => "Create the global configuration entry. DataBody: {name:value}.",
                usage => "|Put data: Json formatted name:value pairs.||",
                example => "|Create the domain attribute|POST|/globalconf/attr/domain {\"domain\":\"cluster.com\"}|?|",
                cmd => "chdef",
                fhandler => \&sitehdl,
            },
            DELETE => {
                desc => "Remove the site attributes.",
                usage => "||?|",
                example => "|Remove the domain configure.|DELETE|/globalconf/attr/domain|?|",
                cmd => "chdef",
                fhandler => \&sitehdl,
            },
        },
    },

    #### definition for database/table resources
    table => {
        table_nodes => {
            desc => "[URI:/table/{tablelist}/nodes/{noderange}/{attrlist}] - The node table resource",
            matcher => '^/table/[^/]+/nodes(/[^/]+){0,2}$',
            GET => {
                desc => "Get table attibutes for a noderange. {noderange} and {attrlist} are optional.",
                usage => "||An object for the specific attributes.|",
                example => "|Get |GET|/table/mac/nodes/node1/mac|{\n   \"mac\":[\n      {\n         \"name\":\"node1\",\n         \"mac\":\"mac=6c:ae:8b:41:3f:53\"\n      }\n   ]\n}|",
                cmd => "getTablesNodesAttribs",     # not used
                fhandler => \&tablenodehdl,
                outhdler => \&tableout,
            },
            #PUT => {
            #    desc => "Change the attibutes for the table {table}.",
            #    cmd => "chdef",
            #    fhandler => \&defhdl,
                #outhdler => \&defout,
            #},
            #POST => {
            #    desc => "Create the table {table}. DataBody: {attr1:v1,att2:v2...}.",
            #    cmd => "mkdef",
            #    fhandler => \&defhdl,
            #},
            #DELETE => {
            #    desc => "Remove the table {table}.",
            #    cmd => "rmdef",
            #    fhandler => \&defhdl,
            #},
        },
        table_rows => {
            desc => "[URI:/table/{tablelist}/row/{keys}/{attrlist}] - The non-node table resource",
            matcher => '^/table/[^/]+/row(/[^/]+){0,2}$',
            GET => {
                desc => "Get attibutes for rows of non-node tables. {rows} and {attrlist} are optional.",
                usage => "||?|",
                example => qq(|Get|GET|/table/networks/row/net=192.168.122.0,mask=255.255.255.0/mgtifname,tftpserver|{\n   "mgtifname":"virbr0",\n   "tftpserver":"192.168.122.1"\n}|),
                cmd => "getTablesAllRowAttribs",        # not used
                fhandler => \&tablerowhdl,
                outhdler => \&tableout,
            },
            #PUT => {
            #    desc => "Change the attibutes for the table {table}.",
            #    cmd => "chdef",
            #    fhandler => \&defhdl,
                #outhdler => \&defout,
            #},
            #POST => {
            #    desc => "Create the table {table}. DataBody: {attr1:v1,att2:v2...}.",
            #    cmd => "mkdef",
            #    fhandler => \&defhdl,
            #},
            #DELETE => {
            #    desc => "Remove the table {table}.",
            #    cmd => "rmdef",
            #    fhandler => \&defhdl,
            #},
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
    if (defined ($ARGV[1])) {
        genrestapidoc::gendoc(\%URIdef, $ARGV[1]);
    } else {
        genrestapidoc::gendoc(\%URIdef);
    }
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
    #addPageContent($q->p("This is the root page for the xCAT Rest Web Service.  Available resources are:"));
    my $json;
    foreach (sort keys %URIdef) {
        push @{$json}, $_;
    }
    if ($json) {
        addPageContent($JSON->encode($json));
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
            unless (defined ($URIdef{$uriLayer1}->{$res}->{$requestType})) {
                 error("request method '$requestType' is not supported on resource '$pathInfo'", $STATUS_NOT_ALLOWED);
            }
            if (defined ($URIdef{$uriLayer1}->{$res}->{$requestType}->{fhandler})) {
                 my $params;
                 
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
        #my $jsonnode;
        my $nodename;
        my $lines = $d->{info};
        foreach my $l (@$lines) {
            if ($l =~ /^Object name: /) {    # start new node
                #if (defined($jsonnode)) { push @$json, $jsonnode; $nodename=undef; $jsonnode=undef;}     # push previous object onto array
                $l =~ /^Object name:\s+(\S+)/;
                $nodename = $1;
            }
            else {      # just an attribute of the current node
                if (! $nodename) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                my ($attr, $val) = $l =~ /^\s*(\S+)=(.*)$/;
                if (!defined($attr)) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                $json->{$nodename}->{$attr} = $val;
            }
        }
        #if (defined($jsonnode)) { push @$json, $jsonnode; $nodename=undef; $jsonnode=undef; }     # push last object onto array
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

# This is the general callback subroutine for PUT/POST/DELETE methods
# when this subroutine is called, that means the operation has been done successfully
# The correct output is 'null'
sub noout {

### for debugging
    my $data = shift;

    addPageContent(qq(\n\n\n=======================================================\nDebug: Following message is just for debugging. It will be removed in the GAed version.\n));

    my $json;
    if ($data) {
        addPageContent($JSON->encode($data));
    }

    addPageContent(qq(["Debug: the operation has been done successfully"]));
### finish the debugging

    
}

# hanlde the output which is node irrelevant
sub infoout {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        if (defined ($d->{info})) {
            push @{$json}, @{$d->{info}};
        }
        if (defined ($d->{data})) {
            if (ref($d->{data}->[0]) ne "HASH") {
                push @{$json}, @{$d->{data}};
            } else {
                if (defined($d->{data}->[0]->{contents})) {
                    push @{$json}, @{$d->{data}->[0]->{contents}};
                }
            }
        }
        if (defined ($d->{error})) {
            push @{$json}, @{$d->{error}};
        }
    }
    if ($json) {
        addPageContent($JSON->encode($json));
    }
}

# handle the action against noderange
sub actionout {
    my $data = shift;
    my $param =shift;

    my $jsonnode;
    foreach my $d (@$data) {
        unless (defined ($d->{node}->[0]->{name})) {
            next;
        }
        if (defined ($d->{node}->[0]->{data}) && (ref($d->{node}->[0]->{data}->[0]) ne "HASH" || ! defined($d->{node}->[0]->{data}->[0]->{contents}))) {
            $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}} = $d->{node}->[0]->{data}->[0];
        } elsif (defined ($d->{node}->[0]->{data}->[0]->{contents})) {
            if (defined($d->{node}->[0]->{data}->[0]->{desc})) {
                $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$d->{node}->[0]->{data}->[0]->{desc}->[0]} = $d->{node}->[0]->{data}->[0]->{contents}->[0];
            } else {
                if ($param->{'resourcename'} eq "eventlog") {
                    push @{$jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}}}, $d->{node}->[0]->{data}->[0]->{contents}->[0];
                } else {
                    $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}} = $d->{node}->[0]->{data}->[0]->{contents}->[0];
                }
            }
        } 
    }

    addPageContent($JSON->encode($jsonnode)) if ($jsonnode);
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
    my $resrctype = $params->{'resourcegroup'};
    $resrctype =~ s/s$//;  # remove the last 's' as the type of object
    push @args, ('-t', $resrctype);

    # push the object name - node/noderange
    if (defined ($urilayers[1])) {
        push @args, ('-o', $urilayers[1]);
    }

    foreach my $k (keys(%$paramhash)) {
        push @args, "$k=$paramhash->{$k}" if ($k);
    } 
    
    if ($params->{'resourcename'} eq "allnode") {
        push @args, '-s';
    } elsif ($params->{'resourcename'} =~ /(nodeattr|osimage_attr|group_attr)/) {
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
                my @attrs = split(',', $urilayers[3]);
                push @args, @attrs;
            }
        } elsif ($paramhash) {
            my @params = keys(%$paramhash);
            push @args, "$params[0]=$paramhash->{$params[0]}";
        } else {
            error("Missed Action.",$STATUS_NOT_FOUND);
        }
    } elsif  ($params->{'resourcename'}eq "bootstate") {
        if (isGET()) {
            push @args, 'stat';
        } elsif ($paramhash->{'action'}) {
            push @args, $paramhash->{'action'};
        } elsif ($paramhash) {
            my @params = keys(%$paramhash);
            if ($params[0] eq "state") {
                # hanlde the {state:offline}
                push @args, $paramhash->{$params[0]};
            } else {
                # handle the {osimage:imagename}
                push @args, "$params[0]=$paramhash->{$params[0]}";
            }
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
    } elsif ($params->{'resourcename'} eq "serviceprocessor") {
        if (isGET()) {
            push @args, $urilayers[3];
        } elsif ($paramhash->{'value'}) {
            push @args, $urilayers[3]."=".$paramhash->{'value'};
        }
    } elsif ($params->{'resourcename'} eq "eventlog") {
        if (isGET()) {
            push @args, 'all';
        } elsif (isDelete()) {
            push @args, 'clear';
        }
    } elsif ($params->{'resourcename'} eq "beacon") {
        if (isPut()) {
            push @args, $paramhash->{'action'};
        }
    } elsif ($params->{'resourcename'} eq "filesyncing") {
        push @args, '-F';
    } elsif ($params->{'resourcename'} eq "software_maintenance") {
        push @args, '-S';
    } elsif ($params->{'resourcename'} eq "postscript") {
        push @args, '-P';
        if (defined ($paramhash->{'scripts'})) {
            push @args, join (',', @{$paramhash->{'scripts'}});
        }
    } elsif ($params->{'resourcename'} eq "nodeshell") {
        if (defined ($paramhash->{'command'})) {
            push @args, join (';', @{$paramhash->{'command'}});
        }
    } elsif ($params->{'resourcename'} eq "nodecopy") {
        if (defined ($paramhash->{'src'})) {
            push @args, @{$paramhash->{'src'}};
        }
        if (defined ($paramhash->{'target'})) {
            push @args, $paramhash->{'target'};
        }
    } elsif ($params->{'resourcename'} =~ /(dns|dhcp)/) {
        if (isDelete()) {
            push @args, '-d';
        }
    }

    push @{$request->{arg}}, @args;  
    my $req = genRequest();
    my $responses = sendRequest($req);

    return $responses;
}

# handle the request for node irrelevant commands like makedns -n and makedhcp -n
sub nonobjhdl {
    my $params = shift;

    my @args;

    # set the command name
    $request->{command} = $params->{'cmd'};
    if ($params->{'resourcename'} =~ /(dns|dhcp)/) {
        push @args, '-n';
    }
    
    push @{$request->{arg}}, @args;  
    my $req = genRequest();
    my $responses = sendRequest($req);

    return $responses;
}


# operate image instance for a osimage
sub imgophdl {
    my $params = shift;
    my @args = ();
    if (isPost()) {
        if ($params->{'resourcename'} eq "osimage_op") {
            my $action = $paramhash->{'action'};
            unless ($action) {
                error("Missed Action.",$STATUS_NOT_FOUND);
            } elsif ($action eq "gen") {
                $params->{'cmd'} = "genimage";
            } elsif ($action eq "pack") {
                $params->{'cmd'} = "packimage";
            } elsif ($action eq "export") {
                $params->{'cmd'} = "imgexport";
            } else {
                error("Incorrect action:$action.",$STATUS_BAD_REQUEST);
            }
        } elsif ($params->{'resourcename'} eq "osimage") {
            if (exists($paramhash->{'iso'})) {
                $params->{'cmd'} = "copycds";
                push @{$params->{layers}}, $paramhash->{'iso'};
            } elsif (exists($paramhash->{'file'})) {
                $params->{'cmd'} = "imgimport";
                push @{$params->{layers}}, $paramhash->{'file'};
            } elsif (exists($paramhash->{'node'})) {
                $params->{'cmd'} = "imgcapture";
                push @{$params->{layers}}, $paramhash->{'node'};
            } else {
                error("Invalid source.",$STATUS_NOT_FOUND);
            }
        }
    }
    $request->{command} = $params->{'cmd'};
    push @args, $params->{layers}->[1]; 
    if (exists($paramhash->{'params'})) {
        foreach (keys %{$paramhash->{'params'}->[0]}) {
            push @args, ($_, $paramhash->{'params'}->[0]->{$_});
        }
    }
    push @{$request->{arg}}, @args;  
    my $req = genRequest();
    my $responses = sendRequest($req);
    return $responses;
}

sub sitehdl {
    my $params = shift;
    my @args;
    my @urilayers = @{$params->{'layers'}};

    # set the command name
    $request->{command} = $params->{'cmd'};
    # push the -t args
    push @args, '-t';
    push @args, 'site';
    if (isGET()) {	
        push @args, 'clustersite';
    }			
    if (defined ($urilayers[2])){
        if (isGET()) {
            push @args, ('-i', $urilayers[2]);
		}	
    }
    if (isDelete()) {
        if (defined ($urilayers[2])){
            push @args, "$urilayers[2]=";
       }
    }
    foreach my $k (keys(%$paramhash)) {
        push @args, "$k=$paramhash->{$k}" if ($k);
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

# Filter out the error message
#   If has 'error' message in the output data, push them all to one list
#   If has 'errorcode' in the output data, set it to be the errorcode of response. Otherwise, the errorcode to '1'
# When get the 'serverdone' identifer
#   If 'errorcode' has been set, return the error message and error code like {error:[msg1,msg2...], errorcode:num}
#   Otherwise, pass the output to the outputhandler for the specific resource

sub filterData {
    my $data             = shift;
    #debugandexit(Dumper($data));

    my $outputdata;
    my $outputerror;
    # set the default errorcode to '1'
    $outputerror->{errorcode} = '1';
    
    #trim the serverdone message off
    foreach (@{$data}) {
        if (defined($_->{error})) {
            if (ref($_->{error}) eq 'ARRAY') {
                foreach my $msg (@{$_->{error}}) {
                    if ($msg =~ /(Permission denied|Authentication failure)/) {
                        # return 401 Unauthorized
                        sendResponseMsg($STATUS_UNAUTH);
                    } else {
                        push @{$outputerror->{error}}, $msg;
                    }
                }
            } else {
                push @{$outputerror->{error}}, $_->{error};
            }
            
            if (defined ($_->{errorcode})) {
                $outputerror->{errorcode} = $_->{errorcode}->[0];
            } 
        }

        # handle the output like 
        #<node>
        #  <name>node1</name>
        #  <error>Unable to identify plugin for this command, check relevant tables: nodehm.power,mgt;nodehm.mgt</error>
        #  <errorcode>1</errorcode>
        #</node>
        if (defined($_->{node}) && defined ($_->{node}->[0]->{error})) {
            if (defined ($_->{node}->[0]->{name})) {
                push @{$outputerror->{error}}, "$_->{node}->[0]->{name}->[0]: ".$_->{node}->[0]->{error}->[0];
            }
            if (defined ($_->{node}->[0]->{errorcode})) {
                $outputerror->{errorcode} = $_->{node}->[0]->{errorcode}->[0];
            } 
        }


        if (exists($_->{serverdone})) {
            if (defined ($outputerror->{error})) {
                 addPageContent($JSON->encode($outputerror));
                 #return the default http error code to be 403 forbidden
                 sendResponseMsg($STATUS_FORBIDDEN);
            } else {
                #otherwise, ignore the 'servicedone' data
                next;
            }
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

    debug("request xml=$request");
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
        if ($@) { 
            # remove the code location information to make the output looks better
            if ($@ =~ / at \//) {
                $@ =~ s/ at \/.*$//;
            }
            error("$@",$STATUS_BAD_REQUEST); 
        }
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
    my ($errmsg, $httpcode, $errorcode) = @_;
    my $json;
    $json->{error} = $errmsg;
    $json->{errorcode} = '2';
    if ($errorcode) {
        $json->{errorcode} = $errorcode;
    }
   
    addPageContent($JSON->encode($json));
    sendResponseMsg($httpcode);
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


