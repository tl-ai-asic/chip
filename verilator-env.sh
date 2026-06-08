#!/usr/bin/env sh

if [ -n "${BASH_SOURCE:-}" ]; then
    ENV_SCRIPT="${BASH_SOURCE[0]}"
else
    ENV_SCRIPT="$0"
fi

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$ENV_SCRIPT")" && pwd)"
VERILATOR_PREFIX="$PROJECT_ROOT/.local/verilator"
YOSYS_PREFIX="$PROJECT_ROOT/.local/yosys"
OPENROAD_PREFIX="$PROJECT_ROOT/.local/openroad"

export PATH="$PROJECT_ROOT/.local/bin:$PATH"
export VERILATOR_ROOT="$VERILATOR_PREFIX/share/verilator"
export YOSYS_DATDIR="$YOSYS_PREFIX/share/yosys"
export OPENROAD_HOME="$OPENROAD_PREFIX"
export PKG_CONFIG_PATH="$VERILATOR_PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# macOS does not provide C.UTF-8, which causes Perl warnings from Verilator.
if [ "${LC_ALL:-}" = "C.UTF-8" ]; then
    export LC_ALL="en_US.UTF-8"
fi
if [ "${LANG:-}" = "C.UTF-8" ]; then
    export LANG="en_US.UTF-8"
fi
if [ "${LC_CTYPE:-}" = "C.UTF-8" ]; then
    export LC_CTYPE="en_US.UTF-8"
fi
