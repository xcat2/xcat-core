#!/usr/bin/env python
#TODO: Delete the old files to support removing a man page

import glob
import os
import sys
import subprocess

from optparse import OptionParser

usage = "usage: %prog [options]"

parser = OptionParser(usage=usage)
parser.add_option("--prefix", dest="PREFIX", help="Specify the location of the Perl modules")

(options, args) = parser.parse_args()

POD2RST="pod2rst"

def cmd_exists(cmd):
    return subprocess.call("type " + cmd, shell=True, 
        stdout=subprocess.PIPE, stderr=subprocess.PIPE) == 0

prefix_path = None
prefix_lib_path = None

if options.PREFIX: 
    if '~' in options.PREFIX:
        # else assume full path is provided 
        prefix_path = os.path.expanduser(options.PREFIX)
    else:
        prefix_path = options.PREFIX

    if not cmd_exists("%s/bin/pod2rst" %(prefix_path)):
        print "ERROR, %s requires pod2rst, not found in %s/bin/" %(os.path.basename(__file__), prefix_path)
        parser.print_help()
        sys.exit(1)

    prefix_lib_path = "%s/lib" %(prefix_path)
    if not os.path.isdir(prefix_lib_path): 
        prefix_lib_path = "%s/lib64" %(prefix_path)
        if not os.path.isdir(prefix_lib_path):
            print "ERROR, Cannot find the Perl lib directory in %s/lib or %s/lib64" %(prefix_path, prefix_path)
            sys.exit(1)

else: 
    if not cmd_exists(POD2RST):
        print "ERROR, %s requires pod2rst to continue!" %(os.path.basename(__file__))
        parser.print_help()
        sys.exit(1)


# the location relativate to xcat-core where the man pages will go
MANPAGE_DEST="./docs/source/guides/admin-guides/references/man"

# List the xCAT component directory which contain pod pages
COMPONENTS = ['xCAT-SoftLayer', 'xCAT-test', 'xCAT-client', 'xCAT-vlan']

for component in COMPONENTS: 
    for root,dirs,files in os.walk("%s" %(component)):

        for file in files:
            # only interested in .pod files 
            if file.endswith(".pod"):
                pod_input = os.path.join(root,file)

                filename = os.path.basename(pod_input)
                # get the man version (1,3,5,8,etc)
                man_ver = filename.split('.')[1]
                # title is needed to pass to pod2rst
                title = filename.split('.')[0]

                #
                # Wanted to have DESTINATION contain the man version,
                # but we currently have man1,man3,man5,man8, etc in 
                # the .gitignore file.  Need to fix Ubuntu builds
                #
		# DESTINATION = "%s%s" %(MANPAGE_DEST, man_ver)
                #
                DESTINATION = "%s" %(MANPAGE_DEST)
                try:
                    os.stat(DESTINATION)
                except:
                    # Create the directory if it does not exist
                    os.mkdir(DESTINATION)

                outputFile = filename.replace("pod", "rst")
                rst_output = "%s/%s" %(DESTINATION, outputFile)

                # generate the pod2rst command
                cmd = "%s" %(POD2RST)
                if options.PREFIX:
                    cmd = "perl -I %s/share/perl5 %s/bin/%s " %(prefix_path, prefix_path, POD2RST)

                cmd += " --infile=%s --outfile=%s --title=%s.%s" %(pod_input, rst_output, title, man_ver)
                print cmd 
                os.system(cmd)
