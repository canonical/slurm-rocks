#!/usr/bin/env sh

set -eu

main() {
    mkdir -p /sys/fs/cgroup/system.slice
    /usr/sbin/slurmd -D -s $@
}
main $@
