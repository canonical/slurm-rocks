#!/usr/bin/env bash
set -eux pipefail

SLINKY_VERSION=1.1.0

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

lxc file push $SCRIPT_DIR/values-mariadb.yaml $MACHINE/root/values-mariadb.yaml

lxc exec $MACHINE -- bash <<EOF
set -eux pipefail

echo "Installing helm requirements..."

helm repo add mariadb-operator https://helm.mariadb.com/mariadb-operator
helm repo update

helm install mariadb-operator-crds mariadb-operator/mariadb-operator-crds
helm install mariadb-operator mariadb-operator/mariadb-operator \
  -n=mariadb \
  --create-namespace
k8s kubectl wait pod --all --for=condition=Ready -n=mariadb --timeout=10m

helm install slurm-operator-crds oci://ghcr.io/slinkyproject/charts/slurm-operator-crds \
  --version=${SLINKY_VERSION}
helm install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
  --version=${SLINKY_VERSION} \
  -n=slinky \
  --create-namespace
k8s kubectl wait pod --all --for=condition=Ready -n=slinky --timeout=10m

k8s kubectl create ns slurm

echo "Deploying mariadb..."
k8s kubectl create secret generic mariadb-root --from-literal=password=password -n=slurm
k8s kubectl create secret generic mariadb-password --from-literal=password=password -n=slurm
helm install mariadb mariadb-operator/mariadb-cluster -n=slurm -f values-mariadb.yaml
k8s kubectl wait pod --all --for=condition=Ready -n=slurm --timeout=10m

echo "Deploying slurm..."
helm install slurm oci://ghcr.io/slinkyproject/charts/slurm \
  --version=${SLINKY_VERSION} \
  -n=slurm \
  --set 'controller.slurmctld.image.repository=localhost:30100/slurmctld' \
  --set 'controller.slurmctld.image.tag=latest' \
  --set 'controller.reconfigure.image.repository=localhost:30100/slurmctld' \
  --set 'controller.reconfigure.image.tag=latest' \
  --set 'restapi.slurmrestd.image.repository=localhost:30100/slurmrestd' \
  --set 'restapi.slurmrestd.image.tag=latest' \
  --set 'accounting.enabled=true' \
  --set 'accounting.slurmdbd.image.repository=localhost:30100/slurmdbd' \
  --set 'accounting.slurmdbd.image.tag=latest' \
  --set 'accounting.storageConfig.host=mariadb-mariadb-cluster' \
  --set 'accounting.storageConfig.database=slurmdb' \
  --set 'nodesets.slinky.slurmd.image.repository=localhost:30100/slurmd' \
  --set 'nodesets.slinky.slurmd.image.tag=latest' \
  --set 'nodesets.slinky.partition.enabled=true' \
  --set 'loginsets.slinky.enabled=true' \
  --set 'loginsets.slinky.login.image.repository=localhost:30100/login' \
  --set 'loginsets.slinky.login.image.tag=latest' \
  --set 'loginsets.slinky.service.spec.type=NodePort' \
  --set 'loginsets.slinky.service.port=22' \
  --set-file "loginsets.slinky.rootSshAuthorizedKeys=\${HOME}/.ssh/id_ed25519.pub"

k8s kubectl wait pod --all --for=condition=Ready -n=slurm --timeout=10m

# Generate JWT token
LOGIN_POD=\$(k8s kubectl get pod -n=slurm -o name | grep 'slurm-login-slinky' | head -1)
export "\$(k8s kubectl exec -n=slurm "\$LOGIN_POD" -- scontrol token lifespan=3600)"

# Get slurmrestd service ClusterIP
RESTAPI_IP=\$(k8s kubectl get svc slurm-restapi -n=slurm -o jsonpath='{.spec.clusterIP}')

echo "Testing slurmrestd ping endpoint..."
PING_RESPONSE=\$(curl -s -H "X-SLURM-USER-NAME: root" -H "X-SLURM-USER-TOKEN: \$SLURM_JWT" http://\${RESTAPI_IP}:6820/slurm/v0.0.41/ping)
echo "\$PING_RESPONSE" | grep -q '"pinged": "UP"'

echo "Testing slurmrestd nodes endpoint..."
NODES_RESPONSE=\$(curl -s -H "X-SLURM-USER-NAME: root" -H "X-SLURM-USER-TOKEN: \$SLURM_JWT" http://\${RESTAPI_IP}:6820/slurm/v0.0.41/nodes)
echo "\$NODES_RESPONSE" | grep -q '"nodes":'

echo "Testing slurmrestd partitions endpoint..."
PARTITIONS_RESPONSE=\$(curl -s -H "X-SLURM-USER-NAME: root" -H "X-SLURM-USER-TOKEN: \$SLURM_JWT" http://\${RESTAPI_IP}:6820/slurm/v0.0.41/partitions)
echo "\$PARTITIONS_RESPONSE" | grep -q '"partitions":'

echo "Testing login node..."
port="\$(k8s kubectl -n=slurm get svc slurm-login-slinky -o jsonpath='{.spec.ports[0].nodePort}')"
ssh localhost \
    -i \${HOME}/.ssh/id_ed25519 \
    -p \$port \
    -o StrictHostKeyChecking=no \
    -- bash <<EOS

set -eux pipefail

scontrol ping
srun hostname < /dev/null
sacctmgr list stats

EOS

EOF
