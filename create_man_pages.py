#!/usr/bin/env python
#TODO: Delete the old files to support removing a man page

import glob
import os
import sys
import subprocess
from glob import glob
import shutil

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

#
# add the following to delete the generate files before creating them
# essentially this allows us to remove man pages and they will be 
# removed in the generation
print "Cleaning up the generated man pages in %s" %(MANPAGE_DEST)
allfiles = glob("%s*/*.rst" %(MANPAGE_DEST))
for d in allfiles: 
    # Skip over the index.rst file 
    if not "index.rst" in d: 
        print "Removing file %s" %(d)
        os.remove(d)

# The database man pages are created in the perl-xCAT subdirectory
# using the db2man script
def build_db_man_pages():
    thepwd = os.getcwd()
    os.chdir("perl-xCAT")
    cmd = "./db2man"
    os.system(cmd)
    os.chdir(thepwd)

def cleanup_db_man_pages_dir():
    shutil.rmtree("perl-xCAT/pods")
    shutil.rmtree("perl-xCAT/share")

def fix_vertical_bar(rst_file):
    # Verical bar can not appear with spaces around it, otherwise
    # it gets displayed as a link in .html
    sed_cmd = "sed 's/\*\*\\\ |\\\ \*\*/ | /g' %s > %s.sed1" %(rst_file, rst_file)
    os.system(sed_cmd)

def fix_double_dash(rst_file):
    # -- gets displayed in .html as a sinle long dash, need to insert
    # a non bold space between 2 dashes
    sed_cmd = "sed '/\*\*/s/--/-\*\*\\\ \*\*-/g' %s.sed1 > %s" %(rst_file, rst_file)
    os.system(sed_cmd)
    #remove intermediate .sed1 file
    rm_sed1file_cmd = "rm %s.sed1" %(rst_file)
    os.system(rm_sed1file_cmd)   

build_db_man_pages()

# List the xCAT component directory which contain pod pages
COMPONENTS = ['xCAT-SoftLayer', 'xCAT-test', 'xCAT-client', 'xCAT-vlan', 'perl-xCAT', 'xCAT-buildkit']

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

                DESTINATION = "%s%s" %(MANPAGE_DEST, man_ver)
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
		if man_ver == '1' or man_ver == '8':
                    fix_vertical_bar(rst_output)
                    fix_double_dash(rst_output)

cleanup_db_man_pages_dir()

