# Homelab Infrastructure: ISO Build and Colmena Provisioning

This repository manages the deployment and configuration of homelab nodes (like Kubernetes nodes) using **Colmena** and **NixOS**. It includes a customized ISO builder for easy bootstrapping.

## 🚀 Quick Start

### 1. Initialize Settings
Run the settings generator to configure your username, SSH public key, password, and optional signing key.
```bash
./set-settings.sh
```
*Note: This script will ask to overwrite existing settings if they are already present.*

### 2. Build the Bootable ISO
Generate a minimal, headless NixOS installer ISO that comes pre-configured with your SSH key and passwordless sudo.
```bash
./build-iso.sh
```
The ISO will be located in `./result/iso/`.

### 3. Deploy to a Node
Once you've booted a node with the ISO and it's reachable on the network:
```bash
# Apply configuration to a specific node (e.g., k8s-node)
nix run github:zhaofengli/colmena -- apply --on k8s-node
```

## 📁 Repository Structure

- `flake.nix`: Entry point for Nix configurations and Colmena Hive.
- `deployment/`: Contains `deployment.nix` which defines the network-specific settings (IPs, hostnames) for each node.
- `hosts/`: Contains reusable NixOS modules for different types of nodes (e.g., `k8s-node.nix`).
- `common/`: Shared configuration applied to all systems (users, ssh, base packages).
  - `settings.nix`: (Generated) Private-but-safe-to-commit settings (username, pubkey, hashed password).
- `disko.nix`: Disk partitioning layouts using [disko](https://github.com/nix-community/disko).

## 🛠 Adding a New Node

1. Define the node's hardware and network details in `deployment/deployment.nix`.
2. Ensure the `targetHost` IP matches your new node.
3. Run the Colmena apply command for that node.
