Building Source Code
====================

xcat-core
---------

Clone the xCAT project from `GitHub <https://github.com/xcat2/xcat-core>`_::

    cd xcat-core
    ./buildcore.sh 

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
    
    * **[as non-root]** Extrat and build the Perl module using PREFIX to specify a directory that you have write permission ::
    
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
