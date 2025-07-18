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

build_dir := justfile_dir() / "_build"
rocks_dir := justfile_dir() / "rocks"
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

# Import rocks into the Docker daemon
[group("dev")]
import *args:
    #!/usr/bin/env bash
    set -eu pipefail

    targets=({{prepend(rocks_dir + "/", args) || default_targets}})
    for target in ${targets[@]}; do
        name=$(basename $target)
        rock=$(find {{build_dir}} -maxdepth 1 -type f -iname "${name}_*.rock" | head -1)
        echo -e "\033[1mImporting rock $name\033[0m"
        {{skopeo}} --insecure-policy copy \
            oci-archive:$rock \
            docker-daemon:${name}:latest
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

# Check code against coding style standards
[group("lint")]
lint:
	{{yamllint}} {{rocks_dir}}

# Show available recipes
help:
	@just --list --unsorted
