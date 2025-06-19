#!/bin/bash

svmanager_list() {
  local target="odasrv.target"

  printf "%-15s %-10s\n" "Servers" "Status"
  printf "%-15s %-10s\n" "-------" "------"

  # List all dependencies of the target (recursive = false to get direct deps)
  local deps
  mapfile -t deps < <(systemctl list-dependencies --plain --no-legend "$target" | grep 'odasrv@' | xargs)

  for svc in "${deps[@]}"; do
    if systemctl is-active --quiet "$svc"; then
      local status="running"
    else
      local status="stopped"
    fi
    local instance="${svc#*@}"
    instance="${instance%.service}"
    printf "%-15s %-10s\n" "$instance" "$status"
  done
}

svmanager_console() {
  local instance="$1"
  if [ -z "$instance" ]; then
    echo -e "\e[4mUsage:\e[0m $script_name console <server instance>"
    echo
    echo "Run $0 list to see currently running servers"
    exit 1
  fi

  local input_file="/opt/odasrv/con/$instance"
  local log_file="/opt/odasrv/logs/$instance.log"
  local tmux_session="odasrv-$instance"
  local systemd_service="odasrv@$instance.service"

  if ! systemctl is-active --quiet "$systemd_service"; then
    echo "Error: Cannot attach to stopped server instance $instance"
    exit 1
  fi

  if tmux has-session -t "$tmux_session" 2>/dev/null; then
    tmux attach-session -t "$tmux_session"
  else
    tmux new-session -s "$tmux_session" \; \
      split-window -vb \; \
      send-keys "tail -f /opt/odasrv/logs/${1}.log" C-m \; \
      select-pane -D \; \
      send-keys "while true; do read -e -p '> ' cmd && echo \"\$cmd\" >> /opt/odasrv/con/${1}; done" C-m \; \
      resize-pane -D -y 1
  fi
}

svmanager_update() {
  if [[ -f /opt/odasrv/.repo_path ]]; then
    local repo_dir=$(< /opt/odasrv/.repo_path)
  else
    echo "Repo path file missing!" >&2
    exit 1
  fi

  sudo install -m 755 "$repo_dir/odasrvmgr.sh" /usr/local/bin/odasrvmgr
  echo "Update complete."
}

script_name=$(basename "$0")

if declare -f "svmanager_$1" >/dev/null; then
    func="svmanager_$1"
    shift
    "$func" "$@"
else
    echo -e "\e[4mUsage:\e[0m $script_name <COMMAND>"
    echo
    echo -e "\e[4mCommands:\e[0m"
    echo "  list"
    echo "  console"
    echo "  start"
    echo "  stop"
    echo "  reload"
    echo "  restart"
    echo "  update"
    echo "  uninstall"
    exit 1
fi
