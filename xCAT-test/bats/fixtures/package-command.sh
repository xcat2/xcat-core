#!/bin/sh

command=${0##*/}
case "$command" in
    logger|mount|apt-cache|dpkg) exit 0 ;;
esac

printf '%s\t' "$command" "${DEBIAN_FRONTEND-unset}" "${ACCEPT_EULA-unset}" "${ARCH-unset}" "$@" >>/run/fixture/commands
printf '\n' >>/run/fixture/commands

for argument do
    case "$argument" in
        cuda-toolkit) exit "${CUDA_STATUS:-0}" ;;
    esac
done
for argument do
    case "$argument" in
        upgrade) exit "${UPGRADE_STATUS:-0}" ;;
        install) exit "${INSTALL_STATUS:-0}" ;;
    esac
done
exit 0
