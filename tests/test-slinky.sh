#!/usr/bin/env bash
set -eux pipefail

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

helm install slurm-operator-crds oci://ghcr.io/slinkyproject/charts/slurm-operator-crds
helm install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
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
  -n=slurm \
  --set imagePullPolicy=always \
  --set controller.slurmctld.image.repository=localhost:30100/slurmctld \
  --set controller.slurmctld.image.tag=latest \
  --set controller.reconfigure.image.repository=localhost:30100/sackd \
  --set controller.reconfigure.image.tag=latest \
  --set restapi.slurmrestd.image.repository=localhost:30100/slurmrestd \
  --set restapi.slurmrestd.image.tag=latest \
  --set accounting.enabled=true \
  --set accounting.slurmdbd.image.repository=localhost:30100/slurmdbd \
  --set accounting.slurmdbd.image.tag=latest \
  --set accounting.storageConfig.host=mariadb-mariadb-cluster \
  --set accounting.storageConfig.database=slurmdb \
  --set nodesets.slinky.slurmd.image.repository=localhost:30100/slurmd \
  --set nodesets.slinky.slurmd.image.tag=latest \
  --set loginsets.slinky.enabled=true \
  --set loginsets.slinky.login.image.repository=localhost:30100/login \
  --set loginsets.slinky.login.image.tag=latest \
  --set loginsets.slinky.service.type=NodePort \
  --set loginsets.slinky.service.port=22 \
  --set loginsets.slinky.service.protocol=TCP \
  --set-file "loginsets.slinky.rootSshAuthorizedKeys=\${HOME}/.ssh/id_ed25519.pub"

k8s kubectl wait pod --all --for=condition=Ready -n=slurm --timeout=10m

port="\$(k8s kubectl -n=slurm get svc slurm-login-slinky -o jsonpath='{.spec.ports[0].nodePort}')"

ssh localhost \
    -i \${HOME}/.ssh/id_ed25519 \
    -p \$port \
    -o StrictHostKeyChecking=no \
    -- bash <<EOS

set -eux pipefail

scontrol ping
srun hostname
sacctmgr list stats

EOS

EOF
