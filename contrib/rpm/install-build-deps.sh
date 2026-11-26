#!/usr/bin/env bash
# Install everything needed to run contrib/build-rpm.sh on Fedora or on
# AlmaLinux/RHEL-compatible 9 and 10 (cargo-rpm-macros comes from EPEL there).
set -euo pipefail

SPEC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cable-uhid-bridge.spec"
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

. /etc/os-release
case "$ID" in
    fedora)
        $SUDO dnf -y install rpm-build git-core cargo-rpm-macros 'dnf5-command(builddep)'
        ;;
    almalinux|rocky|rhel|centos)
        $SUDO dnf -y install epel-release dnf-plugins-core
        $SUDO dnf config-manager --set-enabled crb
        $SUDO dnf -y install rpm-build git-core cargo-rpm-macros
        ;;
    *)
        echo "Error: unsupported distribution '$ID' (expected Fedora or an EL9/EL10 clone)." >&2
        exit 1
        ;;
esac

# BuildRequires from the spec (rust, cargo, clang, dbus/openssl/xkbcommon -devel)
$SUDO dnf -y builddep "$SPEC"
