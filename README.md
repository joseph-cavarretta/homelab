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

## Network

```
Pis + pi-hole ──eth──▶ GL.iNet (switch + DHCP) ──eth──▶ arch-mini ──Wi-Fi──▶ home router ──▶ internet
```

- The homelab LAN is `192.168.8.0/24` behind the GL.iNet travel router, which
  only switches and hands out addresses (DNS: `pi-hole`). It has no uplink.
- `arch-mini` is the LAN's internet gateway: its Wi-Fi joins the home network and
  it NATs `192.168.8.0/24` out through it (`ansible/roles/gateway`). The other hosts
  route via `192.168.8.130` (`ansible/roles/lan_route`).
- k3s is pinned to the LAN address `192.168.8.130` (`/etc/rancher/k3s/config.yaml`),
  not the Wi-Fi one.
- `make network` applies just these settings, without the rest of `site.yml`.

## Stack

| Layer | Tool | Where |
|---|---|---|
| Node provisioning | cloud-init + Ansible | `cloud-init/`, `ansible/` |
| LAN gateway | arch-mini NAT (nftables) + static routes | `ansible/roles/gateway`, `ansible/roles/lan_route` |
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
├── Makefile                  # ping / site / network / kubeconfig / argocd / root-app
├── cloud-init/
│   └── user-data.yaml        # Pi first-boot template
├── ansible/
│   ├── inventory.ini         # control_plane + workers + dns
│   ├── group_vars/all.yml    # k3s version pin
│   ├── site.yml              # full-cluster provisioning
│   ├── network.yml           # gateway + LAN routes + k3s node address
│   └── roles/
│       ├── common/           # swap off, worker Wi-Fi off, Pi cgroup flags
│       ├── gateway/          # arch-mini forwards + NATs the LAN
│       ├── lan_route/        # LAN hosts route via arch-mini
│       ├── k3s_server/       # k3s config, install + join token
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
