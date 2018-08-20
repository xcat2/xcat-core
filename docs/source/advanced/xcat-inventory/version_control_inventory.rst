Manage the xCAT Cluster Definition under Source Control
=======================================================

The xCAT cluster inventory data, including global configuration and object definitions(node/osimage/passwd/policy/network/router), and the relationship of the objects, can be exported to a YAML/JSON file(**inventory file**) from xCAT Database, or be imported to xCAT Database from the inventory file.

By managing the inventory file under source control system, you can manage the xCAT cluster definition under source control. This section presents a typical step-by-step scenario on how to manage cluster inventory data under ``git``.


1. create a directory ``/git/cluster`` under git directory to hold the cluster inventory ::

    mkdir -p /git/cluster
    cd /git/cluster
    git init

2. export the current cluster configuration to a inventory file "mycluster.yaml" under the git directory created above ::

    xcat-inventory export --format=yaml >/git/cluster/mycluster.yaml

3. check diff and commit the cluster inventory file(commit no: c95673) ::

    cd /git/cluster
    git diff
    git add /git/cluster/mycluster.yaml
    git commit /git/cluster/mycluster.yaml -m "$(date "+%Y_%m_%d_%H_%M_%S"): initial cluster inventory data; blah-blah"

4. ordinary cluster maintenance and operation: replaced bad nodes, turn on xcatdebugmode...

5. cluster setup is stable now, export and commit the cluster configuration(commit no: c95673) ::

    xcat-inventory export --format=yaml >/git/cluster/mycluster.yaml
    cd /git/cluster
    git diff
    git add /git/cluster/mycluster.yaml
    git commit /git/cluster/mycluster.yaml -m "$(date "+%Y_%m_%d_%H_%M_%S"): replaced bad nodes; turn on xcatdebugmode; blah-blah"

6. ordinary cluster maintenance and operation, some issues are founded in current cluster, need to restore the current cluster configuration to commit no c95673 [1]_ ::

    cd /git/cluster
    git checkout c95673
    xcat-inventory import -f /git/cluster/mycluster.yaml

*Notice:*

1. The cluster inventory data exported by ``xcat-inventory`` does not include intermidiate data, transiate data and historical data in xCAT DataBase, such as node status, auditlog table

2.  We suggest you backup your xCAT database by ``dumpxCATdb`` before your trial on this feature, although we have run sufficient test on this

.. [1] When you import the inventory data to xCAT Database in step 6, there are 2 modes: ``clean mode`` and ``update mode``. If you choose the ``clean mode`` by ``xcat-inventory import -c|--clean``, all the objects definitions that are not included in the inventory file will be removed; Otherwise, only the objects included in the inventory file will be updated or inserted. Please choose the proper mode according to your need


