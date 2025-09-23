#!/bin/bash

set -eux pipefail

# Creates a common network that will be used by all the Slurm services.
docker network inspect charmed-hpc >/dev/null 2>&1 \
    || docker network create charmed-hpc

docker run --rm --detach \
    --name slurmctld \
    --network charmed-hpc \
    --user 401:401 \
    slurmctld:latest

docker run --rm --detach \
    --name slurmdbd \
    --network charmed-hpc \
    --user 401:401 \
    slurmdbd:latest

docker run --rm --detach \
    --name sackd \
    --network charmed-hpc \
    --user 401:401 \
    sackd:latest \
        --conf-server slurmctld

# The slurmd service requires a privileged container to setup its cgroup directory.
docker run --rm --detach \
    --name slurmd \
    --network charmed-hpc \
    --privileged \
    slurmd:latest \
        --conf-server slurmctld

# The slurmrestd service requires SYS_ADMIN capabilities.
docker run --rm --detach \
    --name slurmrestd \
    --network charmed-hpc \
    --user 65534:65534 \
    slurmrestd:latest \
        -f /etc/slurm/slurm.conf \
        0.0.0.0:6820

# The slurmdbd service requires a MySQL database to store accounting data
docker run --rm --detach \
    --name mysql \
    --network charmed-hpc \
    --env MYSQL_ROOT_PASSWORD=password \
    mysql:latest

export SLURMCTLD=$(docker exec slurmctld hostname -s)
export SLURMD=$(docker exec slurmd hostname -s)
export SLURMDBD=$(docker exec slurmdbd hostname -s)

# Generate the secret keys

dd if=/dev/random of=/tmp/slurm.key bs=256 count=1
dd if=/dev/random of=/tmp/jwt_hs256.key bs=32 count=1

# Copy the secret keys onto all the services.

docker cp /tmp/slurm.key slurmctld:/etc/slurm/slurm.key
docker cp /tmp/slurm.key slurmd:/etc/slurm/slurm.key
docker cp /tmp/slurm.key slurmdbd:/etc/slurm/slurm.key
docker cp /tmp/slurm.key sackd:/etc/slurm/slurm.key
docker cp /tmp/slurm.key slurmrestd:/etc/slurm/slurm.key
docker cp /tmp/jwt_hs256.key slurmctld:/var/lib/slurm/checkpoint/jwt_hs256.key
docker cp /tmp/jwt_hs256.key slurmdbd:/var/lib/slurm/checkpoint/jwt_hs256.key

# Setup the correct permissions for the keys.

docker exec --user 0 slurmctld chmod 600 /etc/slurm/slurm.key
docker exec --user 0 slurmctld chown slurm:slurm /etc/slurm/slurm.key
docker exec --user 0 slurmctld chmod 600 /var/lib/slurm/checkpoint/jwt_hs256.key
docker exec --user 0 slurmctld chown slurm:slurm /var/lib/slurm/checkpoint/jwt_hs256.key

docker exec --user 0 slurmd chmod 600 /etc/slurm/slurm.key
docker exec --user 0 slurmd chown slurm:slurm /etc/slurm/slurm.key

docker exec --user 0 slurmdbd chmod 600 /etc/slurm/slurm.key
docker exec --user 0 slurmdbd chown slurm:slurm /etc/slurm/slurm.key
docker exec --user 0 slurmdbd chmod 600 /var/lib/slurm/checkpoint/jwt_hs256.key
docker exec --user 0 slurmdbd chown slurm:slurm /var/lib/slurm/checkpoint/jwt_hs256.key

docker exec --user 0 slurmrestd chmod 600 /etc/slurm/slurm.key
docker exec --user 0 slurmrestd chown slurm:slurm /etc/slurm/slurm.key

docker exec --user 0 sackd chmod 600 /etc/slurm/slurm.key
docker exec --user 0 sackd chown slurm:slurm /etc/slurm/slurm.key

# Setup the correct permissions for the configuration files

docker exec --user 0 slurmctld touch /etc/slurm/slurm.conf
docker exec --user 0 slurmctld chmod 644 /etc/slurm/slurm.conf
docker exec --user 0 slurmctld chown slurm:slurm /etc/slurm/slurm.conf
docker exec --user 0 slurmctld touch /etc/slurm/cgroup.conf
docker exec --user 0 slurmctld chmod 644 /etc/slurm/cgroup.conf
docker exec --user 0 slurmctld chown slurm:slurm /etc/slurm/cgroup.conf

docker exec --user 0 slurmdbd touch /etc/slurm/slurmdbd.conf
docker exec --user 0 slurmdbd chmod 600 /etc/slurm/slurmdbd.conf
docker exec --user 0 slurmdbd chown slurm:slurm /etc/slurm/slurmdbd.conf

docker exec --user 0 slurmrestd touch /etc/slurm/slurm.conf
docker exec --user 0 slurmrestd chmod 644 /etc/slurm/slurm.conf
docker exec --user 0 slurmrestd chown slurm:slurm /etc/slurm/slurm.conf

# Write the configuration files into the services.

cat slurm.conf.tmpl \
    | envsubst \
    | docker exec --user 0 --interactive slurmctld sh -c 'cat > /etc/slurm/slurm.conf'
cat cgroup.conf \
    | docker exec --user 0 --interactive slurmctld sh -c 'cat > /etc/slurm/cgroup.conf'
cat slurm.conf.tmpl \
    | envsubst \
    | docker exec --user 0 --interactive slurmrestd sh -c 'cat > /etc/slurm/slurm.conf'
cat slurmdbd.conf.tmpl \
    | envsubst \
    | docker exec --user 0 --interactive slurmdbd sh -c 'cat > /etc/slurm/slurmdbd.conf'
