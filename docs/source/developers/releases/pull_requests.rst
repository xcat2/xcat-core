Pull Requests and Backports
===========================

Open every change against ``master``. A fix reaches a maintenance branch as a backport of the
merged ``master`` pull request.

Labels and Milestones
---------------------

Set a label and a milestone on each pull request against ``master``. The milestone is the first
release that contains the change.

.. list-table::
   :header-rows: 1
   :widths: 50 20 30

   * - Change
     - Label
     - Milestone
   * - A fix that users of the maintained series need: a regression, a failure on a supported
       platform, a security fix, or a change that the maintenance branch needs to build or test
     - ``backport X.Y``
     - the next release of the series, for example ``2.19.1``
   * - Any other change: a feature, a refactor, a change to tests only, documentation, or a fix
       for an old or high-risk problem
     - none
     - the next minor release, for example ``2.20``

Do not add a backport label to a change of the ``Version`` file.

When a patch release ships, the next patch milestone replaces it. After 2.19.1, the milestone for
backported fixes is ``2.19.2``.

Automatic Backports
-------------------

The ``backport`` workflow in ``.github/workflows/backport.yml`` starts when a pull request with a
``backport X.Y`` label is merged. It also starts when the label is added to a pull request that is
already merged. The workflow:

#. cherry-picks the commits of the pull request onto the ``X.Y`` branch,
#. opens a pull request named ``[Backport X.Y] <original title>``,
#. approves that pull request and turns on auto-merge.

The backport pull request merges when ``xcat_pr_test`` passes. Do not set a milestone on it. The
milestone stays on the original pull request.

Manual Backports
----------------

If the cherry-pick has a conflict, the workflow fails and comments on the original pull request.
Then do the backport by hand from your fork: ::

    $ git fetch upstream
    $ git switch -c backport-<number>-to-X.Y upstream/X.Y
    $ git cherry-pick -x <commit> ...
    $ git push origin backport-<number>-to-X.Y

Resolve each conflict before you continue the cherry-pick. Open a pull request against ``X.Y``
named ``[Backport X.Y] <original title>``, and set the patch release milestone on it.

The ``release-branches`` ruleset protects each maintenance branch in the same way as ``master``.
A change needs a pull request, an approval and a passing ``xcat_pr_test``, and the branch refuses
direct pushes.
