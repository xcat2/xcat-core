#!/usr/bin/python
"""
Usage:
    softlayer_nas.py [--verbose --hostname=<hostname> --username=<username> --password=<password> --mountpoint=<mountpoint> ] (mount | unmount)
    softlayer_nas.py [OPTIONS] (mount | unmount)

Options:
    -h --help                  Show help screen
    --version                  Show version
    --verbose                  Print verbose information
    --hostname=<hostname>      SoftLayer Storage hostname
    --username=<username>      SoftLayer Storage LUN username 
    --password=<password>      SoftLayer Storage LUN password
    --mountpoint=<mountpoint>  The mountpoint to use [default: /mnt/nas]
"""
import os
import sys
import docopt

path = os.path.dirname(os.path.realpath(__file__))
path = os.path.realpath(os.path.join(path, '..', 'lib', 'python'))
if path.startswith('/opt'):
    # if installed into system path, do not muck with things
    sys.path.append(path)

from xcat import xcatutils

def mount_nas(hostname, user, passwd, mountPoint): 
    print "Attempting to mount the NAS at %s" %(mountPoint)

    if xcatutils.isMounted(mountPoint):
        raise xcatutils.xCatError("The mount point %s is already in use." %(mountPoint))
 

    cmd = "mount -t cifs //%s/%s -o username=%s,password=%s,rw,nounix,iocharset=utf8,file_mode=0644,dir_mode=0755 %s" %(hostname, user, user, passwd, mountPoint)
    out,err = xcatutils.run_command(cmd)

def unmount_nas(mountPoint):
    print "Attempting to unmount the NAS at %s..." %(mountPoint)

    if not xcatutils.isMounted(mountPoint):
        raise xcatutils.xCatError("The mount point %s is NOT mounted." %(mountPoint))
    else: 
        cmd = "umount %s" %(mountPoint)
        out,err = xcatutils.run_command(cmd)

        if err: 
            print "Encountered error while unmounting..."
            print err


def configure_nas_automount(hostname, user, passwd, mountPoint): 
    print "\nNote: To configure automount on reboot, add the following into /etc/fstab:"
    cmd = "//%s/%s   %s cifs defaults,username=%s,password=%s 0 0" %(hostname,user,mountPoint,user,passwd)
    print "%s\n" %(cmd)

def setup_softlayer_nas(): 
    # verify information before starting 
    if arguments['--hostname'] is None: 
        arguments['--hostname'] = xcatutils.getUserInput("Enter the SoftLayer storage hostname")

    if arguments['--username'] is None: 
        arguments['--username'] = xcatutils.getUserInput("Enter the SoftLayer storage username")

    if arguments['--password'] is None: 
        arguments['--password'] = xcatutils.getUserInput("Enter the SoftLayer storage password")

    # install prereqs
    preReqPackages = ['cifs-utils']
    if arguments['--verbose']:
        print "Checking for installed packages: %s" %(preReqPackages)
    xcatutils.installPackages(preReqPackages)

    # mount the NAS
    mount_nas(arguments['--hostname'],arguments['--username'],arguments['--password'],arguments['--mountpoint'])

    configure_nas_automount(arguments['--hostname'],arguments['--username'],arguments['--password'],arguments['--mountpoint'])


if __name__ == '__main__':
    try:
        arguments = (docopt.docopt(__doc__, version="1.0")) 

        if arguments['unmount']:
            unmount_nas(arguments['--mountpoint'])
        else:
            setup_softlayer_nas()

    except docopt.DocoptExit as e:
        print e
    except xcatutils.xCatError as e:
        print "xCatError: %s" %(e) 
