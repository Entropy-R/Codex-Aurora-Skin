Name: codex-aurora-skin
Version: 1.0.1
Release: 1%{?dist}
Summary: Local theme manager for ChatGPT Codex on Linux
License: MIT
URL: https://github.com/Entropy-R/Codex-Aurora-Skin
BuildArch: noarch
Requires: chatgpt
Requires: bash
Requires: coreutils
Requires: iproute
Requires: xdg-utils

%description
Codex Aurora Skin injects a local visual theme through a loopback-only
Chrome DevTools Protocol session. It does not modify ChatGPT application
files, account data, model settings, plugins, or task data.

%install
mkdir -p %{buildroot}/opt/codex-aurora-skin
cp -a %{_sourcedir}/runtime/. %{buildroot}/opt/codex-aurora-skin/
mkdir -p %{buildroot}%{_datadir}/applications
cp %{_sourcedir}/codex-aurora-skin.desktop \
  %{buildroot}%{_datadir}/applications/
cp %{_sourcedir}/codex-aurora-skin-restore.desktop \
  %{buildroot}%{_datadir}/applications/

%files
/opt/codex-aurora-skin
%{_datadir}/applications/codex-aurora-skin.desktop
%{_datadir}/applications/codex-aurora-skin-restore.desktop

%changelog
* Wed Aug 26 2026 Entropy-R <Entropy-R@users.noreply.github.com> - 1.0.1-1
- Add initial Linux support for DEB and RPM ChatGPT packages.
