#!/bin/bash

# Copyright (C) 2025 Mia McMahill
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

errcho() {
  echo "$@" 1>&2
}

server_exists() {
  local -r target="odasrv.target"
  local -r service="$1"

  while read -r dep; do
    if [[ "$dep" == "$service" ]]; then
      return 0
    fi
  done < <(systemctl list-dependencies --plain --no-legend "$target" | grep 'odasrv@')

  return 1
}

svmanager_list() {
  local -r target="odasrv.target"

  printf "%-15s %-10s\n" "Servers" "Status"
  printf "%-15s %-10s\n" "-------" "------"

  local status
  while read -r dep; do
    if systemctl is-active --quiet "$dep"; then
      status="running"
    elif systemctl is-failed --quiet "$dep"; then
      status="failed"
    else
      status="stopped"
    fi
    local instance="${dep#*@}"
    instance="${instance%.service}"
    printf "%-15s %-10s\n" "$instance" "$status"
  done < <(systemctl list-dependencies --plain --no-legend "$target" | grep 'odasrv@')
}

restartreload() {
  # TODO: make sure all properly propagates to instances if target is not actually running
  local -r instance="$1"
  local -r command="$2"
  local -r service="odasrv@$instance.service"
  if [[ -z "$instance" ]]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name $command <server instance>"
    echo
    echo "Run $script_name list to see currently running servers"
    echo "Oh or also you can use all for all instances"
    exit 1
  fi

  if [[ "$instance" == "all" ]]; then
    systemctl "$command" odasrv.target
  elif server_exists "$service"; then
    systemctl "$command" "$service"
  else
    echo "Error: Server instance $instance does not exist"
    exit 1
  fi
}

svmanager_stop() {
  local -r instance="$1"
  local -r service="odasrv@$instance.service"
  if [[ -z "$instance" ]]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name stop <server instance>"
    echo
    echo "Run $script_name list to see currently running servers"
    echo "Oh or also you can use all for all instances"
    exit 1
  fi

  if [[ "$instance" == "all" ]]; then
    systemctl stop odasrv@*.service
    systemctl stop odasrv.target
  elif server_exists "$service"; then
    systemctl stop "$service"
  else
    echo "Error: Server instance $instance does not exist"
    exit 1
  fi
}

svmanager_start() {
  restartreload "$1" start
}

svmanager_restart() {
  restartreload "$1" restart
}

svmanager_reload() {
  restartreload "$1" reload
}

svmanager_new() {
  # add option to start a new server without enabling, temp for this session
  local -r instance="$1"
  local -r service="odasrv@$instance.service"
  if [[ -z "$instance" ]]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name new <server name>"
    exit 1
  fi

  if [[ ! "$instance" =~ ^[A-Za-z0-9_-]+$ ]]; then
    errcho "Error: New server names must match the pattern ^[A-Za-z0-9_-]+$"
    exit 1
  fi

  if server_exists "$service"; then
    errcho "Error: Server name $instance already in use"
    exit 1
  fi

  sudo systemctl enable "$service" # maybe make this print some different output instead of the symlink stuff
}

svmanager_delete() {
  local -r instance="$1"
  local -r service="odasrv@$instance.service"
  if [[ -z "$instance" ]]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name delete <server instance>"
    echo
    echo "Run $script_name list to see currently running servers"
    echo "Oh or also you can use all for all instances"
    exit 1
  fi

  if server_exists "$service"; then
    systemctl stop "$service"
    sudo systemctl disable "$service" # maybe make this print some different output instead of the symlink stuff
  else
    echo "Error: Server instance $instance does not exist"
    exit 1
  fi
}

svmanager_console() {
  if ! command -v tmux &>/dev/null; then
    echo "tmux must be installed to use this feature."
  fi

  local -r instance="$1"
  if [ -z "$instance" ]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name console <server instance>"
    echo
    echo "Run $script_name list to see currently running servers"
    exit 1
  fi

  local -r input_file="/run/odasrv/con/$instance"
  local -r log_file="/var/log/odasrv/logs/$instance.log"
  local -r tmux_session="odasrv-$instance"
  local -r systemd_service="odasrv@$instance.service"

  if ! server_exists "$systemd_service"; then
    echo "Error: Server instance $instance does not exist"
    exit 1
  fi

  if ! systemctl is-active --quiet "$systemd_service"; then
    echo "Error: Cannot attach to stopped server instance $instance"
    exit 1
  fi

  if tmux has-session -t "$tmux_session" 2>/dev/null; then
    tmux attach-session -t "$tmux_session"
  else
    tmux -f /dev/null \; \
      new-session -s "$tmux_session" \; \
      split-window -vb \; \
      send-keys "set +o history" C-m \; \
      send-keys "tail -f "$log_file" -n 100" C-m \; \
      select-pane -D \; \
      send-keys "trap 'tmux kill-session' SIGINT" C-m \; \
      send-keys "unset HISTFILE" C-m \; \
      send-keys "set -o history" C-m \; \
      send-keys "history -c" C-m \; \
      send-keys "while true; do read -e -p '> ' cmd || continue; history -s \"\$cmd\"; echo \"\$cmd\" >> "$input_file"; done" C-m \; \
      send-keys C-m \; \
      resize-pane -D -y 1
  fi
}

svmanager_update() {
  if [[ -f /opt/odasrvmgr/.repo_path ]]; then
    local repo_dir=$(< /opt/odasrvmgr/.repo_path)
  else
    echo "Repo path file missing!" >&2
    exit 1
  fi

  local -r install_dir="/opt/odasrvmgr"
  local -r service_user="odasrv"
  local -r service_group="odasrvmgr"

  sudo install -T -m 644 "$repo_dir/odasrvmgr.rules" "/usr/share/polkit-1/rules.d/50-odasrvmgr.rules"
  sudo install -T -m 644 "$repo_dir/odasrvmgr-completions" "/usr/share/bash-completion/completions/odasrvmgr"

  sudo install -T -D -m 644 -o root -g root "$repo_dir/odasrvargs.sh" "/opt/odasrvmgr/bin/odasrvargs.sh"
  sudo install -T -D -m 644 -o root -g root "$repo_dir/tomlconfig.py" "/opt/odasrvmgr/bin/tomlconfig.py"
  sudo install -T -D -m 644 -o root -g root "$repo_dir/wadfetch.py" "/opt/odasrvmgr/bin/wadfetch.py"
  sudo install -T -D -m 664 -o root -g odasrvmgr "$repo_dir/odasrvmgr.toml" "/etc/odasrvmgr/odasrvmgr.toml.sample"

  sudo install -T -m 644 -o root -g root "$repo_dir/systemd-units/odasrv.target" "/etc/systemd/system/odasrv.target"
  sudo install -T -m 644 -o root -g root "$repo_dir/systemd-units/odasrv@.service" "/etc/systemd/system/odasrv@.service"

  # change this to check if any service running and restart those specifically
  # might be able to use try-restart here
  sudo systemctl daemon-reload
  if systemctl is-active --quiet odasrv.target || systemctl is-active --quiet odasrv@*.service; then
    systemctl stop odasrv@*.service
    systemctl stop odasrv.target
    systemctl start odasrv.target
  fi

  # needed for any updated rules to take effect
  sudo systemctl restart polkit.service

  sudo install -T -D -m 755 -o root -g root "$repo_dir/odasrvmgr.sh" /opt/odasrvmgr/bin/odasrvmgr
  if [[ ! -L /usr/local/bin/odasrvmgr ]]; then
    sudo ln -s /opt/odasrvmgr/bin/odasrvmgr /usr/local/bin/odasrvmgr
  fi
  echo "Update complete."
}

svmanager_validate() {
  python3 /opt/odasrvmgr/bin/tomlconfig.py validate
}

svmanager_fetch() {
  python3 /opt/odasrvmgr/bin/wadfetch.py "$@"
}

svmanager_edit() {
  "${EDITOR:-vi}" /etc/odasrvmgr/odasrvmgr.toml
}

declare -r script_name=$(basename "$0")
declare -r required_group="odasrvmgr"
declare -r text_red="\e[91m"
declare -r text_green="\e[92m"
declare -r text_ul="\e[4m"
declare -r text_normal="\e[0m"

if (( EUID == 0 )); then
  errcho "Error: Do not run this script as root."
  exit 1
fi

if ! id -Gnz | grep -qzxF "$required_group"; then
  errcho "Error: You must be added to the $required_group group to manage odasrv instances."
  exit 1
fi

if declare -f "svmanager_$1" >/dev/null; then
  func="svmanager_$1"
  shift
  "$func" "$@"
else
  echo -e "${text_ul}Usage:${text_normal} $script_name command"
  echo
  echo -e "${text_ul}Commands:${text_normal}"
  echo "  list            list all enabled server intances" # todo make it show any running that are not enabled
  echo "  console         attach to a server instance console (requires tmux)"
  echo "  start           start a server instance"
  echo "  stop            stop a server instance"
  echo "  reload          reload a server instance's cfg"
  echo "  restart         restart a server instance"
  echo "  new             create a new server instance (does not start it)"
  echo "  delete          delete a server instance (stops it if running)"
  echo "  update          idk what this does really"
  echo "  validate        checks /etc/odasrvmgr/odasrvmgr.toml for errors"
  echo "  fetch           smth about downloading wads idk"
  echo "  edit            edit the odasrvmgr config"
  echo "  uninstall       unimplemented but should remove all of odasrvmgr"
  exit 1
fi
