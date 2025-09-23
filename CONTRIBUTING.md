## Hacking on `slurm-rocks`

This repository uses [just] and [rockcraft] for development which provide some
useful commands that will help you while hacking on `slurm-rocks`:

```shell
# Pack all rocks
just pack

# Publish all rocks to the docker-daemon registry
just publish docker-daemon: latest
```

Run `just help` to view the full list of available recipes.

[just]: https://github.com/casey/just
[rockcraft]: https://documentation.ubuntu.com/rockcraft/stable/

## Testing against Slinky

To test the Rocks while hacking, you will first require deploying a local container
registry. If you have [Docker](https://www.docker.com/) installed, you can
deploy a local registry by running

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
