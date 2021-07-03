# A Dockerfile to create an agent
#
# This is here for developer's convenience only and is not guaranteed
# to be up-to-date, as only the ansible scripts are used for deployment.
# However, it can be useful to spin an image locally to debug.
#
# To use it, one can first run `docker build $(pwd) -t dlangci`
# (provided pwd is the directory containing that file) to build the image,
# then `docker run --rm dlangci --token XXX --tags="memory=high" --name $USERNAME`
#
# The `token` can be found in Buildkite's dlang agents panel
# (https://buildkite.com/organizations/dlang/agents) if one has access.
#
# The `memory=high` tag is not required but your agent will not be dispatched
# jobs which have this requirement (see memory_req in buildkite.sh).
#
# Finally, the `--name` argument is not required but makes custom runners
# easier to identify from the agent tab.
#
# To debug build failures, one can use `docker run -it --entrypoint=/bin/sh dlangci`
# to get a shell and see if any dependency is missing / the state of the build directory.
#
# To target your runner specifically for a certain job, other `--tags` arguments  can be used.
FROM buildkite/agent:ubuntu

ADD travis_get_script /usr/local/bin/get_travis_test_script

RUN apt-get update && \
    apt-get install -y build-essential cmake curl gdb git jq sqlite3 libblas-dev \
    libbz2-dev libcairo-dev libcurl4-gnutls-dev libevent-dev libgcrypt20-dev libgpg-error-dev \
    libgtk-3-0 liblapack-dev liblzo2-dev libopenblas-dev libreadline-dev libssl-dev libxml2-dev \
    libxslt1-dev libzmq3-dev mongodb-server moreutils ninja-build \
    pkg-config python-dev python-yaml python3-nose redis-server \
    rsync ruby ruby-dev sudo unzip wget gnupg lsb-release \
    apt-utils software-properties-common
RUN bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"

# Install d-apt for dub / dmd (https://d-apt.sourceforge.io/)
RUN wget https://netcologne.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list
RUN apt update --allow-insecure-repositories && \
    apt -y --allow-unauthenticated install --reinstall d-apt-keyring && \
    apt-get update && apt -y install dmd-compiler dub

# Build ebtree for sociomantic libraries
# https://github.com/sociomantic-tsunami/ocean/commit/e895d9d6fc10f7f8a8829c197b2c66d310e2156f
RUN git clone https://github.com/sociomantic-tsunami/ebtree.git && \
    gem install --no-document fpm && \
    make -C ebtree deb && dpkg -i ebtree/deb/libebtree6*.deb && \
    rm -rf ebtree
