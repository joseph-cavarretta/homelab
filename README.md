# Homelab

Kubernetes homelab: a k3s cluster on a Minisforum mini PC (control plane) and
3x Raspberry Pi worker nodes, provisioned with Ansible and managed with
GitOps via Argo CD. A separate Raspberry Pi runs Pi-hole as DNS and ad-blocking
for the homelab LAN.

## Hardware

| Host | Role | OS | Arch |
|---|---|---|---|
| `arch-mini` | k3s control plane | Arch Linux | x86_64 |
| `pi-node-1` … `pi-node-3` | k3s workers | Debian 13 (Raspberry Pi 5) | arm64 |
| `pi-hole` | DNS + ad-blocking (Pi-hole, outside k3s) | Debian 13 (Raspberry Pi 4) | arm64 |

## Stack

| Layer | Tool | Where |
|---|---|---|
| Node provisioning | cloud-init + Ansible | `cloud-init/`, `ansible/` |
| Kubernetes | k3s (traefik ingress, servicelb disabled) | `ansible/roles/k3s_*` |
| GitOps | Argo CD (app-of-apps) | `bootstrap/`, `apps/` |
| LoadBalancer IPs | MetalLB (L2) | `apps/metallb*.yaml`, `infra/metallb/` |
| Ingress & allowlist | Traefik + `lan-only` IPAllowList | `apps/traefik-middleware.yaml`, `infra/traefik/` |
| Certificates | cert-manager | `apps/cert-manager.yaml` |
| Cluster UI | Rancher | `apps/rancher.yaml` |
| Object storage | Garage (S3-compatible) | `apps/garage.yaml` |
| ML tracking | MLflow (backed by Garage S3) | `apps/mlflow.yaml` |
| DNS & ad-blocking | Pi-hole on a dedicated Pi | `ansible/inventory.ini` (`[dns]`) |

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
│   ├── inventory.ini         # control_plane + workers + dns
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
│   ├── cert-manager.yaml
│   ├── garage.yaml
│   ├── metallb.yaml
│   ├── metallb-config.yaml
│   ├── mlflow.yaml
│   ├── rancher.yaml
│   └── traefik-middleware.yaml
└── infra/                    # raw manifests / values referenced by apps
    ├── metallb/
    │   └── ipaddresspool.yaml
    └── traefik/
        ├── ip-allowlist.yaml
        └── traefik-config.yaml
```

## DNS (Pi-hole)

`pi-hole` (`192.168.8.108`, wired) runs Pi-hole v6 directly on the host, not in
the cluster, so name resolution keeps working when k3s is down. The GL.iNet
router hands it out as the DNS server on the homelab LAN, and every node
resolves through it. Upstream resolvers are Quad9 (`9.9.9.9`,
`149.112.112.112`). The admin UI is at `http://192.168.8.108/admin/`.

It sits in the `[dns]` inventory group, so `make ping` reaches it but
`make site` (which targets `k3s_cluster`) leaves it alone.

## Adding an App

Drop a new Argo CD `Application` manifest in `apps/` (helm chart or a path
in this repo) and merge — the root app picks it up automatically.

## Next Steps

- [ ] kube-prometheus-stack (Grafana + Prometheus) — mind Pi RAM limits
- [ ] Storage: NFS provisioner or Longhorn (prefer SSD-backed nodes over SD cards)
- [ ] sealed-secrets or SOPS for secrets in git
- [ ] Renovate to keep chart versions in `apps/` current
