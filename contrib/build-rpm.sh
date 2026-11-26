#!/usr/bin/env bash
# Build a Fedora RPM (and SRPM) of cable-uhid-bridge.
#
# Uses Fedora's own toolchain and libraries (rust/cargo, cargo-rpm-macros,
# dbus/openssl/libxkbcommon -devel). Rust crates are bundled with
# "cargo vendor" because most of them are not packaged in Fedora; that is the
# only step that needs network access.
#
# Any extra arguments are passed straight to rpmbuild, e.g.:
#   ./contrib/build-rpm.sh --without check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="cable-uhid-bridge"
VERSION=$(grep '^version = ' "$SCRIPT_DIR/Cargo.toml" | cut -d '"' -f2)
SPEC_IN="$SCRIPT_DIR/contrib/rpm/$NAME.spec"
TOPDIR="$SCRIPT_DIR/target/rpm"
SPEC="$TOPDIR/SPECS/$NAME.spec"
SRC_TARBALL="$TOPDIR/SOURCES/$NAME-$VERSION.tar.gz"
VENDOR_TARBALL="$TOPDIR/SOURCES/$NAME-$VERSION-vendor.tar.gz"

echo "Building RPM package: $NAME-$VERSION"

missing=()
for cmd in rpmbuild git cargo; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ] || [ ! -e /usr/lib/rpm/macros.d/macros.cargo ]; then
    echo "Error: missing build tooling (${missing[*]:-cargo-rpm-macros})."
    echo "On Fedora / AlmaLinux (EPEL): ./contrib/rpm/install-build-deps.sh"
    exit 1
fi

mkdir -p "$TOPDIR"/{SOURCES,SPECS}

# --- %changelog -------------------------------------------------------------
# One entry per release, where a release is a commit that changed "version" in
# Cargo.toml and covers the commits since the previous such commit. Commits
# after the last version bump get a snapshot entry on top. Only feat/fix/perf
# subjects are listed. Shallow clones fall back to a single entry.
cl_git() { LC_ALL=C git -C "$SCRIPT_DIR" "$@"; }

cl_header() { # <commit> <version>
    cl_git log -1 --date='format:%a %b %d %Y' --format="* %cd %an <%ae> - $2-1" "$1"
}

cl_bullets() { # <revision range>
    cl_git log --no-merges --format='%s' "$1" \
        | grep -E '^(feat|fix|perf)(\([^)]*\))?!?: ' \
        | sed -e 's/%/%%/g' -e 's/^/- /' || true
}

generate_changelog() {
    local head bumps=() i commit older ver last_ver="" bullets
    head=$(cl_git rev-parse HEAD)
    if [ "$(cl_git rev-parse --is-shallow-repository)" != "true" ]; then
        mapfile -t bumps < <(cl_git log --first-parent --format='%H' -G'^version = ' -- Cargo.toml)
    fi

    if [ "${#bumps[@]}" -eq 0 ]; then
        cl_header "$head" "$VERSION"
        echo "- Build from git commit $(cl_git rev-parse --short "$head")"
        return
    fi

    if [ "${bumps[0]}" != "$head" ]; then
        cl_header "$head" "$VERSION"
        echo "- Snapshot of git commit $(cl_git rev-parse --short "$head")"
        cl_bullets "${bumps[0]}..$head"
        echo
    fi

    for i in "${!bumps[@]}"; do
        commit=${bumps[$i]}
        older=${bumps[$((i + 1))]:-}
        ver=$(cl_git show "$commit:Cargo.toml" | grep -m1 '^version = ' | cut -d '"' -f2)
        [ "$ver" = "$last_ver" ] && continue
        last_ver=$ver
        cl_header "$commit" "$ver"
        bullets=$(cl_bullets "${older:+$older..}$commit")
        echo "${bullets:-- Release $ver}"
        echo
    done
}


# 1. Spec file: version from Cargo.toml, changelog from git history
sed -e "s/^Version:.*/Version:        $VERSION/" -e '/^%changelog/q' "$SPEC_IN" > "$SPEC"
generate_changelog >> "$SPEC"

# 2. Source tarball: tracked files as they are in the working tree
echo "Creating source tarball..."
(cd "$SCRIPT_DIR" && git ls-files -z --cached --exclude-standard \
    | tar --null --no-recursion -T - --ignore-failed-read \
          --transform "s,^,$NAME-$VERSION/," -czf "$SRC_TARBALL")

# 3. Vendored crates (network). Kept out of ./vendor, which holds the patched
#    webauthn-authenticator-rs and ships in the source tarball as a path dep.
if [ ! -f "$VENDOR_TARBALL" ] || [ "$SCRIPT_DIR/Cargo.lock" -nt "$VENDOR_TARBALL" ]; then
    echo "Vendoring crates..."
    rm -rf "$TOPDIR/cargo-vendor"
    cargo vendor --quiet --locked --versioned-dirs \
        --manifest-path "$SCRIPT_DIR/Cargo.toml" "$TOPDIR/cargo-vendor" >/dev/null
    tar -C "$TOPDIR" -czf "$VENDOR_TARBALL" cargo-vendor
    rm -rf "$TOPDIR/cargo-vendor"
else
    echo "Reusing vendored crates: $VENDOR_TARBALL"
fi

# 4. Build source and binary packages
rpmbuild -ba --define "_topdir $TOPDIR" "$@" "$SPEC"

echo "✅ RPM packages created:"
find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -name "$NAME-*$VERSION-*.rpm" | sort | sed 's/^/   /'
