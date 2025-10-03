## Hacking on `slurm-rocks`

This repository uses [just] and [rockcraft] for development which provide some
useful commands that will help you while hacking on `slurm-rocks`:

```shell
# Pack all rocks
just pack

# Publish all rocks to the docker-daemon registry
just publish docker-daemon: latest

# Run integration tests on the rocks using LXD
just integration
```

Run `just help` to view the full list of available recipes.

[just]: https://github.com/casey/just
[rockcraft]: https://documentation.ubuntu.com/rockcraft/stable/

## Testing against Slinky

The [`vm-setup.yaml`](./tests/vm-setup.yaml) and [`test-slinky.sh`](./tests/test-slinky.sh)
files show how to use [Canonical k8s][ck8s] to deploy a testing Slurm cluster with
Slinky.

If you plan on using an alternative local k8s implementation, and you have [Docker]
installed, you can deploy a local registry by running

```shell
docker run -d -p 5000:5000 --restart=always --name registry registry:2
```

This will allow publishing any packed rocks to the registry using the command

```shell
SKOPEO_FLAGS='--dest-tls-verify=false' just publish docker://localhost:5000/ latest
```

Then, you can follow the [Slinky guide][./SLINKY.md], replacing any reference to the
Github Container Registry with the local container registry;
`ghcr.io/canonical/slurm-rocks/slurmctld` becomes `localhost:5000/slurmctld`.

[ck8s]: https://documentation.ubuntu.com/canonical-kubernetes/release-1.32
[Docker]: https://www.docker.com/)
