#!/bin/bash

PS4="~> " # needed to avoid accidentally generating collapsed output
set -uexo pipefail

echo "--- Setting build variables"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

"$DIR/clone_repositories.sh"

echo "--- Patching DMD and druntime (remove failing tests)"

# patch makefile which requires gdb 8 - see https://github.com/dlang/ci/pull/301
sed "s/TESTS+=rt_trap_exceptions_drt_gdb//" -i druntime/test/exceptions/Makefile

# remove tests which require gdb 8 for now (see https://github.com/dlang/ci/pull/291)
rm dmd/test/runnable/gdb{1,10311,14225,14276,14313,14330,4149,4181}.d
rm dmd/test/runnable/b18504.d
rm dmd/test/runnable/gdb15729.sh

echo "--- Exporting build variables"

export BRANCH="${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-}"
export N=2
export OS_NAME=linux
export FULL_BUILD="${BUILDKITE_PULL_REQUEST+false}"

echo "--- Go to dmd and source ci.sh"

cd dmd
source ci.sh

echo "--- Installing $DMD"
install_d "$DMD" # Source a D compiler

echo "--- Running the testsuite"
testsuite
