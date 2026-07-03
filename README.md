# Homelab

Ansible configuration management for a single-node homelab server running Arch Linux.

## Hardware

| Host | Role | OS |
|---|---|---|
| `arch-mini` | General purpose homelab server | Arch Linux |

## Prerequisites

- Ansible installed locally
- SSH key access to the target host

## Usage

```bash
# verify connectivity
make ping

# gather host facts
make facts

# run a playbook
make playbook PLAYBOOK=<playbook>.yml
```

## Project Structure

```
├── Makefile
└── ansible/
    └── inventory.ini    # host definitions
```
