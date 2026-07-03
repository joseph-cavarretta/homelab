# Homelab

Kubernetes homelab: a k3s cluster on a Minisforum mini PC (control plane) and
3x Raspberry Pi worker nodes, provisioned with Ansible and managed with
GitOps via Argo CD.

## Hardware

| Host | Role | OS | Arch |
|---|---|---|---|
| `arch-mini` | k3s control plane | Arch Linux | x86_64 |
| `pi-01` … `pi-03` | k3s workers | Ubuntu Server 24.04 | arm64 |

## Stack

| Layer | Tool | Where |
|---|---|---|
| Node provisioning | cloud-init + Ansible | `cloud-init/`, `ansible/` |
| Kubernetes | k3s (traefik ingress, servicelb disabled) | `ansible/roles/k3s_*` |
| GitOps | Argo CD (app-of-apps) | `bootstrap/`, `apps/` |
| LoadBalancer IPs | MetalLB (L2) | `apps/metallb*.yaml`, `infra/metallb/` |
| Certificates | cert-manager | `apps/cert-manager.yaml` |
| Cluster UI | Rancher | `apps/rancher.yaml` |

## Bootstrap Runbook

Everything below happens exactly once. After step 5, the cluster state is
whatever is in this repo's `apps/` and `infra/` directories on `main`.

### 1. Flash the Pis

Flash Ubuntu Server 24.04 (64-bit) with Raspberry Pi Imager, using
`cloud-init/user-data.yaml` for first-boot config (hostname per node, user,
SSH key). Give each Pi a DHCP reservation and record the addresses in
`ansible/inventory.ini`.

### 2. Verify connectivity

```bash
make ping
```

### 3. Provision the cluster

```bash
make site        # base config + k3s server on arch-mini + agents on the Pis
make kubeconfig  # copy kubeconfig locally
kubectl get nodes -o wide
```

### 4. Install Argo CD

```bash
make argocd
make argocd-password   # initial admin password
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

### 5. Hand control to GitOps

```bash
make root-app
```

The root Application watches `apps/` in this repo; every manifest there
becomes a managed app. From here on, cluster changes are pull requests.

## Repo Structure

```
├── Makefile                  # ping / site / kubeconfig / argocd / root-app
├── cloud-init/
│   └── user-data.yaml        # Pi first-boot template
├── ansible/
│   ├── inventory.ini         # control_plane + workers
│   ├── group_vars/all.yml    # k3s version pin
│   ├── site.yml              # full-cluster provisioning
│   └── roles/
│       ├── common/           # swap off, Pi cgroup flags
│       ├── k3s_server/       # k3s server install + join token
│       └── k3s_agent/        # workers join the cluster
├── bootstrap/                # applied once, by hand
│   ├── argocd/values.yaml
│   └── root-app.yaml         # app-of-apps entry point
├── apps/                     # Argo CD Applications (one file per app)
│   ├── metallb.yaml
│   ├── metallb-config.yaml
│   ├── cert-manager.yaml
│   └── rancher.yaml
└── infra/                    # raw manifests / values referenced by apps
    └── metallb/ipaddresspool.yaml
```

## Adding an App

Drop a new Argo CD `Application` manifest in `apps/` (helm chart or a path
in this repo) and merge — the root app picks it up automatically.

## Next Steps

- [ ] kube-prometheus-stack (Grafana + Prometheus) — mind Pi RAM limits
- [ ] Storage: NFS provisioner or Longhorn (prefer SSD-backed nodes over SD cards)
- [ ] sealed-secrets or SOPS for secrets in git
- [ ] Renovate to keep chart versions in `apps/` current
