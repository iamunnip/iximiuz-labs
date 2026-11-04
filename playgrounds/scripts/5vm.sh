#!/usr/bin/env bash
# Five single-VM playgrounds, node-01 to node-05, joined into one private network.
# Playgrounds share no network and can only expose HTTP(S) ports, so the VPN runs through
# A WebSocket tunnel on a public port of node-01, and all traffic between VMs goes via it.
#
# Usage:
#   5vm.sh up [--k3s]   Start the VMs and connect them, optionally install K3s
#   5vm.sh k3s          Install K3s on running VMs
#   5vm.sh check        Test the network from the first and the last VM
#   5vm.sh status       Show the VMs and how to connect to the control plane
#   5vm.sh down         Stop the VMs and keep their disks
#   5vm.sh restart      Start stopped VMs and reconnect them
#   5vm.sh destroy      Delete the VMs and their data
#
# Every command except destroy is safe to re-run. A restart loses the public port, so the
# Public URL changes, and restart updates the VMs with the new one.
set -euo pipefail

manifest="$(dirname "$0")/../manifests/5vm.yaml"
prefix=node
count=5
machine=vm
port=8080 # fixed: public TCP port on node-01, VPN UDP port on every vm
iface=mesh0
wstunnel_version=11.1.0
k3s_data=/data/k3s
lifetime=24h # the longest a playground can run
parallel=5 # SSH sessions at once, labctl only allows a small number

nodes=()
for ((i = 1; i <= count; i++)); do nodes+=("$(printf '%s-%02d' "$prefix" "$i")"); done
first=${nodes[0]}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
declare -A ids stopped

list_plays() { # print "<id> <title> <RUNNING|STOPPED|BUSY>" for this setup, destroyed ones are left out
  labctl playground list | awk -v p="^$prefix-[0-9]+\$" 'NR > 1 && $3 ~ p {
    if (/DESTROYED|TERMINATED|FAILED/) next
    print $1, $3, (/RUNNING/ ? "RUNNING" : /STOPPED/ ? "STOPPED" : "BUSY")
  }' | while read -r id title state; do
    case "$title" in
      node-0[1-5]) printf '%s %s %s\n' "$id" "$title" "$state" ;;
    esac
  done
}
load_ids() { # remember the ids of running and stopped playgrounds, by title
  local rows id title state _
  for _ in {1..60}; do # a playground that is stopping must not look like a missing one
    rows=$(list_plays)
    grep -q ' BUSY$' <<<"$rows" || break
    log "Waiting for playgrounds that are changing state"
    sleep 3
  done
  ! grep ' BUSY$' <<<"$rows" >&2 || { log "Playgrounds above are stuck, try again later"; exit 1; }
  ids=() stopped=()
  while read -r id title state; do
    [[ -n $id ]] || continue
    [[ -z ${ids[$title]:-}${stopped[$title]:-} ]] || {
      log "Duplicate playground title: $title. Resolve duplicates before continuing."
      exit 1
    }
    if [[ $state == RUNNING ]]; then ids[$title]=$id; else stopped[$title]=$id; fi
  done <<<"$rows"
}
vpn_ip() { echo "10.8.0.$(($1 + 1))"; } # by index, node-01 is 10.8.0.1
on() { labctl ssh "${ids[$1]}" -- sudo bash -s; } # Run the script on stdin as root
throttle() { while (($(jobs -rp | wc -l) >= parallel)); do wait -n || true; done; }
on_bg() { # like on, but in the background. usage: on_bg <node> [output file]
  local node=$1 out=${2:-} script
  script=$(cat)
  throttle
  log "$node: Executing remote step"
  {
    local try
    for try in 1 2 3; do # an SSH session can drop, the scripts are safe to repeat
      if [[ -n $out ]]; then on "$node" <<<"$script" >"$out"; else on "$node" <<<"$script" >&2; fi && { log "$node: Remote step completed"; exit 0; }
      log "$node: Attempt $try failed"
      sleep 3
    done
    : >"$tmp/failed"
  } &
}
wait_all() { # wait for background jobs, stop if any of them failed
  wait
  [[ ! -e $tmp/failed ]] || { log "Stopping, see the failures above"; exit 1; }
}
log() { printf '[%ss] %s\n' "$SECONDS" "$*" >&2; }
step() { log "Step: $*"; }

require_running() {
  local node
  load_ids
  for node in "${nodes[@]}"; do
    [[ -n ${ids[$node]:-} ]] || { log "$node is not running, run: $0 up"; exit 1; }
  done
}

require_existing() {
  local item
  load_ids
  for item in "${nodes[@]}"; do
    [[ -n ${ids[$item]:-}${stopped[$item]:-} ]] || { log "$item does not exist, run: $0 up"; exit 1; }
  done
}

start_vms() {
  local node created_id
  step "Start or reuse playgrounds"
  load_ids
  for node in "${nodes[@]}"; do
    if [[ -n ${ids[$node]:-} ]]; then
      log "$node: Already running (${ids[$node]})"
      continue
    fi
    throttle
    {
      if [[ -n ${stopped[$node]:-} ]]; then
        labctl playground restart "${stopped[$node]}" >/dev/null && log "$node: Restarted (${stopped[$node]})"
      else
        created_id=$(labctl playground start flexbox -f "$manifest" --title "$node" --quiet) &&
          [[ -n $created_id ]] && log "$node: Started ($created_id)"
      fi || : >"$tmp/failed"
    } &
  done
  wait_all
  load_ids

  # Keep the VMs for 24 hours and keep their disks when stopped. both are safe to repeat.
  step "Set lifetime to $lifetime and enable persistence"
  for node in "${nodes[@]}"; do
    [[ -n ${ids[$node]:-} ]] || { log "$node: Not running after startup"; exit 1; }
    {
      labctl playground lifetime "${ids[$node]}" "$lifetime" >/dev/null &&
        labctl playground persist "${ids[$node]}" >/dev/null || : >"$tmp/failed"
    } &
  done
  wait_all
  log "All playgrounds: lifetime $lifetime, persistent"
}

public_url() {
  labctl expose list "${ids[$first]}" --kind port |
    awk -v t="http://$machine:$port" '$2 == t { print $3; exit }'
}

connect_vms() {
  local node i url hosts="" peers="" finish
  local -A pubkeys
  step "Install network tools and collect public keys"

  # The private key stays on the vm, only the public key comes back.
  for node in "${nodes[@]}"; do
    on_bg "$node" "$tmp/$node.pubkey" <<SCRIPT
set -euo pipefail
hostnamectl set-hostname $node
grep -q ' $node\$' /etc/hosts || echo "127.0.1.1 $node" >> /etc/hosts
export DEBIAN_FRONTEND=noninteractive
command -v wg >/dev/null || { apt-get update -qq; apt-get install -y -qq wireguard-tools; } >/dev/null
if [[ "\$(wstunnel --version 2>/dev/null)" != *$wstunnel_version* ]]; then
  tmp=\$(mktemp -d)
  trap 'rm -rf "\$tmp"' EXIT
  cd "\$tmp"
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
  done
  wait_all
  for node in "${nodes[@]}"; do pubkeys[$node]=$(tail -1 "$tmp/$node.pubkey"); done

  # Expose the port once, a re-run reuses the same URL.
  step "Expose or reuse the tunnel port"
  url=$(public_url)
  [[ -n $url ]] || url=$(labctl expose port "${ids[$first]}" "$port" --machine "$machine" --public | tail -1)
  [[ $url == https://* || $url == http://* ]] || { log "Invalid public URL: $url"; exit 1; }
  log "Public URL: $url"
  step "Configure the VPN server and clients"

  url=${url/http:/ws:}

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

  on "$first" <<SCRIPT
set -euo pipefail
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-vpn.conf
sysctl -q --system
cat > /etc/systemd/system/tunnel.service <<UNIT
[Unit]
Description=WebSocket tunnel server for the private network
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
    on_bg "$node" <<SCRIPT
set -euo pipefail
cat > /etc/systemd/system/tunnel.service <<UNIT
[Unit]
Description=WebSocket tunnel client for the private network
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
  wait_all
}

check() {
  step "Check connectivity from the first and last VM"
  local node
  for node in "$first" "${nodes[-1]}"; do
    on_bg "$node" <<SCRIPT
failed=\$(
  for target in ${nodes[*]}; do
    [[ \$target == $node ]] && continue
    ping -c 1 -w 20 "\$target" >/dev/null 2>&1 || echo "$node -> \$target: FAILED" &
  done
  wait
)
[[ -z \$failed ]] || { echo "\$failed"; exit 1; }
SCRIPT
  done
  wait_all
  log "All $count VMs connected"
}

install_k3s() {
  local node i token
  step "Install K3s on the control plane"
  token=$(on "$first" <<SCRIPT | tail -1
set -euo pipefail
if ! systemctl is-active -q k3s; then
  curl -fsSL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-name $first --node-ip $(vpn_ip 0) --advertise-address $(vpn_ip 0) --flannel-iface $iface --data-dir $k3s_data --write-kubeconfig-mode 600 --disable traefik --disable servicelb" sh - >/dev/null
fi
for _ in \$(seq 1 60); do [[ -s $k3s_data/server/node-token ]] && break; sleep 2; done
cat $k3s_data/server/node-token
SCRIPT
  )
  step "Install K3s agents"
  for ((i = 1; i < count; i++)); do
    node=${nodes[$i]}
    on_bg "$node" <<SCRIPT
set -euo pipefail
if ! systemctl is-active -q k3s-agent; then
  curl -fsSL https://get.k3s.io | K3S_URL=https://$(vpn_ip 0):6443 K3S_TOKEN=$token INSTALL_K3S_EXEC="agent --node-name $node --node-ip $(vpn_ip "$i") --flannel-iface $iface --data-dir $k3s_data" sh - >/dev/null
fi
SCRIPT
  done
  wait_all
  step "Wait for all K3s nodes to become Ready"
  on "$first" <<SCRIPT
set -e
for _ in \$(seq 1 90); do
  [[ \$(k3s kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready') == $count ]] && break
  sleep 2
done
k3s kubectl label node ${nodes[*]:1} node-role.kubernetes.io/node= --overwrite >/dev/null
k3s kubectl get nodes -o wide
[[ \$(k3s kubectl get nodes --no-headers | grep -c ' Ready') == $count ]]
SCRIPT
}

status() {
  step "Show playground status"
  local ssh_cmd
  labctl playground list | awk -v p="^$prefix-0[1-5]\$" 'NR == 1 || ($3 ~ p && !/DESTROYED|TERMINATED|FAILED/)' | cut -c1-100
  load_ids
  if [[ -z ${ids[$first]:-} ]]; then
    if [[ -n ${stopped[$first]:-} ]]; then echo "Stopped, run: $0 restart"; else echo "Not created, run: $0 up"; fi
    return
  fi
  ssh_cmd="labctl ssh ${ids[$first]}"
  echo "Public URL: $(public_url)"
  echo "Control plane: $ssh_cmd"
  if [[ -n $(on "$first" <<<'command -v k3s || true') ]]; then
    echo "K3s: $ssh_cmd -- sudo k3s kubectl get nodes"
  else
    echo "K3s: not installed, run: $0 k3s"
  fi
}

down() {
  step "Stop playgrounds and retain their disks"
  local title
  load_ids
  for title in "${!ids[@]}"; do
    {
      labctl playground stop "${ids[$title]}" >/dev/null && log "$title: Stopped (${ids[$title]})" || : >"$tmp/failed"
    } &
  done
  wait_all
}

destroy() {
  step "Delete playgrounds and their data"
  local title id
  load_ids
  for title in "${!ids[@]}" "${!stopped[@]}"; do
    id=${ids[$title]:-${stopped[$title]}}
    {
      labctl playground destroy "$id" </dev/null && log "$title: Destroyed ($id)" || : >"$tmp/failed"
    } &
  done
  wait_all
}

# Validate arguments before invoking labctl.
if (($# > 2)); then
  log "Too many arguments. Run $0 --help for usage."
  exit 2
fi
case "${1:-}" in
  -h|--help)
    (($# == 1)) || { log "Help takes no arguments"; exit 2; }
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
esac
command -v labctl >/dev/null || { log "Missing dependency: labctl"; exit 1; }

case "${1:-}:${2:-}" in
  up:) start_vms; connect_vms; check ;;
  up:--k3s) start_vms; connect_vms; check; install_k3s ;;
  k3s:) require_running; install_k3s ;;
  check:) require_running; check ;;
  status:) status ;;
  down:) down ;;
  restart:) require_existing; start_vms; connect_vms; check ;;
  destroy:) destroy ;;
  *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" >&2; exit 2 ;;
esac
[[ ${1:-} != up && ${1:-} != restart ]] || log "Done in ${SECONDS}s"
