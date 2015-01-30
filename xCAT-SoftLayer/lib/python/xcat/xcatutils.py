

import sys
import os
import platform

class xCatError(Exception):
    def __init__(self, value):
        self.value = value
    def __str__(self):
        return repr(self.value)

def isMounted(mountPoint): 
    if os.path.ismount(mountPoint): 
        return True
    else:
        return False

def run_command(cmd):
    """
    Function: run_command
    Arguments: cmd - string to be run as a command
    Description: runs the command then returns out and err
    """
    import subprocess

    p = subprocess.Popen(cmd, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, close_fds=True)
    (out,err) = p.communicate()
    return (out,err)


def isRhel():
    myDistro = platform.linux_distribution()
    if "Red Hat Enterprise Linux Server" or "CentOS" in myDistro:
       return True
    else: 
       return False

def isSles(): 
    myDistro = platform.linux_distribution()
    if "SUSE Linux Enterprise Server" in myDistro:
       return True
    else: 
       return False

def isUbuntu():
    myDistro = platform.linux_distribution()
    if "Ubuntu" in myDistro:
       return True
    else: 
       return False

def getUserInput(question):
    response = raw_input("%s: " %(question))
    return response

def filterInstalledPackages(pkglist=[]):
    fulllist = "" 

    if isRhel():
        # using YUM
        import yum 
        yb = yum.YumBase()

        for x in pkglist:
            if not yb.rpmdb.searchNevra(name='%s' %(x)):
                fulllist += "%s " %(x) 
   
    return fulllist
 
def installPackages(pkglist=[]):
    fulllist = filterInstalledPackages(pkglist)

    if isRhel():
        if fulllist.strip() != "": 
            cmd = "yum -y install %s" %(fulllist)
            out,err = xcatutils.run_command(cmd)

    elif isSles(): 
        print "Using zyppr..."
    elif isUbuntu():
        print "Using apt-get..."
    else:
        print "Error!" 

