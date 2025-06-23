#!/bin/bash

errcho() {
  echo "$@" 1>&2
}

server_exists() {
  local target="odasrv.target"
  local service="$1"

  while read -r dep; do
    if [[ "$dep" == "$service" ]]; then
      return 0
    fi
  done < <(systemctl list-dependencies --plain --no-legend "$target" | grep 'odasrv@')

  return 1
}

svmanager_list() {
  local target="odasrv.target"

  printf "%-15s %-10s\n" "Servers" "Status"
  printf "%-15s %-10s\n" "-------" "------"

  while read -r dep; do
    if systemctl is-active --quiet "$dep"; then
      local status="running"
    else
      local status="stopped"
    fi
    local instance="${dep#*@}"
    instance="${instance%.service}"
    printf "%-15s %-10s\n" "$instance" "$status"
  done < <(systemctl list-dependencies --plain --no-legend "$target" | grep 'odasrv@')
}

restartreload() {
  # TODO: make sure all properly propagates to instances if target is not actually running
  local instance="$1"
  local command="$2"
  local service="odasrv@$instance.service"
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
  local instance="$1"
  local service="odasrv@$instance.service"
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
  local instance="$1"
  local service="odasrv@$instance.service"
  if [[ -z "$instance" ]]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name new <server name>"
    exit 1
  fi

  if [[ ! "$instance" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    errcho "Error: New server names must match the pattern ^[a-zA-Z0-9_-]+$"
    exit 1
  fi

  sudo systemctl enable "$service" # maybe make this print some different output instead of the symlink stuff
}

svmanager_delete() {
  local instance="$1"
  local service="odasrv@$instance.service"
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

  local instance="$1"
  if [ -z "$instance" ]; then
    echo -e "${text_ul}Usage:${text_normal} $script_name console <server instance>"
    echo
    echo "Run $script_name list to see currently running servers"
    exit 1
  fi

  local input_file="/run/odasrv/con/$instance"
  local log_file="/var/log/odasrv/logs/$instance.log"
  local tmux_session="odasrv-$instance"
  local systemd_service="odasrv@$instance.service"

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
    tmux new-session -s "$tmux_session" \; \
      split-window -vb \; \
      send-keys "tail -f "$log_file" -n 100" C-m \; \
      select-pane -D \; \
      send-keys "while true; do read -e -p '> ' cmd && echo \"\$cmd\" >> "$input_file"; done" C-m \; \
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

  local doomtools_dir="$repo_dir/DoomTools"
  local downloads_dir="$repo_dir/downloads"

  local skip_pattern='^\[Skipping\] File found in target directory: (.+)$'
  local skipped=()
  while read -r line; do
    if [[ "$line" =~ $skip_pattern ]]; then
      skipped+=("${BASH_REMATCH[1]}")
    fi
    echo "$line"
  done < <("$doomtools_dir/doomfetch" --target "$downloads_dir" --lockfile "$repo_dir/doomfetch.lock")

  for zipfile in "$downloads_dir"/*.zip; do
    local base="$(basename "${zipfile%.zip}")"
    if [[ " ${skipped[*]} " =~ " $base " ]]; then
      continue
    fi

    echo "Extracting $zip..."
    unzip -j -o "$zipfile" '*.wad' -d "$repo_dir/wads/PWAD"
  done

  local install_dir="/opt/odasrv"
  local service_user="odasrv"
  local service_group="odasrvmgr"

  sudo rsync -a --chown="$service_user:$service_group" \
    --update "$repo_dir/configs/" "$install_dir/configs/"
  sudo rsync -a --chown="$service_user:$service_group" \
    --update "$repo_dir/wads/" "$install_dir/wads/"
  sudo rsync -a --chown="$service_user:$service_group" \
    --update "$repo_dir/banlist.json" "$install_dir/banlist.json"

  sudo find "$install_dir/configs" "$install_dir/wads" -type d -exec chmod 570 {} +
  sudo find "$install_dir/configs" "$install_dir/wads" -type f -exec chmod 460 {} +

  sudo chmod 660 "$install_dir/banlist.json"

  sudo find "$install_dir/configs" "$install_dir/wads" -type d -exec chmod g+s {} +

  sudo install -m 644 "$repo_dir/odasrvmgr.rules" "/usr/share/polkit-1/rules.d/50-odasrvmgr.rules"
  sudo install -T -m 644 "$repo_dir/odasrvmgr-completions" "/usr/share/bash-completion/completions/odasrvmgr"

  # TODO: get the owners right here
  sudo install -T -D -m 644 -o root -g root "$repo_dir/odasrvargs.sh" "/opt/odasrv/bin/odasrvargs.sh"
  sudo install -T -D -m 644 -o root -g root "$repo_dir/tomlconfig.py" "/opt/odasrv/bin/tomlconfig.py"
  # TODO: this should instead update a .sample and only setup.sh should overwrite the actual config
  sudo install -T -D -m 664 -o root -g odasrvmgr "$repo_dir/odasrvmgr.toml" "/etc/odasrvmgr/odasrvmgr.toml"

  # change this to check if any service running and restart those specifically
  # might be able to use try-restart here
  sudo systemctl daemon-reload
  if systemctl is-active --quiet odasrv.target; then
    sudo systemctl stop odasrv@*.service
    sudo systemctl stop odasrv.target
    sudo systemctl start odasrv.target
  fi

  # needed for any updated rules to take effect
  sudo systemctl restart polkit.service

  sudo install -T -D -m 755 -o root -g root "$repo_dir/odasrvmgr.sh" /opt/odasrv/bin/odasrvmgr
  if [[ ! -L /usr/local/bin/odasrvmgr ]]; then
    sudo ln -s /opt/odasrv/bin/odasrvmgr /usr/local/bin/odasrvmgr
  fi
  echo "Update complete."
}

svmanager_validate() {
  python3 /opt/odasrv/tomlconfig.py validate
}

script_name=$(basename "$0")
required_group="odasrvmgr"
text_red="\e[91m"
text_green="\e[92m"
text_ul="\e[4m"
text_normal="\e[0m"

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
  echo "  uninstall       unimplemented but should remove all of odasrvmgr"
  exit 1
fi
