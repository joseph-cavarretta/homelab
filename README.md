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
ansible all -i ansible/inventory.ini -m ping

# run a playbook
ansible-playbook -i ansible/inventory.ini <playbook>.yml
```

## Project Structure

```
ansible/
└── inventory.ini    # host definitions
```
