# Architecture

Each setup creates five playgrounds from its matching YAML manifest. The single-VM setup names VMs `node-01` through `node-05`; the three-VM setup uses names such as `node-01-vm-01` through `node-05-vm-03`.

## Private network

WireGuard uses the `mesh0` interface, MTU 1280, and addresses starting at `10.8.0.1` in `10.8.0.0/24`. The scripts install public-key peer configuration and add managed VM-name entries to `/etc/hosts`. Private keys remain on each VM under `/etc/wireguard`.

The first VM runs a wstunnel server on TCP port 8080, exposed through the playground's public HTTP endpoint. Each other VM runs a wstunnel client that carries local WireGuard UDP traffic through a WebSocket connection to that server. The first VM enables IPv4 forwarding and routes traffic between peers. The scripts install `tunnel.service` and enable `wg-quick@mesh0` through systemd.

The tunnel endpoint is public; WireGuard encrypts private network traffic. VPN keys and disks persist across stops. The public endpoint can change when a playground restarts.

## Optional K3s cluster

The first VM runs the K3s server and has the control plane role. All remaining VMs run K3s agents and receive the `node` role label. K3s uses VPN addresses and `mesh0` for Flannel. Traefik and ServiceLB are disabled. Cluster data lives in `/data/k3s` on the data disk, and the server kubeconfig uses mode `600`.

The scripts wait for the expected number of Ready nodes before reporting K3s installation success. The K3s installer selects its default version; wstunnel is pinned in each script. Changing those versions should be validated against a live playground separately.
