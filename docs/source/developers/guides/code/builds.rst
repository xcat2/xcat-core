Building Source Code
====================

xcat-core
---------

Clone the xCAT project from `GitHub <https://github.com/xcat2/xcat-core>`_::

    cd xcat-core
    ./buildcore.sh

To build the source rpms and no binary rpms, set ``SRCONLY``::

    cd xcat-core
    ./buildcore.sh SRCONLY=1

A source rpm is the input that a build service such as mock, koji, COPR or OBS
takes, and it lets one machine make the source rpms while another makes the
binary rpms for each architecture. ``rpmbuild`` does not need the packages named
in ``BuildRequires`` to make a source rpm, so this also builds on a machine that
cannot complete a full build. ``SRCONLY`` is not supported on AIX.

``buildcore.sh`` builds the architecture specific packages (``xCAT``, ``xCATsn``,
``xCAT-genesis-scripts``) for every supported architecture, riscv64 included, with
``rpmbuild --target``. The build host therefore needs an rpm that knows the riscv64
architecture and the ``Recommends:`` tag (EL8 or later); an older host fails the riscv64
builds and, as the script only publishes when every architecture built, produces no rpms.

xcat-deps
---------

The ``xcat-deps`` package is currently owned and maintained by the core development on our internal servers. Use the packages created at: http://xcat.org/download.html#xcat-dep


man pages
---------

The xCAT man pages are written in Perl POD files and automatically get built into the xCAT rpms.  The content in the .pod files are always the master.

In the past, the man pages were converted into html files and uploaded to SourceForge.  In moving to `ReadTheDocs <http://xcat-docs.readthedocs.org>`_ we want to also provide the man pages as references in the documentation.  To convert the ``pods`` to ``rst``, we are using The Perl module: `pod2rst <http://search.cpan.org/~dowens/Pod-POM-View-Restructured-0.02/bin/pod2rst>`_.

The following steps will help configure ``pod2rst`` and be able to generate the changes .rst files to push to GitHub.

#. Download the following Perl modules:

    - `Pod-POM-View-Restructured-0.02 <http://search.cpan.org/~dowens/Pod-POM-View-Restructured-0.02/lib/Pod/POM/View/Restructured.pm>`_
    - `Pod-POM-2.00 <http://search.cpan.org/~neilb/Pod-POM-2.00/lib/Pod/POM.pm>`_

#. For each of the above Perl modules:

    * **[as root]** Extract and build the Perl module ::

        perl Makefile.PL
        make
        make install

    * **[as non-root]** Extract and build the Perl module using PREFIX to specify a directory that you have write permission ::

        mkdir ~/perllib
        perl Makefile.PL PREFIX=~/perllib
        make
        make install

#. Execute the script ``create_man_pages.py`` to generate the .rst files into ``xcat-core/docs`` :

    * **[as root]** ::

        cd xcat-core
        ./create_man_pages.py

    * **[as non root]** ::

        cd xcat-core
        ./create_man_pages.py --prefix=~/perllib
