#!/usr/bin/python
"""
Usage:
    softlayer_storage.py --type=<type> [--hostname=<hostname> --username=<username> --password=<password> --mountpoint=<mountpoint> ] (mount | unmount)
    softlayer_storage.py --type=<type> [options] (mount | unmount)

Options:
    -h --help                  Show help screen
    --version                  Show version
    --type=<type>              Type of File Storage to mount ( consistent | nas ) 
    --hostname=<hostname>      SoftLayer Storage hostname
    --username=<username>      SoftLayer Storage LUN username 
    --password=<password>      SoftLayer Storage LUN password
    --mountpoint=<mountpoint>  The mountpoint to use [default: /mnt/nas]

Description:
    For consistent performance file storate, make sure the host accessing the 
    file storage has been authorized through the SoftLayer portal.
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

def mount_nas_storage(hostname, user, passwd, mountPoint): 
    print "Attempting to mount the NAS File Storage at %s" %(mountPoint)

    if xcatutils.isMounted(mountPoint):
        raise xcatutils.xCatError("The mount point %s is already in use." %(mountPoint))

    cmd = "mount -t cifs //%s/%s -o username=%s,password=%s,rw,nounix,iocharset=utf8,file_mode=0644,dir_mode=0755 %s" %(hostname, user, user, passwd, mountPoint)
    out,err = xcatutils.run_command(cmd)
    if err: 
        raise xcatutils.xCatError("Error when mounting. (%s)" %(err))
    else: 
        print "Success\n"

    # To help out with automount, print this msg 
    print "\nNote: To configure automount on reboot, add the following into /etc/fstab:"
    cmd = "//%s/%s   %s cifs defaults,username=%s,password=%s 0 0" %(hostname,user,mountPoint,user,passwd)
    print "%s\n" %(cmd)

def mount_consistent_storage(hostname, user, mountPoint): 
    print "Attempting to mount the Consistent Performance File Storage at %s" %(mountPoint)

    if xcatutils.isMounted(mountPoint):
        raise xcatutils.xCatError("The mount point %s is already in use." %(mountPoint))

    cmd = "mount -t nfs4 %s:/%s %s" %(hostname, user, mountPoint)
    out,err = xcatutils.run_command(cmd)
    if err: 
        raise xcatutils.xCatError("Error when mounting. (%s)" %(err))
    else: 
        print "Success\n"

def unmount_storage(mountPoint):
    print "Attempting to unmount the NAS at %s..." %(mountPoint)

    if not xcatutils.isMounted(mountPoint):
        raise xcatutils.xCatError("The mount point %s is NOT mounted." %(mountPoint))
    else: 
        cmd = "umount %s" %(mountPoint)
        out,err = xcatutils.run_command(cmd)

        if err: 
            print "Encountered error while unmounting..."
            print err


def setup_softlayer_storage(): 
    # 
    # set code defaults to consistent file storage options 
    # 
    requirePassword=False
    preReqPackages = ['nfs-utils','nfs-utils-lib']

    #
    # if NAS is selected as the type, override the code defaults 
    #
    if 'nas' in arguments['--type']:
        requirePassword=True
        preReqPackages = ['cifs-utils']

    #
    # verify information before starting 
    #
    if arguments['--hostname'] is None: 
        arguments['--hostname'] = xcatutils.getUserInput("Enter the SoftLayer storage hostname")

    if arguments['--username'] is None: 
        arguments['--username'] = xcatutils.getUserInput("Enter the SoftLayer storage username")

    if arguments['--password'] is None and requirePassword:
        arguments['--password'] = xcatutils.getUserInput("Enter the SoftLayer storage password")

    #
    # install prereqs
    #
    print "Checking for installed packages: %s" %(preReqPackages)
    xcatutils.installPackages(preReqPackages)

    #
    # mount the file storage 
    #
    if 'nas' in arguments['--type']:
        mount_nas_storage(arguments['--hostname'],arguments['--username'],arguments['--password'],arguments['--mountpoint'])
    elif 'consistent' in arguments['--type']:
        mount_consistent_storage(arguments['--hostname'],arguments['--username'],arguments['--mountpoint'])



if __name__ == '__main__':
    try:
        arguments = (docopt.docopt(__doc__, version="1.0")) 

        if not arguments['--type'] in ('nas', 'consistent'):
            raise xcatutils.xCatError("The type=%s is not a supported file system type." %(arguments['--type']))
            
        if arguments['unmount']:
            unmount_storage(arguments['--mountpoint'])
        else:
            setup_softlayer_storage()

    except docopt.DocoptExit as e:
        print e
    except xcatutils.xCatError as e:
        print "xCatError: %s" %(e) 
