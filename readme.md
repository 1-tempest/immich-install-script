# Immich Install Script

This repository contains the installation script for Immich.

## Installation

To install Immich, you can use the following command:

```sh
curl -o- https://raw.githubusercontent.com/immich-app/immich/main/install.sh | sudo bash
```

```sh
curl -o- https://raw.githubusercontent.com/1-tempest/immich-install-script/main/install.sh | sudo bash
```

## Script Arguments

The `install.sh` script accepts the following arguments:

- `--hwa <framework>`: Specify the machine learning framework for hardware acceleration. Accepted values are `auto`, `openvino`, `armnn`, and `cuda`
- `--hwt <framework>`: Specify the machine learning framework for hardware transcoding. Accepted values are `auto`, `nvec`, `quicksync`, `rkmpp`, and `vaapi`
- `--enable-backups`: Enable database backups

### Example usage:

Auto-detect hardware, with backups:

```sh
curl -o- https://raw.githubusercontent.com/1-tempest/immich-install-script/main/install.sh | sudo bash -s -- --hwa auto --hwt auto --enable-backups
```

Without hardware acceleration, with backups:

```sh
curl -o- https://raw.githubusercontent.com/immich-app/immich/main/install.sh | sudo bash -s -- --enable-backups
```

Manually select hardware, without backups:

```sh
curl -o- https://raw.githubusercontent.com/immich-app/immich/main/install.sh | sudo bash -s -- --hwa openvino --hwt quicksync
```
