#!/bin/bash
# This script is used by the xdcp MERGE: function to perform the
# merge operation on the nodes for the /etc/passwd, /etc/shadow and 
# and /etc/group files. These are the only supported files for merge.
# The MERGE function is also only supported on Linux.
#First parameter is nodesyncfiledir
#The next parameter is the MERGE clause put in the following format   
#mergefile1:currfile1 mergefile2:currfile2.....
#For example:
#/tmp/myusers:/etc/passwd /tmp/mypasswds:/etc/shadow /tmp/mygrps:/etc/group
#

# Check for Linux, AIX not supported 

if [ "$(uname -s)" != "Linux" ]; then
  logger -t xcat -p local4.err "Merge: xdcp merge is only supported on Linux" 
  exit 1
fi
#this is the base path to the merge directory
nodesyncfiledir=$1
#this is the backup copy of the original current file 
nodesyncfiledirorg="$nodesyncfiledir/org"
#this is the path to merge working files
nodesyncfiledirmerge="$nodesyncfiledir/merge"
#this is the path to the files containing the merge data
nodesynfiledirmergefiles="$nodesyncfiledir/merge/mergefiles"
skip=0
# for each input parameter
for i in $*; do
  # skip first parm
  if [ $skip -eq 0 ]; then
    skip=1
    continue
  fi
  # get the merge file path and name, for example /tmp/myusers
  mergefilename=`echo "$i"|cut -d ':' -f 1`
  # get location on the node
  mergefile="$nodesynfiledirmergefiles$mergefilename"
  # get the file path and name to merge into, for example /etc/passwd
  curfile=`echo "$i"|cut -d ':' -f 2`

  # if curfile not /etc/passwd  or /etc/shadow or /etc/group 
  # exit error
  #if [ "$curfile" != "/etc/passwd" ] && [ "$curfile" != "/etc/shadow" ] && [ "$curfile" != "/etc/group" ]; then
  #  logger -t xcat -p local4.err "Merge: $curfile is not /etc/passwd or /etc/shadow or /etc/group. It cannot be processes." 
  #   exit 1
  #fi 
  # get the directory to backup the original file  
  curfiledir=`dirname $curfile`
  curfilename=`basename $curfile`
  filebackupdir="$nodesyncfiledirorg$curfiledir"
  # name of the path to the backup of original file
  filebackup="$nodesyncfiledirorg$curfile"
  # now do the work
  # make the necessary directories
  mkdir -p $filebackupdir 
  # copy current to  backup 
  cp -p $curfile $filebackup

  # Go though the backup copy and remove duplicate lines that  are
  # in the merge file and create a new backup 
  # first get a list of  duplicate lines to remove 
  # based on only username:  the first field in the file
 cut -d: -f1 $filebackup > $filebackup.userlist
 cut -d: -f1 $mergefile > $mergefile.userlist
  comm -12 <(sort $filebackup.userlist | uniq) <(sort $mergefile.userlist | uniq) > $filebackup.remove
 
  # now if there is a remove file,  use it to remove the dup lines in backup 
  # Need to buit a command like the following with all users 
  #grep -v -E ^(root|bin|...) $filebackup > $filebackup.nodups 
  if [ -s "$filebackup.remove" ]; then
    grepcmd="grep -v -E " 
    removeusers=`cat $filebackup.remove`
    startlist="'^("
    userlist=$startlist
    delim="|"
    for u in $removeusers
    do
      userlist=$userlist$u$delim
    done
    # remove the last delimiter
    userlisttmp="${userlist%?}"
    listend=")'"
    userlist=$userlisttmp$listend
    grepcmd=$grepcmd$userlist
    #set -x
    grepcmd="$grepcmd $filebackup > $filebackup.nodups"
    #echo "grepcmd=$grepcmd"
    # now run it
    eval $grepcmd
    # if no dups file created
    if [ -s "$filebackup.nodups" ]; then
      cp -p $filebackup.nodups $filebackup
      #echo "cp -p $filebackup.nodups $filebackup" 
      rm $filebackup.nodups
    fi 
  fi 
  # Now update the currentfile  
  cat $filebackup $mergefile > $curfile
  #echo "cat $filebackup $mergefile > $curfile"
  # now cleanup
  rm $filebackup.userlist 
  #  echo "rm $filebackup.userlist"
  rm $filebackup.remove 
  #  echo "rm $filebackup.remove"
  rm $mergefile.userlist 
  #  echo "rm $mergefile.userlist"
   
done
exit 0
