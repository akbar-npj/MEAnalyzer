#!/usr/bin/env bash
#
# build.sh - Build, test, and package ME Analyzer
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.312.0"
DIST_DIR="${SCRIPT_DIR}/dist"
BUILD_DIR="${SCRIPT_DIR}/build"
RPMBUILD_DIR="${HOME}/rpmbuild"

# Terminal color output
if [ -t 1 ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    RESET=''
fi

log_info() {
    echo -e "${BLUE}${BOLD}[INFO]${RESET} $*"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $*"
}

log_warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${RESET} $*"
}

log_error() {
    echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2
}

show_help() {
    cat << EOF
${BOLD}ME Analyzer Build & Packaging Automation Tool${RESET}

Usage: ./build.sh [COMMAND] [OPTIONS]

Commands:
  ${CYAN}compile${RESET}, ${CYAN}build${RESET}     Compile standalone native binary using PyInstaller (default)
  ${CYAN}test${RESET}              Run execution verification tests
  ${CYAN}rpm${RESET}               Generate source tarball and build RPM packages (binary + SRPM)
  ${CYAN}install${RESET}           Install compiled binary and data files to system (--prefix supported)
  ${CYAN}clean${RESET}             Remove build directories, PyInstaller caches, and temporary files
  ${CYAN}all${RESET}               Execute clean, compile, test, and rpm sequentially
  ${CYAN}help${RESET}, ${CYAN}-h${RESET}          Display this usage guide

Options:
  --prefix <PATH>    Installation prefix (default: /usr/local)

Examples:
  ./build.sh compile
  ./build.sh test
  ./build.sh rpm
  sudo ./build.sh install --prefix /usr/local
EOF
}

find_pyinstaller() {
    export PATH="$HOME/.local/bin:$PATH"
    if command -v pyinstaller >/dev/null 2>&1; then
        echo "pyinstaller"
    elif [ -x "$HOME/.local/bin/pyinstaller" ]; then
        echo "$HOME/.local/bin/pyinstaller"
    elif python3 -m PyInstaller --version >/dev/null 2>&1; then
        echo "python3 -m PyInstaller"
    else
        echo ""
    fi
}

do_clean() {
    log_info "Cleaning build artifacts..."
    rm -rf "${BUILD_DIR}" "${DIST_DIR}" "${SCRIPT_DIR}/MEA.spec" "${SCRIPT_DIR}/__pycache__"
    find "${SCRIPT_DIR}" -name "*.pyc" -delete 2>/dev/null || true
    log_success "Clean completed."
}

do_compile() {
    log_info "Compiling ME Analyzer standalone executable..."
    local pyi_cmd
    pyi_cmd="$(find_pyinstaller)"

    if [ -z "$pyi_cmd" ]; then
        log_error "PyInstaller is not installed. Install via: pip3 install pyinstaller"
        return 1
    fi

    log_info "Using PyInstaller: $pyi_cmd"
    local hook_opt=""
    if [ -f "${SCRIPT_DIR}/packaging/pyi_rth_warnings.py" ]; then
        hook_opt="--runtime-hook ${SCRIPT_DIR}/packaging/pyi_rth_warnings.py"
    fi

    mkdir -p "${DIST_DIR}"
    $pyi_cmd --noupx --onefile --clean \
        --distpath "${DIST_DIR}" \
        --workpath "${BUILD_DIR}" \
        --specpath "${SCRIPT_DIR}" \
        ${hook_opt} \
        "${SCRIPT_DIR}/MEA.py"

    log_info "Copying database assets into dist directory..."
    cp -p "${SCRIPT_DIR}/MEA.dat" "${DIST_DIR}/"
    cp -p "${SCRIPT_DIR}/FileTable.dat" "${DIST_DIR}/"
    cp -p "${SCRIPT_DIR}/Huffman.dat" "${DIST_DIR}/"

    log_success "Compilation finished successfully."
    log_info "Binary and database assets available at: ${DIST_DIR}/"
}

do_test() {
    log_info "Running ME Analyzer verification tests..."
    export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::DeprecationWarning}"

    if [ -f "${DIST_DIR}/MEA" ]; then
        log_info "Testing standalone compiled binary..."
        "${DIST_DIR}/MEA" -skip -exit -? >/dev/null
        log_success "Standalone binary test PASSED."
    fi

    log_info "Testing Python script execution..."
    python3 "${SCRIPT_DIR}/MEA.py" -skip -exit -? >/dev/null
    log_success "Python script execution test PASSED."
}

do_rpm() {
    log_info "Building RPM packages for current system ($(uname -m))..."
    mkdir -p "${RPMBUILD_DIR}/"{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    local tarball="${RPMBUILD_DIR}/SOURCES/meanalyzer-${VERSION}.tar.gz"
    log_info "Generating source tarball: ${tarball}"
    tar -czf "${tarball}" \
        --transform "s,^\.,meanalyzer-${VERSION}," \
        --exclude='.git' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='MEA.spec' \
        --exclude='__pycache__' \
        -C "${SCRIPT_DIR}" .

    log_info "Copying RPM spec file..."
    cp -p "${SCRIPT_DIR}/meanalyzer.spec" "${RPMBUILD_DIR}/SPECS/meanalyzer.spec"

    log_info "Executing rpmbuild..."
    rpmbuild -ba "${RPMBUILD_DIR}/SPECS/meanalyzer.spec"

    log_success "RPM build completed successfully!"
    echo ""
    log_info "Generated packages:"
    find "${RPMBUILD_DIR}/RPMS" -name "meanalyzer-*.rpm" -exec ls -lh {} +
    find "${RPMBUILD_DIR}/SRPMS" -name "meanalyzer-*.src.rpm" -exec ls -lh {} +
}

do_install() {
    local prefix="${1:-/usr/local}"
    log_info "Installing ME Analyzer to prefix: ${prefix}..."

    mkdir -p "${prefix}/bin"
    mkdir -p "${prefix}/libexec/meanalyzer"
    mkdir -p "${prefix}/share/meanalyzer"
    mkdir -p "${prefix}/share/man/man1"

    if [ ! -f "${DIST_DIR}/MEA" ]; then
        log_info "Binary not found in dist/. Compiling first..."
        do_compile
    fi

    install -p -m 0755 "${DIST_DIR}/MEA" "${prefix}/libexec/meanalyzer/MEA"
    install -p -m 0644 "${SCRIPT_DIR}/MEA.dat" "${prefix}/share/meanalyzer/MEA.dat"
    install -p -m 0644 "${SCRIPT_DIR}/FileTable.dat" "${prefix}/share/meanalyzer/FileTable.dat"
    install -p -m 0644 "${SCRIPT_DIR}/Huffman.dat" "${prefix}/share/meanalyzer/Huffman.dat"
    install -p -m 0755 "${SCRIPT_DIR}/MEA.py" "${prefix}/share/meanalyzer/MEA.py"

    ln -sf ../../share/meanalyzer/MEA.dat "${prefix}/libexec/meanalyzer/MEA.dat"
    ln -sf ../../share/meanalyzer/FileTable.dat "${prefix}/libexec/meanalyzer/FileTable.dat"
    ln -sf ../../share/meanalyzer/Huffman.dat "${prefix}/libexec/meanalyzer/Huffman.dat"

    cat << 'EOF' > "${prefix}/bin/meanalyzer"
#!/bin/bash
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::DeprecationWarning}"
BASE_PREFIX="$(dirname "$(dirname "$(realpath "$0")")")"
if [ -x "${BASE_PREFIX}/libexec/meanalyzer/MEA" ]; then
    exec "${BASE_PREFIX}/libexec/meanalyzer/MEA" "$@"
elif [ -f "${BASE_PREFIX}/share/meanalyzer/MEA.py" ]; then
    exec /usr/bin/python3 "${BASE_PREFIX}/share/meanalyzer/MEA.py" "$@"
else
    echo "Error: ME Analyzer executable not found." >&2
    exit 1
fi
EOF
    chmod 0755 "${prefix}/bin/meanalyzer"
    ln -sf meanalyzer "${prefix}/bin/mea"
    ln -sf meanalyzer "${prefix}/bin/MEA"

    if [ -f "${SCRIPT_DIR}/man/meanalyzer.1" ]; then
        install -p -m 0644 "${SCRIPT_DIR}/man/meanalyzer.1" "${prefix}/share/man/man1/meanalyzer.1"
        ln -sf meanalyzer.1 "${prefix}/share/man/man1/mea.1"
        ln -sf meanalyzer.1 "${prefix}/share/man/man1/MEA.1"
    fi

    log_success "Installed successfully to ${prefix}"
}

# Parse command line arguments
COMMAND="${1:-compile}"
shift || true

case "${COMMAND}" in
    compile|build)
        do_compile
        ;;
    test)
        do_test
        ;;
    rpm)
        do_rpm
        ;;
    clean)
        do_clean
        ;;
    all)
        do_clean
        do_compile
        do_test
        do_rpm
        log_success "All tasks completed successfully."
        ;;
    install)
        PREFIX="/usr/local"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --prefix)
                    PREFIX="$2"
                    shift 2
                    ;;
                *)
                    log_error "Unknown option: $1"
                    exit 1
                    ;;
            esac
        done
        do_install "${PREFIX}"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        log_error "Unknown command: ${COMMAND}"
        show_help
        exit 1
        ;;
esac
