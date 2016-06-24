Build Kit Repositories
======================

After the buildkit configuration file is validated, run the ``buildrepo`` subcommand to build the Kit Package Repositories.  The build server has to have same OS distributions, versions, or architectures with build kit repositories. User can copy the kit template directory to an appropriate server to build the repository then copy the results back the current system.

IBM HPC Products are using pre-built rpms.  There are no OS/arch specific in the kitcomponent meta-package rpm and should be able to build all repositories on the same server.

To list the repos defined in the buildkit.conf: ::

  buildkit listrepo

To build the repositories, specifiy a particular reporitory: ::

  buildkit buildrepo <kit repo name>

or build all the repositories for this kit: ::

  buildkit buildrep all

The repository would be built in ``<Kit directory location>/build/kit_repodir/`` subdirectory.
If the Kit Package Repository is already fully built, then this command performs no operation.
If the Kit Package Repository is not fully built, the command builds it as follows:

    #. Create the Kit Package Repository directory ``<Kit directory location>/build/kit_repodir/<Kit Pkg Repo>`` .
    #. Build the Component Meta-Packages associated with this Kit Package Repository. Create the packages under the Kit Package Repository directory
    #. Build the Kit Packages associated with this Kit Package Repository. Create the packages under the Kit Package Repository directory
    #. Build the repository meta-data for the Kit Package Repository. The repository meta-data is based on the OS native package format. For example, for RHEL, we build the YUM repository meta-data with the createrepo command.
 
