# Built by contrib/build-rpm.sh, which rewrites Version from Cargo.toml, appends
# the changelog and generates both source tarballs. Targets Fedora and
# EL9/EL10 with EPEL. Crates that the distributions do not package (eframe,
# btleplug, uhidrs-sys, ...) are bundled in Source1 via "cargo vendor"; the
# toolchain, C libraries and build flags all come from the distribution.

%bcond check 1

Name:           cable-uhid-bridge
Version:        0.1.1
Release:        1%{?dist}
Summary:        Virtual USB FIDO2 token bridge for mobile passkeys (caBLE v2)

# The package itself is "MIT OR Apache-2.0". The binary statically links the
# vendored crates listed in LICENSE.dependencies, hence the longer expression
# (taken from the %%cargo_license_summary output printed during %%build).
License:        %{shrink:
    (MIT OR Apache-2.0)
    AND MIT
    AND Apache-2.0
    AND BSD-2-Clause
    AND BSD-3-Clause
    AND BSL-1.0
    AND ISC
    AND MPL-2.0
    AND OFL-1.1
    AND Ubuntu-font-1.0
    AND Unicode-3.0
    AND Zlib
    AND (0BSD OR MIT OR Apache-2.0)
    AND (Apache-2.0 OR GPL-2.0-only)
    AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT)
    AND (BSD-2-Clause OR Apache-2.0 OR MIT)
    AND (BSD-3-Clause OR Apache-2.0)
    AND (BSD-3-Clause OR MIT OR Apache-2.0)
    AND (MIT OR Apache-2.0 OR LGPL-2.1-or-later)
    AND (MIT OR Apache-2.0 OR Zlib)
    AND (Unlicense OR MIT)
}
URL:            https://github.com/baseman70/cable-uhid-bridge
Source0:        %{name}-%{version}.tar.gz
Source1:        %{name}-%{version}-vendor.tar.gz

BuildRequires:  cargo-rpm-macros >= 26
BuildRequires:  systemd-rpm-macros
BuildRequires:  gcc
# bindgen (uhidrs-sys) needs libclang
BuildRequires:  clang-devel
BuildRequires:  pkgconfig(dbus-1)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(xkbcommon)

# libdbus, libssl and glibc are picked up automatically from the binary.
# libxkbcommon is dlopen()ed by the UI toolkit, so it has to be listed by hand.
Requires:       libxkbcommon
# Bluetooth LE proximity check talks to bluetoothd over D-Bus
Requires:       bluez
Requires:       systemd-udev

%description
Emulates a physical FIDO2 USB token over /dev/uhid so that browsers can use
passkeys stored on an Android or iOS phone. A floating Wayland/X11 window shows
the caBLE v2 QR code, and Bluetooth LE is used for proximity verification.

%prep
%autosetup -n %{name}-%{version} -a 1
%cargo_prep -v cargo-vendor

%build
%cargo_build -- --locked
%cargo_vendor_manifest
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies

%install
install -Dpm 0755 target/rpm/%{name} %{buildroot}%{_bindir}/%{name}
install -Dpm 0644 contrib/%{name}.service %{buildroot}%{_userunitdir}/%{name}.service
sed -i 's|^ExecStart=.*|ExecStart=%{_bindir}/%{name}|' \
    %{buildroot}%{_userunitdir}/%{name}.service
install -Dpm 0644 contrib/70-uhid.rules %{buildroot}%{_udevrulesdir}/70-uhid.rules
install -Dpm 0644 contrib/uhid.conf %{buildroot}%{_modulesloaddir}/uhid.conf

%if %{with check}
%check
%cargo_test -- --locked
%endif

%post
%systemd_user_post %{name}.service
# Load uhid now (modules-load.d only applies at boot) and apply the uaccess ACL
modprobe uhid >/dev/null 2>&1 || :
udevadm control --reload-rules >/dev/null 2>&1 || :
udevadm trigger -s misc -a name=uhid >/dev/null 2>&1 || :

%preun
%systemd_user_preun %{name}.service

%postun
%systemd_user_postun_with_restart %{name}.service
udevadm control --reload-rules >/dev/null 2>&1 || :

%files
%license LICENSE-MIT LICENSE-APACHE LICENSE.dependencies cargo-vendor.txt
%doc README.md
%{_bindir}/%{name}
%{_userunitdir}/%{name}.service
%{_udevrulesdir}/70-uhid.rules
%{_modulesloaddir}/uhid.conf

# Entries are generated from git history by contrib/build-rpm.sh
%changelog
