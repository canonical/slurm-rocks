# Slurm rocks

The `slurm-rocks` repository is a collection of files to build rocks for the upstream
Slurm services.

## Getting started

To get started with the Slurm rocks, you must have [Rockcraft] and [just] installed for
packing the rocks, [skopeo] for copying the generated OCI images to your local Docker registry, and
finally [Docker] for running the images.

```bash
just pack  # Packs all the rocks.
just import  # Imports all the rocks into your local Docker registry.
docker run --rm -d --name slurmctld slurmctld:latest  # Runs the slurmctld rock with Docker.
```

A more extensive usage example can be seen on the (example)[./example] directory, which sets up all
the Slurm services into a simple cluster.

[Rockcraft]: https://documentation.ubuntu.com/rockcraft
[just]: https://github.com/casey/just
[skopeo]: https://github.com/containers/skopeo
[Docker]: https://www.docker.com
