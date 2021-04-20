#!/bin/bash

# Don't run Buildkite for the dmd-cxx branch
if [ "${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-master}" == "dmd-cxx" ] ; then
    echo ""
    exit 0
fi

read -r -d '' LOAD_CI_FOLDER <<- EOM
        # just to be sure there isn't anything old left
        git clean -ffdxq .
        echo "--- Load CI folder"
        # make sure the entire CI folder is loaded
        if [ ! -d buildkite ] ; then
           mkdir -p buildkite && pushd buildkite
           wget https://github.com/dlang/ci/archive/master.tar.gz
           tar xvfz master.tar.gz --strip-components=2 ci-master/buildkite
           rm -rf master.tar.gz && popd
        fi
        echo "--- Merging with the upstream target branch"
        ./buildkite/merge_head.sh
EOM

read -r -d '' LOAD_DISTRIBUTION <<- EOM
        # just to be sure there isn't anything old left
        git clean -ffdxq .
        echo "--- Load distribution archive"
        buildkite-agent artifact download distribution.tar.xz .
        tar xfJ distribution.tar.xz
        rm -rf buildkite
        mv distribution/buildkite buildkite
        rm distribution.tar.xz
EOM

read -r -d '' DEFAULT_COMMAND_PROPS <<- EOM
    branches: !dmd-cxx
    timeout_in_minutes: 60
    retry:
      automatic:
        limit: 3
EOM

cat << EOF
steps:
  - command: |
        echo "--- Print environment"
        uname -a
        git --version
        make --version
        \\\${SHELL} --version || true
        c++ --version
        ld -v
        ! command -v gdb &>/dev/null || gdb --version
        ! dmd --version # ensure that no dmd is the current environment
        ${LOAD_CI_FOLDER}
        ./buildkite/build_distribution.sh
    label: "Build"
    artifact_paths: "distribution.tar.xz"
    ${DEFAULT_COMMAND_PROPS}
EOF

################################################################################

cat << 'EOF'
  - wait
EOF

################################################################################
# Style & coverage targets
# Must run after the 'wait' to avoid blocking the build_distribution step
# (and thus all subsequent project builds)
################################################################################

case "${BUILDKITE_REPO:-x}" in
    "https://github.com/dlang/dmd.git" | \
    "https://github.com/dlang/druntime.git" | \
    "https://github.com/dlang/phobos.git")

cat << EOF
  - command: |
        ${LOAD_DISTRIBUTION}
        . ./buildkite/load_distribution.sh
        echo "--- Merging with the upstream target branch"
        ./buildkite/merge_head.sh
        echo "--- Running style testing"
        ./buildkite/style.sh
    label: "Style"
    ${DEFAULT_COMMAND_PROPS}

  - command: |
        ${LOAD_DISTRIBUTION}
        . ./buildkite/load_distribution.sh
        echo "--- Merging with the upstream target branch"
        ./buildkite/merge_head.sh
        echo "--- Running coverage testing"
        ./buildkite/test_coverage.sh
    label: "Coverage"
    ${DEFAULT_COMMAND_PROPS}
EOF
        ;;
    *)
        ;;
esac

################################################################################
# Add your project here.
# By default, the Project Tester will perform your Travis 'script' tests.
# If a different action is preferred, set it in buildkite/build_project.sh
################################################################################
projects=(
    # sorted by test time fast to slow (to minimize pending queue length)
    "vibe-d/vibe.d+examples" # 9m51s
    "vibe-d/vibe.d+tests" # 6m44s
    "dlang/dlang-bot" # 4m54s
    "ldc-developers/ldc" # 4m49s
    "vibe-d/vibe.d+base" # 4m31s
    "dlang/phobos" # 4m50s
    "dlang/phobos+no-autodecode"
    "sociomantic-tsunami/ocean" # 4m49s
    "sociomantic-tsunami/swarm"
    "sociomantic-tsunami/turtle"
    "dlang/dub" # 3m55s
    "vibe-d/vibe-core+epoll" # 3m38s
    "vibe-d/vibe-core+select" # 3m30s
    "higgsjs/Higgs" # 3m10s
    "rejectedsoftware/ddox" # 2m42s
    "BlackEdder/ggplotd" # 1m56s
    #"d-language-server/dls" # 1m55s
    "eBay/tsv-utils" # 1m41s
    "dlang-community/D-Scanner" # 1m40s
    "dlang/druntime" # 1m18s
    "dlang-tour/core" # 1m17s
    "d-widget-toolkit/dwt" # 1m16s
    "rejectedsoftware/diet-ng" # 56s
    "mbierlee/poodinis" # 40s
    "dlang/tools" # 40s
    "atilaneves/unit-threaded" #38s
    #"d-gamedev-team/gfm" # 28s
    "gecko0307/dagon" # 25s
    "dlang-community/DCD" # 23s
    #"weka-io/mecca" # 22s
    "CyberShadow/ae" # 22s
    "jmdavis/dxml" # 22s
    "jacob-carlborg/dstep" # 18s
    "libmir/mir-algorithm" # 17s
    "dlang-community/D-YAML" # 15s
    "libmir/mir-random" # 13s
    "dlang-community/libdparse" # 13s
    "aliak00/optional" # 12s
    "dlang-community/dfmt" # 11s
    # run in under 10s sorted alphabetically
    "Abscissa/libInputVisitor"
    #"ariovistus/pyd"
    "atilaneves/automem"
    "AuburnSounds/intel-intrinsics"
    "bpfkorea/agora"
    "DerelictOrg/DerelictFT"
    "DerelictOrg/DerelictGL3"
    "DerelictOrg/DerelictGLFW3"
    "DerelictOrg/DerelictSDL2"
    "dlang-community/containers"
    "dlang/undeaD"
    "DlangScience/scid"
    "Geod24/localrest"
    "ikod/dlang-requests"
    "kaleidicassociates/excel-d"
    "kaleidicassociates/lubeck"
    # Need a zmq version >= 4.3
    # See https://github.com/kyllingstad/zmqd/blob/v1.2.0/CHANGELOG.md#changed
    #"kyllingstad/zmqd"
    "lgvz/imageformats"
    "libmir/mir"
    "libmir/mir-core"
    "libmir/mir-cpuid"
    "libmir/mir-optim"
    "msoucy/dproto"
    "Netflix/vectorflow"
    "nomad-software/dunit"
    "pbackus/sumtype"
    "PhilippeSigaud/Pegged"
    "repeatedly/mustache-d"
    "s-ludwig/std_data_json"
    "s-ludwig/taggedalgebraic"
    "MartinNowak/io"
)
# Add all projects that require more than 3GB of memory to build
declare -A memory_req
memory_req["BlackEdder/ggplotd"]=high
memory_req["dlang-community/D-Scanner"]=high
memory_req["vibe-d/vibe-core+select"]=high
memory_req["vibe-d/vibe-core+epoll"]=high
memory_req["vibe-d/vibe.d+base"]=high
memory_req["libmir/mir-algorithm"]=high
memory_req["sociomantic-tsunami/ocean"]=high
memory_req["dlang/dlang-bot"]=high
memory_req["dlang/phobos"]=high
memory_req["dlang/phobos+no-autodecode"]=high
memory_req["dlang/dub"]=high
memory_req["higgsjs/Higgs"]=high
memory_req["d-language-server/dls"]=high

# self-test PRs to dlang/ci
if [[ "${BUILDKITE_REPO:-b}" =~ ^https://github.com/dlang/ci([.]git)?$ ]] ; then
    projects+=("dlang/ci")
fi

for project_name in "${projects[@]}" ; do
    project="$(echo "$project_name" | sed "s/\([^+]*\)+.*/\1/")"
cat << EOF
  - command: |
        # just to be sure there isn't anything old left
        git clean -ffdxq .

        # don't build everything from the root folder
        mkdir build && cd build

        export REPO_URL="https://github.com/${project}"
        export REPO_DIR="$(echo "${project_name}" | tr '/' '-')"
        export REPO_FULL_NAME="${project_name}"

        ${LOAD_DISTRIBUTION}
        ./buildkite/build_project.sh
    label: "${project_name}"
    ${DEFAULT_COMMAND_PROPS}
EOF

if [ "${memory_req["$project_name"]:-x}" != "x" ] ; then
cat << EOF
    agents:
      - "memory=${memory_req["$project_name"]}"
EOF
fi

done
