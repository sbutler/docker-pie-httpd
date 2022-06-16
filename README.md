# Publish HTTPD Image

This repository is for the Publish HTTPD Docker image. It include Apache
preconfigured with settings and modules, and some management scripts available
on an agent port.

Instead of having a normal branch structure with `main` and `develop`, this
repository is organized with branches for the base Docker image. Current
branches used for building:

- `main/ubuntu22.04`: production as of June 2022.
- `main/ubuntu20.04`
- `main/ubuntu18.04`: production before June 2022.
