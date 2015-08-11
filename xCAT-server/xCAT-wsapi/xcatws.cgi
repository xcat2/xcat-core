#!/usr/bin/perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
use strict;
use CGI qw/:standard/;      #todo: remove :standard when the code only uses object oriented interface
use Data::Dumper;

#talk to the server
use Socket;
use IO::Socket::INET;
use IO::Socket::SSL;

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

# The common messages which can be used in the %URIdef
my %usagemsg = (
    objreturn => "Json format: An object which includes multiple \'<name> : {att:value, attr:value ...}\' pairs.",
    objchparam => "Json format: An object which includes multiple \'att:value\' pairs.",
    non_getreturn => "No output when execution is successfull. Otherwise output the error information in the Standard Error Format: {error:[msg1,msg2...],errocode:errornum}."
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
            desc => "[URI:/nodes/{noderange}] - The node resource",
            matcher => '^/nodes/[^/]*$',
            GET => {
                desc => "Get all the attibutes for the node {noderange}.",
                desc1 => "The keyword ALLRESOURCES can be used as {noderange} which means to get node attributes for all the nodes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the attibutes for node \'node1\'.|GET|/nodes/node1|{\n   \"node1\":{\n      \"profile\":\"compute\",\n      \"netboot\":\"xnba\",\n      \"arch\":\"x86_64\",\n      \"mgt\":\"ipmi\",\n      \"groups\":\"all\",\n      ...\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Change the attributes mgt=dfm and netboot=yaboot.|PUT|/nodes/node1 {\"mgt\":\"dfm\",\"netboot\":\"yaboot\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            POST => {
                desc => "Create the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Create a node with attributes groups=all, mgt=dfm and netboot=yaboot|POST|/nodes/node1 {\"groups\":\"all\",\"mgt\":\"dfm\",\"netboot\":\"yaboot\"}||",
                cmd => "mkdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the node {noderange}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the node node1|DELETE|/nodes/node1||",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
        },
        nodeattr => {
            desc => "[URI:/nodes/{noderange}/attrs/{attr1,attr2,attr3 ...}] - The attributes resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/attrs/\S+$',
            GET => {
                desc => "Get the specific attributes for the node {noderange}.",
                desc1 => "The keyword ALLRESOURCES can be used as {noderange} which means to get node attributes for all the nodes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the attributes {groups,mgt,netboot} for node node1|GET|/nodes/node1/attrs/groups,mgt,netboot|{\n   \"node1\":{\n      \"netboot\":\"xnba\",\n      \"mgt\":\"ipmi\",\n      \"groups\":\"all\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT_backup => {
                desc => "Change attributes for the node {noderange}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                usage => "||An array of node objects.|",
                example => "|Get the attributes {groups,mgt,netboot} for node node1|GET|/nodes/node1/attrs/groups;mgt;netboot||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            }
        },
        nodestat => {
            desc => "[URI:/nodes/{noderange}/nodestat}] - The attributes resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/nodestat$',
            GET => {
                desc => "Get the running status for the node {noderange}.",
                usage => "||An object which includes multiple entries like: <nodename> : { nodestat : <node state> }|",
                example => "|Get the running status for node node1|GET|/nodes/node1/nodestat|{\n   \"node1\":{\n      \"nodestat\":\"noping\"\n   }\n}|",
                cmd => "nodestat",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        nodehost => {
            desc => "[URI:/nodes/{noderange}/host] - The mapping of ip and hostname for the node {noderange}",
            matcher => '^/nodes/[^/]*/host$',
            POST => {
                desc => "Create the mapping of ip and hostname record for the node {noderange}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the mapping of ip and hostname record for node \'node1\'.|POST|/nodes/node1/host||",
                cmd => "makehosts",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        noderename => {
            desc => "[URI:/nodes/{noderange}/rename] - Change old_nodename into new_nodename",
            matcher => '^/nodes/[^/]*/rename$',
            PUT => {
                desc => "Change node name.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Change nodename for node \'node1\'.|PUT|/nodes/node1/rename||",
                cmd => "chdef",
                fhandler => \&actionhdl,
                outhdler => \&defout_remove_appended_info,
            },
        },
        nodedns => {
            desc => "[URI:/nodes/{noderange}/dns] - The dns record resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/dns$',
            POST => {
                desc => "Create the dns record for the node {noderange}.",
                desc1 => "The prerequisite of the POST operation is the mapping of ip and noderange for the node has been added in the /etc/hosts.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the dns record for node \'node1\'.|POST|/nodes/node1/dns||",
                cmd => "makedns",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the dns record for the node {noderange}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the dns record for node node1|DELETE|/nodes/node1/dns||",
                cmd => "makedns",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        nodedhcp => {
            desc => "[URI:/nodes/{noderange}/dhcp] - The dhcp record resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/dhcp$',
            POST => {
                desc => "Create the dhcp record for the node {noderange}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the dhcp record for node \'node1\'.|POST|/nodes/node1/dhcp||",
                cmd => "makedhcp",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the dhcp record for the node {noderange}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the dhcp record for node node1|DELETE|/nodes/node1/dhcp||",
                cmd => "makedhcp",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        power => {
            desc => "[URI:/nodes/{noderange}/power] - The power resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/power$',
            GET => {
                desc => "Get the power status for the node {noderange}.",
                usage => "||An object which includes multiple entries like: <nodename> : { power : <powerstate> }|",
                example => "|Get the power status.|GET|/nodes/node1/power|{\n   \"node1\":{\n      \"power\":\"on\"\n   }\n}|",
                cmd => "rpower",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change power status for the node {noderange}.",
                usage => "|Json Formatted DataBody: {action:on/off/reset ...}.|$usagemsg{non_getreturn}|",
                example => "|Change the power status to on|PUT|/nodes/node1/power {\"action\":\"on\"}||",
                cmd => "rpower",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        energy => {
            desc => "[URI:/nodes/{noderange}/energy] - The energy resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/energy$',
            GET => {
                desc => "Get all the energy status for the node {noderange}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the energy attributes.|GET|/nodes/node1/energy|{\n   \"node1\":{\n      \"cappingmin\":\"272.3 W\",\n      \"cappingmax\":\"354.0 W\"\n      ...\n   }\n}|",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change energy attributes for the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: {powerattr:value}.|$usagemsg{non_getreturn}|",
                example => "|Turn on the cappingstatus to [on]|PUT|/nodes/node1/energy {\"cappingstatus\":\"on\"}||",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        energyattr => {
            disable => 1,
            desc => "[URI:/nodes/{noderange}/energy/{cappingmaxmin,cappingstatus,cappingvalue ...}] - The specific energy attributes resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/energy/\S+$',
            GET => {
                desc => "Get the specific energy attributes cappingmaxmin,cappingstatus,cappingvalue ... for the node {noderange}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the energy attributes which are specified in the URI.|GET|/nodes/node1/energy/cappingmaxmin,cappingstatus|{\n   \"node1\":{\n      \"cappingmin\":\"272.3 W\",\n      \"cappingmax\":\"354.0 W\"\n   }\n}|",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT_backup => {
                desc => "Change energy attributes for the node {noderange}. ",
                usage => "|$usagemsg{objchparam} DataBody: {powerattr:value}.|$usagemsg{non_getreturn}|",
                example => "|Turn on the cappingstatus to [on]|PUT|/nodes/node1/energy {\"cappingstatus\":\"on\"}||",
                cmd => "renergy",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            }
        },
        serviceprocessor => {
            disable => 1,
            desc => "[URI:/nodes/{noderange}/sp/{community|ip|netmask|...}] - The attribute resource of service processor for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/mac] - The mac address resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/mac$',
            GET => {
                desc => "Get the mac address for the node {noderange}. Generally, it also updates the mac attribute of the node.",
                cmd => "getmacs",
                fhandler => \&common,
            },
        },
        nextboot => {
            desc => "[URI:/nodes/{noderange}/nextboot] - The temporary bootorder resource in next boot for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/bootorder] - The permanent bootorder resource for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/vitals] - The vitals resources for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/vitals/{temp|voltage|wattage|fanspeed|power|leds...}] - The specific vital attributes for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/inventory] - The inventory attributes for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/inventory/{pci|model...}] - The specific inventory attributes for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/eventlog] - The eventlog resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/eventlog$',
            GET => {
                desc => "Get all the eventlog for the node {noderange}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the eventlog for node1.|GET|/nodes/node1/eventlog|{\n   \"node1\":{\n      \"eventlog\":[\n         \"03/19/2014 15:17:58 Event Logging Disabled, Log Area Reset/Cleared (SEL Fullness)\"\n      ]\n   }\n}|",
                cmd => "reventlog",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            DELETE => {
                desc => "Clean up the event log for the node {noderange}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete all the event log for node1.|DELETE|/nodes/node1/eventlog|[\n   {\n      \"eventlog\":[\n         \"SEL cleared\"\n      ],\n      \"name\":\"node1\"\n   }\n]|",
                cmd => "reventlog",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        beacon => {
            desc => "[URI:/nodes/{noderange}/beacon] - The beacon resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/beacon$',
            GET_backup => {
                desc => "Get the beacon status for the node {noderange}.",
                cmd => "rbeacon",
                fhandler => \&common,
            },
            PUT => {
                desc => "Change the beacon status for the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: {action:on/off/blink}.|$usagemsg{non_getreturn}|",
                example => "|Turn on the beacon.|PUT|/nodes/node1/beacon {\"action\":\"on\"}|[\n   {\n      \"name\":\"node1\",\n      \"beacon\":\"on\"\n   }\n]|",
                cmd => "rbeacon",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        vm => {
            desc => "[URI:/nodes/{noderange}/vm] - The virtualization node {noderange}.",
            desc1 => "The node should be a virtual machine of type kvm, esxi ...",
            matcher => '^/nodes/[^/]*/vm$',
            GET_backup => {
                desc => "Get the vm status for the node {noderange}.",
                cmd => "lsvm",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
            PUT => {
                desc => "Change the configuration for the virtual machine {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: \n    Set memory size - {\"memorysize\":\"sizeofmemory(MB)\"}\n    Add new disk - {\"adddisk\":\"sizeofdisk1(GB),sizeofdisk2(GB)\"}\n    Purge disk - {\"purgedisk\":\"scsi_id1,scsi_id2\"}|$usagemsg{non_getreturn}|",
                example => "|Set memory to 3000MB.|PUT|/nodes/node1/vm {\"memorysize\":\"3000\"}||",
                example1 => "|Add a new 20G disk.|PUT|/nodes/node1/vm {\"adddisk\":\"20G\"}||",
                example2 => "|Purge the disk \'hdb\'.|PUT|/nodes/node1/vm {\"purgedisk\":\"hdb\"}||",
                cmd => "chvm",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
            POST => {
                desc => "Create the vm node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: \n    Set CPU count - {\"cpucount\":\"numberofcpu\"}\n    Set memory size - {\"memorysize\":\"sizeofmemory(MB)\"}\n    Set disk size - {\"disksize\":\"sizeofdisk\"}\n    Do it by force - {\"force\":\"yes\"}|$usagemsg{non_getreturn}|",
                example => "|Create the vm node1 with a 30G disk, 2048M memory and 2 cpus.|POST|/nodes/node1/vm {\"disksize\":\"30G\",\"memorysize\":\"2048\",\"cpucount\":\"2\"}||",
                cmd => "mkvm",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the vm node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: \n    Purge disk - {\"purge\":\"yes\"}\n    Do it by force - {\"force\":\"yes\"}|$usagemsg{non_getreturn}|",
                example => "|Remove the vm node1 by force and purge the disk.|DELETE|/nodes/node1/vm {\"force\":\"yes\",\"purge\":\"yes\"}||",
                cmd => "rmvm",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        vmclone => {
            desc => "[URI:/nodes/{noderange}/vmclone] - The clone resource for the virtual node {noderange}.",
            desc1 => "The node should be a virtual machine of kvm, esxi ...",
            matcher => '^/nodes/[^/]*/vmclone$',
            POST => {
                desc => "Create a clone master from node {noderange}. Or clone the node {noderange} from a clone master.",
                usage => "|$usagemsg{objchparam} DataBody: \n    Clone a master named \"mastername\" - {\"tomaster\":\"mastername\"}\n    Clone a node from master \"mastername\" - {\"frommaster\":\"mastername\"}\n    Use Detach mode - {\"detach\":\"yes\"}\n    Do it by force - {\"force\":\"yes\"}|The messages of creating Clone target.|",
                example1 => "|Create a clone master named \"vmmaster\" from the node1.|POST|/nodes/node1/vmclone {\"tomaster\":\"vmmaster\",\"detach\":\"yes\"}|{\n   \"node1\":{\n      \"vmclone\":\"Cloning of node1.hda.qcow2 complete (clone uses 9633.19921875 for a disk size of 30720MB)\"\n   }\n}|",
                example2 => "|Clone the node1 from the clone master named \"vmmaster\".|POST|/nodes/node1/vmclone {\"frommaster\":\"vmmaster\"}||",
                cmd => "clonevm",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        vmmigrate => {
            desc => "[URI:/nodes/{noderange}/vmmigrate] - The virtualization resource for migration.",
            desc1 => "The node should be a virtual machine of kvm, esxi ...",
            matcher => '^/nodes/[^/]*/vmmigrate$',
            POST => {
                desc => "Migrate a node to targe node.",
                usage => "|$usagemsg{objchparam} DataBody: {\"target\":\"targethost\"}.",
                example => "|Migrate node1 to target host host2.|POST|/nodes/node1/vmmigrate {\"target\":\"host2\"}||",
                cmd => "rmigrate",
                fhandler => \&actionhdl,
                outhdler => \&actionout,
            },
        },
        updating => {
            desc => "[URI:/nodes/{noderange}/updating] - The updating resource for the node {noderange}",
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
            desc => "[URI:/nodes/{noderange}/filesyncing] - The filesyncing resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/filesyncing$',
            POST => {
                desc => "Sync files for the node {noderange}.",
                usage => "||An array of messages for performing the file syncing for the node.|",
                example => "|Initiate an file syncing process.|POST|/nodes/node2/filesyncing|[\n   \"There were no syncfiles defined to process. File synchronization has completed.\"\n]|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        software_maintenance => {
            desc => "[URI:/nodes/{noderange}/sw] - The software maintenance for the node {noderange}",
            matcher => '^/nodes/[^/]*/sw$',
            POST => {
                desc => "Perform the software maintenance process for the node {noderange}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Initiate an software maintenance process.|POST|/nodes/node2/sw|{\n   \"node2\":[\n      \" Wed Apr  3 09:05:42 CST 2013 Running postscript: ospkgs\",\n      \" Unable to read consumer identity\",\n      \" Postscript: ospkgs exited with code 0\",\n      \" Wed Apr  3 09:05:44 CST 2013 Running postscript: otherpkgs\",\n      \" ./otherpkgs: no extra rpms to install\",\n      \" Postscript: otherpkgs exited with code 0\",\n      \" Running of Software Maintenance has completed.\"\n   ]\n}|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        postscript => {
            desc => "[URI:/nodes/{noderange}/postscript] - The postscript resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/postscript$',
            POST => {
                desc => "Run the postscripts for the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: {scripts:[p1,p2,p3,...]}.|$usagemsg{objreturn}|",
                example => "|Initiate an updatenode process.|POST|/nodes/node2/postscript {\"scripts\":[\"syslog\",\"remoteshell\"]}|{\n   \"node2\":[\n      \" Wed Apr  3 09:01:33 CST 2013 Running postscript: syslog\",\n      \" Shutting down system logger: [  OK  ]\",\n      \" Starting system logger: [  OK  ]\",\n      \" Postscript: syslog exited with code 0\",\n      \" Wed Apr  3 09:01:33 CST 2013 Running postscript: remoteshell\",\n      \" Stopping sshd: [  OK  ]\",\n      \" Starting sshd: [  OK  ]\",\n      \" Postscript: remoteshell exited with code 0\",\n      \" Running of postscripts has completed.\"\n   ]\n}|",
                cmd => "updatenode",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        nodeshell => {
            desc => "[URI:/nodes/{noderange}/nodeshell] - The nodeshell resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/nodeshell$',
            POST => {
                desc => "Run the command in the shell of the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: set environment {ENV:{en1:v1,en2:v2}}, raw command {raw:[op1,op2]}, direct command {command:[cmd1,cmd2]}.|$usagemsg{objreturn}|",
                example => "|Run the \'date\' command on the node2.|POST|/nodes/node2/nodeshell {\"command\":[\"date\",\"ls\"]}|{\n   \"node2\":[\n      \" Wed Apr  3 08:30:26 CST 2013\",\n      \" testline1\",\n      \" testline2\"\n   ]\n}|Use ENV and raw command on the node2.|POST|/nodes/node2/nodeshell {\"ENV\":{\"DSH_REMOTE_PASSWORD\":\"cluster\",\"DSH_FROM_USERID\":\"root\",\"DSH_TO_USERID\":\"root\"},\"raw\":[\"-K\"]}|[\n  \"/usr/bin/ssh setup is complete.\",\n  \"return code = 0\"\n]|",
                cmd => "xdsh",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        nodecopy => {
            desc => "[URI:/nodes/{noderange}/nodecopy] - The nodecopy resource for the node {noderange}",
            matcher => '^/nodes/[^/]*/nodecopy$',
            POST => {
                desc => "Copy files to the node {noderange}.",
                usage => "|$usagemsg{objchparam} DataBody: {src:[file1,file2],target:dir}.|$usagemsg{non_getreturn}|",
                example => "|Copy files /tmp/f1 and /tmp/f2 from xCAT MN to the node2:/tmp.|POST|/nodes/node2/nodecopy {\"src\":[\"/tmp/f1\",\"/tmp/f2\"],\"target\":\"/tmp\"}|no output for succeeded copy.|",
                cmd => "xdcp",
                fhandler => \&actionhdl,
                outhdler => \&infoout,
            },
        },
        subnodes => {
            desc => "[URI:/nodes/{noderange}/subnodes] - The sub-nodes resources for the node {noderange}",
            matcher => '^/nodes/[^/]*/subnodes$',
            GET => {
                desc => "Return the Children nodes for the node {noderange}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the children nodes for node \'node1\'.|GET|/nodes/node1/subnodes|{\n   \"cmm01node09\":{\n      \"mpa\":\"ngpcmm01\",\n      \"parent\":\"ngpcmm01\",\n      \"serial\":\"1035CDB\",\n      \"mtm\":\"789523X\",\n      \"cons\":\"fsp\",\n      \"hwtype\":\"blade\",\n      \"objtype\":\"node\",\n      \"groups\":\"blade,all,p260\",\n      \"mgt\":\"fsp\",\n      \"nodetype\":\"ppc,osi\",\n      \"slotid\":\"9\",\n      \"hcp\":\"10.1.9.9\",\n      \"id\":\"1\"\n   },\n   ...\n}|",
                cmd => "rscan",
                fhandler => \&actionhdl,
                outhdler => \&defout,
            },
            # the put should be implemented by customer that using GET to get all the resources and define it with PUT /nodes/<node name>
            PUT_bak => {
                desc => "Update the Children node for the node {noderange}.",
                cmd => "rscan",
                fhandler => \&common,
            },
        },
        bootstate => {
            desc => "[URI:/nodes/{noderange}/bootstate] - The boot state resource for node {noderange}.",
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
            desc => "[URI:/groups/{groupname}/attrs/{attr1,attr2,attr3 ...}] - The attributes resource for the group {groupname}",
            matcher => '^/groups/[^/]*/attrs/\S+$',
            GET => {
                desc => "Get the specific attributes for the group {groupname}.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the attributes {mgt,netboot} for group all|GET|/groups/all/attrs/mgt,netboot|{\n   \"all\":{\n      \"netboot\":\"yaboot\",\n      \"mgt\":\"dfm\"\n   }\n}|",
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
        bmcdiscover => {
            desc => "[URI:/services/bmcdiscover] - The bmc which does support nmap in the xCAT cluster.",
            matcher => '^/services/bmcdiscover/[^/]+$',
            GET => {
                desc => "Get all the bmc alive.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the bmc which do not support slp in the network.|",
                cmd => "bmcdiscover",
                fhandler => \&bmclisthdl,
                outhdler => \&defout_remove_appended_info,

            }
        },
        checkbmcauth => {
            desc => "[URI:/services/checkbmcauth] - Check if bmc user or password is correct.",
            matcher => '^/services/checkbmcauth/[^/]*/[^/]+$',
            GET => {
                desc => "Check if bmc user or password is correct.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Check bmc user or password.|GET|/services/checkbmcauth||",
                cmd => "bmcdiscover",
                fhandler => \&bmccheckhdl,
                outhdler => \&defout_remove_appended_info,

            }
        },
        getbmcipsource => {
            desc => "[URI:/services/getbmcipsource] - Get BMC IP Address source.",
            matcher => '^/services/getbmcipsource/[^/]*/[^/]+$',
            GET => {
                desc => "Get BMC IP Address source.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get BMC IP Address source.|GET|/services/getbmcipsource||",
                cmd => "bmcdiscover",
                fhandler => \&bmccheckhdl,
                outhdler => \&defout_remove_appended_info,

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
        # todo: for slpnode, we need use the query attribute to specify the network parameter for lsslp command
        slpnodes => {
            desc => "[URI:/services/slpnodes] - The nodes which support SLP in the xCAT cluster",
            matcher => '^/services/slpnodes',
            GET => {
                desc => "Get all the nodes which support slp protocol in the network.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the nodes which support slp in the network.|GET|/services/slpnodes|{\n   \"ngpcmm01\":{\n      \"mpa\":\"ngpcmm01\",\n      \"otherinterfaces\":\"10.1.9.101\",\n      \"serial\":\"100037A\",\n      \"mtm\":\"789392X\",\n      \"hwtype\":\"cmm\",\n      \"side\":\"2\",\n      \"objtype\":\"node\",\n      \"nodetype\":\"mp\",\n      \"groups\":\"cmm,all,cmm-zet\",\n      \"mgt\":\"blade\",\n      \"hidden\":\"0\",\n      \"mac\":\"5c:f3:fc:25:da:99\"\n   },\n   ...\n}|",
                cmd => "lsslp",
                fhandler => \&nonobjhdl,
                outhdler => \&defout,
            },
            PUT_bakcup => {
                desc => "Update the discovered nodes to database.",
                cmd => "lsslp",
                fhandler => \&common,
            },
        },
        specific_slpnodes => {
            desc => "[URI:/services/slpnodes/{CEC|FRAME|MM|IVM|RSA|HMC|CMM|IMM2|FSP...}] - The slp nodes with specific service type in the xCAT cluster",
            matcher => '^/services/slpnodes/[^/]*$',
            GET => {
                desc => "Get all the nodes with specific slp service type in the network.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the CMM nodes which support slp in the network.|GET|/services/slpnodes/CMM|{\n   \"ngpcmm01\":{\n      \"mpa\":\"ngpcmm01\",\n      \"otherinterfaces\":\"10.1.9.101\",\n      \"serial\":\"100037A\",\n      \"mtm\":\"789392X\",\n      \"hwtype\":\"cmm\",\n      \"side\":\"2\",\n      \"objtype\":\"node\",\n      \"nodetype\":\"mp\",\n      \"groups\":\"cmm,all,cmm-zet\",\n      \"mgt\":\"blade\",\n      \"hidden\":\"0\",\n      \"mac\":\"5c:f3:fc:25:da:99\"\n   },\n   \"Server--SNY014BG27A01K\":{\n      \"mpa\":\"Server--SNY014BG27A01K\",\n      \"otherinterfaces\":\"10.1.9.106\",\n      \"serial\":\"100CF0A\",\n      \"mtm\":\"789392X\",\n      \"hwtype\":\"cmm\",\n      \"side\":\"1\",\n      \"objtype\":\"node\",\n      \"nodetype\":\"mp\",\n      \"groups\":\"cmm,all,cmm-zet\",\n      \"mgt\":\"blade\",\n      \"hidden\":\"0\",\n      \"mac\":\"34:40:b5:df:0a:be\"\n   }\n}|",
                cmd => "lsslp",
                fhandler => \&nonobjhdl,
                outhdler => \&defout,
            },
            PUT_backup => {
                desc => "Update the discovered nodes to database.",
                cmd => "lsslp",
                fhandler => \&common,
            },
        },
        #### definition for mknb <ppc64|x86_64> [-c]
        nbimage => {
            desc => "[URI:/nbimage] - Create netboot root image for specified arch.",
            matcher => '^/services/nbimage/arch/[ppc64|x86_64]',
            POST => {
                desc => "creates a network boot root image",
                usage => "|$usagemsg{objchparam} DataBody: {\"onlyconfigfile\":\"[true|yes|Y|1]|[false|no|N|0]\"}.|$usagemsg{non_getreturn}|",
                example => "|Create a network boot root iamge for the specified arch|",
                cmd => "mknb",
                fhandler => \&actionhdl,
            },
        },
    },
    
    #### definition for network resources
    networks => {
        allnetwork => {
            desc => "[URI:/networks] - The network list resource.",
            desc1 => "This resource can be used to display all the networks which have been defined in the xCAT database.",
            matcher => '^\/networks$',
            GET => {
                desc => "Get all the networks in xCAT.",
                desc1 => "The attributes details for the networks will not be displayed.",
                usage => "||Json format: An array of networks names.|",
                example => "|Get all the networks names from xCAT database.|GET|/networks|[\n   \"network1\",\n   \"network2\",\n   \"network3\",\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
            POST => {
                desc => "Create the networks resources base on the network configuration on xCAT MN.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Create the networks resources base on the network configuration on xCAT MN.|POST|/networks||",
                cmd => "makenetworks",
                fhandler => \&actionhdl,
                outhdler => \&noout,
            },
        },
        network_allattr => {
            desc => "[URI:/networks/{netname}] - The network resource",
            matcher => '^\/networks\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for the network {netname}.",
                desc1 => "The keyword ALLRESOURCES can be used as {netname} which means to get network attributes for all the networks.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the attibutes for network \'network1\'.|GET|/networks/network1|{\n   \"network1\":{\n      \"gateway\":\"<xcatmaster>\",\n      \"mask\":\"255.255.255.0\",\n      \"mgtifname\":\"eth2\",\n      \"net\":\"10.0.0.0\",\n      \"tftpserver\":\"10.0.0.119\",\n      ...\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the network {netname}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Change the attributes mgtifname=eth0 and net=10.1.0.0.|PUT|/networks/network1 {\"mgtifname\":\"eth0\",\"net\":\"10.1.0.0\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            POST => {
                desc => "Create the network {netname}. DataBody: {attr1:v1,att2:v2...}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Create a network with attributes gateway=10.1.0.1, mask=255.255.0.0 |POST|/networks/network1 {\"gateway\":\"10.1.0.1\",\"mask\":\"255.255.0.0\"}||",
                cmd => "mkdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the network {netname}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the network network1|DELETE|/networks/network1||",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&noout
            },
        },
        network_attr => {
            desc => "[URI:/networks/{netname}/attrs/attr1,attr2,...] - The attributes resource for the network {netname}",
            matcher => '^\/networks\/[^\/]*/attrs/\S+$',
            GET => {
                desc => "Get the specific attributes for the network {netname}.",
                desc1 => "The keyword ALLRESOURCES can be used as {netname} which means to get network attributes for all the networks.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the attributes {groups,mgt,netboot} for network network1|GET|/networks/network1/attrs/gateway,mask,mgtifname,net,tftpserver|{\n   \"network1\":{\n      \"gateway\":\"9.114.34.254\",\n      \"mask\":\"255.255.255.0\",\n         }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT__backup => {
                desc => "Change attributes for the network {netname}. DataBody: {attr1:v1,att2:v2,att3:v3 ...}.",
                usage => "||An array of network objects.|",
                example => "|Get the attributes {gateway,mask,mgtifname,net,tftpserver} for networks network1|GET|/networks/network1/attrs/gateway;mask;net||",
                cmd => "chdef",
                fhandler => \&noout,
            }
        },

    },

    #### definition for osimage resources
    osimages => {
        osimage => {
            desc => "[URI:/osimages] - The osimage resource.",
            matcher => '^\/osimages$',
            GET => {
                desc => "Get all the osimage in xCAT.",               
                usage => "||Json format: An array of osimage names.|",
                example => "|Get all the osimage names.|GET|/osimages|[\n   \"sles11.2-x86_64-install-compute\",\n   \"sles11.2-x86_64-install-iscsi\",\n   \"sles11.2-x86_64-install-iscsiibft\",\n   \"sles11.2-x86_64-install-service\"\n]|",

                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
            POST => {
                desc => "Create the osimage resources base on the parameters specified in the Data body.",
                #usage => "|$usagemsg{objchparam} DataBody: {iso:isoname\\file:filename\\node:noderange,params:[{attr1:value1,attr2:value2}]}|$usagemsg{non_getreturn}|",
                usage => "|$usagemsg{objchparam} DataBody: {iso:isoname\\file:filename,params:[{attr1:value1,attr2:value2}]}|$usagemsg{non_getreturn}|",
                example1 => "|Create osimage resources based on the ISO specified|POST|/osimages {\"iso\":\"/iso/RHEL6.4-20130130.0-Server-ppc64-DVD1.iso\"}||",
                example2 => "|Create osimage resources based on an xCAT image or configuration file|POST|/osimages {\"file\":\"/tmp/sles11.2-x86_64-install-compute.tgz\"}||",
                # TD: the imgcapture need to be moved to nodes/.*/osimages
                # example3 => "|Create a image based on the specified Linux diskful node|POST|/osimages {\"node\":\"rhcn1\"}||",
                cmd => "copycds",
                fhandler => \&imgophdl,
                outhdler => \&noout,
            },
        },
        osimage_allattr => {
            desc => "[URI:/osimages/{imgname}] - The osimage resource",
            matcher => '^\/osimages\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for the osimage {imgname}.",
                desc1 => "The keyword ALLRESOURCES can be used as {imgname} which means to get image attributes for all the osimages.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the attributes for the specified osimage.|GET|/osimages/sles11.2-x86_64-install-compute|{\n   \"sles11.2-x86_64-install-compute\":{\n      \"provmethod\":\"install\",\n      \"profile\":\"compute\",\n      \"template\":\"/opt/xcat/share/xcat/install/sles/compute.sles11.tmpl\",\n      \"pkglist\":\"/opt/xcat/share/xcat/install/sles/compute.sles11.pkglist\",\n      \"osvers\":\"sles11.2\",\n      \"osarch\":\"x86_64\",\n      \"osname\":\"Linux\",\n      \"imagetype\":\"linux\",\n      \"otherpkgdir\":\"/install/post/otherpkgs/sles11.2/x86_64\",\n      \"osdistroname\":\"sles11.2-x86_64\",\n      \"pkgdir\":\"/install/sles11.2/x86_64\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },

            POST => {
                desc => "Create the osimage {imgname}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,attr2:v2]|$usagemsg{non_getreturn}|",
                example => "|Create a osimage obj with the specified parameters.|POST|/osimages/sles11.3-ppc64-install-compute {\"osvers\":\"sles11.3\",\"osarch\":\"ppc64\",\"osname\":\"Linux\",\"provmethod\":\"install\",\"profile\":\"compute\"}||",
                cmd => "mkdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            PUT => {
                desc => "Change the attibutes for the osimage {imgname}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,attr2:v2...}|$usagemsg{non_getreturn}|",
                example => "|Change the 'osvers' and 'osarch' attributes for the osiamge.|PUT|/osimages/sles11.2-ppc64-install-compute/ {\"osvers\":\"sles11.3\",\"osarch\":\"x86_64\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the osimage {imgname}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the specified osimage.|DELETE|/osimages/sles11.3-ppc64-install-compute||",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
        },
        osimage_attr => {
            desc => "[URI:/osimages/{imgname}/attrs/attr1,attr2,attr3 ...] - The attributes resource for the osimage {imgname}",
            matcher => '^\/osimages\/[^\/]*/attrs/\S+$',
            GET => {
                desc => "Get the specific attributes for the osimage {imgname}.",
                desc1 => "The keyword ALLRESOURCES can be used as {imgname} which means to get image attributes for all the osimages.",
                usage => "||Json format: An array of attr:value pairs for the specified osimage.|",
                example => "|Get the specified attributes.|GET|/osimages/sles11.2-ppc64-install-compute/attrs/imagetype,osarch,osname,provmethod|{\n   \"sles11.2-ppc64-install-compute\":{\n      \"provmethod\":\"install\",\n      \"osname\":\"Linux\",\n      \"osarch\":\"ppc64\",\n      \"imagetype\":\"linux\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            # TD, the implementation may need to be change.
            PUT_backup => {
                desc => "Change the attibutes for the osimage {imgname}.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,attr2:v2...}|$usagemsg{non_getreturn}|",
                example => "|Change the 'osvers' and 'osarch' attributes for the osiamge.|PUT|/osimages/sles11.2-ppc64-install-compute/attrs/osvers;osarch {\"osvers\":\"sles11.3\",\"osarch\":\"x86_64\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },

        },
        osimage_op => {
            desc => "[URI:/osimages/{imgname}/instance] - The instance for the osimage {imgname}",
            matcher => '^\/osimages\/[^\/]*/instance$',
            POST => {
                desc => "Operate the instance of the osimage {imgname}.",
                usage => "|$usagemsg{objchparam} DataBody: {action:gen\\pack\\export,params:[{attr1:value1,attr2:value2...}]}|$usagemsg{non_getreturn}|",
                example1 => "|Generates a stateless image based on the specified osimage|POST|/osimages/sles11.2-x86_64-install-compute/instance {\"action\":\"gen\"}||",
                example2 => "|Packs the stateless image from the chroot file system based on the specified osimage|POST|/osimages/sles11.2-x86_64-install-compute/instance {\"action\":\"pack\"}||",
                example3 => "|Exports an xCAT image based on the specified osimage|POST|/osimages/sles11.2-x86_64-install-compute/instance {\"action\":\"export\"}||",
                cmd => "",
                fhandler => \&imgophdl,
            },
            DELETE => {
                desc => "Delete the stateless or statelite image instance for the osimage {imgname} from the file system",
                usage => "||$usagemsg{non_getreturn}",
                example => "|Delete the stateless image for the specified osimage|DELETE|/osimages/sles11.2-x86_64-install-compute/instance||",
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
                desc1 => "It will dislplay all the policy resource.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the policy objects.|GET|/policy|[\n   \"1\",\n   \"1.2\",\n   \"2\",\n   \"4.8\"\n]|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout_remove_appended_type,
            },
        },
        policy_allattr => {
            desc => "[URI:/policy/{policy_priority}] - The policy resource",
            matcher => '^\/policy\/[^\/]*$',
            GET => {
                desc => "Get all the attibutes for a policy {policy_priority}.",
                desc1 => "It will display all the policy attributes for one policy resource.",
                desc2 => "The keyword ALLRESOURCES can be used as {policy_priority} which means to get policy attributes for all the policies.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the attribute for policy 1.|GET|/policy/1|{\n   \"1\":{\n      \"name\":\"root\",\n      \"rule\":\"allow\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the attibutes for the policy {policy_priority}.",
                desc1 => "It will change one or more attributes for a policy.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Set the name attribute for policy 3.|PUT|/policy/3 {\"name\":\"root\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            POST => {
                desc => "Create the policy {policyname}. DataBody: {attr1:v1,att2:v2...}.",
                desc1 => "It will creat a new policy resource.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Create a new policy 10.|POST|/policy/10 {\"name\":\"root\",\"commands\":\"rpower\"}||",
                cmd => "chdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the policy {policy_priority}.",
                desc1 => "Remove one or more policy resource.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Delete the policy 10.|DELETE|/policy/10||",
                cmd => "rmdef",
                fhandler => \&defhdl,
                outhdler => \&noout,
            },
        },
        policy_attr => {
            desc => "[URI:/policy/{policyname}/attrs/{attr1,attr2,attr3,...}] - The attributes resource for the policy {policy_priority}",
            matcher => '^\/policy\/[^\/]*/attrs/\S+$',
            GET => {
                desc => "Get the specific attributes for the policy {policy_priority}.",
                desc1 => "It will get one or more attributes of a policy.",
                desc2 => "The keyword ALLRESOURCES can be used as {policy_priority} which means to get policy attributes for all the policies.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the name and rule attributes for policy 1.|GET|/policy/1/attrs/name,rule|{\n   \"1\":{\n      \"name\":\"root\",\n      \"rule\":\"allow\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&defhdl,
                outhdler => \&defout,
            },
        },
    },
    #### definition for global setting resources
    globalconf => {
        all_site => {
            desc => "[URI:/globalconf] - The global configuration resource.",
            desc1 => "This resource can be used to display all the global configuration which have been defined in the xCAT database.",
            matcher => '^\/globalconf$',
            GET => {
                desc => "Get all the xCAT global configuration.",
                desc1=> "It will display all the global attributes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get all the global configuration|GET|/globalconf|{\n   \"clustersite\":{\n      \"xcatconfdir\":\"/etc/xcat\",\n      \"tftpdir\":\"/tftpboot\",\n      ...\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&sitehdl,
                outhdler => \&defout,
            },
            POST_backup => {
                desc => "Add the site attributes. DataBody: {attr1:v1,att2:v2...}.",
                desc1 => "One or more global attributes could be added/modified.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Add one or more attributes to xCAT database|POST|/globalconf {\"domain\":\"cluster.com\",\"mydomain\":\"mycluster.com\"}||",
                cmd => "chdef",
                fhandler => \&sitehdl,
            },
        },
        site => {
            desc => "[URI:/globalconf/attrs/{attr1,attr2 ...}] - The specific global configuration resource.",
            matcher => '^\/globalconf/attrs/\S+$',
            GET => {
                desc => "Get the specific configuration in global.",
                desc1 => "It will display one or more global attributes.",
                usage => "||$usagemsg{objreturn}|",
                example => "|Get the \'master\' and \'domain\' configuration.|GET|/globalconf/attrs/master,domain|{\n   \"clustersite\":{\n      \"domain\":\"cluster.com\",\n      \"master\":\"192.168.1.15\"\n   }\n}|",
                cmd => "lsdef",
                fhandler => \&sitehdl,
                outhdler => \&defout,
            },
            PUT => {
                desc => "Change the global attributes.",
                desc1 => "It can be used for changing/adding global attributes.",
                usage => "|$usagemsg{objchparam} DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => "|Change/Add the domain attribute.|PUT|/globalconf/attrs/domain {\"domain\":\"cluster.com\"}||",
                cmd => "chdef",
                fhandler => \&sitehdl,
                outhdler => \&noout,
            },
            POST_backup => {
                desc => "Create the global configuration entry. DataBody: {name:value}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Create the domain attribute|POST|/globalconf/attrs/domain {\"domain\":\"cluster.com\"}|?|",
                cmd => "chdef",
                fhandler => \&sitehdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Remove the site attributes.",
                desc1 => "Used for femove one or more global attributes.",
                usage => "||$usagemsg{non_getreturn}|",
                example => "|Remove the domain configure.|DELETE|/globalconf/attrs/domain||",
                cmd => "chdef",
                fhandler => \&sitehdl,
                outhdler => \&noout,
            },
        },
    },

    #### definition for database/table resources
    tables => {
        table_nodes => {
            desc => "[URI:/tables/{tablelist}/nodes/{noderange}] - The node table resource",
            desc1 => "For a large number of nodes, this API call can be faster than using the corresponding nodes resource.  The disadvantage is that you need to know the table names the attributes are stored in.",
            matcher => '^/tables/[^/]+/nodes/[^/]+$',
            GET => {
                desc => "Get attibutes of tables for a noderange.",
                usage => "||An object containing each table.  Within each table object is an array of node objects containing the attributes.|",
                example1  => qq(|Get all the columns from table nodetype for node1 and node2.|GET|/tables/nodetype/nodes/node1,node2|{\n   \"nodetype\":[\n      {\n         \"provmethod\":\"rhels6.4-x86_64-install-compute\",\n         \"profile\":\"compute\",\n         \"arch\":\"x86_64\",\n         \"name\":\"node1\",\n         \"os\":\"rhels6.4\"\n      },\n      {\n         \"provmethod\":\"rhels6.3-x86_64-install-compute\",\n         \"profile\":\"compute\",\n         \"arch\":\"x86_64\",\n         \"name\":\"node2\",\n         \"os\":\"rhels6.3\"\n      }\n   ]\n}|),
                example2 => qq(|Get all the columns from tables nodetype and noderes for node1 and node2.|GET|/tables/nodetype,noderes/nodes/node1,node2|{\n   \"noderes\":[\n      {\n         \"installnic\":\"mac\",\n         \"netboot\":\"xnba\",\n         \"name\":\"node1\",\n         \"nfsserver\":\"192.168.1.15\"\n      },\n      {\n         \"installnic\":\"mac\",\n         \"netboot\":\"pxe\",\n         \"name\":\"node2\",\n         \"proxydhcp\":\"no\"\n      }\n   ],\n   \"nodetype\":[\n      {\n         \"provmethod\":\"rhels6.4-x86_64-install-compute\",\n         \"profile\":\"compute\",\n         \"arch\":\"x86_64\",\n         \"name\":\"node1\",\n         \"os\":\"rhels6.4\"\n      },\n      {\n         \"provmethod\":\"rhels6.3-x86_64-install-compute\",\n         \"profile\":\"compute\",\n         \"arch\":\"x86_64\",\n         \"name\":\"node2\",\n         \"os\":\"rhels6.3\"\n      }\n   ]\n}|),
                fhandler => \&tablenodehdl,
                outhdler => \&tableout,
            },
            PUT => {
                desc => "Change the node table attibutes for {noderange}.",
                usage => "|A hash of table names and attribute objects.  DataBody: {table1:{attr1:v1,att2:v2,...}}.|$usagemsg{non_getreturn}|",
                example => '|Change the nodetype.arch and noderes.netboot attributes for nodes node1,node2.|PUT|/tables/nodetype,noderes/nodes/node1,node2 {"nodetype":{"arch":"x86_64"},"noderes":{"netboot":"xnba"}}||',
                fhandler => \&tablenodeputhdl,
                outhdler => \&noout,
            },
        },
        table_nodes_attrs => {
            desc => "[URI:/tables/{tablelist}/nodes/nodes/{noderange}/{attrlist}] - The node table attributes resource",
            desc1 => "For a large number of nodes, this API call can be faster than using the corresponding nodes resource.  The disadvantage is that you need to know the table names the attributes are stored in.",
            matcher => '^/tables/[^/]+/nodes/[^/]+/[^/]+$',
            GET => {
                desc => "Get table attibutes for a noderange.",
                usage => "||An object containing each table.  Within each table object is an array of node objects containing the attributes.|",
                example => qq(|Get OS and ARCH attributes from nodetype table for node1 and node2.|GET|/tables/nodetype/nodes/node1,node2/os,arch|{\n   \"nodetype\":[\n      {\n         \"arch\":\"x86_64\",\n         \"name\":\"node1\",\n         \"os\":\"rhels6.4\"\n      },\n      {\n         \"arch\":\"x86_64\",\n         \"name\":\"node2\",\n         \"os\":\"rhels6.3\"\n      }\n   ]\n}|),
                fhandler => \&tablenodehdl,
                outhdler => \&tableout,
            },
            PUT_backup => {
                desc => "[URI:/tables/nodes/{noderange}] - Change the node table attibutes for the {noderange}.",
                usage => "|A hash of table names and attribute objects.  DataBody: {table1:{attr1:v1,att2:v2,...}}.|$usagemsg{non_getreturn}|",
                example => '|Change the nodehm.mgmt and noderes.netboot attributes for nodes node1-node5.|PUT|/tables/nodes/node1-node5 {"nodehm":{"mgmt":"ipmi"},"noderes":{"netboot":"xnba"}}||',
                fhandler => \&tablenodeputhdl,
                outhdler => \&noout,
            },
        },
        table_all_rows => {
            desc => "[URI:/tables/{tablelist}/rows] - The non-node table resource",
            desc1 => "Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.",
            matcher => '^/tables/[^/]+/rows$',
            GET => {
                desc => "Get all rows from non-node tables.",
                usage => "||An object containing each table.  Within each table object is an array of row objects containing the attributes.|",
                example => qq(|Get all rows from networks table.|GET|/tables/networks/rows|{\n   \"networks\":[\n      {\n         \"netname\":\"192_168_13_0-255_255_255_0\",\n         \"gateway\":\"192.168.13.254\",\n         \"staticrangeincrement\":\"1\",\n         \"net\":\"192.168.13.0\",\n         \"mask\":\"255.255.255.0\"\n      },\n      {\n         \"netname\":\"192_168_12_0-255_255_255_0\",\n         \"gateway\":\"192.168.12.254\",\n         \"staticrangeincrement\":\"1\",\n         \"net\":\"192.168.12.0\",\n         \"mask\":\"255.255.255.0\"\n      },\n   ]\n}|),
                fhandler => \&tablerowhdl,
                outhdler => \&tableout,
            },
        },
        table_rows => {
            desc => "[URI:/tables/{tablelist}/rows/{keys}] - The non-node table rows resource",
            desc1 => "Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.",
            desc2 => "{keys} should be the name=value pairs which are used to search table. e.g. {keys} should be [net=192.168.1.0,mask=255.255.255.0] for networks table query since the net and mask are the keys of networks table.",
            matcher => '^/tables/[^/]+/rows/[^/]+$',
            GET => {
                desc => "Get attibutes for rows from non-node tables.",
                usage => "||An object containing each table.  Within each table object is an array of row objects containing the attributes.|",
                example => qq(|Get row which net=192.168.1.0,mask=255.255.255.0 from networks table.|GET|/tables/networks/rows/net=192.168.1.0,mask=255.255.255.0|{\n   \"networks\":[\n      {\n         \"mgtifname\":\"eth0\",\n         \"netname\":\"192_168_1_0-255_255_255_0\",\n         \"tftpserver\":\"192.168.1.15\",\n         \"gateway\":\"192.168.1.100\",\n         \"staticrangeincrement\":\"1\",\n         \"net\":\"192.168.1.0\",\n         \"mask\":\"255.255.255.0\"\n      }\n   ]\n}|),
                fhandler => \&tablerowhdl,
                outhdler => \&tableout,
            },
            PUT => {
                desc => "Change the non-node table attibutes for the row that matches the {keys}.",
                usage => "|A hash of attribute names and values.  DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
                example => '|Create a route row in the routes table.|PUT|/tables/routes/rows/routename=privnet {"net":"10.0.1.0","mask":"255.255.255.0","gateway":"10.0.1.254","ifname":"eth1"}||',
                fhandler => \&tablerowputhdl,
                outhdler => \&noout,
            },
            DELETE => {
                desc => "Delete rows from a non-node table that have the attribute values specified in {keys}.",
                usage => "||$usagemsg{non_getreturn}|",
                example => '|Delete a route row which routename=privnet in the routes table.|DELETE|/tables/routes/rows/routename=privnet||',
                fhandler => \&tablerowdelhdl,
                outhdler => \&noout,
            },
        },
        table_rows_attrs => {
            desc => "[URI:/tables/{tablelist}/rows/{keys}/{attrlist}] - The non-node table attributes resource",
            desc1 => "Use this for tables that don't have node name as the key of the table, for example: passwd, site, networks, polciy, etc.",
            matcher => '^/tables/[^/]+/rows/[^/]+/[^/]+$',
            GET => {
                desc => "Get specific attibutes for rows from non-node tables.",
                usage => "||An object containing each table.  Within each table object is an array of row objects containing the attributes.|",
                example => qq(|Get attributes mgtifname and tftpserver which net=192.168.1.0,mask=255.255.255.0 from networks table.|GET|/tables/networks/rows/net=192.168.1.0,mask=255.255.255.0/mgtifname,tftpserver|{\n   \"networks\":[\n      {\n         \"mgtifname\":\"eth0\",\n         \"tftpserver\":\"192.168.1.15\"\n      }\n   ]\n}|),
                fhandler => \&tablerowhdl,
                outhdler => \&tableout,
            },
        },
    },

    #### definition for tokens resources
    tokens => {
        tokens => {
            desc => "[URI:/tokens] - The authentication token resource.",
            matcher => '^\/tokens',
            POST => {
                desc => "Create a token.",
                usage => "||An array of all the global configuration list.|",
                example => "|Aquire a token for user \'root\'.|POST|/tokens {\"userName\":\"root\",\"userPW\":\"cluster\"}|{\n   \"token\":{\n      \"id\":\"a6e89b59-2b23-429a-b3fe-d16807dd19eb\",\n      \"expire\":\"2014-3-8 14:55:0\"\n   }\n}|",
                fhandler => \&nonobjhdl,
                outhdler => \&tokenout,
            },
            POST_backup => {
                desc => "Add the site attributes. DataBody: {attr1:v1,att2:v2...}.",
                usage => "|?|?|",
                example => "|?|?|?|?|",
                cmd => "chdef",
                fhandler => \&sitehdl,
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

# error status codes
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

# good status codes
my $STATUS_OK      = "200 OK";
my $STATUS_CREATED = "201 Created";

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

# To get the HTTP elements through perl CGI module
my $q           = CGI->new;
my $pathInfo    = $q->path_info;        # the resource specification, i.e. everything in the url after xcatws
my $requestType = $q->request_method();     # GET, PUT, POST, PATCH, DELETE
my $userAgent = $q->user_agent();        # the client program: curl, etc.
my @path = split(/\//, $pathInfo);    # The uri path like /nodes/node1/...

# Define the golbal variables which will be used through the handling process
my $pageContent = '';       # Global var containing the ouptut back to the rest client
my $request     = {clienttype => 'ws'};     # Global var that holds the request to send to xcatd
my $format = 'json';    # The output format for a request invoke
my $xmlinstalled;    # Global var to speicfy whether the xml modules have been loaded

# To easy the perl debug, this script can be run directly with 'perl -d'
# This script also support to generate the rest api doc automatically.
# Following part of code will not be run when this script is called by http server
my $dbgdata;
sub dbgusage { print "Usage:\n    $0 -h\n    $0 -g [wiki] (generate document)\n    $0 {GET|PUT|POST|DELETE} URI user:password \'{data}\'\n"; }

if ($ARGV[0] eq "-h") {
    dbgusage();    
    exit 0;
} elsif ($ARGV[0] eq "-g") {
    # generate the document
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
    # parse the parameters when run this script locally
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
# Since the json is the only supported format, load it at beginning
# need to do this early, so we can fetch the PUT/POST params
loadJSON();        

# the input parameters from both the url and put/post data will be combined and then
# separated into the general params (not specific to the api call) and params specific to the call
# Note: some of the values of the params in the hash can be arrays
# $generalparams - the general parameters like 'debug=1', 'pretty=1'
# $paramhash - all parameters that come from the url or put/post data except the ones that are put in $generalparams
my ($generalparams, $paramhash) = fetchParameters();

my $DEBUGGING = $generalparams->{debug};      # turn on or off the debugging output by setting debug=1 (or 2) in the url string
if ($DEBUGGING) {
    displaydebugmsg();
}

# The filter flag is used to group the nodes which have the same output 
my $XCOLL = $generalparams->{xcoll}; 

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
    # make the output to be readable if 'pretty=1' is specified
    if ($generalparams->{pretty}) { $JSON->indent(1); }
}

# we need XML all the time to send request to xcat, even if thats not the return format requested by the user
loadXML();

# The first layer of resource URI. It should be 'nodes' for URI '/nodes/node1'
my $uriLayer1;

# Get all the layers in the URI
my @layers = split('\/', $pathInfo);
shift (@layers);

if ($#layers < 0) {
    # If no resource was specified, list all the resource groups which have been defined in the %URIdef
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
$request->{becomeuser}->[0]->{username}->[0] = $ENV{userName} if (defined($ENV{userName}));
$request->{becomeuser}->[0]->{username}->[0] = $generalparams->{userName} if (defined($generalparams->{userName}));
$request->{becomeuser}->[0]->{password}->[0] = $ENV{password} if (defined($ENV{password}));
$request->{becomeuser}->[0]->{password}->[0] = $generalparams->{userPW} if (defined($generalparams->{userPW}));

# use the token if it is specified with X_AUTH_TOKEN head
$request->{tokens}->[0]->{tokenid}->[0] = $ENV{'HTTP_X_AUTH_TOKEN'} if (defined($ENV{'HTTP_X_AUTH_TOKEN'}));

# find and invoke the correct handler and output handler functions
my $outputdata;
my $handled;
if (defined ($URIdef{$uriLayer1})) {
    # Make sure the resource has been defined
    foreach my $res (keys %{$URIdef{$uriLayer1}}) {
        my $matcher = $URIdef{$uriLayer1}->{$res}->{matcher};
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
                 # Call the handler subroutine which specified in 'fhandler' to send request to xcatd and get the response
                 $outputdata = $URIdef{$uriLayer1}->{$res}->{$requestType}->{fhandler}->($params);
                 # Filter the output data from the response
                 $outputdata = filterData ($outputdata);
                 # Restructure the output data with the subroutine which is specified in 'outhdler' 
                 if (defined ($URIdef{$uriLayer1}->{$res}->{$requestType}->{outhdler})) {
                     $outputdata = $URIdef{$uriLayer1}->{$res}->{$requestType}->{outhdler}->($outputdata, $params);
                 } else {
                     # Call the appropriate formatting function stored in the formatters hash as default output handler
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
    # not matches to any resource group. Check the 'resource group' to improve the performance
    error("Unspported resource.",$STATUS_NOT_FOUND);
}

# the URI cannot match to any resources which are defined in %URIdef
unless ($handled) {
    error("Unspported resource.",$STATUS_NOT_FOUND);
}


# all output has been added into the global varibale pageContent, call the response funcion to generate HTTP reply and exit

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


#handle the output for def command and rscan 
#handle the input like  
# ===raw xml input
#  $d->{info}->[msg list] - each msg could be mulitple msg which split with '\n' 
#  $d->{data}->[msg list]
#
# ===msg format
# Object name: <objname>
#   attr=value
#OR
# <objname>:
#   attr=value
# ---
#TO
# ---
# {<objname> : {
#   attr : value
#   ...
# } ... }
sub defout {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        my $nodename;
        my $lines;
        my @alldata;
        if (defined ($d->{info})) {
            foreach (@{$d->{info}}) {
                push @alldata, split ('\n', $_);
            }
            $lines = \@alldata;
        } elsif (defined ($d->{data})) {
            foreach (@{$d->{data}}) {
                push @alldata, split ('\n', $_);
            }
            $lines = \@alldata;
        }
        foreach my $l (@$lines) {
            if ($l =~ /No responses/) { # handle the case that no output from lsslp command
                return;
            } elsif ($l =~ /Could not find any object definitions/) {
                $json->{info} = $l;
                last;
            }
            if ($l =~ /^Object name: / || $l =~ /^\S+:$/) {    # start new node
                if ($l =~ /^Object name:\s+(\S+)/) {    # handle the output of lsdef -t <type> <obj>
                    $nodename = $1;
                }
                if ($l =~ /^(\S+):$/) {    # handle the output for stanza format '-z'
                    $nodename = $1;
                }
            }
            else {      # just an attribute of the current node
                if (! $nodename) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                my ($attr, $val) = $l =~ /^\s*(\S+.*?)=(.*)$/;
                if (!defined($attr)) { error('improperly formatted lsdef output from xcatd', $STATUS_TEAPOT); }
                $json->{$nodename}->{$attr} = $val;
            }
        }
    }
    if ($json) {
        addPageContent($JSON->encode($json), 1);
    }
}

#handle the output for lsdef -t <type> command
#handle the input like  
# ===raw xml input
#  $d->{info}->[msg list] - each msg could be mulitple msg which split with '\n' 
#
# ===msg format
# node1  (node)
# node2  (node)
# node3  (node)
# ---
#TO
# ---
# node1
# node2
# node3
sub defout_remove_appended_type {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        my $jsonnode;
        my $lines = $d->{info};
        foreach my $l (@$lines) {
            if ($l =~ /^(\S*)\s+\(.*\)$/) {    # start new node
                push @{$json}, $1;
            } elsif ($l =~ /Could not find any object definitions/) {
                push @{$json}, $l;
                last;
            }
        }
    }
    if ($json) {
        addPageContent($JSON->encode($json), 1);
    }
}

#handle the output for bmcdiscover command
#handle the input like
#
#$VAR1 = [
#          {
#            'info' => [
#                      'bmc_1'
#                    ]
#          },
#          {
#            'info' => [
#                      'bmc_2'
#                    ]
#          },
#          {
#            'info' => [
#                      'bmc_3'
#                    ]
#          }
#        ];
#
# ===msg format
#  bmc_1
#  bmc_2
#  bmc_3
# ---
#
#TO
# ---
# [
#   "bmc_1",
#   "bmc_2",
#   "bmc_3"
# ]

#
sub defout_remove_appended_info {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        my $jsonnode;
        my $lines = $d->{info};
        foreach my $l (@$lines) {
          #  if ($l =~ /^(\S*)\s+\(.*\)$/) {    # start new node
                push (@{$json}, $l);
          #  }
        }
    }
    if ($json) {
        addPageContent($JSON->encode($json), 1);
    }
}



# hanlde the output which has the node irrelevant message (e.g. the output for updatenode command)
# handle the input like  
# ===raw xml input
#  $d->{info}->[msg list] - each msg could be mulitple msg which split with '\n' 
#  $d->{data}->[msg list]
#  $d->{data}->{contents}->[msg list]
#
# ===msg format
# "There were no syncfiles defined to process. File synchronization has completed.",
# "Performing software maintenance operations. This could take a while, if there are packages to install.",
# "node2: Tue Apr  2 15:55:57 CST 2013 Running postscript: ospkgs",
# ---
#TO
# ---
# [
#   "There were no syncfiles defined to process. File synchronization has completed.",
#   "Performing software maintenance operations. This could take a while, if there are packages to install.",
#   "node2: Tue Apr  2 15:55:57 CST 2013 Running postscript: ospkgs",
# ]
#
# An exception is to handle the output of 'xdsh'(nodeshell). Since each msg has a <node>: head, split the head out and group
# the msg with the name in the head.

sub infoout {
    my $data = shift;
    my $param =shift;

    my $json;
    foreach my $d (@$data) {
        if (defined ($d->{info})) {
            foreach (@{$d->{info}}) {
                push @{$json}, split ('\n', $_);
            }
        }
        if (defined ($d->{data})) {
            if (ref($d->{data}->[0]) ne "HASH") {
                foreach (@{$d->{data}}) {
                    push @{$json}, split ('\n', $_);
                }
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

    # for nodeshell (xdsh), group msg with node name
    if ($param->{'resourcename'} =~ /(nodeshell|postscript|software_maintenance)/) {
        my $jsonnode;
        foreach (@{$json}) {
            if (/^(\S+):(.*)$/) {
                push @{$jsonnode->{$1}}, $2 if ($2 !~ /^\s*$/);
            }
        }
        if (!$jsonnode && $json)
        {
            push (@{$jsonnode},@{$json});
        }
        addPageContent($JSON->encode($jsonnode), 1);
        return;
    }
    if ($json) {
        addPageContent($JSON->encode($json), 1);
    }
}

# hanlde the output which is node relevant (rpower, rinv, rvitals ...)
# the output must be grouped with 'node' as key
# handle the input like  
# ===raw xml input
#  $d->{node}->{name}->[name] # this is must have, otherwise ignore the msg
#  $d->{node}->{data}->[msg]
#OR
#  $d->{node}->{name}->[name] # this is must have, otherwise ignore the msg
#  $d->{node}->{data}->{contents}->[msg]
#OR
#  $d->{node}->{name}->[name] # this is must have, otherwise ignore the msg
#  $d->{node}->{data}->{contents}->[msg]
#  $d->{node}->{data}->{desc}->[msg]
#
# Note: if does not have '$d->{node}->{data}->{desc}', use the resource name as the name of attribute.
# e.g. Get /node/node1/power, the record is '"power":"off"'
#
# ===msg format
#  <node>
#    <data>
#      <contents>1.41 (VVE128GUS  2013/07/22)</contents>
#      <desc>UEFI Version</desc>
#    </data>
#    <name>node1</name>
#  </node>
# ---
#TO
# ---
# {
#   "node1":{
#       "UEFI Version":"1.41 (VVE128GUS  2013/07/22)",
#   }
# }
sub actionout {
    my $data = shift;
    my $param =shift;

    my $jsonnode;
    foreach my $d (@$data) {
        unless (defined ($d->{node}->[0]->{name})) {
            next;
        }
        if (defined ($d->{node}->[0]->{data}) && (ref($d->{node}->[0]->{data}->[0]) ne "HASH" || ! defined($d->{node}->[0]->{data}->[0]->{contents}))) {
            # no $d->{node}->{data}->{contents} or $d->{node}->[0]->{data} is not hash
            $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}} = $d->{node}->[0]->{data}->[0];
        } elsif (defined ($d->{node}->[0]->{data}->[0]->{contents})) {
            if (defined($d->{node}->[0]->{data}->[0]->{desc})) {
                # has $d->{node}->{data}->{desc}
                $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$d->{node}->[0]->{data}->[0]->{desc}->[0]} = $d->{node}->[0]->{data}->[0]->{contents}->[0];
            } else {
                # use resourcename as the record name
                if ($param->{'resourcename'} eq "eventlog") {
                    push @{$jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}}}, $d->{node}->[0]->{data}->[0]->{contents}->[0];
                } elsif ($param->{'resourcename'} =~ /(vitals|inventory)/) {
                    # handle output of rvital and rinv for ppc node
                    push @{$jsonnode->{$d->{node}->[0]->{name}->[0]}}, $d->{node}->[0]->{data}->[0]->{contents}->[0];
                } else {
                    $jsonnode->{$d->{node}->[0]->{name}->[0]}->{$param->{'resourcename'}} = $d->{node}->[0]->{data}->[0]->{contents}->[0];
                }
            }
        } 
    }

    addPageContent($JSON->encode($jsonnode), 1) if ($jsonnode);
}

# hanlde the output which has the token id
# handle the input like  
# ===raw xml input
#  $d->{data}->{token}->{id}
#  $d->{data}->{token}->{expire}
sub tokenout {
    my $data = shift;

    my $json;
    foreach my $d (@$data) {
        if (defined ($d->{data}) && defined ($d->{data}->[0]->{token})) {
            $json->{token}->{id} = $d->{data}->[0]->{token}->[0]->{id}->[0];
            $json->{token}->{expire} = $d->{data}->[0]->{token}->[0]->{expire}->[0];
        }
    }

    if ($json) {
        addPageContent($JSON->encode($json));
    }
}

# This is the general callback subroutine for PUT/POST/DELETE methods
# when this subroutine is called, that means the operation has been done successfully
# The correct output is 'null'
sub noout {
    return;
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

# The operation callback subroutine for def related resource (lsdef, chdef ...)
# assembe the xcat request, send it to xcatd and get response
sub defhdl {
    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};

    # set the command name
    $request->{command} = $params->{'cmd'};

    # push the -t args for *def command
    my $resrctype = $params->{'resourcegroup'};
    $resrctype =~ s/s$//;  # remove the last 's' as the type of object
    push @args, ('-t', $resrctype);

    # push the object name - node/noderange
    if (defined ($urilayers[1])) {
        if ($urilayers[1] eq "ALLRESOURCES") {
            unless (isGET()) {
                error("Keyword ALLRESOURCES is only supported for GET Action.",$STATUS_NOT_FOUND);
            }
            push @args, '-l';
        } else {
            push @args, ('-o', $urilayers[1]);
        }
    }

    # For the put/post which specifies attributes like mgt=ipmi groups=all
    foreach my $k (keys(%$paramhash)) {
        push @args, "$k=$paramhash->{$k}" if ($k);
    } 
    
    if ($params->{'resourcename'} eq "allnode") {
        push @args, '-s';
    } elsif ($params->{'resourcename'} =~ /(nodeattr|osimage_attr|group_attr|policy_attr|network_attr)/) {
        # if /nodes/node1/attrs/attr1,att2 is specified, for get request, 
        # use 'lsdef -i' to specify the attribute list
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

# The operation callback subroutine for any node related resource (power, energy ...)
# assembe the xcat request, send it to xcatd and get response
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
        } else { # default, get all attrs
            push @args, "all";
        }
    } elsif ($params->{'resourcename'} eq "serviceprocessor") {
        if (isGET()) {
            push @args, $urilayers[3];
        } elsif (isPut() or isPost()) {
            if ($paramhash->{'value'} and defined($urilayers[3])) {
                push @args, $urilayers[3]."=".$paramhash->{'value'};
            } else {
                foreach my $key (keys %$paramhash) {
                    if (($key ne '') and (exists($paramhash->{$key}))) {
                        push @args, $key."=".$paramhash->{$key};
                    }
                }
            }
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
        if(%$paramhash)
        {
          foreach my $key1 (keys %$paramhash) {
            if ( $key1 eq "ENV" && defined ($paramhash->{'ENV'})) {
                 foreach my $key (keys %{$paramhash->{'ENV'}}) {
                      if (($key ne '') and (exists($paramhash->{'ENV'}->{$key}))) {
                          push (@{$request->{env}},"$key=$paramhash->{'ENV'}->{$key}");
                      }
                 }
                 next;
            }
            elsif ( $key1 eq "raw" && defined ($paramhash->{'raw'})) {
                 if (ref($paramhash->{'raw'}) eq "ARRAY") {
                     push @args, join (';', @{$paramhash->{'raw'}});
                 } else {
                     push @args, $paramhash->{'raw'};
                 }
                 next;
            }
            elsif ( $key1 eq "command" && defined ($paramhash->{'command'})) {
                 if (ref($paramhash->{'command'}) eq "ARRAY") {
                      push @args, join (';', @{$paramhash->{'command'}});
                 } else {
                      push @args, $paramhash->{'command'};
                 }
                 next;
            }
         }
        }
        else {
            error ("Lack of operation data.",$STATUS_BAD_REQUEST,3);
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
    } elsif ($params->{'resourcename'} eq "subnodes") {
        if (isGET()) {
            push @args, '-z';
        }
    } elsif ($params->{'resourcename'} eq "vm") {
        # handle the virtual machine
        if (isGET()) {
            # do nothing for kvm and esxi
        }elsif (isPut()) {  # change the configuration of vm
            if (defined ($paramhash->{'adddisk'})) { #add new disk
                push @args, ('-a', $paramhash->{'adddisk'});
            }
            #if (defined ($paramhash->{'rmdisk'})) { #remove disk
            #    push @args, ('-d', $paramhash->{'rmdisk'});
            #}
            if (defined ($paramhash->{'purgedisk'})) { #purge disk
                push @args, ('-p', $paramhash->{'purgedisk'});
            }
            if (defined ($paramhash->{'resizedisk'})) { #change the disk size
                $paramhash->{'resizedisk'} =~ s/\:/=/;   # replace : to be = in the param
                push @args, ('--resize', $paramhash->{'resizedisk'});
            }
            if (defined ($paramhash->{'memorysize'})) { #change the memory size
                push @args, ('--mem', $paramhash->{'memorysize'});
            }
            if (defined ($paramhash->{'cpucount'})) { #change the cpu size
                push @args, ('--cpus', $paramhash->{'cpucount'});
            }
        } elsif (isPost()) {  # create virtual machine
            if (defined ($paramhash->{'master'})) { # specify the master node for clone
                push @args, ('-m', $paramhash->{'master'});
            }
            if (defined ($paramhash->{'disksize'})) { # specify disk size
                push @args, ('-s', $paramhash->{'disksize'});
            }
            if (defined ($paramhash->{'memorysize'})) { #specify the memory size
                push @args, ('--mem', $paramhash->{'memorysize'});
            }
            if (defined ($paramhash->{'cpucount'})) { #specify the cpu size
                push @args, ('--cpus', $paramhash->{'cpucount'});
            }
            if (defined ($paramhash->{'force'}) && $paramhash->{'force'} eq "yes") { # force the recreate
                push @args, "-f";
            }
        } elsif (isDelete()) {
            if (defined ($paramhash->{'force'}) && $paramhash->{'force'} eq "yes") { # force the recreate
                push @args, "-f";
            }
            if (defined ($paramhash->{'purge'}) && $paramhash->{'purge'} eq "yes") { # purge disk when remove the vm
                push @args, "-p";
            }
        }
    } elsif ($params->{'resourcename'} eq "vmclone") {
        # handle the clone of virtual machine
        if (isPost()) {
            if (defined ($paramhash->{'tomaster'})) {
                push @args, ("-t", $paramhash->{'tomaster'});
            } elsif (defined ($paramhash->{'frommaster'})) {
                push @args, ("-b", $paramhash->{'frommaster'});
            } else {
                error ("Lack of operation data.",$STATUS_BAD_REQUEST,3);
            }
            
            if (defined ($paramhash->{'detach'}) && $paramhash->{'detach'} eq "yes") {
                push @args, "-d";
            }
            if (defined ($paramhash->{'force'}) && $paramhash->{'force'} eq "yes") { # force the recreate
                push @args, "-f";
            }
        }
    } elsif (($params->{'resourcename'} eq "vmmigrate")) {
        # handle the migration of virtual machine
        if (isPost()) {
            if (defined ($paramhash->{'target'})) {
                push @args, $paramhash->{'target'};
            } else {
                error ("Lack of operation data.",$STATUS_BAD_REQUEST,3);
            }
        }
    } elsif  ($params->{'resourcename'} eq "noderename") {

        if (isPut()) {
            if (defined ($paramhash->{'newNode'})) { #specify the new name for node
                push @args, ('-t', "node");
                push @args, ('-o', $urilayers[1]);
                push @args, ('-n', $paramhash->{'newNode'});
            }
        }
    } elsif ($params->{'resourcename'} eq "nbimage") {
        delete $request->{noderange};
        push @args, $urilayers[3];
        if (isPost()) {
            if (defined($paramhash->{'onlyconfigfile'})) {
                my $tmp_value = $paramhash->{'onlyconfigfile'};
                if ($tmp_value =~ /true|yes|Y|1/i) {
                    push @args, "-c";     
                } elsif ($tmp_value !~ /false|no|N|0/i) {
                    error ("Option value \"$tmp_value\" invalid.", $STATUS_BAD_REQUEST, 3);
                }
            }
        }

    }

    push @{$request->{arg}}, @args;  
    my $req = genRequest();
    my $responses = sendRequest($req);

    return $responses;
}

# The operation callback subroutine for node irrelevant commands like makedns -n and makedhcp -n
# assembe the xcat request, send it to xcatd and get response
sub nonobjhdl {
    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};

    # set the command name
    $request->{command} = $params->{'cmd'};
    if ($params->{'resourcename'} =~ /(dns|dhcp)/) {
        push @args, '-n';
    } elsif ($params->{'resourcename'} eq "slpnodes") {
        if (isGET()) {
            push @args, '-z';
        }
    } elsif ($params->{'resourcename'} eq "specific_slpnodes") {
        if (isGET()) {
            push @args, "-z";
            push @args, "-s";
            push @args, $urilayers[2];
        }
    } elsif ($params->{'resourcename'} eq "tokens") {
        $request->{gettoken}->[0]->{username}->[0] = $generalparams->{userName} if (defined($generalparams->{userName}));
        $request->{gettoken}->[0]->{password}->[0] = $generalparams->{userPW} if (defined($generalparams->{userPW}));
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
                #push @{$params->{layers}}, $paramhash->{'node'};
                push @{$request->{noderange}}, $paramhash->{'node'};
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
    # 2 - 'nodes'
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

    # For both getTablesAllNodeAttribs and getTablesNodesAttribs, the rest of the request strucutre looks like this:
    # table => [
    #   {
    #       tablename => nodehm,
    #       attr => [
    #           mgmt,
    #           cons
    #       ]
    #   },
    #   {
    #       tablename => ipmi,
    #       attr => [
    #           ALL
    #       ]
    #   }
    # ]

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

#get bmc ip address source
#check if bmc user or password is correct 
sub bmccheckhdl {

    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};
    my $bmc_ip;
    my $bmc_user;
    my $bmc_pw;

    # set the command name
    $request->{command} = $params->{'cmd'};

    # get bmc ip
    if (defined($urilayers[2]))
    {
            $bmc_ip=$urilayers[2];
    }

    # get bmc user and password
    if (defined($urilayers[3]))
    {
            my @keyvals = split(/,/, $urilayers[3]);
            foreach my $kv (@keyvals)
            {
                my ($key, $value) = split(/\s*=\s*/, $kv, 2);
                if ($key eq "bmcuser")
                {
                    $bmc_user=$value;
                }
                elsif ($key eq "bmcpw")
                {
                    $bmc_pw=$value;
                }
            }
    }
    
    if ($params->{'resourcename'} eq "checkbmcauth") {
        if (isGET()) {

            push @args, "-i";
            push @args, $bmc_ip;
            if ( defined($bmc_user) && $bmc_user ne "none")
            {
                push @args, "-u";
                push @args, $bmc_user;

            }
            push @args, "-p";
            push @args, $bmc_pw;
            push @args, "-c";
        }
    }

    if ($params->{'resourcename'} eq "getbmcipsource") {
        if (isGET()) {
            push @args, "-i";
            push @args, $bmc_ip;
            if ( defined($bmc_user) && $bmc_user ne "none" )
            {
                push @args, "-u";
                push @args, $bmc_user;
            }
            push @args, "-p";
            push @args, $bmc_pw;
            push @args, "--ipsource";
        }
    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    my $responses = sendRequest($req);

    return $responses;


}


#get bmc list for bmcdiscover
sub bmclisthdl {

    my $params = shift;

    my @args;
    my @urilayers = @{$params->{'layers'}};
    my $m_value;
    my $ip_range;
    # the array elements for @urilayers are:
    # 0 - 'bmcdiscover'
    # 1 - <key-val-list>  (optional)

    # set the command name
    $request->{command} = $params->{'cmd'};

    # get method and ip_range
    if (defined($urilayers[2])) 
    {
            my @keyvals = split(/,/, $urilayers[2]);
            foreach my $kv (@keyvals) 
            {
                my ($key, $value) = split(/\s*=\s*/, $kv, 2);
                if ($key eq "method")
                {
                    $m_value=$value;   
                }
                elsif ($key eq "iprange")
                {
                    $ip_range=$value;
                }
            }
    }


    if ($params->{'resourcename'} eq "bmcdiscover") {
        if (isGET()) {
            push @args, "-s";
            push @args, $m_value;
            push @args, "--range";
            push @args, $ip_range;
        }

    }

    push @{$request->{arg}}, @args;
    my $req = genRequest();
    my $responses = sendRequest($req);

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
    # 2 - 'rows'
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
        # For getTablesAllRowAttribs, the rest of the request strucutre needs to look like this:
        # table => [
        #   {
        #       tablename => nodehm,
        #       attr => [
        #           mgmt,
        #           cons
        #       ]
        #   },
        #   {
        #       tablename => ipmi,
        #       attr => [
        #           ALL
        #       ]
        #   }
        # ]

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
        # For getAttribs, the rest of the request strucutre needs to look like this:
        #   {
        #       table => networks,
        #       keys => {
        #           net => 11.35.0.0,
        #           mask => 255.255.0.0
        #       }
        #       attr => [
        #           netname,
        #           dhcpserver
        #       ]
        #   },
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

# parse the output of all attrs of tables for the GET calls.  This is used for both node-oriented tables
# and non-node-oriented tables.
#todo: investigate a converter straight from xml to json
sub tableout {
    my $data = shift;
    my $json = {};
    # For the table get calls, we turned off ForceArray and KeyAttr for XMLin(), so the output is a little
    # different than usual.  Each element is a hash with key "table" that is either a hash or array of hashes.
    # Each element of that is a hash with 2 keys called "tablename" and "node". The latter has either: an array of node hashes,
    # or (if there is only 1 node returned) the node hash directly.
    # We are producing json that is a hash of table name keys that each have an array of node objects.
    foreach my $d (@$data) {
        my $table = $d->{table};
        if (!defined($table)) {     # special case for the getAttribs cmd
            $json->{$request->{table}}->[0] = $d;
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

# set attrs of nodes in tables
sub tablenodeputhdl {
    my $params = shift;

    # from the %URIdef:
    # desc => "[URI:/tables/nodes/{noderange}] - Change the table attibutes for the {noderange}.",
    # usage => "|An array of table objects.  Each table object contains the table name and an object of attribute values. DataBody: {table1:{attr1:v1,att2:v2,...}}.|$usagemsg{non_getreturn}|",
    # example => '|Change the nodehm.mgmt and noderes.netboot attributes for nodes node1-node5.|PUT|/tables/nodes/node1-node5 {"nodehm":{"mgmt":"ipmi"},"noderes":{"netboot":"xnba"}}||',

    my @args;
    my @urilayers = @{$params->{'layers'}};
    # the array elements for @urilayers are:
    # 0 - 'table'
    # 1 - <tablelist>
    # 2 - 'nodes'
    # 3 - <noderange>

    # set the command name
    $request->{command} = 'setNodesAttribs';
    $request->{noderange} = $urilayers[3];

    # For setNodesAttribs, the rest of the request strucutre looks like this:
    # arg => {
    # table => [
    #   {
    #       name => nodehm,
    #       attr => {
    #           mgmt => ipmi
    #       }
    #   },
    #   {
    #       name => noderes,
    #       attr => {
    #           netboot => xnba
    #       }
    #   }
    # ]
    # }

    # Get table list in the URI
    my @uritbs = split(/,/, $urilayers[1]); 

    # Go thru the list of tables (which are the top level keys in paramhash)
    my $tables = [];
    $request->{arg}->{table} = $tables;
    foreach my $k (keys(%$paramhash)) {
        my $intable = $k;
        # Check the validity of tables
        if (! grep(/^$intable$/, @uritbs)) {
            error("The table $intable is NOT in the URI.", $STATUS_BAD_REQUEST);
        }
        my $attrhash = $paramhash->{$k};
        my $outtable = { name=>$intable, attr=>$attrhash };
        push @$tables, $outtable;
    } 

    my $req = genRequest();
    # disabling the KeyAttr option is important in this case, so xmlin doesn't pull the name attribute
    # out of the node hash and make it the key
    my $responses = sendRequest($req, {SuppressEmpty => undef, ForceArray => 1, KeyAttr => []});

    return $responses;
}

# set attrs of a row in a non-node table
sub tablerowputhdl {
    my $params = shift;

    # from %URIdef:
    # desc => "[URI:/tables/{table}/rows/{keys}] - Change the non-node table attibutes for the row that matches the {keys}.",
    # usage => "|A hash of attribute names and values.  DataBody: {attr1:v1,att2:v2,...}.|$usagemsg{non_getreturn}|",
    # example => '|Creat a route row in the routes table.|PUT|/tables/routes/rows/routename=privnet {"net":"10.0.1.0","mask":"255.255.255.0","gateway":"10.0.1.254","ifname":"eth1"}||',

    my @args;
    my @urilayers = @{$params->{'layers'}};
    # the array elements for @urilayers are:
    # 0 - 'table'
    # 1 - <tablename>
    # 2 - 'rows'
    # 3 - <keys>

    # set the command name
    $request->{command} = 'setAttribs';

    # For setAttribs, the rest of the xml request strucutre looks like this:
    # <table>routes</table>
    # <keys>
    #   <routename>foo</routename>  
    # </keys>
    # <attr>
    #  <net>10.0.1.0</net>  
    #  <comments>This is a test</comments>  
    # </attr>

    # set the table name and keys
    $request->{table} = $urilayers[1];
    my @keyvals = split(/,/, $urilayers[3]);
    foreach my $kv (@keyvals) {
        my ($key, $value) = split(/\s*=\s*/, $kv, 2);
        $request->{keys}->{$key} = $value; 
    }

    # the attribute/value hash is already in paramhash
    $request->{attr} = $paramhash;

    my $req = genRequest();
    # disabling the KeyAttr option is important in this case, so xmlin doesn't pull the name attribute
    # out of the node hash and make it the key
    my $responses = sendRequest($req, {SuppressEmpty => undef, ForceArray => 1, KeyAttr => []});

    return $responses;
}

# delete rows in a non-node table
sub tablerowdelhdl {
    my $params = shift;

    # from %URIdef:
    # desc => "[URI:/tables/{table}/rows/{attrvals}] - Delete rows from a non-node table that have the attribute values specified in {attrvals}.",
    # usage => "||$usagemsg{non_getreturn}|",
    # example => '|Delete a route row in the routes table.|PUT|/tables/routes/rows/routename=privnet||',

    my @args;
    my @urilayers = @{$params->{'layers'}};
    # the array elements for @urilayers are:
    # 0 - 'table'
    # 1 - <tablename>
    # 2 - 'rows'
    # 3 - <attrvals>

    # set the command name
    $request->{command} = 'delEntries';

    # For delEntries, the rest of the xml request strucutre looks like this:
    # <table>
    #       <name>nodelist</name>
    #       <attr>
    #          <groups>compute1,lissa</groups>
    #          <status>down</status>
    #       </attr>
    # </table>

    # set the table name and attr/vals
    my $table = {};     # will hold the name and attr/vals
    $request->{table}->[0] = $table;        #todo: the xcat delEntries cmd supports multiple tables in 1 request. We could support this if the attr names were table.attr
    $table->{name} = $urilayers[1];
    my @attrvals = split(/,/, $urilayers[3]);
    foreach my $av (@attrvals) {
        my ($attr, $value) = split(/\s*=\s*/, $av, 2);
        $table->{attr}->{$attr} = $value; 
    }

    my $req = genRequest();
    # disabling the KeyAttr option is important in this case, so xmlin doesn't pull the name attribute
    # out of the node hash and make it the key
    my $responses = sendRequest($req, {SuppressEmpty => undef, ForceArray => 1, KeyAttr => []});

    return $responses;
}


# display the resource list when run 'xcatws.cgi -d'
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
    my @errmsgindata; # put the out->{data} for error message output
    
    #trim the serverdone message off
    foreach (@{$data}) {
        if (defined($_->{error})) {
            if (ref($_->{error}) eq 'ARRAY') {
                foreach my $msg (@{$_->{error}}) {
                    if ($msg =~ /(Permission denied|Authentication failure)/) {
                        # return 401 Unauthorized
                        error("Authentication failure", $STATUS_UNAUTH);
                    } else {
                        push @{$outputerror->{error}}, $msg;
                    }
                }
            } else {
                push @{$outputerror->{error}}, $_->{error};
            }
            
            if (defined ($_->{errorcode})) {
                if (ref($_->{errorcode}) eq 'ARRAY') {
                    $outputerror->{errorcode} = $_->{errorcode}->[0];
                } else {
                    $outputerror->{errorcode} = $_->{errorcode};
                }
            } else {
                # set the default errorcode to '1'
                $outputerror->{errorcode} = '1';
            }
        } elsif (defined($_->{errorcode}) && $_->{errorcode}->[0] ne "0") { # defined errorcode, but not define the error msg
            $outputerror->{errorcode} = $_->{errorcode}->[0];
            if (defined ($_->{data}) && ref($_->{data}->[0]) ne "HASH") {
                # to get the message in data for the case that errorcode is set but no 'error' attr
                push @errmsgindata, $_->{data}->[0];
            }
            if (@errmsgindata) {
                push @{$outputerror->{error}}, @errmsgindata;
            } else {
                push @{$outputerror->{error}}, "Failed with unknown reason.";
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
            } else {
                # set the default errorcode to '1'
                $outputerror->{errorcode} = '1';
            }
        } 


        if (exists($_->{serverdone})) {
            if (defined ($outputerror->{error}) || defined ($outputerror->{error})) {
                 addPageContent($JSON->encode($outputerror));
                 #return the default http error code to be 403 forbidden
                 sendResponseMsg($STATUS_FORBIDDEN);
            #} else {
                #otherwise, ignore the 'servicedone' data
            #    next;
            } else {
                delete ($_->{serverdone});
                if (scalar(keys %{$_}) > 0) {
                    push @{$outputdata}, $_;
                }
            }
        } else {
            if (defined ($_->{data}) && ref($_->{data}->[0]) ne "HASH") {
                # to get the message in data for the case that errorcode is set but no 'error' attr
                push @errmsgindata, $_->{data}->[0];
            }
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

# Append content to the global var holding the output to go back to the rest client
# 1st param - The output message
# 2nd param - A flag to specify the format of 1st param: 1 - json formatted standard xcat output data
sub addPageContent {
    my $newcontent = shift;
    my $userdata = shift;

    if ($userdata && $XCOLL) {
        my $group;
        my $hash = $JSON->decode($newcontent);
        if (ref($hash) eq "HASH") {
            foreach my $node (keys %{$hash}) {
                if (ref($hash->{$node}) eq "HASH") {
                    my $value;
                    foreach (sort (keys %{$hash->{$node}})) {
                        $value .= "$_$hash->{$node}->{$_}";
                    }
                    push @{$group->{$value}->{node}}, $node; 
                    $group->{$value}->{orig} = $hash->{$node};
                } elsif (ref($hash->{$node}) eq "ARRAY") {
                    my $value;
                    foreach (sort (@{$hash->{$node}})) {
                        $value .= "$_";
                    }
                    push @{$group->{$value}->{node}}, $node; 
                    $group->{$value}->{orig} = $hash->{$node};
                }
            }
        }
        my $groupout;
        foreach my $value (keys %{$group}) {
            if (defined $group->{$value}->{node}) {
                my $nodes = join(',', @{$group->{$value}->{node}});
                if (defined ($group->{$value}->{orig})) {
                    $groupout->{$nodes} = $group->{$value}->{orig};
                }
            }
        }
        $newcontent = $JSON->encode($groupout) if ($groupout);
    }
    
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
            SSL_verify_mode => 0,
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
# 1st output param - The params which are listed in @generalparamlis as a general parameters like 'debug=1, pretty=1'
# 2nd output param - All the params from url params and 'PUTDATA'/'POSTDATA' except the ones in @generalparamlis
sub fetchParameters {
    my @generalparamlist = qw(userName userPW pretty debug xcoll);
    # 1st check for put/post data and put that in the hash
    my $pdata;
    if (isPut()) { 
        $pdata = $q->param('PUTDATA'); 
        # in the sles 11.x, the 'PUTDATA' param is not supported for PUT method
        # so we have to work around it by getting it by myself
        unless ($pdata) {
            if (-f "/etc/SuSE-release")  {# SUSE os
                if ($ENV{'CONTENT_TYPE'} =~ /json/) {
                    $q->read_from_client(\$pdata, $ENV{'CONTENT_LENGTH'});
                }
            }
        }
    } elsif (isPost()) {
        $pdata = $q->param('POSTDATA'); 
    } elsif (isDelete()) { 
        if ($ENV{'CONTENT_TYPE'} =~ /json/) {
            $q->read_from_client(\$pdata, $ENV{'CONTENT_LENGTH'});
        } 
    }
    
    if ($dbgdata) {
        $pdata = $dbgdata;
    }
    
    my $genparms = {};
    my $phash;
    if ($pdata) {
        $phash = eval { $JSON->decode($pdata); };
        if ($@) { 
            # remove the code location information to make the output looks better
            if ($@ =~ m/ at \//) {
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


