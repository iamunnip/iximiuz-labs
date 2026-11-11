#!/usr/bin/env bash
# One playground, 4vm, with four VMs on its private network: dev-machine, node-1, node-2
# and node-3. The VMs share the playground network, which already names them in
# /etc/hosts, so no VPN is needed. The script can install K3s, with node-1 as the control
# plane, node-2 and node-3 as nodes, and kubectl on dev-machine.
#
# Usage:
#   4vm.sh start [--k3s]  Start the VMs and connect them, optionally install K3s
#   4vm.sh k3s            Install K3s on running VMs
#   4vm.sh check          Test the network from dev-machine
#   4vm.sh status         Show the VMs and how to connect to dev-machine
#   4vm.sh stop           Stop the VMs and keep their disks
#   4vm.sh restart        Start stopped VMs and reconnect them
#   4vm.sh destroy        Delete the VMs and their data
#
# Every command except destroy is safe to re-run.
set -euo pipefail

# Parse the entire file before any playground operations.
bash -n "$0"

manifest="$(dirname "$0")/../manifests/4vm.yaml"
title=4vm
dev='dev-machine'
server='node-1'
agents=(node-2 node-3)
nodes=("$dev" "$server" "${agents[@]}")
count=${#nodes[@]}
k3s_count=$((1 + ${#agents[@]}))
lifetime=24h # the longest a playground can run

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
id="" stopped_id=""

fetch_playgrounds() {
  local attempt
  for attempt in 1 2 3; do
    if labctl playground list >"$tmp/playgrounds.list" 2>"$tmp/playgrounds.err"; then
      cat "$tmp/playgrounds.list"
      return 0
    fi
    if ((attempt == 3)) || ! grep -Eqi 'status (429|500|502|503|504)|error code: (429|500|502|503|504)|timed? out|timeout|temporary failure|connection (reset|refused)|unexpected EOF' "$tmp/playgrounds.err"; then
      log "Unable to list playgrounds; no further operations will run"
      sed 's/^/  /' "$tmp/playgrounds.err" >&2
      return 1
    fi
    log "Temporary playground-list failure (attempt $attempt/3); retrying in $((attempt * 2))s"
    sleep "$((attempt * 2))"
  done
}

list_plays() { # print "<id> <RUNNING|STOPPED|BUSY>" for this setup, destroyed ones are left out
  fetch_playgrounds | awk -v t="$title" 'NR > 1 && $3 == t {
    if (/DESTROYED|TERMINATED|FAILED/) next
    print $1, (/RUNNING/ ? "RUNNING" : /STOPPED/ ? "STOPPED" : "BUSY")
  }'
}
load_ids() { # remember the id of the running or stopped playground
  local rows row_id state _
  for _ in {1..60}; do # a playground that is stopping must not look like a missing one
    rows=$(list_plays)
    grep -q ' BUSY$' <<<"$rows" || break
    log "Waiting for the playground to finish changing state"
    sleep 3
  done
  ! grep ' BUSY$' <<<"$rows" >&2 || { log "The playground above is stuck, try again later"; exit 1; }
  id="" stopped_id=""
  while read -r row_id state; do
    [[ -n $row_id ]] || continue
    [[ -z $id$stopped_id ]] || {
      log "Duplicate playground title: $title. Resolve duplicates before continuing."
      exit 1
    }
    if [[ $state == RUNNING ]]; then id=$row_id; else stopped_id=$row_id; fi
  done <<<"$rows"
}
on() { labctl ssh "$id" --machine "$1" -- sudo bash -s; } # Run the script on stdin as root
on_logged() { # like on, but the remote stderr is indented under the current step
  local rc=0
  on "$1" 2>"$tmp/$1.logged.err" || rc=$?
  sed 's/^/  /' "$tmp/$1.logged.err" >&2
  return "$rc"
}
on_bg() { # like on, but in the background. usage: on_bg <node> [output file]
  local node=$1 out=${2:-} script
  script=$(cat)
  log "$node: Executing remote step"
  {
    local try
    for try in 1 2 3; do # an SSH session can drop, the scripts are safe to repeat
      if on "$node" <<<"$script" >"${out:-$tmp/$node.remote.log}" 2>"$tmp/$node.remote.err"; then
        if [[ -z $out ]]; then sed 's/^/  /' "$tmp/$node.remote.log" >&2; fi
        sed 's/^/  /' "$tmp/$node.remote.err" >&2
        log "$node: Remote step completed"
        exit 0
      fi
      sed 's/^/  /' "$tmp/$node.remote.err" >&2
      if [[ -z $out ]]; then sed 's/^/  /' "$tmp/$node.remote.log" >&2; fi
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
log() { printf '  %s\n' "$*" >&2; }
step_started=false
step() {
  [[ $step_started == false ]] || printf '\n' >&2
  printf '[%ss] Step: %s\n' "$SECONDS" "$*" >&2
  step_started=true
}

run_task() {
  local label=$1 output=$2
  shift 2
  if "$@" >"$output" 2>&1; then
    log "$label"
  else
    log "$label: Failed"
    sed 's/^/  /' "$output" >&2
    return 1
  fi
}

show_connections() {
  [[ -n $id ]] || return 0
  step "Access to $dev"
  printf '  %s: labctl ssh %s --machine %s\n' "$dev" "$id" "$dev" >&2
}

require_running() {
  step "Verify the playground is running"
  load_ids
  [[ -n $id ]] || { log "$title is not running, run: $0 start"; exit 1; }
}

require_existing() {
  step "Verify the playground exists"
  load_ids
  [[ -n $id$stopped_id ]] || { log "$title does not exist, run: $0 start"; exit 1; }
}

start_vms() {
  local created_id
  step "Start or reuse the playground"
  load_ids
  if [[ -n $id ]]; then
    log "$title: Already running ($id)"
  elif [[ -n $stopped_id ]]; then
    run_task "$title: Restarted ($stopped_id)" "$tmp/restart.log" labctl playground restart "$stopped_id"
  elif created_id=$(labctl playground start flexbox -f "$manifest" --title "$title" --quiet 2>"$tmp/start.log") &&
       [[ -n $created_id ]]; then
    log "$title: Started ($created_id)"
  else
    sed 's/^/  /' "$tmp/start.log" >&2
    exit 1
  fi
  load_ids
  [[ -n $id ]] || { log "$title: Not running after startup"; exit 1; }

  # Keep the VMs for 24 hours and keep their disks when stopped. both are safe to repeat.
  step "Set lifetime to $lifetime and enable persistence"
  if { labctl playground lifetime "$id" "$lifetime" &&
       labctl playground persist "$id"; } >"$tmp/lifecycle.log" 2>&1; then
    log "$title: Lifetime $lifetime; persistent"
  else
    log "$title: Failed to set lifetime or persistence"
    sed 's/^/  /' "$tmp/lifecycle.log" >&2
    exit 1
  fi
}

check() {
  step "Check connectivity from $dev"
  on_bg "$dev" <<SCRIPT
failed=\$(
  for target in ${nodes[*]:1}; do
    ping -c 1 -w 20 "\$target" >/dev/null 2>&1 || echo "$dev -> \$target: FAILED" &
  done
  wait
)
[[ -z \$failed ]] || { echo "\$failed"; exit 1; }
SCRIPT
  wait_all
}

install_k3s() {
  local node token info version kubeconfig
  step "Install K3s on $server"
  token=$(on_logged "$server" <<SCRIPT | tail -1
set -euo pipefail
if ! systemctl is-active -q k3s; then
  curl -fsSL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-name $server --tls-san $server --write-kubeconfig-mode 600 --disable traefik --disable servicelb" sh - >/dev/null
fi
for _ in \$(seq 1 60); do [[ -s /var/lib/rancher/k3s/server/node-token ]] && break; sleep 2; done
cat /var/lib/rancher/k3s/server/node-token
SCRIPT
  )
  [[ -n $token ]] || { log "$server: No K3s join token"; exit 1; }

  step "Install K3s agents"
  # exec, not notify: on K3s v1.37 the agent never signals systemd, so the installer would wait forever.
  for node in "${agents[@]}"; do
    on_bg "$node" <<SCRIPT
set -euo pipefail
if ! systemctl is-active -q k3s-agent; then
  curl -fsSL https://get.k3s.io | K3S_URL=https://$server:6443 K3S_TOKEN=$token INSTALL_K3S_TYPE=exec INSTALL_K3S_EXEC="agent --node-name $node" sh - >/dev/null
fi
SCRIPT
  done
  wait_all

  step "Wait for all K3s nodes to become Ready"
  on "$server" <<SCRIPT 2>&1 | sed 's/^/  /' >&2
set -e
for _ in \$(seq 1 90); do
  [[ \$(k3s kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready') == $k3s_count ]] && break
  sleep 2
done
k3s kubectl label node ${agents[*]} node-role.kubernetes.io/node= --overwrite >/dev/null
k3s kubectl get nodes -o wide
[[ \$(k3s kubectl get nodes --no-headers | grep -c ' Ready') == $k3s_count ]]
SCRIPT

  # The kubeconfig holds the admin credentials, so it is copied but never logged.
  step "Set up kubectl on $dev"
  info=$(on_logged "$server" <<'SCRIPT'
set -euo pipefail
k3s --version | awk 'NR == 1 { sub(/\+.*/, "", $3); print $3 }'
base64 -w0 /etc/rancher/k3s/k3s.yaml
echo
SCRIPT
  )
  version=$(sed -n 1p <<<"$info")
  kubeconfig=$(sed -n 2p <<<"$info")
  [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { log "$server: Unknown K3s version: $version"; exit 1; }
  [[ -n $kubeconfig ]] || { log "$server: No kubeconfig"; exit 1; }
  log "kubectl $version"
  on_bg "$dev" <<SCRIPT
set -euo pipefail
if [[ "\$(kubectl version --client 2>/dev/null)" != *"$version"* ]]; then
  tmp=\$(mktemp -d)
  trap 'rm -rf "\$tmp"' EXIT
  cd "\$tmp"
  base=https://dl.k8s.io/release/$version/bin/linux/amd64
  curl -fsSLO "\$base/kubectl"
  echo "\$(curl -fsSL "\$base/kubectl.sha256")  kubectl" | sha256sum -c --quiet -
  install kubectl /usr/local/bin/kubectl
fi
home=\$(getent passwd laborant | cut -d: -f6)
install -d -o laborant -g laborant -m 700 "\$home/.kube"
base64 -d <<<'$kubeconfig' | sed 's#https://127.0.0.1:6443#https://$server:6443#' > "\$home/.kube/config"
chown laborant:laborant "\$home/.kube/config"
chmod 600 "\$home/.kube/config"
kubectl --kubeconfig "\$home/.kube/config" get nodes >/dev/null
SCRIPT
  wait_all
}

status() {
  step "Show playground status"
  local k3s_path
  load_ids
  if [[ -n $id ]]; then
    log "$title: Running ($id)"
  elif [[ -n $stopped_id ]]; then
    log "$title: Stopped ($stopped_id)"
    log "Run: $0 restart"
    return
  else
    log "$title: Not created"
    log "Run: $0 start"
    return
  fi
  if ! k3s_path=$(on "$server" <<<'command -v k3s || true' 2>"$tmp/status-ssh.err"); then
    log "Failed to inspect K3s on $server"
    sed 's/^/  /' "$tmp/status-ssh.err" >&2
    return 1
  fi
  if [[ -n $k3s_path ]]; then
    log "K3s: labctl ssh $id --machine $dev -- kubectl get nodes"
  else
    log "K3s: Not installed, run: $0 k3s"
  fi
}

stop() {
  step "Stop the playground and retain its disks"
  load_ids
  [[ -z $id ]] || run_task "$title: Stopped ($id)" "$tmp/stop.log" labctl playground stop "$id" </dev/null
}

destroy() {
  step "Delete the playground and its data"
  local target
  load_ids
  target=${id:-$stopped_id}
  [[ -n $target ]] || return 0
  if labctl playground destroy "$target" </dev/null >"$tmp/destroy.log" 2>&1; then
    log "$title: Destroyed ($target)"
  else
    log "$title: Failed to destroy ($target)"
    sed 's/^/  /' "$tmp/destroy.log" >&2
    exit 1
  fi
}

# Parse dispatch and completion together before any long-running operation.
main() {
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
    start:) start_vms; check ;;
    start:--k3s) start_vms; check; install_k3s ;;
    k3s:) require_running; install_k3s ;;
    check:) require_running; check ;;
    status:) status ;;
    stop:) stop ;;
    restart:) require_existing; start_vms; check ;;
    destroy:) destroy ;;
    *) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" >&2; exit 2 ;;
  esac
  case ${1:-} in
    start|restart)
      step "Completed setting up VMs"
      log "All $count VMs connected"
      show_connections ;;
    check)
      step "Completed connectivity check"
      log "All $count VMs connected"
      show_connections ;;
    k3s)
      step "Completed installing K3s"
      log "All $k3s_count K3s nodes are Ready"
      show_connections ;;
    status)
      step "Completed checking playground status"
      show_connections ;;
    stop) step "Completed stopping the playground; disks retained" ;;
    destroy) step "Completed deleting the playground and its data" ;;
  esac
}

# Exit in the same parsed command list if the file is replaced during execution.
main "$@"; exit "$?"
