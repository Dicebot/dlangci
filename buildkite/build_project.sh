#!/bin/bash

PS4="~> " # needed to avoid accidentally generating collapsed output
set -uexo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. "$DIR/load_distribution.sh"

# set environment configs and allow build_project to be conveniently used in standalone
if [ -z "$REPO_FULL_NAME" ] ; then
    echo 'ERROR: You must set $REPO_FULL_NAME'
    exit 1
fi
if [ -z "${REPO_URL:-}" ] ; then
    REPO_URL="https://github.com/$REPO_FULL_NAME"
    echo "WARNING: \$REPO_URL not set. Falling back to $REPO_URL"
fi
if [ -z "${REPO_DIR:-}" ] ; then
    REPO_DIR="$(basename $REPO_FULL_NAME)"
    echo "WARNING: \$REPO_DIR not set. Falling back to $REPO_DIR"
fi

# clone the latest tag
latest_tag=$(git ls-remote --tags ""${REPO_URL}"" | \
    sed -n 's|.*refs/tags/\(v\?[0-9]*\.[0-9]*\.[0-9]*$\)|\1|p' | \
    sort --version-sort | \
    tail -n 1)
ref_to_use="${latest_tag:-master}"

case "$REPO_URL" in
    https://github.com/vibe-d/vibe.d)
        # Use master as Vibe.d covers a lot of the language features
        ref_to_use=master
        ;;
    https://github.com/bpfkorea/agora)
        # BPFK doesn't really have releases for the time being
        latest_tag=v0.x.x
        ;;
    *)
        ;;
esac

echo "--- Checking ${REPO_FULL_NAME} for a core repository and branch merging with ${BUILDKITE_REPO}"

# Don't checkout a tagged version of the core repositories like Phobos
case "$REPO_FULL_NAME" in
    "dlang/dmd" | \
    "dlang/druntime" | \
    "dlang/phobos" | \
    "dlang/phobos+no-autodecode" | \
    "dlang/tools" | \
    "dlang/dub" | \
    "dlang/ci")
        # if the core repo is the current repo, then just merge its head
        if [[ "${BUILDKITE_REPO:-b}" =~ ^${REPO_URL:-a}([.]git)?$ ]] ; then
            echo "--- Merging with the upstream target branch"
            "$DIR/merge_head.sh"
            ref_to_use="IS-ALREADY-CHECKED-OUT"
        else
            # for the main core repositories,
            # clone_repositories.sh will clone them together
            case "$REPO_FULL_NAME" in
                "dlang/dmd" | \
                "dlang/druntime" | \
                "dlang/phobos" | \
                "dlang/phobos+no-autodecode")
                ref_to_use="IS-ALREADY-CHECKED-OUT"
                ;;
            *)
                # otherwise checkout the respective branch
                ref_to_use=$("$DIR/origin_target_branch.sh" "${REPO_URL}")
            esac
        fi
        ;;
    *)
esac

if [ "$ref_to_use" != "IS-ALREADY-CHECKED-OUT" ] ; then
    echo "--- Cloning ${REPO_URL} (tag: $ref_to_use)"
    git clone -b "${ref_to_use}" --depth 1 "${REPO_URL}" "${REPO_DIR}"
    cd "${REPO_DIR}"
else
    # list the entire directory layout for debugging
    ls -R
    echo "--- Reusing existing layout for ${REPO_URL}"
    cd ..
fi

use_travis_test_script()
{
    # Strip any meson tests
    (echo "set -xeu" && "$DIR/travis_get_script") | sed -e '/meson/d' | bash
}

remove_spurious_vibed_tests()
{
    # these vibe.d tests tend to timeout or fail often
    rm -rf tests/std.concurrency # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2057
    rm -rf tests/vibe.http.client.1389 # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2078
    rm -rf tests/redis # FIXME
}

remove_spurious_vibe_core_tests()
{
    # https://github.com/vibe-d/vibe-core/issues/184
    rm -rf tests/vibe.core.process.d
    # https://github.com/vibe-d/vibe-core/issues/190
    rm -rf tests/vibe.core.net.1452.d
}

################################################################################
# Add custom build instructions here
################################################################################

echo "--- Running the testsuite"
case "$REPO_FULL_NAME" in

    gtkd-developers/GtkD)
        make "DC=$DC"
        ;;

    higgsjs/Higgs)
        make -C source test "DC=$DC"
        ;;

    vibe-d/vibe.d+base)
        VIBED_DRIVER=vibe-core PARTS=builds,unittests ./travis-ci.sh
        ;;
    vibe-d/vibe.d+examples)
        VIBED_DRIVER=vibe-core PARTS=examples ./travis-ci.sh
        ;;
    vibe-d/vibe.d+tests)
        remove_spurious_vibed_tests
        VIBED_DRIVER=vibe-core PARTS=tests ./travis-ci.sh
        ;;

    vibe-d/vibe-core+epoll)
        remove_spurious_vibe_core_tests
        CONFIG=epoll ./travis-ci.sh
        ;;

    vibe-d/vibe-core+select)
        remove_spurious_vibe_core_tests
        CONFIG=select ./travis-ci.sh
        ;;

    dlang/ci)
        if [ "${BUILDKITE_PULL_REQUEST:-false}" != "false" ]; then
            echo "--- Check that the PR commit has been merged into the target branch"
            echo "Current commit: $(git describe --always)"
            [[ "$(git log --format=%B -n 1)" =~ Merge[[:space:]]${BUILDKITE_COMMIT:-invalid} ]]
        fi
        echo "--- Test cloning all core repositories"
        "$DIR"/clone_repositories.sh
        if [ "${BUILDKITE_PULL_REQUEST:-false}" != "false" ]; then
            ( cd ci && [[ "$(git log --format=%B -n 1)" =~ Merge[[:space:]]${BUILDKITE_COMMIT:-invalid} ]])
        fi
        ;;

    dlang/dlang-bot)
        dub test --compiler=$DC -- --single --trace
        ;;

    dlang/dub)
        rm test/issue895-local-configuration.sh # FIXME
        rm test/issue884-init-defer-file-creation.sh # FIXME
        # https://github.com/dlang/dub/commit/8b4ab6e0ebd930463198b19c4acf2f7fcc7bc7cd
        if [ ! -f ./travis-ci.sh ]; then
           use_travis_test_script
        else
            sed -i '/^source.*activate/d' travis-ci.sh
            DC=$DC ./travis-ci.sh
        fi
        ;;

    dlang/tools)
        # explicit test to avoid Digger setup, see dlang/tools#298 and dlang/tools#301
        make -f posix.mak all DMD='dmd' DFLAGS=
        make -f posix.mak test DMD='dmd' DFLAGS=
        ;;

    msgpack/msgpack-d)
        make -f posix.mak unittest "DMD=$DMD" MODEL=64
        ;;

    dlang-community/libdparse)
        git submodule update --init --recursive
        cd test && ./run_tests.sh
        ;;

    dlang-community/containers)
        make -B -C test/ || echo failed # FIXME
        ;;

    BlackEdder/ggplotd)
        # workaround https://github.com/BlackEdder/ggplotd/issues/34
        sed -i 's|auto seed = unpredictableSeed|auto seed = 54321|' source/ggplotd/example.d
        use_travis_test_script
        ;;

    AuburnSounds/intel-intrinsics)
        export TRAVIS_OS_NAME="none"   # do not run x86 tests
        export TRAVIS_CPU_ARCH="amd64" # do not run arm64 tests
        use_travis_test_script
        ;;


    dlang-community/D-YAML)
        dub build "--compiler=$DC"
        dub test "--compiler=$DC"
        ;;

    sociomantic-tsunami/ocean)
        git submodule update --init
        make test V=1 F=prod ALLOW_DEPRECATIONS=1
        ;;
    sociomantic-tsunami/turtle | \
    sociomantic-tsunami/swarm)
        git submodule update --init
        make test V=1 F=production ALLOW_DEPRECATIONS=1
        ;;

    bpfkorea/agora)
        git submodule update --init
        dub build --compiler=$DC
        dub test --compiler=$DC
        ;;

    eBay/tsv-utils)
        make test "DCOMPILER=$DC"
        ;;

    dlang-tour/core)
        cd public/content && git clone --depth 15 https://github.com/dlang-tour/english en
        cd ../.. && git submodule update
        dub test "--compiler=$DC"
        ;;

    CyberShadow/ae)
        # remove failing extended attribute test
        perl -0777 -pi -e "s/unittest[^{]*{[^{}]*xAttrs[^{}]*}//" sys/file.d
        use_travis_test_script
        ;;

    ikod/dlang-requests)
        # full test suite is currently disabled
        # see https://github.com/dlang/ci/pull/166
        dub build -c std
        ;;

    libmir/mir-algorithm | \
    libmir/mir | \
    pbackus/sumtype | \
    aliak00/optional)
        dub test "--compiler=$DC"
        ;;

    ldc-developers/ldc)
        git submodule update --init
        mkdir bootstrap && cd bootstrap
        cmake .. \
          -GNinja \
          -DCMAKE_BUILD_TYPE=Debug \
          -DD_COMPILER="$DC" \
          -DCMAKE_SYSTEM_NAME=Linux # work around gen_gccbuiltins linker issue with llvm-8 pkg
        ninja -j2 ldmd2 druntime-ldc-debug phobos2-ldc-debug
        cd ..
        mkdir build && cd build
        # LDC_LINK_MANUALLY=OFF works around an LDC 1.24.0 problem with CMAKE_BUILD_TYPE=Debug
        # without *release* host druntime/Phobos.
        cmake .. \
          -GNinja \
          -DCMAKE_BUILD_TYPE=Debug \
          -DD_COMPILER="$(pwd)/../bootstrap/bin/ldmd2" \
          -DLDC_LINK_MANUALLY=OFF \
          -DCMAKE_SYSTEM_NAME=Linux # work around gen_gccbuiltins linker issue with llvm-8 pkg
        ninja -j2 ldc2 druntime-ldc phobos2-ldc
        ;;

    dlang/dmd | \
    dlang/druntime | \
    dlang/phobos)
        "$DIR"/clone_repositories.sh
        # To avoid running into "Path too long" issues, see e.g. https://github.com/dlang/ci/pull/287
        export TMP="/tmp/${BUILDKITE_AGENT_NAME}"
        export TEMP="$TMP"
        export TMPDIR="$TMP"
        rm -rf "$TMP" && mkdir -p "$TMP"
        # patch makefile which requires gdb 8 - see https://github.com/dlang/ci/pull/301
        sed "s/TESTS+=rt_trap_exceptions_drt_gdb//" -i druntime/test/exceptions/Makefile
        # build druntime for phobos first, s.t. it doesn't fault when copying the druntime files in parallel
        # see https://github.com/dlang/ci/pull/340
        if [ "$REPO_FULL_NAME" == "dlang/phobos" ] ; then
            make -C druntime -j2 -f posix.mak
        fi
        cd "$(basename "${REPO_FULL_NAME}")"&& make -f posix.mak clean && make -f posix.mak -j2 buildkite-test
        rm -rf "$TMP"
        ;;

    dlang/phobos+no-autodecode)
        "$DIR"/clone_repositories.sh
        # To avoid running into "Path too long" issues, see e.g. https://github.com/dlang/ci/pull/287
        export TMP="/tmp/${BUILDKITE_AGENT_NAME}"
        export TEMP="$TMP"
        export TMPDIR="$TMP"
        export NO_AUTODECODE=1
        rm -rf "$TMP" && mkdir -p "$TMP"
        # patch makefile which requires gdb 8 - see https://github.com/dlang/ci/pull/301
        sed "s/TESTS+=rt_trap_exceptions_drt_gdb//" -i druntime/test/exceptions/Makefile
        # build druntime for phobos first, s.t. it doesn't fault when copying the druntime files in parallel
        # see https://github.com/dlang/ci/pull/340
        make -C druntime -j2 -f posix.mak
        cd phobos && make -f posix.mak clean && make -f posix.mak -j2 autodecode-test
        rm -rf "$TMP"
        ;;

    d-language-server/dls)
        # https://github.com/dlang/ci/issues/360
        # dub's .editorconfig influences the behavior of dfmt
        rm -f .editorconfig
        rm -f ../.editorconfig
        rm -f ../../.editorconfig
        use_travis_test_script
        ;;

    MartinNowak/io)
        export BUILD_TOOL=dub
        export COVERAGE=false
        export SKIP_IPv6_LOOPBACK_TESTS=yes
        use_travis_test_script
        ;;

    atilaneves/unit-threaded)
        dub test
        ;;

    d-widget-toolkit/dwt)
        dub build
        ./tools/test_snippets.d
        ;;

    *)
        use_travis_test_script
        ;;
esac

# final cleanup
git clean -ffdxq .
