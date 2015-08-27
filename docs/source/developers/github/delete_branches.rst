Deleting Branches
=================

From Command Line
-----------------

Switch off the branch that you want to delete. Most of the time, switching to master will allow you to delete a working branch: ::

        $ git checkout master
        $ git branch -D mybranch

Delete the remote branch off GitHub: ::

        $ git push origin --delete mybranch
        Enter passphrase for key '/home/vhu/.ssh/github/id_rsa': 
        To git@github.com:whowutwut/xcat-doc.git
         - [deleted]         mybranch

Verify branch is gone: ::

        $ git branch -r
          origin/HEAD -> origin/master
          origin/large_cluster
          origin/master
          origin/sync
          upstream/master



Sync up GitHub and Local Machine
--------------------------------

There are times when you delete the branch off your local machine or from GitHub and it's become out of sync, you sync up the list, run the following: ::

        git remote prune origin 
