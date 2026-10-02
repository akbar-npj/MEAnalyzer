%global debug_package %{nil}

Name:           meanalyzer
Version:        1.312.0
Release:        1%{?dist}
Summary:        Intel Engine and Graphics Firmware Analysis Tool

License:        BSD-2-Clause-Patent
URL:            https://github.com/platomav/MEAnalyzer
Source0:        meanalyzer-%{version}.tar.gz

Provides:       MEAnalyzer = %{version}-%{release}
Provides:       mea = %{version}-%{release}
Provides:       MEA = %{version}-%{release}

BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
Requires:       python3

%description
ME Analyzer is a tool which parses Intel Engine, Intel Graphics and their
Independent firmware from the following families:
- (Converged Security) Management Engine - CS(ME) 2-15
- (Converged Security) Trusted Execution Engine - (CS)TXE 0-4
- (Converged Security) Server Platform Services - (CS)SPS 1-5
- Graphics System Controller - GSC 100
- Power Management Controller - PMC
- Platform Controller Hub Configuration - PCHC
- USB Type C Physical - PHY
- Graphics Option ROM - OROM

It can be used by end-users looking for firmware details (Family, Version,
Release, Type, Date, SKU, Platform, Size, Health Status, etc.) or by researchers
to fully unpack and parse CSE and GSC code and file systems (FPT, BPDT, LT,
FTBL/EFST, VFS, OROM-PCIR).

%prep
%autosetup -p1 -n %{name}-%{version}

%build
export PATH="$HOME/.local/bin:$PATH"

# Build standalone native ELF binary if PyInstaller is available
if command -v pyinstaller >/dev/null 2>&1; then
    PYI_CMD="pyinstaller"
elif [ -x "$HOME/.local/bin/pyinstaller" ]; then
    PYI_CMD="$HOME/.local/bin/pyinstaller"
elif python3 -m PyInstaller --version >/dev/null 2>&1; then
    PYI_CMD="python3 -m PyInstaller"
else
    PYI_CMD=""
fi

if [ -n "$PYI_CMD" ]; then
    HOOK_OPT=""
    if [ -f packaging/pyi_rth_warnings.py ]; then
        HOOK_OPT="--runtime-hook packaging/pyi_rth_warnings.py"
    fi
    $PYI_CMD --noupx --onefile --clean $HOOK_OPT MEA.py
else
    echo "Notice: PyInstaller not found, building script-only package"
fi

%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_libexecdir}/%{name}
mkdir -p %{buildroot}%{_datadir}/%{name}
mkdir -p %{buildroot}%{_mandir}/man1

# Install data files into /usr/share/meanalyzer
install -p -m 0644 MEA.dat %{buildroot}%{_datadir}/%{name}/
install -p -m 0644 FileTable.dat %{buildroot}%{_datadir}/%{name}/
install -p -m 0644 Huffman.dat %{buildroot}%{_datadir}/%{name}/
install -p -m 0755 MEA.py %{buildroot}%{_datadir}/%{name}/

# If standalone compiled binary was generated, install it into libexec
if [ -f dist/MEA ]; then
    install -p -m 0755 dist/MEA %{buildroot}%{_libexecdir}/%{name}/MEA
    # Relative symlinks so frozen executable finds data files via get_script_dir()
    ln -s ../../share/%{name}/MEA.dat %{buildroot}%{_libexecdir}/%{name}/MEA.dat
    ln -s ../../share/%{name}/FileTable.dat %{buildroot}%{_libexecdir}/%{name}/FileTable.dat
    ln -s ../../share/%{name}/Huffman.dat %{buildroot}%{_libexecdir}/%{name}/Huffman.dat
fi

# Create launcher wrapper in /usr/bin/meanalyzer
cat << 'EOF' > %{buildroot}%{_bindir}/meanalyzer
#!/bin/bash
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::DeprecationWarning}"
BASE_DIR="${MEANALYZER_ROOT_DIR:-}"

if [ -x "${BASE_DIR}%{_libexecdir}/%{name}/MEA" ]; then
    exec "${BASE_DIR}%{_libexecdir}/%{name}/MEA" "$@"
elif [ -f "${BASE_DIR}%{_datadir}/%{name}/MEA.py" ]; then
    exec /usr/bin/python3 "${BASE_DIR}%{_datadir}/%{name}/MEA.py" "$@"
else
    echo "Error: ME Analyzer executable not found." >&2
    exit 1
fi
EOF
chmod 0755 %{buildroot}%{_bindir}/meanalyzer

# Compatibility symlinks for convenient invocation
ln -s meanalyzer %{buildroot}%{_bindir}/mea
ln -s meanalyzer %{buildroot}%{_bindir}/MEA

# Install man pages
if [ -f man/meanalyzer.1 ]; then
    install -p -m 0644 man/meanalyzer.1 %{buildroot}%{_mandir}/man1/meanalyzer.1
    ln -s meanalyzer.1 %{buildroot}%{_mandir}/man1/mea.1
    ln -s meanalyzer.1 %{buildroot}%{_mandir}/man1/MEA.1
fi

%check
# Verify the installed launcher produces expected help screen without errors
MEANALYZER_ROOT_DIR="%{buildroot}" %{buildroot}%{_bindir}/meanalyzer -skip -exit -?
MEANALYZER_ROOT_DIR="%{buildroot}" %{buildroot}%{_bindir}/mea -skip -exit -?

%files
%license LICENSE
%doc README.md Changelog.txt
%{_bindir}/meanalyzer
%{_bindir}/mea
%{_bindir}/MEA
%{_datadir}/%{name}/
%{_libexecdir}/%{name}/
%{_mandir}/man1/meanalyzer.1*
%{_mandir}/man1/mea.1*
%{_mandir}/man1/MEA.1*

%changelog
* Fri Oct 02 2026 akbar_npj <akbar.npj@protonmail.com> - 1.312.0-1
- Initial RPM package for Fedora Asahi Remix (aarch64)
- Include standalone native compiled binary and database assets (r378)
- Add man page and wrapper launcher with command aliases
