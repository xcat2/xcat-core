#if !defined(__FreeBSD__) || !defined(XCAT_PKG_TARGET_VERSION) || XCAT_PKG_TARGET_VERSION != 20602
#error "The native package adapter requires FreeBSD and pkg 2.6.2"
#endif

#include "private/pkg_jobs.h"

/* File operands do not add their installed versions to the native solver. */
int
xcat_pkg_jobs_add_installed(struct pkg_jobs *jobs, struct pkg *package)
{
    return pkg_jobs_universe_add_pkg(jobs->universe, package, NULL);
}
