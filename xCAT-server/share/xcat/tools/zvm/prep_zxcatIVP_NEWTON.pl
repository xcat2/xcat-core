#!/usr/bin/perl
###############################################################################
#      (c) Copyright International Business Machines Corporation 2016.
#                               All Rights Reserved.
###############################################################################
# COMPONENT: prep_zxcatIVP_NEWTON.pl
#
# This is a preparation script for Installation Verification Program for xCAT
# on z/VM.  It prepares the driver script by gathering information from
# OpenStack configuration files on the compute node.
###############################################################################

use strict;
use warnings;

use File::Basename;
use File::Spec;
use Getopt::Long;
use MIME::Base64;
use Sys::Hostname;
use Socket;
use Text::Wrap;

my %commonConf;              # Common configuration options
my %ceilometerConf;          # Ceilometer configuration options
my %cinderConf;              # Cinder configuration options
my %novaConf;                # Nova configuration options
my %neutronConf;             # Neutron configuration options
my %ml2ConfIni;              # Neutron m12 configuration options
my %neutronZvmPluginIni;     # Neutron zvm configuration options

my $version = "6.0";
my $supportString = "This script supports code based on the OpenStack Newton release.";

my $cmaAppliance = 0;        # Assumed to not be run in a CMA system
my $cmaVersionString = '';   # CMA version string for a CMA
my $cmaSystemRole = '';      # CMA system role string
my $commonOpts = ' host xcat_zhcp_nodename zvm_host zvm_xcat_master zvm_xcat_server zvm_xcat_username zvm_xcat_password ';
                             # Common options that can be specified in more than one configuration file
my $configFound = 0;         # At least 1 config file was found.  Defaults to false.
my $driver;                  # Name of driver file to be created less the ".pl"
my $driverLocation = "/opt/xcat/bin/";  # Location of the IVP program in xCAT MN.
my $driverPrefix = "zxcatIVPDriver_";  # Prefix used in naming the driver program.
my $driverSuffix;            # Suffix used in naming the driver program.
my $displayHelp = 0;         # Display help information.
my $host;                    # Host command option value
my %ignored;                 # List of ignored messages
my $ignoreCnt = 0;           # Number of times we ignored a message
my $infoCnt = 0;             # Count of informations messages
my $initSuffix;              # Suffix used in naming multihomed init scripts
my $ivp = "zxcatIVP.pl";     # z/VM xCAT IVP script name
my %msgsToIgnore;            # Hash of messages to ignore
my $obfuscateProg = '/usr/bin/openstack-obfuscate';  # PW obfuscation program
my $pwVisible = 0;           # PW is visible in the driver script (1 = yes, 0 = no)
my $scan;                    # Type of scan to be performed
my $verbose;                 # Verbose flag - 0: quiet, 1: verbose
my $versionOpt = 0;          # Show version information.
my $warnErrCnt = 0;          # Count of warnings and error messages

my $localIpAddress = '';     # Local IP address of system where we are prepping

# Locations of configuration files
my $locCeilometerConf = '/etc/ceilometer/ceilometer.conf';
my $locCinderConf = '/etc/cinder/cinder.conf';
my $locMl2ConfIni = '/etc/neutron/plugins/ml2/ml2_conf.ini';
my $locNeutronConf = '/etc/neutron/neutron.conf';
my $locNeutronZvmPluginIni = '/etc/neutron/plugins/zvm/neutron_zvm_plugin.ini';
my $locNovaConf = '/etc/nova/nova.conf';

# Version related files
my $locVersionFileCMO = '/opt/ibm/cmo/version';
my $locDMSSICMOCopy = '/var/lib/sspmod/DMSSICMO.COPY';
my $locApplSystemRole = '/var/lib/sspmod/appliance_system_role';

# Stems of startup scripts in /etc/init.d that can be scanned for
# configuration files names and locations.
my $ceilometerStem      = 'openstack-ceilometer-api';
my $neutronZvmAgentStem = 'neutron-zvm-agent';
my $novaComputeStem     = 'openstack-nova-compute';

# Eyecatchers used with --config operand
my $EyeCeilometerConf = 'ceilometer_conf';
my $EyeCinderConf = 'cinder_conf';
my $EyeMl2ConfIni = 'm12_conf';
my $EyeNeutronConf = 'neutron_conf';
my $EyeNeutronZvmPluginIni = 'neutron_zvm_plugin_conf';
my $EyeNovaConf = 'nova_conf';

# Messages
# Severity strings
my @sevInfo = ( '',                 # No header
                'Bypassing test',   # Bypassing message
                'Info',             # Information message
                'unknown',          # Unknown severity
                'Warning',          # Warning message
                'Error'             # Error message
              );

# Hash of message ids.  Message ids should be in uppercase.  'ALL' should not
# be used as a message id as this indicates that all messages are wanted.
# For each message id there is another hash with additional info:
#   severity - Severity of message and indicate whether it gets a header to the
#              message text (e.g. "Error (IVP:MAINT01) " )
#                  0 - no message header, unrated output
#                  1 - bypass message used by automated tests
#                  2 - information message with "Info" header
#                  3 - unknown message severity
#                  4 - warning message with "Warning" header
#                  5 - error message with "Error" header
#   recAction - Recommended action:
#                   0 - non-fatal message, continue processing
#                   1 - fatal message, end further processing
#   explain  - Further explanation of the message.
#   sysAct   - System action to be performed.  Normally, this is not specified
#              because the severity generates a default system action.
#   userResp - Suggested user response.
my %respMsgs = (
    'FATAL_DEFAULTS' =>
         {
           'sysAct'    => 'No further verification will be performed and the driver script '.
                          'will not be created.'
         },
    'NONFATAL_DEFAULTS' =>
         {
           'sysAct'    => 'Verification continues.'
         },
    'GENERIC_RESPONSE' =>
         {
           'severity'  => 0,
           'text'      => '%s',
         },
    'DRIV01' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => '%s is not a z/VM xCAT IVP driver program.  The file will not be changed.',
           'explain'   => 'The preparation script creates the indicated file.  If the file '.
                          'already exists, it will rename it so that a new one can be created. '.
                          'However, the indicated file does not appear to be a driver script '.
                          'created by a previous run of this script.  The indicated file will '.
                          'not be renamed in order to prevent a possible problem due to the '.
                          'unexpected renaming. ',
           'userResp'  => 'Remove or rename the indicated file and rerun the script.',
         },
    'DRIV02' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'Unable to open %s for output: %s',
           'explain'   => 'The preparation script attempted to create the indicated file but '.
                          'encountered an error. ',
           'userResp'  => 'Determine why the preparation script could not write to the indicated file '.
                          'and correct the error.',
         },
    'DRIV03' =>
         { 'severity'  => 5,
           'recAction' => 1,
           'text'      => 'The driver operand does not specify a valid directory: %s',
           'explain'   => 'The -d or --driver operand did not specify a valid directory. '.
                          'The script does not know where to create the driver script.',
           'userResp'  => 'Determine the correct directory and reinvoke this script.',
         },
    'FILE01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => '%s does not exist.',
           'explain'   => 'The indicated file is an OpenStack configuration file which was '.
                          'attempted to be scanned to obtain configuration properties.  Some of the '.
                          'properties in the file would be used to further validate the environment.  '.
                          'This file was expected to exist.',
           'sysAct'    => 'Verification continues but without properties from the specified file.',
           'userResp'  => 'Determine why the file does not exist and correct the issue.  If the file '.
                          'exists under a different name then you may need to modify the invocation '.
                          'parameters for this script and rerun it.',
         },
    'FILE02' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => '%s does not exist.',
           'explain'   => 'The indicated file is an OpenStack configuration file which was '.
                          'attempted to be scanned to obtain configuration properties.  Some of the '.
                          'properties in the file would be used to further validate the environment.  '.
                          'This file is an optional file.',
           'sysAct'    => 'Verification continues but without properties from the specified file.',
           'userResp'  => 'Determine why the file does not exist.  If the file is not needed then you can '.
                          'ignore this message.  Otherwise, you should correct the issue.  If the file '.
                          'exists under a different name then you may need to modify the invocation '.
                          'parameters for this script and rerun it.',
         },
    'FILE03' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'Unable to determine the %s configuration file.',
           'explain'   => 'The configuration file for the indicated OpenStack component was '.
                          'not found. Configuration properties related to that file will not be '.
                          'validated. This will affect the constructed driver script.',
           'sysAct'    => 'Verification continues but without properties for the component.',
           'userResp'  => 'Determine why the configuration file was not found and correct the issue.  If the file '.
                          'exists under a different name then you may need to modify the invocation '.
                          'parameters for this script and rerun it.',
         },
    'FILE04' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'Unable to determine the %s configuration file for the %s.',
           'explain'   => 'One of the configuration files for the indicated OpenStack component was '.
                          'not found. Configuration properties related to that file will not be '.
                          'validated. This will affect the constructed driver script.',
           'sysAct'    => 'Verification continues but without properties for the component.',
           'userResp'  => 'Determine why the configuration file was not found and correct the issue.  If the file '.
                          'exists under a different name then you may need to modify the invocation '.
                          'parameters for this script and rerun it.',
         },
    'FILE05' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => '%s cannot be read.',
           'explain'   => 'The indicated file is an OpenStack configuration file which was '.
                          'attempted to be scanned to obtain configuration properties.  '.
                          'This file cannot be read.',
           'sysAct'    => 'Verification continues but without properties from the indicated file.',
           'userResp'  => 'Determine why the file cannot be read.  If the file is not needed then you can '.
                          'ignore this message.  Otherwise, you should correct the issue.'.
                          "\n".
                          'If this script is being run remotely by the xCAT IVP rather than '.
                          'by your invocation of the script, you may need to specify a '.
                          'different OpenStack user to the orchestrator script (verifynode). '.
                          'This will require that you have set up the certificates on the '.
                          'compute node to allow the xCAT MN to access the system during the IVP. '.
                          'You can find information on setting up SSH keys in the Enabling z/VM for OpenStack '.
                          'manual in the OpenStack Configuration chapter.',
         },
    'FILE06' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => '%s cannot be read.',
           'explain'   => 'The indicated file is an OpenStack configuration file which was '.
                          'attempted to be scanned to obtain configuration properties.  '.
                          'This file cannot be read.',
           'sysAct'    => 'Verification continues but without properties from the indicated file.',
           'userResp'  => 'Determine why the file cannot be read.  If the file is not needed then you can '.
                          'ignore this message.  Otherwise, you should correct the issue.'.
                          "\n".
                          'If this script is being run remotely by the xCAT IVP rather than '.
                          'by your invocation of the script, you may need to specify a '.
                          'different OpenStack user to the orchestrator script (verifynode). '.
                          'This will require that you have set up the certificates on the '.
                          'compute node to allow the xCAT MN to access the system during the IVP. '.
                          'You can find information on setting up SSH keys in the Enabling z/VM for OpenStack '.
                          'manual in the OpenStack Configuration chapter.',
         },
    'MISS01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The required property \'%s\' is missing from section \'%s\' in %s.',
           'explain'   => 'A required property is missing from the indicated configuration file. ',
           'userResp'  => 'Consult the Enabling z/VM for OpenStack manual for this OpenStack version. Specify the '.
                          'missing property as indicated in the book and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'MISS02' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'An optional property \'%s\' is missing from section \'%s\' in %s. %s',
           'explain'   => 'A optional property is missing from the indicated configuration file. '.
                          'This message is intended to let you know that a default will be used '.
                          'so that you are aware of the result of not specifying the value.',
           'userResp'  => 'If the indicated result is not what you want then please consult the Enabling z/VM for OpenStack '.
                          'manual for this OpenStack version to determine what you can specify for the property. '.
                          'Specify the missing property as indicated in the manual and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'MISS03' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'An optional property \'%s\' is missing from section \'%s\' in %s.',
           'explain'   => 'A optional property is missing from the indicated configuration file. ',
           'userResp'  => 'If you intended to specify the property then please consult the Enabling z/VM for OpenStack'.
                          'manual for this OpenStack version to determine what you can specify for the property. '.
                          'Specify the missing property as indicated in the manual and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'MISS04' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'Most z/VM specific Ceilometer options are not defined. Ceilometer ' .
                          'support is not enabled for z/VM.',
           'explain'   => 'A number of properties used for Ceilometer are missing from the Ceilometer configuration file. '.
                          'Ceilometer will not be activated.',
           'userResp'  => 'If you intended to specify the Ceilometer properties then please consult the Enabling z/VM for OpenStack '.
                          'manual for this OpenStack version to determine what you can specify. '.
                          'Specify the missing properties as indicated in the manual and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'MISS05' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'Most z/VM specific Cinder options are not defined. ' .
                          'Cinder support for creation of persistent disks for z/VM ' .
                          'is not enabled.',
           'explain'   => 'A number of properties used for Cinder are missing from the Cinder configuration file. '.
                          'Cinder will not be used for the z/VM host.',
           'sysAct'    => 'Further testing of the Cinder options will not occur in this script.',
           'userResp'  => 'If you intended to specify the Cinder properties then please consult the Enabling z/VM for OpenStack '.
                          'manual for this OpenStack version to determine what you can specify. '.
                          'Specify the missing properties as indicated in the manual and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'MISS06' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'No configuration files were found.',
           'explain'   => 'The script attempted to read OpenStack configuration files in order to validate the '.
                          'properties and create a driver script.  The script was unable to determine the files '.
                          'or read the configuration files.',
           'sysAct'    => 'Validation of OpenStack configuration properties and creation of a driver script will not '.
                          'occur.',
           'userResp'  => 'Determine the reason that no configuration properties could be found. '.
                          'This can be caused by running the script from the wrong user or the configuration '.
                          'properties had the wrong permission set. Other error or warning messages from this run may '.
                          'indicate the reason for the problem. After you correct the issue, rerun the script.',
         },
    'MISS07' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'The %s configuration file was not found. The %s property is used by the driver script. %s',
           'explain'   => 'A optional property is missing from the indicated configuration file. A default will be used.',
           'userResp'  => 'If you intended to specify the property then please consult the Enabling z/VM for OpenStack '.
                          'manual for this OpenStack version to determine what you can specify for the property. '.
                          'Specify the missing property as indicated in the manual and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'MISS08' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'The following properties are missing from the %s file: %s.',
           'explain'   => 'At least one of the listed properties must be specified.',
           'userResp'  => 'Correct the configuration file by specifying one of the listed properties. '.
                          'Consult the Enabling z/VM for OpenStack manual '.
                          'for this OpenStack version to determine what you can specify for the property. '.
                          'Specify the missing property as indicated in the manual and restart the OpenStack services '.
                          'as described in the manual.',
         },
    'PROP01' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \`%s\`, %s would construct a value greater than 8 in length: %s',
           'explain'   => 'The value for the indicated property is required to be 8 characters or less and is not. '.
                          'The value is invalid.',
           'userResp'  => 'Correct the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \`%s\`, %s will not create a usable name with the value: %s',
           'explain'   => 'The property is used to create an instance name which is also used as the z/VM '.
                          'userid. The value of this property will not allow the plugin to generate '.
                          'unique instance names in subsequent deploys.',
           'userResp'  => 'Correct the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP03' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \`%s\`, %s will not create an instance name that is a single blank delimited word using the value: %s',
           'explain'   => 'The instance name is not valid.',
           'userResp'  => 'Correct the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP04' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \`%s\`, %s should not begin with \'rsz\': %s',
           'explain'   => 'The instance name is not valid.',
           'userResp'  => 'Correct the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP05' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \`%s\`, %s does not contain the expected value of \'%s\' and instead contains: \'%s\'',
           'explain'   => 'The value of the property does not match the allowed value(s). This will cause an error.',
           'userResp'  => 'Correct the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP06' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \'%s\', %s specifies a value, \'%s\', which is less than the recommended value of \'%s\'.',
           'explain'   => 'The value of the property is less than the minimun recommended value. This could cause an error.',
           'userResp'  => 'Correct the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP07' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \`%s\`, %s does not exist but other SCSI disk related operands exist. Both should be specified: \'zvm_fcp_list\' and \'zvm_zhcp_fcp_list\'',
           'explain'   => 'The two indicated properties should be specified in the configuration file. Failure to do so '.
                          'may cause errors.',
           'userResp'  => 'Correct the configuration file to specify both properties and rerun the script. Please refer to '.
                          'the Enabling z/VM for OpenStack manual for information about the properties and changing them.',
         },
    'PROP08' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \'%s\', %s specifies a value, \'%s\', which is not the required value of \'%s\'.',
           'explain'   => 'The value of the property does not match the value required for z/VM. This could cause an error.',
           'userResp'  => 'Correct the property and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP09' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \'%s\', \'%s\' is specified but has no value.',
           'explain'   => 'The property was expected to contain a value but did not. '.
                          'This is expected to cause errors.',
           'userResp'  => 'Correct the property and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP10' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \'%s\', \'%s\' contains too many values.',
           'explain'   => 'The property contains more than the allowed number of values. Some will be ignored or '.
                          'errors could occur.',
           'userResp'  => 'Correct the property and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP11' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \'%s\', \'%s\' contains non-hexadecimal characters: \'%s\'.',
           'explain'   => 'The property is expected to contain hexadecimal characters but some non-hexadecimal '.
                          'characters were detected. This is expected to cause processing errors.',
           'userResp'  => 'Correct the property and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'PROP12' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, section \'%s\',\n \'%s\' contains a value that is not 1-4 characters in length: \'%s\'.',
           'explain'   => 'The property is expected to have a length of 1-4 characters but is not.',
           'userResp'  => 'Correct the property and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'OPTS01' =>
         { 'severity'  => 4,
           'recAction' => 1,
           'text'      => '\'%s\' property in section \'%s\' in %s has a value that is different from the value of the ' .
                          '\'%s\' property in section \'%s\' in %s. They should be the same.  The value ' .
                          'in %s is: %s and in %s is: %s\n',
           'explain'   => 'The preparation script detected that two configuration files '.
                          'contained properties which should have the same value but did not. '.
                          'This can cause an error as different OpenStack processes perform '.
                          'functions which use the value.',
           'sysAct'    => 'Verification continues with the value from the first property.',
           'userResp'  => 'Correct the configuration files so that the indicated properties match. '.
                          'After correcting the files, please restart the compute node and verify '.
                          'that the new settings remain across a restart. Rerun the preparation '.
                          'script.',
         },
    'PARM01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => '--config operand: %s did not specify a file. Default file specification will be used.',
           'explain'   => 'The --config operand allows you to specify the configuration file to be '.
                          'processed and overrides the default values. The specified value did not '.
                          'indicate a valid file and as a result the default file will be used.',
           'userResp'  => 'Determine the correct file for the indicated file and reinvoke the preparation script.',
         },
    'PARM02' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => '%s operand (%s) is not %s.',
           'explain'   => 'The indicated operand did not specify a known value.',
           'userResp'  => 'Determine the correct value for the operand and reinvoke the preparation script.',
         },
    'ROLE01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'CMA system role is NOT %s but instead %s. Cinder will not be validated.',
           'explain'   => 'The Cinder component runs in an OpenStack controller. The CMA system ' .
                          'is not configured to run in that system role.',
           'sysAct'    => 'Further testing of the Cinder options will not occur in this script.',
           'userResp'  => 'If you wanted Cinder to run in the CMA system then you should consider '.
                          'changing the system role to \'CONTROLLER\'.  Please note that this system '.
                          'role would then need additional properties defined to allow OpenStack '.
                          'controller related components to run. Otherwise, you should consider '.
                          'removing the cinder configuration file from the CMA system. Please '.
                          'consult the Enabling z/VM for OpenStack manual for more information.',
         },
    'ROLE02' =>
         { 'severity'  => 5,
           'recAction' => 0,
           'text'      => 'The value of the openstack_system_role (%s) is not one of the possible values: %s',
           'explain'   => 'The openstack_system_role property controls the components that are enabled '.
                          'within CMA. The indicated property is not recognized and could cause '.
                          'errors to occur due.',
           'userResp'  => 'Please consult the Enabling z/VM for OpenStack manual for information on '.
                          'the proper values for the property, what they enable and how to set them.',
         },
    'SYS01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'Unable to obtain the host name and/or IP address for this system. '.
                          'The local IP address is used in the name of the driver script.\n%s' ,
           'explain'   => 'The preparation script attempted to determine the host name and IP Address '.
                          'of the system where it is run. It does this using gethostbyname and inet_ntoa '.
                          'functions. An error occurred which prevented the determination of the values. '.
                          'This could affect properties in the created driver script. These values are '.
                          'used when OpenStack properties do not provide the information. '.
                          'Some variables in the driver script such as zxcatIVP_cNAddress ' .
                          'may be set to an empty string value.',
           'userResp'  => 'If you do not encounter any errors related to the IP address when it is run '.
                          'then you can ignore this error.  Otherwise, you should investigate why the '.
                          'IP related information could not be obtained and resolve the issue or change '.
                          'the driver script to specify the correct value. Rerun the preparation script '.
                          'if you changed the system to resolve the issue.',
         },
    'TRON01' =>
         { 'severity'  => 2,
           'recAction' => 0,
           'text'      => 'In %s, \'%s\' in section \'%s\' specifies a value, \'%s\', that is deprecated. The recommended value is \'%s\'.',
           'explain'   => 'The property contains a value that is deprecated. The value was used in a previous release. ',
           'userResp'  => 'Change the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    'TRON02' =>
         { 'severity'  => 4,
           'recAction' => 0,
           'text'      => 'In %s, \'%s\' in section \'%s\' specifies a value, \'%s\', that is not the required value, \'%s\'.',
           'explain'   => 'The property contains a value that is not recognized.  This will cause OpenStack errors.',
           'userResp'  => 'Change the value and rerun the script. Please refer to the Enabling z/VM for OpenStack '.
                          'manual for information about the property and changing it.',
         },
    );

# set the usage message
my $usage_string = "Usage:\n
    $0\n
    or\n
    $0 -s serviceToScan -d driverProgramName\n
    or\n
    $0 --scan serviceToScan -driver driverProgramName\n
    The following options are supported:

      -c | --config <val>
             List of configuration files to be processed.  This list overrides
             the default configuration file locations or the ones determined by
             the --init-files operand.  Each configuration file is identified
             by an eyecatcher indicating which configuration file is being
             overriden followed by a colon and the fully qualified file
             specification.  Multiple configuration files may be specified by
             separating them with a comma (one file per eyecatcher).
             The following are recognized eyecathers and the files that they
             override:
               $EyeCeilometerConf - $locCeilometerConf
               $EyeCinderConf - $locCinderConf
               $EyeMl2ConfIni - $locMl2ConfIni
               $EyeNeutronConf - $locNeutronConf
               $EyeNeutronZvmPluginIni -
                 $locNeutronZvmPluginIni
               $EyeNovaConf - $locNovaConf
      -d | --driver
             File specification of driver program to construct,
             or name of directory to contain the driver program.
      -h | --help
             Display help information.
      -H | --host <val>
             Name of z/VM host to process.  Startup scripts end with this
             suffix for the specified z/VM system. When this option is
             used with the -i option, it indicates which startup scripts should
             be scanned.
             The driver script created will contain the host value as part of
             its name.
      --ignore <val>
             Blank or comma separated list of message ids or message severities
             to ignore.  Ignored messages are not counted as failures and do
             not produce messages. Instead the number of ignored messages and
             their message numbers are displayed at the end of processing.
             Recognized message severities: 'bypass', 'info', 'warning',
             'error'.
             The following is an example of a message id: MISS02.
      -i | --init-files   Scan the system for either System V style startup
             scripts or systemd service files related to OpenStack.  The
             files are scanned for the name of the related configuration file.
             For System V, /etc/init.d directory is scanned.  For systemd, it
             will scan /usr/lib/systemd/system/, /run/systemd/system/, and
             /etc/systemd/system/ service files (.service).
           --help         Display help information.
      -p | --password-visible
             If specified, password values in the constructed driver script
             program will be visible.  Otherwise, password values are
             hidden.  This option is used when building a driver script
             to run against an older xCAT Management Node.
      -s | --scan
             Services to scan ('all', 'nova' or 'neutron').
      -v
             Display script version information.
      -V | --verbose
             Display verbose processing messages.\n";

#-------------------------------------------------------

=head3   buildDriverProgram

    Description : Build or update the driver program with the
                  data obtained by the scans.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = buildDriverProgram();

=cut

#-------------------------------------------------------
sub buildDriverProgram{
    my $rc;
    my @driverText;

    if ( $verbose ) {
        logResponse( 'BLANK_LINE' );
        logResponse( 'GENERIC_RESPONSE', 'Building the IVP driver program.' );
    }

    # Erase any existing driver program.
    if ( -e $driver and ! -z $driver ) {
        # Make certain the file is one of our driver files.
        my $found = `grep 'Function: z/VM xCAT IVP driver program' $driver`;
        if ( ! $found ) {
            logResponse( 'DRIV01', $driver );
            return 251;
        } else {
            # Rename the existing driver file.
            logResponse( 'BLANK_LINE' );
            logResponse( 'GENERIC_RESPONSE', "The existing driver file is being saved as: $driver.old" );
            rename $driver,"$driver.old";
        }
    }

    # Open the driver program for output.
    $rc = open( my $fileHandle, '>', $driver );
    if ( ! defined $rc or $rc ne '1' ) {
        logResponse( 'DRIV02', $driver, $! );
        return 200;
    }

    # Construct the file in an array.
    push( @driverText, "#!/bin/bash" );
    push( @driverText, "# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html" );
    push( @driverText, "#" );
    push( @driverText, "# Function: z/VM xCAT IVP driver program" );
    push( @driverText, "#           Built by $0 version $version." );
    push( @driverText, "#           $supportString" );
    push( @driverText, "" );
    if ( $cmaAppliance == 1 ) {
        push( @driverText, "# System is a CMA" );
        push( @driverText, "# CMA system role: $cmaSystemRole" );
        push( @driverText, "# $cmaVersionString" );
        push( @driverText, "" );
    }
    push( @driverText, "############## Start of Nova Config Properties" );
    if ( exists $novaConf{'DEFAULT'}{'my_ip'} ) {
        push( @driverText, "" );
        push( @driverText, "# IP address or hostname of the compute node that is accessing this xCAT MN." );
        push( @driverText, "# From \'my_ip\' in $locNovaConf." );
        push( @driverText, "export zxcatIVP_cNAddress=\"$novaConf{'DEFAULT'}{'my_ip'}\"" );
    } else {
        if ( $locNovaConf ne '' ) {
            logResponse( 'MISS02', 'my_ip', 'DEFAULT', $locNovaConf,
                         "A default value of \'$localIpAddress\' will be used. ".
                         "If the value is not correct then you should ".
                         "update the zxcatIVP_cNAddress property in the driver script with the desired IP address." );
        } else {
            logResponse( 'MISS07', 'Nova', 'my_ip',
                         "A default value of \'$localIpAddress\' has been specified in the driver ".
                         "program for zxcatIVP_cNAddress property. If the value is not correct then ".
                         "you should update the zxcatIVP_cNAddress property in the driver script with ".
                         "the desired IP address." );
        }
        push( @driverText, "" );
        push( @driverText, "# IP address or hostname of the compute node that is accessing this xCAT MN." );
        push( @driverText, "# From the local IP address of this system." );
        push( @driverText, "export zxcatIVP_cNAddress=\"$localIpAddress\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_user_profile'} ) {
        push( @driverText, "" );
        push( @driverText, "# Default profile used in creation of server instances." );
        push( @driverText, "# From \'zvm_user_profile\' in $locNovaConf." );
        push( @driverText, "export zxcatIVP_defaultUserProfile=\"$novaConf{'DEFAULT'}{'zvm_user_profile'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_diskpool'} ) {
        push( @driverText, "" );
        push( @driverText, "# Array of disk pools that are expected to exist." );
        push( @driverText, "# From \'zvm_diskpool\' in $locNovaConf." );
        push( @driverText, "export zxcatIVP_diskpools=\"$novaConf{'DEFAULT'}{'zvm_diskpool'}\"" );
    }

    if ( exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} ) {
        push( @driverText, "" );
        push( @driverText, "# The list of FCPs used by instances." );
        push( @driverText, "# From \'zvm_fcp_list\' in $locNovaConf." );
        push( @driverText, "export zxcatIVP_instFCPList=\"$novaConf{'DEFAULT'}{'zvm_fcp_list'}\"" );
    }
    if ( exists $commonConf{'zvm_host'}{'value'} ) {
        push( @driverText, "" );
        push( @driverText, "# Node of host being managed.  If blank, IVP will search for the host node." );
        push( @driverText, "# From:");
        push( @driverText, split( '\n', $commonConf{'zvm_host'}{'fromLines'} ) );
        push( @driverText, "export zxcatIVP_hostNode=\"$commonConf{'zvm_host'}{'value'}\"" );

    }
    if ( exists $commonConf{'zvm_xcat_master'}{'value'} ) {
        push( @driverText, "" );
        push( @driverText, "# Node name for xCAT MN (optional)." );
        push( @driverText, "# From:");
        push( @driverText, split( '\n', $commonConf{'zvm_xcat_master'}{'fromLines'} ) );
        push( @driverText, "export zxcatIVP_mnNode=\"$commonConf{'zvm_xcat_master'}{'value'}\"" );
    }
    if ( exists $commonConf{'zvm_xcat_password'}{'value'} ) {
        my $clearPW = '';
        push( @driverText, "" );
        push( @driverText, "# User password defined to communicate with xCAT MN." );
        push( @driverText, "# From:");
        push( @driverText, split( '\n', $commonConf{'zvm_xcat_master'}{'fromLines'} ) );

        if ( -e $obfuscateProg ) {
            # assume password is obfuscated already and get it in the clear.
            $clearPW = `$obfuscateProg -u $commonConf{'zvm_xcat_password'}{'value'}`;
            $clearPW =~ s/\n+$//g;         # trim ending new line
        } else {
            # Assume password is in the clear because the obfuscation program is missing.
            $clearPW = $commonConf{'zvm_xcat_password'}{'value'};
        }

        if ( $pwVisible ) {
            push( @driverText, "export zxcatIVP_xcatUserPw=\"$clearPW\"" );
            push( @driverText, "export zxcatIVP_pw_obfuscated=0" );
        } else {
            my $hiddenPW = obfuscate( $clearPW, 1 );
            push( @driverText, "# Note: Password is hidden." );
            push( @driverText, "#       To override the support and pass the password in the" );
            push( @driverText, "#       clear, either:" );
            push( @driverText, "#         - specify the -p or --password-visible operand when" );
            push( @driverText, "#           invoking prep_zxcatIVP.pl script, or" );
            push( @driverText, "#         - change zxcatIVP_pw_obfuscated variable to 0 and" );
            push( @driverText, "#           specify the password in the clear on the" );
            push( @driverText, "#           zxcatIVP_xcatUserPw variable in the constructed" );
            push( @driverText, "#           driver script." );
            push( @driverText, "export zxcatIVP_xcatUserPw=\"$hiddenPW\"" );
            push( @driverText, "export zxcatIVP_pw_obfuscated=1" );
        }
    }
    if ( exists $commonConf{'zvm_xcat_server'}{'value'} ) {
        push( @driverText, "" );
        push( @driverText, "# Expected IP address of the xcat MN" );
        push( @driverText, "# From:");
        push( @driverText, split( '\n', $commonConf{'zvm_xcat_server'}{'fromLines'} ) );
        push( @driverText, "export zxcatIVP_xcatMNIp=\"$commonConf{'zvm_xcat_server'}{'value'}\"" );
    }
    if ( exists $commonConf{'zvm_xcat_username'}{'value'} ) {
        push( @driverText, "" );
        push( @driverText, "# User defined to communicate with xCAT MN" );
        push( @driverText, "# From:");
        push( @driverText, split( '\n', $commonConf{'zvm_xcat_server'}{'fromLines'} ) );
        push( @driverText, "export zxcatIVP_xcatUser=\"$commonConf{'zvm_xcat_username'}{'value'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'} ) {
        push( @driverText, "" );
        push( @driverText, "# The list of FCPs used by zHCP." );
        push( @driverText, "# From \'zvm_zhcp_fcp_list\' in $locNovaConf." );
        push( @driverText, "export zxcatIVP_zhcpFCPList=\"$novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'}\"" );
    }
    if ( exists $novaConf{'DEFAULT'}{'xcat_free_space_threshold'} ) {
        push( @driverText, "" );
        push( @driverText, "# Expected space available in the xCAT MN image repository" );
        push( @driverText, "# From \'xcat_free_space_threshold\' in $locNovaConf." );
        push( @driverText, "export zxcatIVP_expectedReposSpace=\"$novaConf{'DEFAULT'}{'xcat_free_space_threshold'}G\"" );
    }

    push( @driverText, "" );
    push( @driverText, "############## End of Nova Config Properties" );

    if (( keys %neutronConf ) or ( keys %neutronZvmPluginIni ) or ( keys %ml2ConfIni )) {
        push( @driverText, "" );
        push( @driverText, "############## Start of Neutron Config Properties" );
        if ( exists $neutronConf{'DEFAULT'}{'base_mac'} ) {
            my $prefix = $neutronConf{'DEFAULT'}{'base_mac'};
            $prefix =~ tr/://d;
            $prefix = substr( $prefix, 0, 6 );
            push( @driverText, "" );
            push( @driverText, "# User prefix for MAC Addresses of Linux level 2 interfaces" );
            push( @driverText, "# From \'base_mac\' in $locNeutronConf." );
            push( @driverText, "export zxcatIVP_macPrefix=\"$prefix\"" );
        }
        if ( exists $neutronZvmPluginIni{'agent'}{'xcat_mgt_ip'} ) {
            push( @driverText, "" );
            push( @driverText, "# xCat MN's address on the xCAT management network" );
            push( @driverText, "# From \'xcat_mgt_ip\' in $locNeutronZvmPluginIni." );
            push( @driverText, "export zxcatIVP_xcatMgtIp=\"$neutronZvmPluginIni{'agent'}{'xcat_mgt_ip'}\"" );
        }
        if ( exists $neutronZvmPluginIni{'agent'}{'xcat_mgt_mask'} ) {
            push( @driverText, "" );
            push( @driverText, "# xCat management interface netmask" );
            push( @driverText, "# From \'xcat_mgt_mask\' in $locNeutronZvmPluginIni." );
            push( @driverText, "export zxcatIVP_mgtNetmask=\"$neutronZvmPluginIni{'agent'}{'xcat_mgt_mask'}\"" );
        }
        if ( exists $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} or
             exists $ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'} ) {
            my $list = '';
            if ( exists $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} and
                 $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} ne '*' ) {
                $list = $ml2ConfIni{'ml2_type_flat'}{'flat_networks'};
            }
            if ( exists $ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'} ) {
                if ( $list ne '' ) {
                    $list = "$list,";
                }
                $list = "$list$ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'}";
            }
            $list =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
            if ( $list ne '' ) {
                push( @driverText, "" );
                push( @driverText, "# Array of networks and possible VLAN ranges" );
                push( @driverText, "# From $locMl2ConfIni,");
                push( @driverText, "#     \'flat_networks\' in section \'ml2_type_flat\' and ");
                push( @driverText, "#     \'network_vlan_ranges\' in section \'ml2_type_vlan\'.");
                push( @driverText, "export zxcatIVP_networks=\"$list\"" );
            }
        }
        if ( exists $commonConf{'xcat_zhcp_nodename'}{'value'} ) {
            push( @driverText, "" );
            push( @driverText, "# Node name for xCAT zHCP server" );
            push( @driverText, "# From:");
            push( @driverText, split( '\n', $commonConf{'xcat_zhcp_nodename'}{'fromLines'} ) );
            push( @driverText, "export zxcatIVP_zhcpNode=\"$commonConf{'xcat_zhcp_nodename'}{'value'}\"" );
        }

        # Create the zxcatIVP_vswitchOSAs variable for any networks specified with an rdev list.
        my $vswitchOSAs = '';
        foreach my $section (sort keys %neutronZvmPluginIni) {
            next if ( $section eq 'agent');
            foreach my $property ( keys %{ $neutronZvmPluginIni{$section} } ) {
                next if ( $property ne "rdev_list" );
                my $list = $neutronZvmPluginIni{$section}{$property};
                $list =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
                next if ( $list eq '' );
                $list =~ s/\s+/\,/g;              # insert comma between words
                $vswitchOSAs = "$section $list $vswitchOSAs";
            }
        }
        if ( $vswitchOSAs ne '' ) {
            push( @driverText, "" );
            push( @driverText, "# Vswitches and their related OSAs" );
            push( @driverText, "# From \'rdev_list\' in vswitch sections of $locNeutronZvmPluginIni." );
            push( @driverText, "export zxcatIVP_vswitchOSAs=\"$vswitchOSAs\"" );
        }

        push( @driverText, "" );
        push( @driverText, "############## End of Neutron Config Properties" );
    }

    push( @driverText, "" );
    push( @driverText, "# Name of user under which nova runs, default is nova." );
    push( @driverText, "# If you system is different then change this property." );
    push( @driverText, "export zxcatIVP_expUser=\"nova\"" );
    push( @driverText, "" );
    push( @driverText, "# Controls whether Warnings/Errors detected by the IVP are" );
    push( @driverText, "# logged in the xCAT MN syslog, 0: do not log, 1: log to syslog." );
    push( @driverText, "export zxcatIVP_syslogErrors=1" );
    push( @driverText, "" );
    push( @driverText, "perl $driverLocation$ivp" );

    # Write the array to the driver file.
    foreach (@driverText) {
        #print "$_\n";
        print $fileHandle "$_\n"; # Print each entry in our array to the file
    }

    close $fileHandle;

    logResponse( 'BLANK_LINE' );
    logResponse( 'GENERIC_RESPONSE', "$driver was built." );
    return 0;
}
#-------------------------------------------------------

=head3   buildMsg

    Description : Build a message from a message repository file.
    Arguments   : Message repository or Repository identifier
                  Group identifier
                  Message identifier
                    'BLANK_LINE' is a special identifier that does not appear in
                      the message repository but instead causes a blank line to
                      be printed to the display.
                  Message substitutions
    Returns     : Recommended action:
                    0: Continue processing
                    1: Fatal, end processing
                  severity - Severity of message and indicate whether it gets
                      a header to the message text (e.g. "Error (IVP:MAINT01) " )
                    0 - no message header, unrated output
                    1 - unknown message severity
                    2 - bypass message used by automated tests
                    3 - information message with "Info" header
                    4 - warning message with "Warning" header
                    5 - error message with "Error" header
                  Constructed message
                  Additional information (e.g. explanation, system action, user action)
    Example     : ( $rc, $sev, $msg, $extraInfo ) = xCAT::zvmMsgs->buildMsg('ZXCATIVP', 'IVP', $msgInfo, \@msgSubs);

=cut

#-------------------------------------------------------
sub buildMsg {
    my ( $repos, $groupId, $msgId, $subs ) = @_;
    my @msgSubs = @$subs;
    my $sev = 0;
    my $recAction = 0;
    my $respHash;
    my $retMsg = '';
    my $retExtra = '';

    $Text::Wrap::unexpand = 0;

    # Find the message
    if ( $msgId eq 'BLANK_LINE' ) {
        $retMsg = "\n";
    } elsif ( !exists $respMsgs{$msgId} ) {
        $sev = 3;
        $retMsg = "Warning ($msgId): Unknown message id.\n";
        # Recommended Action is 'continue'.
    } else {
        # Build severity and message Id portion of the message.
        my $msg = '';
        if ( exists $respMsgs{$msgId}{'severity'} ) {
            $sev = $respMsgs{$msgId}{'severity'};
            if ( $respMsgs{$msgId}{'severity'} != 0 ) {
                $msg = $sevInfo[ $respMsgs{$msgId}{'severity'} ] . " ($groupId:$msgId) ";
            }
        } else {
            # Unknown severity
            $sev = 3;
            $msg = $sevInfo[1] . " ($groupId:$msgId) ";
        }

        # Determine the recommended action to return to the caller.
        if ( exists $respMsgs{$msgId}{'recAction'} ) {
            $recAction = $respMsgs{$msgId}{'recAction'};
        }

        # Build text portion of the message.
        if ( exists $respMsgs{$msgId}{'text'} ) {
            if ( @msgSubs ) {
                my $msgText = sprintf( $respMsgs{$msgId}{'text'}, @msgSubs);
                $msg = "$msg$msgText";
            } else {
                $msg = $msg . $respMsgs{$msgId}{'text'};
            }
        }

        # Format the messages lines with proper indentation.
        my $line;
        chomp $msg;
        my @msgLines = split( /\\n/, $msg );
        for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
            $line = "$msgLines[$i]";
            $retMsg = $retMsg . wrap( "", "\t", $line ) . "\n";
        }

        if ( $sev >=2 ) {
            # Build explanation portion of the known messages that are bypass,
            # info, warning or error.  These can have extra information.
            if ( exists $respMsgs{$msgId}{'explain'} ) {
                my $expLines = "    Explanation: $respMsgs{$msgId}{'explain'}";
                @msgLines = split( /\\n/, $expLines );
                for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
                    $line = "$msgLines[$i]";
                    if ( $i != 0 ) {
                        $line = "\t$line";
                    }
                    $retExtra = $retExtra . wrap( "", "\t", $line ) . "\n";
                }
            }

            # Build system action portion of the message.
            my $sysAction;
            if ( exists $respMsgs{$msgId}{'sysAct'} ) {
                $sysAction = "    System Action: $respMsgs{$msgId}{'sysAct'}";
            } else {
                if ( $recAction == 0 and exists $respMsgs{'NONFATAL_DEFAULTS'}{'sysAct'} ) {
                    $sysAction = "    System Action: $respMsgs{'NONFATAL_DEFAULTS'}{'sysAct'}";
                } elsif ( $recAction == 1 and exists $respMsgs{'FATAL_DEFAULTS'}{'sysAct'} ) {
                    $sysAction = "    System Action:  $respMsgs{'FATAL_DEFAULTS'}{'sysAct'}";
                }
            }
            if ( defined $sysAction ) {
                #@msgLines = split( /\\n/, $sysAction );
                #$retMsg = $retMsg . wrap( "", "\t", @msgLines ) . "\n";

                @msgLines = split( /\\n/, $sysAction );
                for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
                    $line = "$msgLines[$i]";
                    if ( $i != 0 ) {
                        $line = "\t$line";
                    }
                    $retExtra = $retExtra . wrap( "", "\t", $line ) . "\n";
                }
            }

            # Build user response portion of the message.
            if ( exists $respMsgs{$msgId}{'userResp'} ) {
                @msgLines = split( /\\n/, "    User Response: $respMsgs{$msgId}{'userResp'}" );
                #$retMsg = $retMsg . wrap( "", "\t", @msgLines ) . "\n";
                for ( my $i = 0; $i < scalar @msgLines; $i++ ) {
                    $line = "$msgLines[$i]";
                    if ( $i != 0 ) {
                        $line = "\t$line";
                    }
                    $retExtra = $retExtra . wrap( "", "\t", $line ) . "\n";
                }
            }
        }
    }

    return ( $recAction, $sev, $retMsg, $retExtra );
}

#-------------------------------------------------------

=head3   hashFile

    Description : Read a file with equal signs designating
                  key value pairs and create a hash from it.
    Arguments   : File to read
                  Reference to hash that should be constructed.
                  File is required to exist or there is a serious error.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = hashFile( $file, \%novaConf, 1 );

=cut

#-------------------------------------------------------
sub hashFile{
    my ( $file, $hash, $required ) = @_;
    my $section = "null";
    my $caseSensitive = 0;    # assume section/properties are case insensitive
    my @parts;
    my $out;

    # Clear the hash
    %$hash = ();

    if ( $file eq '' ) {
        return 602;
    }

    if ( ! -e $file ) {
        if ( $required ) {
            logResponse( 'FILE01', $file );
        } else {
            logResponse( 'FILE02', $file );
        }
        return 601;
    }

    if (( $file =~ /.conf$/ ) or ( $file =~ /.service$/ ) or ( $file =~ /.COPY$/ )) {
        # File is case sensitive, translate sections and property names to uppercase.
        $caseSensitive = 1;
    }

    # Read the configuration file and construct the hash of values.
    if (( $file =~ /.conf$/ ) or ( $file =~ /.ini$/ ) or ( $file =~ /.service$/ )) {
        $out = `egrep -v '(^#|^\\s*\\t*#)' $file`;
        my $rc = $?;
        if ( $rc != 0 ) {
            if ( $required ) {
                logResponse( 'FILE06', $file );
            } else {
                logResponse( 'FILE05', $file );
            }
            return 603;
        }
        my @lines = split( "\n", $out );
        foreach my $line ( @lines ) {
            if ( $line =~ /^\[/ ) {
                # Section header line
                $line =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the line
                $line =~ s/^\[+|\]+$//g;         # trim [] from ends of the line
                if ( !$caseSensitive ) {
                    $section = lc( $line );
                } else {
                    $section = $line;
                }
            } else {
                # Property line
                @parts = split( "=", $line, 2 );
                next if ( ! exists $parts[0] );
                $parts[0] =~ s/^\s+|\s+$//g;       # trim both ends of the string
                next if ( length( $parts[0] ) == 0 );
                if ( !$caseSensitive ) {
                    $parts[0] = lc( $parts[0] );
                }

                if ( exists $parts[1] ) {
                    chomp( $parts[1] );
                    $parts[1] =~ s/^\s+|\s+$//g;       # trim both ends of the string
                } else {
                    $parts[1] = '';
                }

                $$hash{$section}{$parts[0]} = $parts[1];
                #print "$section $parts[0]" . ": " . $parts[1]. "\n";
                #print $parts[0] . ": " . $$hash{$section}{$parts[0]}. "\n";
            }
        }
    } else {
        # Hash .COPY files
        # Read the file and remove comment lines and sequence columns (72-80)
        $out = `grep -v ^\$ $file`;
        my $rc = $?;
        if ( $rc != 0 ) {
            if ( $required ) {
                logResponse( 'FILE06', $file );
            } else {
                logResponse( 'FILE05', $file );
            }
            return 604;
        }
        $out =~ s{/\*.*?\*/}{}gs;

        my @lines = split( "\n", $out );
        foreach my $line ( @lines ) {
            # Remove sequence numbers and weed out blank lines
            $line = substr( $line, 0, 71 );
            $line =~ s/^\s+|\s+$//g;       # trim both ends of the string
            next if ( length( $line ) == 0 );

            # Parse the line
            @parts = split( "=", $line, 2 );
            next if ( ! exists $parts[0] );
            $parts[0] =~ s/^\s+|\s+$//g;       # trim both ends of the string
            next if ( length( $parts[0] ) == 0 );
            if ( !$caseSensitive ) {
                $parts[0] = lc( $parts[0] );
            }

            # Add the property to the hash if it has data.
            if ( exists $parts[1] ) {
                chomp( $parts[1] );
                $parts[1] =~ s/^\s+|\s+$//g;       # trim both ends of the string
                $parts[1] =~ s/^"+|"+$//g;         # trim double quotes from both ends of the string
            } else {
                $parts[1] = '';
            }

            $$hash{$parts[0]} = $parts[1];
            #print $parts[0] . ": " . $$hash{$parts[0]}. "\n";
        }
    }

    return 0;
}

#-------------------------------------------------------

=head3   logResponse

    Description : Build and log the response.
    Arguments   : message ID or special flag:
                  *ALL* indicates all messages should be displayed.
    Returns     : 0 - No error, general response or info message detected.
                  1 - Non-terminating message detected.
                  2 - Terminating message detected.
    Example     : $rc = logResponse( 'VX01' );
                  $rc = logResponse( 'VX03', $nodeName, $sub2);
                  $rc = logResponse( 'VX03', $nodeName, 'sub2a');

=cut

#-------------------------------------------------------
sub logResponse {
    my ( $msgId, @msgSubs ) = @_;
    my $rc = 0;
    my $extraInfo = '';
    my @ids;
    my $msg;
    my @msgLines;
    my $sev;
    my $line;

    if ( $msgId eq 'ALL' ) {
         @ids = ( sort keys %respMsgs );
    } else {
        $ids[0] = $msgId;
    }

    # Process the array of message IDs, a single element array for regular calls
    # or an array of all of the keys when "--showmsg all" is specified on the command.
    foreach my $id ( @ids ) {
        ( $rc, $sev, $msg, $extraInfo ) = buildMsg('VERIFY', 'PREP_ZXCATIVP', $msgId, \@msgSubs);
        #print ("rc: $rc, sev: $sev, msg: $msg");

        if ( defined $msgsToIgnore{$msgId} ) {
            # Ignore this message id
            $ignored{$msgId} = 1;
            $ignoreCnt += 1;
            next;
        } elsif ( defined $msgsToIgnore{$sev} ) {
            # Ignoring all messages of this severity.
            $ignored{$msgId} = 1;
            $ignoreCnt += 1;
            next;
        } elsif (( $sev == 2) or ( $sev == 3 )) {
            $infoCnt += 1;
        } elsif ( $sev >= 4 ) {
            $warnErrCnt += 1;
        }
        if ( $sev >= 3 ) {
            print "\n";
        }
        print "$msg";
        if ( $extraInfo ne '' ) {
            print "$extraInfo";
        }
    }

FINISH_logResponse:
    return $rc;
}

#-------------------------------------------------------

=head3   obfuscate

    Description : Build or update the driver program with the
                  data obtained by the scans.
    Arguments   : string to be processed
                  direction: 1 - obfuscate (hide it!)
                             0 - unobfuscate (unhide it!)
    Returns     : processed password (either hiden or unhidden))
    Example     : $rc = obfuscate( $pw, 1 );

=cut

#-------------------------------------------------------
sub obfuscate{
    my ( $pw, $hide ) = @_;

    if ( $hide == 1 ) {
        $pw = encode_base64( $pw, '' );
    } else {
        $pw = decode_base64( $pw );
    }

    return $pw;
}

#-------------------------------------------------------

=head3   saveCommonOpt

    Description : Save a common option for later use and
                  verify the value is consistent.
    Arguments   : option
                  section that contained the option
                  configuration file name
                  name of the option in the commonConf hash
                  value
    Returns     : 0 - No error
                  1 - Already saved with a different value
    Example     : $rc = saveCommonOpt( $confFile, $opt, $section, $confFile $commonOptName, $value );

=cut

#-------------------------------------------------------
sub saveCommonOpt {
    my ( $opt, $section, $confFile, $commonOptName, $value ) = @_;
    my $rc = 0;

    if ( !exists $commonConf{$commonOptName} ) {
        $commonConf{$commonOptName}{'value'} = $value;
        $commonConf{$commonOptName}{'fromLines'} = '#   ' . $opt . ' in ' . $confFile;
        $commonConf{$commonOptName}{'firstOpt'} = $opt;
        $commonConf{$commonOptName}{'firstSection'} = $section;
        $commonConf{$commonOptName}{'firstConf'} = $confFile;
    } else {
        if ( $commonConf{$commonOptName}{'value'} eq $value ) {
            $commonConf{$commonOptName}{'fromLines'} = $commonConf{$commonOptName}{'fromLines'} .
                "\n#   " . $opt . " in " . $confFile;
        } else {
            logResponse( 'OPTS01',
                         $opt,
                         $section,
                         $confFile,
                         $commonConf{$commonOptName}{'firstOpt'},
                         $commonConf{$commonOptName}{'firstSection'},
                         $commonConf{$commonOptName}{'firstConf'},
                         $confFile,
                         $value,
                         $commonConf{$commonOptName}{'firstConf'},
                         $commonConf{$commonOptName}{'value'} );
            $rc = 1;
        }
    }
    return $rc;
}

#-------------------------------------------------------

=head3   scanCeilometer

    Description : Scan the ceilometer configuration files.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanCeilometer();

=cut

#-------------------------------------------------------
sub scanCeilometer{
    my $rc;

    if ( $locCeilometerConf eq '' ) {
        return 602;
    }

    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Scanning the Ceilometer configuration files:\n$locCeilometerConf" );
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile( $locCeilometerConf, \%ceilometerConf, 0 );
    if ( $rc == 0 ) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanCinder

    Description : Scan the cinder configuration files.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanCinder();

=cut

#-------------------------------------------------------
sub scanCinder{
    my $rc;

    if ( $locCinderConf eq '' ) {
        return 602;
    }

    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Scanning the Cinder configuration files:\n$locCinderConf" );
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile( $locCinderConf, \%cinderConf, 0 );
    if ( $rc == 0 ) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanInitScript

    Description : Scan the init script for the
                  specified configuration file property.
    Arguments   : Configuration file name
                  Config property containing the value
    Returns     : Null - error locating the config file.
                  Non-null - file specification of the
                  configuration file.
    Example     : $confFile = scanInitScript('openstack-cinder-volume-$host',
                                       'config');

=cut

#-------------------------------------------------------
sub scanInitScript{
    my ( $filename, $property ) = @_;
    my $configFile = '';
    my $out;

    if ( -e $filename ) {
        if ( $verbose ) {
            logResponse( 'GENERIC_RESPONSE', "Scanning the $filename file for \'$property\' variable." );
        }

        # Strip out the lines after the desired config property is set and
        # remove comment lines then echo the property value.
        $out = `awk '{print} /$property=/ {exit}' /etc/init.d/$filename | grep -v ^\#  | grep  .`;
        $out = $out . "echo -n \$$property";
        $configFile = `$out`;
    }

    return $configFile;
}

#-------------------------------------------------------

=head3   scanNeutron

    Description : Scan the neutron configuration files.
    Arguments   : None
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanNeutron();

=cut

#-------------------------------------------------------
sub scanNeutron{
    my $rc;

    if ( $locNeutronConf eq '' and $locMl2ConfIni eq ''
         and $locNeutronZvmPluginIni eq '' ) {
        return 602;
    }

    if ( $verbose ) {
       logResponse( 'GENERIC_RESPONSE', "Scanning the Neutron configuration files:\n  $locNeutronConf\n  $locMl2ConfIni\n  $locNeutronZvmPluginIni" );
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile( $locNeutronConf, \%neutronConf, 1 );
    if ( $rc == 0 ) {
        $configFound = 1;
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile( $locMl2ConfIni, \%ml2ConfIni, 1 );
    if ( $rc == 0 ) {
        $configFound = 1;
    }

    # Read the configuration file and construct the hash of values.
    $rc = hashFile( $locNeutronZvmPluginIni, \%neutronZvmPluginIni, 1 );
    if ( $rc == 0 ) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanNova

    Description : Scan the Nova configuration files.
    Arguments   : None.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = scanNova();

=cut

#-------------------------------------------------------
sub scanNova{
    my $rc;

    if ( $locNovaConf eq '' ) {
        return 602;
    }

    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Scanning the Nova configuration file:\n  $locNovaConf" );
    }

    # Verify the /etc/nova/nova.conf exists.
    $rc = hashFile( $locNovaConf, \%novaConf, 1 );
    if ( $rc == 0 ) {
        $configFound = 1;
    }

    return $rc;
}

#-------------------------------------------------------

=head3   scanServiceUnit

    Description : Scan the service unit for the
                  specified configuration file property.
    Arguments   : Service file name
                  Section containing the desired property
                  Config property containing the value
    Returns     : Null - error locating the config file.
                  Non-null - file specification of the
                  configuration file.
    Example     : $confFile = scanServiceUnit( 'openstack-cinder-volume-$host',
                                               'Service', 'ExecStart' );

=cut

#-------------------------------------------------------
sub scanServiceUnit{
    my ( $filename, $section, $property ) = @_;
    my $configFile = '';
    my $out;
    my $serviceFile = '';
    my %serviceFileData;

    # verify the file exists
    if ( -e "/etc/systemd/system/$filename" ) {
        $serviceFile = "/etc/systemd/system/$filename";
    } elsif ( -e "/run/systemd/system/$filename" ) {
        $serviceFile = "/run/systemd/system/$filename";
    } elsif ( -e "/usr/lib/systemd/system/$filename" ) {
        $serviceFile = "/usr/lib/systemd/system/$filename";
    } else {
        return $configFile;   # Unit file was not found
    }

    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Scanning $filename for \'$property\' variable in section $section." );
    }

    my $rc = hashFile( $serviceFile, \%serviceFileData, 0 );
    if ( $rc != 0 ) {
        return $configFile;   # Could not build the hash
    }

    if ( exists $serviceFileData{$section}{$property} ) {
        my @parms = split( ' --config-file ', $serviceFileData{$section}{$property} );
        @parms = split ( ' ', $parms[1] );
        $configFile = $parms[0];
    }

    return $configFile;
}

#-------------------------------------------------------

=head3   showHelp

    Description : Show the help inforamtion.
    Arguments   : None.
    Returns     : None.
    Example     : showHelp();

=cut

#-------------------------------------------------------
sub showHelp{
    print "$0 prepares and builds a z/VM xCAT IVP driver program
    using the information from the configuration files in the
    compute node.

    The default name of the driver program is composed of the following:
      '$driverPrefix', and
      IP address of the system where driver was prepared, and
      (optionally) a hypen and the value specified on --Host operand, and
      '.sh'.
    For example:
      $driverPrefix"."9.123.345.91.sh
      $driverPrefix"."9.123.345.91-hostzvm.sh

    $supportString

    The following configuration files are scanned for input:
      $locCeilometerConf
      $locCinderConf
      $locNovaConf
      $locNeutronConf
      $locMl2ConfIni
      $locNeutronZvmPluginIni

    When the --init-files operand is specified, OpenStack startup
    scripts are scanned in /etc/init.d.  The --host operand should
    be specified to indicate the suffix to use for scripts that
    are unique to a specific z/VM host.  The following startup
    scripts are scanned:
      $ceilometerStem-<hostzvm>
      neutron-server
      $neutronZvmAgentStem-<hostzvm>
      $novaComputeStem-<hostzvm>
      openstack-cinder-volume

    When --init-files is specified without the --host operand,
    the following scripts are scanned:
      $ceilometerStem
      neutron-server
      $neutronZvmAgentStem
      $novaComputeStem
      openstack-cinder-volume

    The constructed driver program can then be uploaded to
    the xCAT MN and used to validate the configuration between
    the compute node and xCAT.\n\n";
    print $usage_string;
    return;
}

#-------------------------------------------------------

=head3   validateConfigs

    Description : Compare and validate the configuration
                  values obtained by the scans.
    Arguments   : None.
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : $rc = validateConfigs();

=cut

#-------------------------------------------------------
sub validateConfigs{
    my $bypassCinder = 0;
    my $rc = 0;
    my $option;
    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', 'Performing a local validation of the configuration files.' );
    }

    #*******************************************************
    # Verify required configuration options were specified.
    #*******************************************************
    if ( keys %ceilometerConf ) {
        my @requiredCeilometerOpts = (
            'DEFAULT','host',
            'DEFAULT','hypervisor_inspector',
            'zvm','zvm_host',
            'zvm','zvm_xcat_master',
            'zvm','zvm_xcat_password',
            'zvm','zvm_xcat_server',
            'zvm','zvm_xcat_username',
        );
        for ( my $i = 0; $i < $#requiredCeilometerOpts; $i = $i + 2 ) {
            my $section = $requiredCeilometerOpts[$i];
            my $option = $requiredCeilometerOpts[$i+1];
            if ( !exists $ceilometerConf{$section}{$option} ) {
                logResponse( 'MISS01', $option, $section, $locCeilometerConf );
            } else {
                saveCommonOpt( $option, $section, $locCeilometerConf, $option, $ceilometerConf{$section}{$option} );
            }
        }
    }

    if ( keys %cinderConf ) {
        my @requiredCinderOpts = ();
        foreach $option ( @requiredCinderOpts ) {
            if ( !exists $cinderConf{'DEFAULT'}{$option} ) {
                logResponse( 'MISS01', $option, 'DEFAULT', $locCinderConf );
            }
        }
    }

    if ( keys %novaConf ) {
        my @requiredNovaOpts = (
            'DEFAULT','compute_driver',
            'DEFAULT','force_config_drive',
            'DEFAULT','host',
            'DEFAULT','instance_name_template',
            'DEFAULT','zvm_diskpool',
            'DEFAULT','zvm_host',
            'DEFAULT','zvm_xcat_master',
            'DEFAULT','zvm_xcat_server',
            'DEFAULT','zvm_xcat_username',
            'DEFAULT','zvm_xcat_password',
            );
        for ( my $i = 0; $i < $#requiredNovaOpts; $i = $i + 2 ) {
            my $section = $requiredNovaOpts[$i];
            my $option = $requiredNovaOpts[$i+1];
            if ( !exists $novaConf{$section}{$option} ) {
                logResponse( 'MISS01', $option, $section, $locNovaConf );
            } elsif ( $commonOpts =~ m/ $option / ) {
                saveCommonOpt( $option, $section, $locNovaConf, $option, $novaConf{'DEFAULT'}{$option} );
            } elsif ( $option eq 'host' ) {
                saveCommonOpt( $option, $section, $locNovaConf, 'zvm_host', $novaConf{'DEFAULT'}{$option} );
            }
        }
    }

    if ( keys %neutronConf ) {
        my @requiredNeutronConfOpts = (
            'DEFAULT','core_plugin',
            );
        for ( my $i = 0; $i < $#requiredNeutronConfOpts; $i = $i + 2 ) {
            my $section = $requiredNeutronConfOpts[$i];
            my $option = $requiredNeutronConfOpts[$i+1];
            if ( !exists $neutronConf{$section}{$option} ) {
                logResponse( 'MISS01', $option, $section, "$locNeutronConf/neutron/neutron.conf" );
            }
        }
    }

    if ( keys %ml2ConfIni ) {
        my @requiredMl2ConfIniOpts = (
            'ml2','mechanism_drivers',
            );
        for ( my $i = 0; $i < $#requiredMl2ConfIniOpts; $i = $i + 2 ) {
            my $section = $requiredMl2ConfIniOpts[$i];
            my $option = $requiredMl2ConfIniOpts[$i+1];
            if ( !exists $ml2ConfIni{$section}{$option} ) {
                logResponse( 'MISS01', $option, $section, $locMl2ConfIni );
            }
        }
    }

    if ( keys %neutronZvmPluginIni ) {
        my @requiredNeutronZvmPluginIniOpts = (
            'agent', 'zvm_host',
            'agent','zvm_xcat_server',
            );
        for ( my $i = 0; $i < $#requiredNeutronZvmPluginIniOpts; $i = $i + 2 ) {
            my $section = $requiredNeutronZvmPluginIniOpts[$i];
            my $option = $requiredNeutronZvmPluginIniOpts[$i+1];
            if ( !exists $neutronZvmPluginIni{$section}{$option} ) {
                logResponse( 'MISS01', $option, $section, $locNeutronZvmPluginIni );
            } else {
                saveCommonOpt( $option, $section, $locNeutronZvmPluginIni, $option, $neutronZvmPluginIni{$section}{$option} );
            }
        }
    }

    #******************************************
    # Verify optional operands were specified.
    #******************************************
    if ( keys %ceilometerConf ) {
        if ( !exists $ceilometerConf{'DEFAULT'}{'host'} and
             !exists $ceilometerConf{'zvm'}{'zvm_host'}
           ) {
            logResponse( 'MISS04' );
        } else {
            my %optionalCeilometerConfOpts = (
                'zvm xcat_zhcp_nodename' => 'A default of \'zhcp\' will be used.',
            );
            my %defaultCeilometerConfOpts = (
                'zvm xcat_zhcp_nodename' => 'zhcp',
            );
            foreach my $key ( keys %optionalCeilometerConfOpts ) {
                my @opts = split( /\s/, $key );
                my $section = $opts[0];
                my $option = $opts[1];
                if ( !exists $ceilometerConf{$section}{$option} ) {
                    if ( $optionalCeilometerConfOpts{$key} ne '' ) {
                        logResponse( 'MISS02', $option, $section, $locCeilometerConf, $optionalCeilometerConfOpts{$key} );
                    } else {
                        logResponse( 'MISS03', $option, $section, $locCeilometerConf );
                    }
                    if ( exists $defaultCeilometerConfOpts{$key} ) {
                        $cinderConf{$section}{$option} = $defaultCeilometerConfOpts{$key};
                    }
                }
            }
        }
    }

    if ( keys %cinderConf ) {
        if ( $cmaSystemRole ne 'CONTROLLER' ) {
            logResponse( 'ROLE01', 'CONTROLLER', $cmaSystemRole );
            $bypassCinder = 1;
        } elsif ( !exists $cinderConf{'DEFAULT'}{'san_ip'} and
                !exists $cinderConf{'DEFAULT'}{'san_private_key'} and
                !exists $cinderConf{'DEFAULT'}{'storwize_svc_volpool_name'}
                ) {
               logResponse( 'MISS05' );
               $bypassCinder = 1;
        } else {
            my %optionalCinderConfOpts = (
                'DEFAULT san_ip' => 'This property is necessary when using persistent SAN disks obtained ' .
                    'from the Cinder service.',
                'DEFAULT san_private_key' => 'This property is necessary when using persistent SAN disks obtained ' .
                    'from the Cinder service.',
                'DEFAULT storwize_svc_connection_protocol' => 'This property is necessary when using StorWize ' .
                    'persistent disks obtained from the Cinder service.',
                "DEFAULT storwize_svc_volpool_name" => "This property is necessary when using StorWize persistent disks obtained " .
                    "from the Cinder service.  The default is 'volpool'.",
                'DEFAULT storwize_svc_vol_iogrp' => 'This property is necessary when using StorWize persistent ' .
                    'disks obtained from the Cinder service.  The default is 0.',
                'DEFAULT volume_driver' => 'This property is necessary when using persistent disks obtained ' .
                    ' from the Cinder service.',
            );
            my %defaultCinderConfOpts = (
                'DEFAULT storwize_svc_volpool_name' => 'volpool',
            );
            foreach my $key ( keys %optionalCinderConfOpts ) {
                my @opts = split( /\s/, $key );
                my $section = $opts[0];
                my $option = $opts[1];
                if ( !exists $cinderConf{$section}{$option} ) {
                    if ( $optionalCinderConfOpts{$key} ne '' ) {
                        logResponse( 'MISS02', $option, $section, $locCinderConf, $optionalCinderConfOpts{$key} );
                    } else {
                        logResponse( 'MISS03', $option, $section, $locCinderConf );
                    }
                    if ( exists $defaultCinderConfOpts{$key} ) {
                        $cinderConf{$section}{$option} = $defaultCinderConfOpts{$key};
                    }
                }
            }
        }
    }

    if ( keys %novaConf ) {
        my %optionalNovaConfOpts = (
            'DEFAULT config_drive_format' => 'Default of \'iso9660\' will be used.',
            "DEFAULT image_cache_manager_interval" => "Default of 2400 (seconds) will be used.",
            "DEFAULT ram_allocation_ratio" => "",
            "DEFAULT rpc_response_timeout" => 'zVM Live migration may timeout with the default value '.
                '(60 seconds). The recommended value for z/VM is 180 to allow zVM live migration to succeed.',
            "DEFAULT xcat_free_space_threshold" => "Default of 50 (G) will be used.",
            "DEFAULT xcat_image_clean_period" => "Default of 30 (days) will be used.",
            "DEFAULT zvm_config_drive_inject_password" => "This value will default to 'FALSE'.",
            "DEFAULT zvm_diskpool_type" => "Default of \'ECKD\' will be used.",
            "DEFAULT zvm_fcp_list" => "As a result, Cinder volumes cannot be attached to server instances.",
            "DEFAULT zvm_zhcp_fcp_list" => "",
            "DEFAULT zvm_image_tmp_path" => "Default of '/var/lib/nova/images' will be used.",
            "DEFAULT zvm_multiple_fcp" => "Default of 'false' will be used.",
            "DEFAULT zvm_reachable_timeout" => "Default of 300 (seconds) will be used.",
            "DEFAULT zvm_scsi_pool" => "Default of \'xcatzfcp\' will be used.",
            "DEFAULT zvm_user_default_privilege" => "Default of G will be used.",
            "DEFAULT zvm_user_profile" => "Default is 'OSDFLT'.",
            "DEFAULT zvm_user_root_vdev" => "Default of 100 will be used.",
            "DEFAULT zvm_vmrelocate_force" => "",
            "DEFAULT zvm_xcat_connection_timeout" => "Default of 3600 seconds will be used.",
            'DEFAULT zvm_image_compression_level' => 'Image compression is controlled by the xCAT ZHCP ' .
                'server in the /var/opt/zhcp/settings.conf file. Compressing images during image ' .
                'capture is the default.'
            );
        my %defaultNovaConfOpts = (
            'DEFAULT config_drive_format' => 'iso9660',
            "DEFAULT xcat_free_space_threshold" => 50,
            "DEFAULT xcat_image_clean_period" => 30,
            "DEFAULT zvm_user_default_privilege" => "G",
            "DEFAULT zvm_user_profile" => 'OSDFLT',
            "DEFAULT zvm_user_root_vdev" => 100,
            "DEFAULT zvm_diskpool_type" => 'ECKD',
            "DEFAULT zvm_scsi_pool" => "xcatzfcp",
            );
        foreach my $key ( keys %optionalNovaConfOpts ) {
            my @opts = split( /\s/, $key );
            my $section = $opts[0];
            my $option = $opts[1];
            if ( !exists $novaConf{$section}{$option} ) {
                if ( $optionalNovaConfOpts{$key} ne '' ) {
                    logResponse( 'MISS02', $option, $section, $locNovaConf, $optionalNovaConfOpts{$key} );
                } else {
                    logResponse( 'MISS03', $option, $section, $locNovaConf );
                }
                if ( exists $defaultNovaConfOpts{$key} ) {
                    $novaConf{$section}{$option} = $defaultNovaConfOpts{$key};
                }
            }
        }
    }

    if ( keys %neutronConf) {
        my %optionalNeutronConfOpts = (
            'DEFAULT base_mac' => 'A default value of \'fa:16:3e:00:00:00\' will be used.',
        );
        my %defaultNeutronConfOpts = (
            'DEFAULT base_mac' => 'fa:16:3e:00:00:00',
        );
        foreach my $key ( keys %optionalNeutronConfOpts ) {
            my @opts = split( /\s/, $key );
            my $section = $opts[0];
            my $option = $opts[1];
            if ( !exists $neutronConf{$section}{$option} ) {
                if ( $optionalNeutronConfOpts{$key} ne '' ) {
                    logResponse( 'MISS02', $option, $section, $locNeutronConf, $optionalNeutronConfOpts{$key} );
                } else {
                    logResponse( 'MISS03', $option, $section, $locNeutronConf );
                }
                if ( exists $defaultNeutronConfOpts{$key} ) {
                    $neutronConf{$section}{$option} = $defaultNeutronConfOpts{$key};
                }
            }
        }
    }

    if ( keys %ml2ConfIni ) {
        my %optionalMl2ConfIniOpts = (
            'ml2 tenant_network_types' => 'This property is an ordered list of '.
                'network types to allocate as tenant (project) networks, separated by commas. '.
                'A default value of \'local\' will be used.',
            'ml2 type_drivers' => 'This property lists the network types to be supported. '.
                'A default value of \'local,flat,vlan\' will be used.',
            );
        my %defaultMl2ConfIniOpts = (
            'ml2 tenant_network_types' => 'local',
            'ml2 type_drivers' => 'local,flat,vlan',
        );
        foreach my $key ( keys %optionalMl2ConfIniOpts ) {
            my @opts = split( /\s/, $key );
            my $section = $opts[0];
            my $option = $opts[1];
            if ( !exists $ml2ConfIni{$section}{$option} ) {
                if ( $optionalMl2ConfIniOpts{$key} ne '' ) {
                    logResponse( 'MISS02', $option, $section, $locMl2ConfIni, $optionalMl2ConfIniOpts{$key} );
                } else {
                    logResponse( 'MISS03', $option, $section, $locMl2ConfIni );
                }
                if ( exists $defaultMl2ConfIniOpts{$key} ) {
                    $ml2ConfIni{$section}{$option} = $defaultMl2ConfIniOpts{$key};
                }
            }
        }
    }

    if ( keys %neutronZvmPluginIni ) {
        my %optionalNeutronZvmPluginIniOpts = (
            'agent xcat_mgt_ip' => 'This property is necessary when deploying virtual server ' .
                'instances that do NOT have public IP addresses.',
            'agent xcat_mgt_mask' => 'This property is necessary when deploying virtual server ' .
                'instances that do NOT have public IP addresses.',
            "agent polling_interval" => "A default value of '5' will be used.",
            "agent xcat_zhcp_nodename" => "A default value of \'zhcp\' will be used.",
            "agent zvm_xcat_password" => "A default value of \'admin\' is used.",
            "agent zvm_xcat_timeout" => "A default value of 300 seconds is used.",
            "agent zvm_xcat_username" => "A default value of \'admin\' is used.",
            );
        my %defaultNeutronZvmPluginIniOpts = (
            "agent polling_interval" => 2,
            "agent xcat_zhcp_nodename" => "zhcp",
            "agent zvm_xcat_password" => "admin",
            "agent zvm_xcat_timeout" => 300,
            "agent zvm_xcat_username" => "admin",
            );
        foreach my $key ( keys %optionalNeutronZvmPluginIniOpts ) {
            my @opts = split( '\s', $key );
            my $section = $opts[0];
            my $option = $opts[1];
            if ( !exists $neutronZvmPluginIni{$section}{$option} ) {
                if ( $optionalNeutronZvmPluginIniOpts{$key} ne '' ) {
                    logResponse( 'MISS02', $option, $section, $locNeutronZvmPluginIni, $optionalNeutronZvmPluginIniOpts{$key} );
                } else {
                    logResponse( 'MISS03', $option, $section, $locNeutronZvmPluginIni );
                }
                if ( exists $defaultNeutronZvmPluginIniOpts{$key} ) {
                    $neutronZvmPluginIni{$section}{$option} = $defaultNeutronZvmPluginIniOpts{$key};
                    if ( $commonOpts =~ m/ $option / ) {
                        saveCommonOpt( $option, $section, $locNeutronZvmPluginIni, $option, $neutronZvmPluginIni{$section}{$option} );
                    }
                }
            }
        }
    }

    # Verify the instance name template is valid
    if ( exists $novaConf{'DEFAULT'}{'instance_name_template'} ) {
        # Use sprintf which is close enough to the python % support for formatting to construct a sample.
        my $base_name = sprintf( $novaConf{'DEFAULT'}{'instance_name_template'}, 1 );
        if ( length( $base_name ) > 8 ) {
            logResponse( 'PROP01', $locNovaConf, 'DEFAULT', 'instance_name_template', $novaConf{'DEFAULT'}{'instance_name_template'} );
        }
        if (( $base_name eq $novaConf{'DEFAULT'}{'instance_name_template'} ) ||
            ( $novaConf{'DEFAULT'}{'instance_name_template'} !~ /%/ )) {
            logResponse( 'PROP02', $locNovaConf, 'DEFAULT', 'instance_name_template', $novaConf{'DEFAULT'}{'instance_name_template'} );
        }
        my $words;
        $words++ while $base_name =~ /\S+/g;
        if ( $words != 1 ) {
            logResponse( 'PROP03', $locNovaConf, 'DEFAULT', 'instance_name_template', $novaConf{'DEFAULT'}{'instance_name_template'} );
        }
        if ( $novaConf{'DEFAULT'}{'instance_name_template'} =~ m/(^RSZ)/i ) {
            logResponse( 'PROP04', $locNovaConf, 'DEFAULT', 'instance_name_template', $novaConf{'DEFAULT'}{'instance_name_template'} );
        }
    }

    # Verify the compute_driver is for z/VM
    if ( exists $novaConf{'DEFAULT'}{'compute_driver'} ) {
        if ( $novaConf{'DEFAULT'}{'compute_driver'} ne "nova.virt.zvm.ZVMDriver" and
             $novaConf{'DEFAULT'}{'compute_driver'} ne "zvm.ZVMDriver") {
            logResponse( 'PROP05', $locNovaConf, 'DEFAULT', 'compute_driver', '\'nova.virt.zvm.ZVMDriver\' or \'zvm.ZVMDriver\'', $novaConf{'DEFAULT'}{'compute_driver'} );
        }
    }

    # Check whether the rpc timeout is too small for z/VM
    if ( exists $novaConf{'DEFAULT'}{'rpc_response_timeout'} ) {
        if ( $novaConf{'DEFAULT'}{'rpc_response_timeout'} < 180 ) {
            logResponse( 'PROP06', $locNovaConf, 'DEFAULT', 'rpc_response_timeout', $novaConf{'DEFAULT'}{'rpc_response_timeout'}, '180' );
        }
    }

    # Verify all SCSI disk operands are specified, if one exists.
    if ( exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} or exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'} ) {
        if ( !exists $novaConf{'DEFAULT'}{'zvm_fcp_list'} ) {
            logResponse( 'PROP07', $locNovaConf, 'DEFAULT', 'zvm_fcp_list' );
        }
        if ( !exists $novaConf{'DEFAULT'}{'zvm_zhcp_fcp_list'} ) {
            logResponse( 'PROP07', $locNovaConf, 'DEFAULT', 'zvm_fcp_list' );
        }
    }

    # Verify neutron.conf operands with a fixed set of possible values
    if ( exists $neutronConf{'DEFAULT'}{'core_plugin'} ) {
        if ( $neutronConf{'DEFAULT'}{'core_plugin'} eq 'neutron.plugins.ml2.plugin.Ml2Plugin' ) {
            logResponse( 'TRON01', $locNeutronConf, 'core_plugin', 'DEFAULT', $neutronConf{'DEFAULT'}{'core_plugin'}, 'ml2' );
        }
        elsif ( $neutronConf{'DEFAULT'}{'core_plugin'} ne 'ml2' ) {
            logResponse( 'TRON02', $locNeutronConf, 'core_plugin', 'DEFAULT', $neutronConf{'DEFAULT'}{'core_plugin'}. 'ml2' );
        }
    }

    # Verify any rdev_list in Neutron z/VM Plugin ini file contains a single value and/or not a comma
    foreach my $section (sort keys %neutronZvmPluginIni) {
        next if ( $section eq 'agent');
        foreach my $property ( keys %{ $neutronZvmPluginIni{$section} } ) {
            next if ( $property ne "rdev_list" );
            my $list = $neutronZvmPluginIni{$section}{$property};
            $list =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
            if ( $list eq '' ) {
                logResponse( 'PROP09', $locNeutronZvmPluginIni, $section, 'rdev_list' );
            } else {
                my @vals = split ( /\s/, $list );
                if ( $#vals > 0 ) {
                    # $#vals is array size - 1.
                    logResponse( 'PROP10', $locNeutronZvmPluginIni, $section, 'rdev_list' );
                }
                foreach my $op ( @vals ) {
                    if ( $op =~ m/[^0-9a-fA-F]+/ ) {
                        logResponse( 'PROP11', $locNeutronZvmPluginIni, $section, 'rdev_list', $op );
                    } elsif ( length($op) > 4 ) {
                        logResponse( 'PROP12', $locNeutronZvmPluginIni, $section, 'rdev_list', $op );
                    }
                }
            }
        }
    }

    # Check whether the storwize_svc_connection_protocol is not 'FC' for z/VM
    if ( exists $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'} ) {
        if ( $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'} ne 'FC' ) {
            logResponse( 'PROP08', $locCinderConf, 'DEFAULT', 'storwize_svc_connection_protocol', $cinderConf{'DEFAULT'}{'storwize_svc_connection_protocol'}, 'FC' );
        }
    }

    # Check whether the volume_driver is correct for z/VM
    if ( ! $bypassCinder and exists $cinderConf{'DEFAULT'}{'volume_driver'} ) {
        if ( $cinderConf{'DEFAULT'}{'volume_driver'} ne 'cinder.volume.drivers.ibm.storwize_svc.storwize_svc_fc.StorwizeSVCFCDriver' ) {
            logResponse( 'PROP08',
                         $locCinderConf,
                         'DEFAULT',
                         'volume_driver',
                         $cinderConf{'DEFAULT'}{'volume_driver'},
                         'cinder.volume.drivers.ibm.storwize_svc.storwize_svc_fc.StorwizeSVCFCDriver' );
        }
    }

    # Check that either flat_networks or network_vlan_ranges is specified.
    if ( !exists $ml2ConfIni{'ml2_type_flat'}{'flat_networks'} &&
         !exists $ml2ConfIni{'ml2_type_vlan'}{'network_vlan_ranges'} ) {
        logResponse( 'MISS08',
                     $locMl2ConfIni,
                     'ml2_type_flat(flat_networks), ml2_type_vlan(network_vlan_ranges)' );
    }

    return;
}


#*****************************************************************************
# Main routine
#*****************************************************************************
my $configOpt;
my $rc = 0;
my $ignoreOpt;
my $obfuscateOpt;
my $out;
my $scanInitOpt;

# Parse the arguments
$Getopt::Long::ignorecase = 0;
Getopt::Long::Configure( "bundling" );
if (!GetOptions(
                 'c|config=s'    => \$configOpt,
                 'd|driver=s'    => \$driver,
                 'h|help'        => \$displayHelp,
                 'H|host=s'      => \$host,
                 'i|init-files'  => \$scanInitOpt,
                 'ignore=s'      => \$ignoreOpt,
                 'p|password-visible'  => \$pwVisible,
                 's|scan=s'      => \$scan,
                 'v'             => \$versionOpt,
                 'V|verbose'     => \$verbose )) {
    print $usage_string;
    goto FINISH;
}

if ( $versionOpt ) {
    logResponse( 'GENERIC_RESPONSE', "Version: $version\n$supportString" );
}

if ( $displayHelp ) {
    showHelp();
}

if ( $displayHelp or $versionOpt ) {
    goto FINISH;
}

# Handle messages to ignore.
if ( defined( $ignoreOpt ) ) {
     if ( $verbose ) {
         logResponse( 'GENERIC_RESPONSE', "Operand --ignore $ignoreOpt" );
    }

    # Make hash from the specified ignore operands
    $ignoreOpt = uc( $ignoreOpt );
    my @ingoreList;
    if ( $ignoreOpt =~ ',' ) {
        @ingoreList = split( ',', $ignoreOpt );
    } else {
        @ingoreList = split( ' ', $ignoreOpt );
    }
    %msgsToIgnore = map { $_ => 1 } @ingoreList;

    # Convert general severity type operands to their numeric value.
    if ( $msgsToIgnore{'BYPASS'} ) {
        delete $msgsToIgnore{'BYPASS'};
        $msgsToIgnore{'2'} = 1;
    }
    if ( $msgsToIgnore{'INFO'} ) {
        delete $msgsToIgnore{'INFO'};
        $msgsToIgnore{'3'} = 1;
    }
    if ( $msgsToIgnore{'WARNING'} ) {
        delete $msgsToIgnore{'WARNING'};
        $msgsToIgnore{'4'} = 1;
    }
    if ( $msgsToIgnore{'ERROR'} ) {
        delete $msgsToIgnore{'ERROR'};
        $msgsToIgnore{'5'} = 1;
    }
}

# Determine the local IP address for this system.
my $errorLines = '';
my $hostname = hostname;
if ( $hostname ne '' ) {
    $localIpAddress = gethostbyname( $hostname );
    if ( defined $localIpAddress ) {
        my $len = length( $localIpAddress );
        if ( $len == 4 ) {
            $localIpAddress = inet_ntoa( $localIpAddress );
        } else {
            $localIpAddress = '';
            $errorLines = $errorLines . "         The IP address obtained from perl gethostbyname function does not\n" .
                                        "         appear to be an IPv4 address.  An IPv4 address should be used.\n";
        }
    } else {
        $errorLines = $errorLines . "         The IP address related to the following host name was not found:\n" .
                                    "             $hostname\n";
        if ( defined $? ) {
            $errorLines = $errorLines . "         The perl gethostbyname function failed with errno: $?\n";
        }
        $localIpAddress = '';
    }
} else {
    $errorLines = $errorLines . "         The host name was not found.\n";
}

if ( $localIpAddress eq '' ) {
    if ( $errorLines eq '' ) {
        logResponse( 'SYS01' );
    } else {
        logResponse( 'SYS01', "    Additional Information:\n$errorLines" );
    }
}

# Detect CMA
if ( -e $locVersionFileCMO ) {
    # CMA version file exists, treat this as a CMA node
    $cmaAppliance = 1;
    $cmaVersionString = `cat $locVersionFileCMO`;
    chomp( $cmaVersionString );
    if ( $cmaVersionString eq '' ) {
        $cmaVersionString = "version unknown";
    }

    # Determine the role of this CMA system
    my %settings;
    if ( -e $locApplSystemRole ) {
        $rc = hashFile( $locApplSystemRole, \%settings, 0 );
        if ( exists $settings{'role'} ) {
        $cmaSystemRole = uc( $settings{'role'} );
    }
    }
    if ( $cmaSystemRole eq '' and -e $locDMSSICMOCopy ) {
        $rc = hashFile( $locDMSSICMOCopy, \%settings, 0 );
        if ( exists $settings{'openstack_system_role'} ) {
            $cmaSystemRole = uc( $settings{'openstack_system_role'} );
        }
    }
    if ( $cmaSystemRole eq '' ) {
        $cmaSystemRole = 'unknown';
    }
}

if ( defined( $scan ) ) {
    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Operand --scan: $scan" );
    }
    if ( 'all cinder neutron nova' !~ $scan ) {
        logResponse( 'PARM02', '--scan', $scan, '\'all\', \'cinder\', \'neutron\' or \'nova\'' );
        $rc = 400;
        goto FINISH;
    }
} else {
    $scan = 'all';
}

if ( defined( $host ) ) {
    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Operand --Host: $host" );
    }
    $driverSuffix = "_$host";
    $initSuffix = "-$host";
} else {
    $host = '';
    $driverSuffix = "";
    $initSuffix = "";
}

if ( defined( $scanInitOpt ) ) {
    if ( $verbose ) {
        logResponse( 'GENERIC_RESPONSE', "Operand --initFiles" );
    }

    my $configFile = '';
    if ( $scan =~ 'all' or $scan =~ 'nova' ) {
        # Look for a System V startup script
        $configFile = scanInitScript( "$novaComputeStem$initSuffix", 'config'  );
        if ( $configFile eq '' ) {
            # Look for systemd unit files
            $configFile = scanServiceUnit( "$novaComputeStem$initSuffix.service", 'Service', 'ExecStart'  );
        }
        if ( $configFile ne '' ) {
            $locNovaConf = $configFile;
        } else {
            logResponse( 'FILE03', 'Nova' );
            $locNovaConf = '';
        }
    }

    if ( $scan =~ 'all' or $scan =~ 'ceilometer' ) {
        # Look for a System V startup script
        $configFile = scanInitScript( "$ceilometerStem$initSuffix", 'config' );
        if ( $configFile eq '' ) {
            # Look for systemd unit files
            $configFile = scanServiceUnit( "$ceilometerStem$initSuffix.service", 'Service', 'ExecStart'  );
        }
        if ( $configFile ne '' ) {
            $locCeilometerConf = $configFile;
        } else {
            logResponse( 'FILE03', 'Ceilometer' );
            $locCeilometerConf = '';
        }
    }

    if ( $scan =~ 'all' or $scan =~ 'cinder' ) {
        # Look for a System V startup script
        $configFile = scanInitScript( 'openstack-cinder-volume', 'config' );
        if ( $configFile eq '' ) {
            # Look for systemd unit files
            $configFile = scanServiceUnit( 'openstack-cinder-volume.service', 'Service', 'ExecStart'  );
        }
        if ( $configFile ne '' ) {
            $locCinderConf = $configFile;
        } else {
            logResponse( 'FILE03', 'Cinder' );
            $locCinderConf = '';
        }
    }

    if ( $scan =~ 'all' or $scan =~ 'neutron' ) {
        # Look for a System V startup script
        $configFile = scanInitScript( 'neutron-server', 'config' );
        if ( $configFile eq '' ) {
            # Look for systemd unit files
            $configFile = scanServiceUnit( 'neutron-server.service', 'Service', 'ExecStart'  );
        }
        if ( $configFile ne '' ) {
            $locNeutronConf = $configFile;
        } else {
            logResponse( 'FILE03', 'Neutron' );
            $locNeutronConf = '';
        }

        $configFile = scanInitScript( "$neutronZvmAgentStem$initSuffix", 'config' );
        if ( $configFile eq '' ) {
            # Look for systemd unit files
            $configFile = scanServiceUnit( "$neutronZvmAgentStem$initSuffix.service", 'Service', 'ExecStart'  );
        }
        if ( $configFile ne '' ) {
            $locNeutronZvmPluginIni = $configFile;
        } else {
            logResponse( 'FILE04', 'Neutron', 'z/VM agent' );
            $locNeutronZvmPluginIni = '';
        }

        $configFile = scanInitScript( "$neutronZvmAgentStem$initSuffix", 'plugin_config' );
        if ( $configFile eq '' ) {
            # Look for systemd unit files
            $configFile = scanServiceUnit( "$neutronZvmAgentStem$initSuffix.service", 'Service', 'ExecStart'  );
        }
        if ( $configFile ne '' ) {
            $locMl2ConfIni = $configFile;
        } else {
            logResponse( 'FILE04', 'Neutron', 'ml2 plugin' );
            $locMl2ConfIni = '';
        }
    }
}

if ( defined( $configOpt ) ) {
     if ( $verbose ) {
         logResponse( 'GENERIC_RESPONSE', "Operand --config $configOpt" );
    }

    my @items = split( ',', $configOpt );
    foreach my $item ( @items ) {
        my @parts = split( ':', $item );
        if ( defined $parts[1] ) {
            $parts[0] =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
        }
        if ( defined $parts[1] ) {
            $parts[1] =~ s/^\s+|\s+$//g;         # trim blanks from both ends of the list
        }

        if ( !defined $parts[1] or $parts[1] eq '' ) {
            logResponse( 'PARM01', $parts[0] );
            next;
        }

        if (      $parts[0] eq $EyeCeilometerConf ) {
            $locCeilometerConf =  $parts[1];
        } elsif ( $parts[0] eq $EyeCinderConf ) {
            $locCinderConf =  $parts[1];
        } elsif ( $parts[0] eq $EyeMl2ConfIni ) {
            $locMl2ConfIni = $parts[1];
        } elsif ( $parts[0] eq $EyeNeutronConf ) {
            $locNeutronConf = $parts[1];
        } elsif ( $parts[0] eq $EyeNeutronZvmPluginIni ) {
            $locNeutronZvmPluginIni = $parts[1];
        } elsif ( $parts[0] eq $EyeNovaConf ) {
            $locNovaConf = $parts[1];
        }
    }
}

my ( $volume, $directory, $file ) = '';
if ( defined( $driver ) ) {
    if ( $verbose ) {
      logResponse( 'GENERIC_RESPONSE', "Operand --driver: $driver" );
    }

    my @dirs;
    if ( -d $driver ) {
        # Driver operand is a directory name only
        ( $volume, $directory, $file ) = File::Spec->splitpath( $driver, 1 );
        $driver = File::Spec->catpath( $volume, $directory, "$driverPrefix$localIpAddress$driverSuffix.sh" );
    } else {
        # Driver operand is a bad directory or a file in a directory
        ( $volume, $directory, $file ) = File::Spec->splitpath( $driver );
        if ( -d $directory ) {
            $driver = File::Spec->catpath( $volume, $directory, $file );
        } else {
            logResponse( 'DRIV03', $directory );
            $rc = 500;
            goto FINISH;
        }
    }
} else {
    $directory = File::Spec->curdir();
    $driver = File::Spec->catpath( $volume, $directory, "$driverPrefix$localIpAddress$driverSuffix.sh" );
}

# Validate CMA related information
if ( $cmaSystemRole ne '' ) {
    my %cmaRoles = ( 'CONTROLLER'=>1, 'COMPUTE'=>1, 'COMPUTE_MN'=>1, 'MN'=>1, 'ZHCP'=>1 );
    # Validate Controller related information
    if ( ! exists $cmaRoles{$cmaSystemRole} ) {
        my @k = keys %cmaRoles;
        my $keyNames = join( ', ', @k );
        logResponse( 'ROLE02', $cmaSystemRole, $keyNames );
        $rc = 503;
        # Allow other processing to continue
    }
}

# Scan the configuration files.
if ( $scan =~ 'all' or $scan =~ 'nova' ) {
    scanNova();
}

if ( $scan =~ 'all' or $scan =~ 'ceilometer' ) {
    scanCeilometer();
}

if ( $scan =~ 'all' or $scan =~ 'cinder' ) {
    scanCinder();
}

if ( $scan =~ 'all' or $scan =~ 'neutron' ) {
    scanNeutron();
}

# Validate the settings and produce the driver script.
if ( ! $configFound ) {
    logResponse( 'MISS06' );
    $rc = 501;
    # Allow other processing to continue
}

!( $rc = validateConfigs() ) or goto FINISH;

!( $rc = buildDriverProgram() ) or goto FINISH;

FINISH:

if ( !$displayHelp and !$versionOpt ) {
    # Produce summary messages.
    logResponse( 'BLANK_LINE' );
    logResponse( 'GENERIC_RESPONSE', "$infoCnt info or bypass messages were generated." );
    logResponse( 'GENERIC_RESPONSE', "$warnErrCnt warnings or errors were generated." );
    if ( $ignoreCnt != 0 ){
        logResponse( 'GENERIC_RESPONSE', "Ignored messages $ignoreCnt times." );
        my @ignoreArray = sort keys %ignored;
        my $ignoreList = join ( ', ', @ignoreArray );
        logResponse( 'GENERIC_RESPONSE', "Message Ids of ignored messages: $ignoreList" );
    }
}

exit $rc;

