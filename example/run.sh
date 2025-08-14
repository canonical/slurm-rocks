#!/bin/bash

set -eux pipefail

# Creates a common network that will be used by all the Slurm services.
docker network inspect charmed-hpc >/dev/null 2>&1 || \
    docker network create charmed-hpc

docker run --rm -d \
    --name slurmctld \
    --network charmed-hpc \
    slurmctld:latest

docker run --rm -d \
    --name slurmdbd \
    --network charmed-hpc \
    slurmdbd:latest

docker run --rm -d \
    --name sackd \
    --network charmed-hpc \
    sackd:latest \
        --args sackd \
        --conf-server slurmctld

# The slurmd service requires a privileged container to setup its cgroup directory.
docker run --rm -d \
    --name slurmd \
    --network charmed-hpc \
    --privileged \
    slurmd:latest \
        --args slurmd \
        --conf-server slurmctld

# The slurmrestd service requires SYS_ADMIN capabilities.
docker run --rm -d \
    --name slurmrestd \
    --network charmed-hpc \
    --cap-add SYS_ADMIN \
    slurmrestd:latest \
        --args slurmrestd \
        -f /etc/slurm/slurm.conf \
        0.0.0.0:6820

# The slurmdbd service requires a MySQL database to store accounting data
docker run --rm -d \
    --name mysql \
    --network charmed-hpc \
    -e MYSQL_ROOT_PASSWORD=password \
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

docker exec slurmctld chmod 600 /etc/slurm/slurm.key
docker exec slurmctld chown slurm:slurm /etc/slurm/slurm.key
docker exec slurmctld chmod 600 /var/lib/slurm/checkpoint/jwt_hs256.key
docker exec slurmctld chown slurm:slurm /var/lib/slurm/checkpoint/jwt_hs256.key

docker exec slurmd chmod 600 /etc/slurm/slurm.key
docker exec slurmd chown slurm:slurm /etc/slurm/slurm.key

docker exec slurmdbd chmod 600 /etc/slurm/slurm.key
docker exec slurmdbd chown slurm:slurm /etc/slurm/slurm.key
docker exec slurmdbd chmod 600 /var/lib/slurm/checkpoint/jwt_hs256.key
docker exec slurmdbd chown slurm:slurm /var/lib/slurm/checkpoint/jwt_hs256.key

docker exec slurmrestd chmod 600 /etc/slurm/slurm.key
docker exec slurmrestd chown slurmrestd:slurmrestd /etc/slurm/slurm.key

docker exec sackd chmod 600 /etc/slurm/slurm.key
docker exec sackd chown slurm:slurm /etc/slurm/slurm.key

# Setup the correct permissions for the configuration files

docker exec slurmctld touch /etc/slurm/slurm.conf
docker exec slurmctld chmod 644 /etc/slurm/slurm.conf
docker exec slurmctld chown slurm:slurm /etc/slurm/slurm.conf
docker exec slurmctld touch /etc/slurm/cgroup.conf
docker exec slurmctld chmod 644 /etc/slurm/cgroup.conf
docker exec slurmctld chown slurm:slurm /etc/slurm/cgroup.conf

docker exec slurmdbd touch /etc/slurm/slurmdbd.conf
docker exec slurmdbd chmod 600 /etc/slurm/slurmdbd.conf
docker exec slurmdbd chown slurm:slurm /etc/slurm/slurmdbd.conf

docker exec slurmrestd touch /etc/slurm/slurm.conf
docker exec slurmrestd chmod 644 /etc/slurm/slurm.conf
docker exec slurmrestd chown slurmrestd:slurmrestd /etc/slurm/slurm.conf

# Write the configuration files into the services.

cat slurm.conf.tmpl | envsubst | docker exec -i slurmctld sh -c 'cat > /etc/slurm/slurm.conf'
cat cgroup.conf | docker exec -i slurmctld sh -c 'cat > /etc/slurm/cgroup.conf'
cat slurm.conf.tmpl | envsubst | docker exec -i slurmrestd sh -c 'cat > /etc/slurm/slurm.conf'
cat slurmdbd.conf.tmpl | envsubst | docker exec -i slurmdbd sh -c 'cat > /etc/slurm/slurmdbd.conf'

# Make sure the slurmctld daemon has time to setup itself.
sleep 10

# Restart the slurmd and sackd services to establish the connection with the slurmctld service
docker exec slurmd pebble restart slurmd
docker exec slurmd pebble restart sackd
