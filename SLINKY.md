# Using the Slurm rocks with Slinky

First, install Microk8s

```shell
sudo snap install microk8s --channel 1.34-strict/stable
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
chmod 0700 ~/.kube
su - $USER
microk8s status --wait-ready
alias kubectl='microk8s kubectl'
```

Next, enable some required plugins

```shell
sudo microk8s enable hostpath-storage
sudo microk8s enable cert-manager
sudo microk8s enable observability
```

Install Helm

```shell
sudo snap install helm --classic
```

Then, install the required helm repo
```shell
helm repo add mariadb-operator https://helm.mariadb.com/mariadb-operator
```

Next, install the required custom resource definitions.
```shell
helm install mariadb-operator-crds mariadb-operator/mariadb-operator-crds
helm install slurm-operator-crds oci://ghcr.io/slinkyproject/charts/slurm-operator-crds:0.4.0
```

Furthermore, install the required operators:

```shell
helm install mariadb-operator mariadb-operator/mariadb-operator \
  --set metrics.enabled=true --set webhook.cert.certManager.enabled=true
helm install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
    --namespace=slinky --create-namespace
```

Create the namespace for the Slurm cluster:
```shell
kubectl create namespace slurm
```

And create the required secrets for the database. Replace `<password>` with your specific passwords
for the root user and the slurm user, respectively:

```shell
kubectl -n slurm create secret generic mariadb-root --from-literal=password=<password>
kubectl -n slurm create secret generic slurmdb-password --from-literal=password=<password>
```

Create the configuration values for the database, and save it as `values-mariadb.yaml`.
This is one sample configuration to deploy a MariaDB for the Slurm cluster, but there are multiple
ways of deploying the database. You can read mariadb-operator's [guide](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/helm.md#mariadb-cluster-helm-chart)
if you want to customize your deployment.
```yaml
mariadb:
  rootPasswordSecretKeyRef:
    name: mariadb-root
    key: password
  storage:
    size: 1Gi
  replicas: 1
  galera:
    enabled: false
  myCnf: |
    [mariadb]
    bind-address=*
    default_storage_engine=InnoDB
    binlog_format=row
    innodb_autoinc_lock_mode=2
    innodb_buffer_pool_size=4096M
    innodb_lock_wait_timeout=900
    innodb_log_file_size=1024M
    max_allowed_packet=256M
  metrics:
    enabled: true
databases:
  - name: slurmdb
    characterSet: utf8
    collate: utf8_general_ci
    cleanupPolicy: Delete
    requeueInterval: 10h
    retryInterval: 30s
users:
  - name: slurm
    passwordSecretKeyRef:
      name: slurmdb-password
      key: password
    host: "%"
    cleanupPolicy: Delete
    requeueInterval: 10h
    retryInterval: 30s
grants:
  - name: slurmdb
    privileges:
      - "ALL PRIVILEGES"
    database: "slurmdb"
    table: "*"
    username: slurm
    grantOption: true
    host: "%"
    cleanupPolicy: Delete
    requeueInterval: 10h
    retryInterval: 30s
```

Deploy MariaDB on the `slurm` namespace:
```shell
helm install -n slurm slurmdb mariadb-operator/mariadb-cluster -f values-mariadb.yaml
```

Download and update the slurm values file.
```shell
curl -L https://raw.githubusercontent.com/SlinkyProject/slurm-operator/refs/tags/v0.4.0/helm/slurm/values.yaml \
  -o values-slurm.yaml
```

In `values-slurm.yaml`, change the image configuration to use the OCI images published by this repository.
For example, to use the `slurmctld` image, replace this:

```yaml
image:
  repository: ghcr.io/slinkyproject/slurmctld
  tag: 25.05-ubuntu24.04
```

with this:

```yaml
image:
  repository: ghcr.io/canonical/slurm-rocks/slurmctld
  tag: latest
```

Make sure to also setup the accounting configuration to point to the deployed MariaDB:

```yaml
accounting:
  # The storage configuration.
  storageConfig:
    # -- The name of the host where the database is running.
    # Ref: https://slurm.schedmd.com/slurmdbd.conf.html#OPT_StorageHost
    host: slurmdb-mariadb-cluster
    # -- The port number to communicate with the database with.
    # Ref: https://slurm.schedmd.com/slurmdbd.conf.html#OPT_StoragePort
    port: 3306
    # -- The name of the database where records are written into.
    # Ref: https://slurm.schedmd.com/slurmdbd.conf.html#OPT_StorageLoc
    database: slurmdb
    # -- The name of the user used to connect to the database with.
    # Ref: https://slurm.schedmd.com/slurmdbd.conf.html#OPT_StorageUser
    username: slurm
    # -- (secretKeyRef) The password used to connect to the database, from secret reference.
    # Ref: https://slurm.schedmd.com/slurmdbd.conf.html#OPT_StoragePass
    passwordKeyRef:
      name: slurmdb-password
      key: password
```

Finally, deploy the Slurm cluster:

```shell
helm install slurm oci://ghcr.io/slinkyproject/charts/slurm \
  --values=values-slurm.yaml \
  --namespace=slurm \
  --create-namespace
```

You can track the status of every deployed pod in the `slurm` namespace with the command:
```shell
kubectl --namespace=slurm get pods --watch
```
