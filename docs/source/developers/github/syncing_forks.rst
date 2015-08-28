Syncing a Fork
==============

**Note:** *The examples below all reference the master branch*

References: https://help.github.com/articles/syncing-a-fork/

From time to time, your master branch will start to fall behind the upstream/master because changes are being pulled into the `xcat2/xcat-core`` project from other developers. 

.. image:: github-behind_master.png

Use the following steps to sync up your forked copy: 

Fetching commits from upstream to your local
--------------------------------------------

#. Fetch the upstream changes for the master branch.  (changed are stored in a local branch: ``upstream/master``) ::

      $ git fetch upstream
      Enter passphrase for key '/home/vhu/.ssh/github/id_rsa': 
      From github.com:xcat2/xcat-core
       * [new branch]      master     -> upstream/master

 
#. Switch to your master branch and merge from upstream/master: ::

      $ git checkout master
      Switched to branch 'master'
      
      $ git merge upstream/master
      Updating a24d02f..f531ff8
      Fast-forward
      ...
     
Pushing the merged changes from your local to your remote fork
--------------------------------------------------------------

The following is needed to push the changes that you merged from upstream into your local clone on your development machine to the remote GitHub repository.

#. Sync the changes in your master branch to GitHub: ::

      $ git push origin master


Your fork master branch should now be even with ``xcat2/xcat-core``

.. image:: github-even_with_master.png 





