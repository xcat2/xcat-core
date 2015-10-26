Changing Code
=============

Checkout Branch
---------------

Checkout and switch to the branch using ``git checkout -b`` ::

        $ git checkout -b mybranch origin/mybranch
        Branch mybranch set up to track remote branch mybranch from origin.
        Switched to a new branch 'mybranch'


Changing the code
-----------------

Now you are ready to make changes related to your function in this branch 

Multiple Remote Branches
^^^^^^^^^^^^^^^^^^^^^^^^

It may take days before your pull request is properly reviewed and you want to keep changes out of that branch so in the event that you are asked to fix something, you can push directly to the branch with the active pull request.  

Creating additional branches will allow you to work on different tasks/enhancements at the same time.  You can easily manage your working changes between branches with ``git stash.``.


Commiting code and pushing to remote branch
-------------------------------------------

Once your code is ready....

#. Commit the code to your local branch: ::

        $ git add <files> 
        $ git commit | git commit -m "<comments>"

#. Push the changes to your remote branch: ::

        $ git push origin <branch name>

