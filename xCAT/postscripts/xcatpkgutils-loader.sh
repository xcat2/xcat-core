#!/bin/sh
# EPL license http://www.eclipse.org/legal/epl-v10.html

xcatpkgutils="$(dirname "$0")/xcatpkgutils.sh"
if [ ! -r "$xcatpkgutils" ]; then
    printf 'Error: package utility library is not readable: %s\n' "$xcatpkgutils" >&2
    unset xcatpkgutils
    return 1
fi

unset XCATPKGUTILS_LOADED
# shellcheck source-path=SCRIPTDIR
# shellcheck source=xcatpkgutils.sh
if ! . "$xcatpkgutils"; then
    printf 'Error: package utility library could not be loaded: %s\n' "$xcatpkgutils" >&2
    unset XCATPKGUTILS_LOADED xcatpkgutils
    return 1
fi
if [ "${XCATPKGUTILS_LOADED:-}" != "1" ]; then
    printf 'Error: package utility library did not finish loading: %s\n' "$xcatpkgutils" >&2
    unset XCATPKGUTILS_LOADED xcatpkgutils
    return 1
fi
unset XCATPKGUTILS_LOADED xcatpkgutils
