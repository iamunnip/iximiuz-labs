#!/usr/bin/env bash
# five playgrounds, node-01 to node-05, with three vms each, joined into one private network.
# playgrounds share no network and can only expose http(s) ports, so the vpn runs through
# a websocket tunnel on a public port of node-01-vm-01, and all traffic between vms goes via it.
#
# usage:
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh up [--k3s]   start the vms and connect them, optionally install k3s
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh k3s          install k3s on running vms
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh check        test the network from the first and the last vm
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh status       show the vms and how to connect to the control plane
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh down         stop the vms and keep their disks
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh restart      start stopped vms and reconnect them
#   15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh destroy      delete the vms and their data
#
# every command except destroy is safe to re-run. a restart loses the public port, so the
# public url changes, and restart updates the vms with the new one.
set -euo pipefail

manifest="$(dirname "$0")/../manifests/15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.yaml"
prefix=node
playgrounds=5
machines=(vm-01 vm-02 vm-03)
port=8080 # fixed: public tcp port on node-01-vm-01, vpn udp port on every vm
iface=mesh0
wstunnel_version=11.1.0
k3s_data=/data/k3s
lifetime=24h # the longest a playground can run
parallel=5 # ssh sessions at once, labctl only allows a small number

plays=() nodes=()
for ((i = 1; i <= playgrounds; i++)); do
  play=$(printf '%s-%02d' "$prefix" "$i")
  plays+=("$play")
  for machine in "${machines[@]}"; do nodes+=("$play-$machine"); done
done
count=${#nodes[@]}
first=${nodes[0]}
first_play=${plays[0]}
first_machine=${machines[0]}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
declare -A ids stopped

list_plays() { # print "<id> <title> <RUNNING|STOPPED|BUSY>" for this setup, destroyed ones are left out
  labctl playground list | awk -v p="^$prefix-[0-9]+\$" 'NR > 1 && $3 ~ p {
    if (/DESTROYED|TERMINATED|FAILED/) next
    print $1, $3, (/RUNNING/ ? "RUNNING" : /STOPPED/ ? "STOPPED" : "BUSY")
  }'
}
load_ids() { # remember the ids of running and stopped playgrounds, by title
  local rows id title state _
  for _ in {1..60}; do # a playground that is stopping must not look like a missing one
    rows=$(list_plays)
    grep -q ' BUSY$' <<<"$rows" || break
    log "waiting for playgrounds that are changing state"
    sleep 3
  done
  ! grep ' BUSY$' <<<"$rows" >&2 || { log "playgrounds above are stuck, try again later"; exit 1; }
  ids=() stopped=()
  while read -r id title state; do
    [[ -n $id ]] || continue
    if [[ $state == RUNNING ]]; then ids[$title]=$id; else stopped[$title]=$id; fi
  done <<<"$rows"
}
vpn_ip() { echo "10.8.0.$(($1 + 1))"; } # by index, node-01-vm-01 is 10.8.0.1
on() { # run the script on stdin as root on a node, named <play>-<machine>
  labctl ssh "${ids[${1%-vm-*}]}" --machine "${1#"${1%-vm-*}"-}" -- sudo bash -s
}
throttle() { while (($(jobs -rp | wc -l) >= parallel)); do wait -n || true; done; }
on_bg() { # like on, but in the background. usage: on_bg <node> [output file]
  local node=$1 out=${2:-} script
  script=$(cat)
  throttle
  {
    local try
    for try in 1 2 3; do # an ssh session can drop, the scripts are safe to repeat
      if [[ -n $out ]]; then on "$node" <<<"$script" >"$out"; else on "$node" <<<"$script" >&2; fi && exit 0
      log "$node: attempt $try failed"
      sleep 3
    done
    : >"$tmp/failed"
  } &
}
wait_all() { # wait for background jobs, stop if any of them failed
  wait
  [[ ! -e $tmp/failed ]] || { log "stopping, see the failures above"; exit 1; }
}
log() { echo "$*" >&2; }

require_running() {
  local play
  load_ids
  for play in "${plays[@]}"; do
    [[ -n ${ids[$play]:-} ]] || { log "$play is not running, run: $0 up"; exit 1; }
  done
}

require_existing() {
  local item
  load_ids
  for item in "${plays[@]}"; do
    [[ -n ${ids[$item]:-}${stopped[$item]:-} ]] || { log "$item does not exist, run: $0 up"; exit 1; }
  done
}

start_vms() {
  local play
  load_ids
  for play in "${plays[@]}"; do
    if [[ -n ${ids[$play]:-} ]]; then
      log "$play: already running (${ids[$play]})"
      continue
    fi
    throttle
    {
      if [[ -n ${stopped[$play]:-} ]]; then
        labctl playground restart "${stopped[$play]}" >/dev/null 2>&1 && log "$play: restarted (${stopped[$play]})"
      else
        log "$play: started ($(labctl playground start flexbox -f "$manifest" --title "$play" --quiet))"
      fi || : >"$tmp/failed"
    } &
  done
  wait_all
  load_ids

  # keep the vms for 24 hours and keep their disks when stopped. both are safe to repeat.
  for play in "${plays[@]}"; do
    {
      labctl playground lifetime "${ids[$play]}" "$lifetime" >/dev/null 2>&1 &&
        labctl playground persist "${ids[$play]}" >/dev/null 2>&1 || : >"$tmp/failed"
    } &
  done
  wait_all
  log "all playgrounds: lifetime $lifetime, persistent"
}

public_url() {
  labctl expose list "${ids[$first_play]}" --kind port |
    awk -v t="http://$first_machine:$port" '$2 == t { print $3; exit }'
}

connect_vms() {
  local node i url hosts="" peers="" finish
  local -A pubkeys

  # the private key stays on the vm, only the public key comes back.
  for node in "${nodes[@]}"; do
    on_bg "$node" "$tmp/$node.pubkey" <<SCRIPT
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
  done
  wait_all
  for node in "${nodes[@]}"; do pubkeys[$node]=$(tail -1 "$tmp/$node.pubkey"); done

  # expose the port once, a re-run reuses the same url.
  url=$(public_url)
  [[ -n $url ]] || url=$(labctl expose port "${ids[$first_play]}" "$port" --machine "$first_machine" --public | tail -1)
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
    on_bg "$node" <<SCRIPT
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
  wait_all
}

check() {
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
  log "all $count vms connected"
}

install_k3s() {
  local node i token
  log "installing k3s"
  token=$(on "$first" <<SCRIPT | tail -1
set -euo pipefail
if ! systemctl is-active -q k3s; then
  curl -fsSL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-name $first --node-ip $(vpn_ip 0) --advertise-address $(vpn_ip 0) --flannel-iface $iface --data-dir $k3s_data --write-kubeconfig-mode 644 --disable traefik --disable servicelb" sh - >/dev/null 2>&1
fi
for _ in \$(seq 1 60); do [[ -s $k3s_data/server/node-token ]] && break; sleep 2; done
cat $k3s_data/server/node-token
SCRIPT
  )
  for ((i = 1; i < count; i++)); do
    node=${nodes[$i]}
    on_bg "$node" <<SCRIPT
set -euo pipefail
if ! systemctl is-active -q k3s-agent; then
  curl -fsSL https://get.k3s.io | K3S_URL=https://$(vpn_ip 0):6443 K3S_TOKEN=$token INSTALL_K3S_EXEC="agent --node-name $node --node-ip $(vpn_ip "$i") --flannel-iface $iface --data-dir $k3s_data" sh - >/dev/null 2>&1
fi
SCRIPT
  done
  wait_all
  on "$first" <<SCRIPT
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
  local ssh_cmd
  labctl playground list | awk -v p="^$prefix-[0-9]+\$" 'NR == 1 || ($3 ~ p && !/DESTROYED/)' | cut -c1-100
  load_ids
  if [[ -z ${ids[$first_play]:-} ]]; then
    if [[ -n ${stopped[$first_play]:-} ]]; then echo "stopped, run: $0 restart"; else echo "not created, run: $0 up"; fi
    return
  fi
  ssh_cmd="labctl ssh ${ids[$first_play]} --machine $first_machine"
  echo "public url: $(public_url)"
  echo "control plane: $ssh_cmd"
  if [[ -n $(on "$first" <<<'command -v k3s || true') ]]; then
    echo "k3s: $ssh_cmd -- kubectl get nodes"
  else
    echo "k3s: not installed, run: $0 k3s"
  fi
}

down() {
  local title
  load_ids
  for title in "${!ids[@]}"; do
    {
      labctl playground stop "${ids[$title]}" >/dev/null 2>&1 && log "$title: stopped (${ids[$title]})" || : >"$tmp/failed"
    } &
  done
  wait_all
}

destroy() {
  local id title state
  load_ids
  while read -r id title state; do
    [[ -n $id ]] || continue
    {
      labctl playground destroy "$id" >/dev/null 2>&1 && log "$title: destroyed ($id)"
    } &
  done <<<"$(list_plays)"
  wait
}

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
[[ ${1:-} != up && ${1:-} != restart ]] || log "done in ${SECONDS}s"
