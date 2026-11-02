#!/usr/bin/env bash
# five single-vm playgrounds, cluster-01 to cluster-05, joined into one private network.
# playgrounds share no network and can only expose http(s) ports, so the vpn runs through
# a websocket tunnel on a public port of cluster-01, and all traffic between vms goes via it.
#
# usage:
#   ubuntu26-4c-10g-os20g-data80g.sh up [--k3s]   start the vms and connect them, optionally install k3s
#   ubuntu26-4c-10g-os20g-data80g.sh k3s          install k3s on running vms
#   ubuntu26-4c-10g-os20g-data80g.sh check        test that every vm reaches every other vm
#   ubuntu26-4c-10g-os20g-data80g.sh status       list the vms and the public url
#   ubuntu26-4c-10g-os20g-data80g.sh down         destroy the vms and their data
#
# every command except down is safe to re-run.
set -euo pipefail

manifest="$(dirname "$0")/../manifests/ubuntu26-4c-10g-os20g-data80g.yaml"
prefix=cluster
count=5
machine=vm
port=8080 # fixed: public tcp port on cluster-01, vpn udp port on every vm
iface=mesh0
wstunnel_version=11.1.0
k3s_data=/data/k3s

nodes=()
for ((i = 1; i <= count; i++)); do nodes+=("$(printf '%s-%02d' "$prefix" "$i")"); done
first=${nodes[0]}

play_id() { labctl playground list | awk -v t="$1" '$3 == t && /RUNNING/ { print $1; exit }'; }
vpn_ip() { echo "10.8.0.$(($1 + 1))"; } # by index, cluster-01 is 10.8.0.1
on() { labctl ssh "$(play_id "$1")" -- sudo bash -s; } # run the script on stdin as root
log() { echo "$*" >&2; }

require_running() {
  local node
  for node in "${nodes[@]}"; do
    [[ -n $(play_id "$node") ]] || { log "$node is not running, run: $0 up"; exit 1; }
  done
}

start_vms() {
  local node id
  for node in "${nodes[@]}"; do
    id=$(play_id "$node")
    if [[ -n $id ]]; then
      log "$node: already running ($id)"
    else
      log "$node: started ($(labctl playground start flexbox -f "$manifest" --title "$node" --quiet))"
    fi
  done
}

public_url() {
  labctl expose list "$(play_id "$first")" --kind port |
    awk -v t="http://$machine:$port" '$2 == t { print $3; exit }'
}

connect_vms() {
  local node i url hosts="" peers="" finish
  local -A pubkeys

  # the private key stays on the vm, only the public key comes back.
  for node in "${nodes[@]}"; do
    log "$node: installing packages"
    pubkeys[$node]=$(on "$node" <<SCRIPT | tail -1
set -euo pipefail
hostnamectl set-hostname $node
grep -q ' $node\$' /etc/hosts || echo "127.0.1.1 $node" >> /etc/hosts
export DEBIAN_FRONTEND=noninteractive
command -v wg >/dev/null || { apt-get update -qq; apt-get install -y -qq wireguard-tools; } >/dev/null
if [[ "\$(wstunnel --version 2>/dev/null)" != *$wstunnel_version* ]]; then
  tmp=\$(mktemp -d); cd "\$tmp"
  base=https://github.com/erebe/wstunnel/releases/download/v$wstunnel_version
  tarball=wstunnel_${wstunnel_version}_linux_amd64.tar.gz
  curl -fsSLO "\$base/\$tarball"
  curl -fsSLO "\$base/checksums.txt"
  grep " \$tarball\\\$" checksums.txt | sha256sum -c --quiet -
  tar xzf "\$tarball" wstunnel
  install wstunnel /usr/local/bin/wstunnel
fi
umask 077
mkdir -p /etc/wireguard
[[ -s /etc/wireguard/private.key ]] || wg genkey > /etc/wireguard/private.key
wg pubkey < /etc/wireguard/private.key
SCRIPT
    )
  done

  # expose the port once, a re-run reuses the same url.
  url=$(public_url)
  [[ -n $url ]] || url=$(labctl expose port "$(play_id "$first")" "$port" --machine "$machine" --public | tail -1)
  log "public url: $url"

  for i in "${!nodes[@]}"; do hosts+="$(vpn_ip "$i") ${nodes[$i]} # $prefix"$'\n'; done
  for ((i = 1; i < count; i++)); do
    peers+="[Peer]
PublicKey = ${pubkeys[${nodes[$i]}]}
AllowedIPs = $(vpn_ip "$i")/32

"
  done

  finish="
chmod 600 /etc/wireguard/$iface.conf
systemctl daemon-reload
systemctl enable -q tunnel wg-quick@$iface
systemctl restart tunnel wg-quick@$iface
sed -i '/# $prefix\$/d' /etc/hosts
cat >> /etc/hosts <<'HOSTS'
$hosts
HOSTS
"

  log "$first: configuring"
  on "$first" <<SCRIPT
set -euo pipefail
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-vpn.conf
sysctl -q --system
cat > /etc/systemd/system/tunnel.service <<UNIT
[Unit]
Description=websocket tunnel server for the private network
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/wstunnel server --restrict-to 127.0.0.1:$port ws://0.0.0.0:$port
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/wireguard/$iface.conf <<CONF
[Interface]
Address = $(vpn_ip 0)/24
ListenPort = $port
MTU = 1280
PostUp = wg set %i private-key /etc/wireguard/private.key

$peers
CONF
$finish
SCRIPT

  for ((i = 1; i < count; i++)); do
    node=${nodes[$i]}
    log "$node: configuring"
    on "$node" <<SCRIPT
set -euo pipefail
cat > /etc/systemd/system/tunnel.service <<UNIT
[Unit]
Description=websocket tunnel client for the private network
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/wstunnel client -L udp://127.0.0.1:$port:127.0.0.1:$port?timeout_sec=0 ${url/https:/wss:}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/wireguard/$iface.conf <<CONF
[Interface]
Address = $(vpn_ip "$i")/24
MTU = 1280
PostUp = wg set %i private-key /etc/wireguard/private.key

[Peer]
PublicKey = ${pubkeys[$first]}
Endpoint = 127.0.0.1:$port
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
CONF
$finish
SCRIPT
  done
}

check() {
  local node failed=0
  for node in "${nodes[@]}"; do
    on "$node" <<SCRIPT || failed=1
rc=0
for target in ${nodes[*]}; do
  [[ \$target == $node ]] && continue
  if ping -c 2 -W 5 "\$target" >/dev/null 2>&1; then r=ok; else r=FAILED; rc=1; fi
  echo "$node -> \$target: \$r"
done
exit \$rc
SCRIPT
  done
  [[ $failed == 0 ]] || { log "some vms cannot reach each other"; return 1; }
  log "all $count vms connected"
}

install_k3s() {
  local node i token
  log "$first: installing k3s server"
  token=$(on "$first" <<SCRIPT | tail -1
set -euo pipefail
if ! systemctl is-active -q k3s; then
  curl -fsSL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip $(vpn_ip 0) --advertise-address $(vpn_ip 0) --flannel-iface $iface --data-dir $k3s_data --write-kubeconfig-mode 644" sh - >/dev/null 2>&1
fi
for _ in \$(seq 1 60); do [[ -s $k3s_data/server/node-token ]] && break; sleep 2; done
cat $k3s_data/server/node-token
SCRIPT
  )
  for ((i = 1; i < count; i++)); do
    node=${nodes[$i]}
    log "$node: installing k3s agent"
    on "$node" <<SCRIPT
set -euo pipefail
if ! systemctl is-active -q k3s-agent; then
  curl -fsSL https://get.k3s.io | K3S_URL=https://$(vpn_ip 0):6443 K3S_TOKEN=$token INSTALL_K3S_EXEC="agent --node-ip $(vpn_ip "$i") --flannel-iface $iface --data-dir $k3s_data" sh - >/dev/null 2>&1
fi
SCRIPT
  done
  on "$first" <<SCRIPT
for _ in \$(seq 1 90); do
  [[ \$(k3s kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready') == $count ]] && break
  sleep 2
done
k3s kubectl get nodes -o wide
[[ \$(k3s kubectl get nodes --no-headers | grep -c ' Ready') == $count ]]
SCRIPT
}

status() {
  labctl playground list | awk -v p="^$prefix-[0-9]+\$" 'NR == 1 || $3 ~ p' | cut -c1-100
  [[ -z $(play_id "$first") ]] || echo "public url: $(public_url)"
}

down() {
  local node id
  for node in "${nodes[@]}"; do
    id=$(play_id "$node")
    [[ -n $id ]] || continue
    labctl playground destroy "$id" >/dev/null
    log "$node: destroyed ($id)"
  done
}

case "${1:-}:${2:-}" in
  up:) start_vms; connect_vms; check ;;
  up:--k3s) start_vms; connect_vms; check; install_k3s ;;
  k3s:) require_running; install_k3s ;;
  check:) require_running; check ;;
  status:) status ;;
  down:) down ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
