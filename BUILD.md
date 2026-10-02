# Building, Compiling, and Packaging ME Analyzer

This guide provides detailed instructions on how to compile, build, and package **ME Analyzer (MEA)** from source, with a particular focus on generating native **RPM packages** for Fedora, Red Hat Enterprise Linux (RHEL), CentOS Stream, and Fedora Asahi Remix (`aarch64` on Apple Silicon).

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites & Dependencies](#prerequisites--dependencies)
  - [Fedora / RHEL / CentOS / Fedora Asahi Remix](#fedora--rhel--centos--fedora-asahi-remix)
  - [Debian / Ubuntu](#debian--ubuntu)
  - [Arch Linux](#arch-linux)
- [Quick Start: Automated Build Script (`build.sh`)](#quick-start-automated-build-script-buildsh)
- [Building the RPM Package (Fedora / RHEL / Asahi)](#building-the-rpm-package-fedora--rhel--asahi)
  - [1. Prepare the RPM Build Tree](#1-prepare-the-rpm-build-tree)
  - [2. Generate the Source Tarball](#2-generate-the-source-tarball)
  - [3. Install the RPM Spec File](#3-install-the-rpm-spec-file)
  - [4. Build Binary and Source RPMs](#4-build-binary-and-source-rpms)
  - [5. Install and Verify the RPM](#5-install-and-verify-the-rpm)
- [Manual Standalone Compilation (PyInstaller)](#manual-standalone-compilation-pyinstaller)
  - [Compiling a Native Binary](#compiling-a-native-binary)
  - [Packaging Data Files](#packaging-data-files)
- [Running as a Python Script (Alternative)](#running-as-a-python-script-alternative)
  - [Virtual Environment (Isolated)](#virtual-environment-isolated)
  - [Direct Execution](#direct-execution)
- [Package Layout & Installed Files](#package-layout--installed-files)
- [Troubleshooting & FAQ](#troubleshooting--faq)

---

## Overview

**ME Analyzer** is an Intel Engine and Graphics firmware analysis tool that parses CS(ME) 2–15, (CS)TXE 0–4, (CS)SPS 1–5, GSC 100, PMC, PCHC, PHY, and OROM firmware.

Because Fedora official repositories provide `python3-colorama` but omit `python3-crccheck` and `python3-pltable`, standard RPM packaging typically faces unresolvable dependency issues on clean systems. Our RPM packaging resolves this cleanly by:

1. **Freezing & Compiling**: Building a native, standalone ELF executable (`aarch64` / `x86_64`) using PyInstaller with all required Python dependencies baked in.
2. **Zero External Python Library Dependencies**: The produced binary RPM installs cleanly via `dnf` on any compatible system without requiring manual `pip` installs.
3. **Multi-command Access**: Providing `/usr/bin/meanalyzer`, `/usr/bin/mea`, and `/usr/bin/MEA`.
4. **UNIX Manual Pages**: Including comprehensive man pages in `/usr/share/man/man1/`.
5. **Clean Output**: Silencing Python 3.14+ `ctypes` MSVC pack deprecation warnings via an automated runtime hook.

---

## Prerequisites & Dependencies

### Fedora / RHEL / CentOS / Fedora Asahi Remix

Install the required build tools, Python packages, and RPM packaging utilities:

```bash
sudo dnf install -y \
    python3 \
    python3-devel \
    python3-pip \
    python3-setuptools \
    rpm-build \
    rpmdevtools \
    git \
    tar \
    gzip
```

Install the Python libraries required by ME Analyzer and the PyInstaller compiler:

```bash
pip3 install --user pyinstaller colorama crccheck pltable
```

Make sure your local user bin directory is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git tar gzip
pip3 install --user pyinstaller colorama crccheck pltable
```

### Arch Linux

```bash
sudo pacman -S --needed python python-pip git tar gzip
pip install --user pyinstaller colorama crccheck pltable
```

---

## Quick Start: Automated Build Script (`build.sh`)

An all-in-one automation script [`build.sh`](build.sh) is provided in the root of the repository:

```bash
# 1. Compile native standalone executable into dist/
./build.sh compile

# 2. Run verification tests
./build.sh test

# 3. Build RPM packages (Binary + SRPM)
./build.sh rpm

# 4. Clean, compile, test, and build RPM in a single command
./build.sh all

# 5. Install locally to /usr/local (or custom prefix)
sudo ./build.sh install --prefix /usr/local

# 6. Clean build artifacts
./build.sh clean
```

---

## Building the RPM Package (Fedora / RHEL / Asahi)

To build the RPM package manually using standard RPM build infrastructure:

### 1. Prepare the RPM Build Tree

Create the standard RPM directory structure in your home directory:

```bash
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
```

### 2. Generate the Source Tarball

From the root of the `MEAnalyzer` repository:

```bash
tar -czf ~/rpmbuild/SOURCES/meanalyzer-1.312.0.tar.gz \
    --transform 's,^\.,meanalyzer-1.312.0,' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='MEA.spec' \
    --exclude='__pycache__' \
    .
```

Verify that the tarball contains all files under the prefix `meanalyzer-1.312.0/`:

```bash
tar -ztvf ~/rpmbuild/SOURCES/meanalyzer-1.312.0.tar.gz | head -n 15
```

### 3. Install the RPM Spec File

Copy [`meanalyzer.spec`](meanalyzer.spec) to your `~/rpmbuild/SPECS/` directory:

```bash
cp meanalyzer.spec ~/rpmbuild/SPECS/meanalyzer.spec
```

### 4. Build Binary and Source RPMs

Invoke `rpmbuild`:

```bash
rpmbuild -ba ~/rpmbuild/SPECS/meanalyzer.spec
```

Upon successful completion, the generated packages will be located at:

- **Binary RPM (aarch64 / ARM64):**
  `~/rpmbuild/RPMS/aarch64/meanalyzer-1.312.0-1.fc44.aarch64.rpm`
- **Source RPM (SRPM):**
  `~/rpmbuild/SRPMS/meanalyzer-1.312.0-1.fc44.src.rpm`

### 5. Install and Verify the RPM

Install the package using `dnf`:

```bash
sudo dnf install ~/rpmbuild/RPMS/aarch64/meanalyzer-1.312.0-1.fc*.aarch64.rpm
```

Verify the installation:

```bash
# Check version and usage
meanalyzer -?
mea -?

# View installed manual page
man meanalyzer

# Inspect package file listing
rpm -ql meanalyzer
```

To remove the package:

```bash
sudo dnf remove meanalyzer
```

---

## Manual Standalone Compilation (PyInstaller)

If you wish to compile a standalone executable without building an RPM:

### Compiling a Native Binary

From the repository root:

```bash
# Ensure dependencies are installed
pip3 install --user pyinstaller colorama crccheck pltable

# Compile MEA.py into a single ELF binary
pyinstaller --noupx --onefile --clean \
    --runtime-hook packaging/pyi_rth_warnings.py \
    MEA.py
```

### Packaging Data Files

ME Analyzer requires its three lookup databases to be located alongside the executable:

```bash
cp MEA.dat FileTable.dat Huffman.dat dist/
```

Run the compiled executable:

```bash
./dist/MEA -skip -exit -?
```

You can now copy the `dist/` directory to any system with the same architecture and glibc version.

---

## Running as a Python Script (Alternative)

If you prefer running ME Analyzer directly with Python:

### Virtual Environment (Isolated)

```bash
# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install colorama crccheck pltable

# Run ME Analyzer
python3 MEA.py -skip -exit -?
```

### Direct Execution

If dependencies are installed in your user site:

```bash
pip3 install --user colorama crccheck pltable
python3 MEA.py path/to/firmware.bin
```

---

## Package Layout & Installed Files

When installed via RPM, the package places files in standard FHS locations:

| Path | Purpose |
| :--- | :--- |
| `/usr/bin/meanalyzer` | Primary executable launcher script |
| `/usr/bin/mea` | Symbolic link to `/usr/bin/meanalyzer` |
| `/usr/bin/MEA` | Symbolic link to `/usr/bin/meanalyzer` |
| `/usr/libexec/meanalyzer/MEA` | Native compiled standalone ELF executable |
| `/usr/libexec/meanalyzer/*.dat` | Symlinks to shared database assets |
| `/usr/share/meanalyzer/MEA.py` | Original Python script |
| `/usr/share/meanalyzer/MEA.dat` | Firmware repository lookup database |
| `/usr/share/meanalyzer/FileTable.dat` | CSE File Table definition database |
| `/usr/share/meanalyzer/Huffman.dat` | Huffman lookup dictionaries |
| `/usr/share/man/man1/meanalyzer.1.gz` | Manual page |
| `/usr/share/licenses/meanalyzer/LICENSE` | License file (`BSD-2-Clause-Patent`) |
| `/usr/share/doc/meanalyzer/README.md` | Upstream documentation |
| `/usr/share/doc/meanalyzer/Changelog.txt` | Detailed release history |

---

## Troubleshooting & FAQ

### 1. `Error: MEA.dat file is missing!`
ME Analyzer requires `MEA.dat` to be located in the same directory as the executable (or followed symlink destination). Ensure that `MEA.dat`, `FileTable.dat`, and `Huffman.dat` exist alongside `MEA`.

### 2. Python 3.14 ctypes MSVC Pack Deprecation Warnings
On Python 3.14+, `ctypes.LittleEndianStructure` with `_pack_` emits deprecation warnings. Both the RPM wrapper and `build.sh` suppress these non-critical warnings automatically via `PYTHONWARNINGS="ignore::DeprecationWarning"` and [`packaging/pyi_rth_warnings.py`](packaging/pyi_rth_warnings.py).

### 3. Interactive Prompts during Automation
By default, ME Analyzer pauses with interactive prompts. For scripting or automation, pass `-skip` (skip welcome screen) and `-exit` (skip "Press enter to exit" prompt):

```bash
meanalyzer -skip -exit -?
```

### 4. Cross-compilation across Architectures
Because the compiled RPM contains native machine code (ARM64 `aarch64` or x86_64), build the RPM on the target architecture or rebuild the SRPM (`meanalyzer-*.src.rpm`) on the target machine:

```bash
rpmbuild --rebuild meanalyzer-1.312.0-1.fc44.src.rpm
```
