Syncing a Fork
==============

**Note:** *The examples below all reference the master branch*

Before the Syncing
------------------

References: https://help.github.com/articles/syncing-a-fork/

From time to time, your master branch will start to **fall behind** the upstream/master because changes are being pulled into the `xcat2/xcat-core`` project from other developers. 

.. image:: github-behind_master.png

Update the **master branch** of your forked copy from xcat2/xcat-core
---------------------------------------------------------------------

#. Pull the ahead commits from the ``upstream master`` to your local master branch. ::

    $ git pull upstream master
    remote: Counting objects: 38, done.
    remote: Compressing objects: 100% (15/15), done.
    remote: Total 38 (delta 14), reused 9 (delta 9), pack-reused 14
    Unpacking objects: 100% (38/38), done.
    From github.com:xcat2/xcat-core
     * branch            master     -> FETCH_HEAD
       8f0cb07..d0651b5  master     -> upstream/master
    Updating 8f0cb07..d0651b5
    Fast-forward
    ...

#. Push the commits from your local master to your forked copy in GitHub: ::

    $ git push origin master

After the Syncing
-----------------

Your fork master branch should now be **even** with ``xcat2/xcat-core``

.. image:: github-even_with_master.png 





