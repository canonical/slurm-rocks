# Copyright 2025 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set unstable := true
rockcraft := require("rockcraft")
skopeo := which("rockcraft.skopeo") || require("skopeo")
yamllint := require("yamllint")
lxc := require("lxc")
yq := require("yq")

build_dir := justfile_dir() / "_build"
rocks_dir := justfile_dir() / "rocks"
tests_dir := justfile_dir() / "tests"
default_targets := shell("ls -d -- $1/*", rocks_dir)

[private]
default:
    @just help

# Pack rocks
[group("dev")]
pack *args:
    #!/usr/bin/env bash
    set -eu pipefail

    mkdir -p {{build_dir}}
    targets=({{prepend(rocks_dir + "/", args) || default_targets}})
    for target in ${targets[@]}; do
        echo -e "\033[1mPacking rock \`$(basename $target)\`\033[0m"

        cd $target
        {{rockcraft}} -v pack
        mv *.rock {{build_dir}}
        echo
    done

[doc("""
  Publish rocks into an OCI archive using `skopeo copy`.

  The `SKOPEO_FLAGS` environment variable can be used to pass any arguments to
  Skopeo.
""")]
[group("dev")]
publish base version="latest" *args:
    #!/usr/bin/env bash
    set -eu pipefail

    targets=({{prepend(rocks_dir + "/", args) || default_targets}})
    for target in ${targets[@]}; do
        name=$(basename $target)
        rock=$(find {{build_dir}} -maxdepth 1 -type f -iname "${name}_*.rock" | head -1)
        echo -e "\033[1mPublishing rock $name\033[0m"
        {{skopeo}} --insecure-policy copy \
            ${SKOPEO_FLAGS:-} \
            oci-archive:$rock \
            {{base}}${name}:{{version}}
    done


# Clean project directory and rock builder instances
[group("dev")]
clean:
    #!/usr/bin/env bash
    set -eu pipefail

    rm -rf {{build_dir}}

    targets=({{default_targets}})
    for target in ${targets[@]}; do
       echo -e "\033[1mCleaning rock builder instance \`$(basename $target)\`\033[0m"
       cd $target
       {{rockcraft}} -v clean
       echo
    done

[doc("""
  Run integration tests using LXD

  Setting the `SLURM_ROCKS_PRESERVE` environment will skip deleting the
  machine after a test success. Failing a test will always preserve the machine
  it was run on.
""")]
[group("dev")]
integration:
    #!/usr/bin/env bash
    set -eu pipefail

    run_test() {
        test_file=$1
        test_name=$(basename -s .sh $test_file)
        export MACHINE="slurm-rocks-$test_name-{{choose('6', HEX)}}"

        {{lxc}} launch ubuntu:24.04 $MACHINE \
            -c limits.cpu=4 \
            -c limits.memory=8GiB \
            --device root,size=50GiB \
            --vm \
            --config=user.user-data="$(cat {{tests_dir / "vm-setup.yaml"}})"

        processes=-1
        while : ; do
            processes=$({{lxc}} info $MACHINE | {{yq}} .Resources.Processes)
            # The number of processes will be -1 if the LXD agent has not started.
            [[ $processes -eq -1 ]] || break
            sleep 2
        done

        echo -e "\033[1mWaiting for cloud-init\033[0m"
        {{lxc}} exec $MACHINE -- cloud-init status --wait --long

        targets=({{default_targets}})
        for target in ${targets[@]}; do
            name=$(basename $target)
            rock=$(find {{build_dir}} -maxdepth 1 -type f -iname "${name}_*.rock" | head -1)
            echo -e "\033[1mPushing rock $name\033[0m"
            {{lxc}} file push $rock $MACHINE/root/${name}.rock

            {{lxc}} exec $MACHINE -- rockcraft.skopeo copy \
                --insecure-policy \
                --dest-tls-verify=false \
                oci-archive:/root/${name}.rock \
                docker://localhost:30100/${name}:latest
        done

        echo -e "\033[1mRunning \`${test_name}\`\033[0m"
        $test_file

        if [ -v SLURM_ROCKS_PRESERVE ]; then
            echo -e "\033[1mSkipped Cleaning up machine \`${MACHINE}\`\033[0m"
        else
            echo -e "\033[1mCleaning up machine \`${MACHINE}\`\033[0m"
            {{lxc}} delete $MACHINE --force
        fi
    }

    export -f run_test

    find {{tests_dir}} -maxdepth 1 -type f -iname "test*.sh" \
        | xargs -0L1 bash -c 'set -eu pipefail; run_test "$0"'

# Check code against coding style standards
[group("lint")]
lint:
	{{yamllint}} {{rocks_dir}}

# Show available recipes
help:
	@just --list --unsorted
