#!/bin/bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Error: This script must be run with sudo." >&2
  exit 1
fi

if [[ -z "$SUDO_USER" ]]; then
  echo "Error: Could not find current user." >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
install_dir="/opt/odasrv"

admin_user="$SUDO_USER"
service_user="odasrv"
service_group="odasrvmgr"

polkit_src="$script_dir/odasrvmgr.rules"
bash_completion_src="$script_dir/odasrvmgr-completions"

echo "Creating install directory..."
install -o root -g root -m 0755 -d "$install_dir"

# Create user if missing
if ! id -u "$service_user" >/dev/null 2>&1; then
  echo "Creating user $service_user..."
  useradd --system -M --shell /usr/sbin/nologin "$service_user"
  install -o "$service_user" -g "$service_user" -m 0750 -d "$install_dir/odasrvhome"
  install -o "$service_user" -g "$service_user" -m 0755 -d "$install_dir/odasrvhome/.odamex"
  usermod -d "$install_dir/odasrvhome" "$service_user"
else
  echo "User $service_user already exists."
fi

# Create group if missing
if ! getent group "$service_group" >/dev/null 2>&1; then
  echo "Creating group $service_group..."
  groupadd "$service_group"
else
  echo "Group $service_group already exists."
fi

# Add users to group
echo "Adding $admin_user to $service_group..."
usermod -aG "$service_group" "$admin_user"

# Copy files
echo "Installing files..."
install -T -m 644  -o root -g root "$polkit_src" "/usr/share/polkit-1/rules.d/50-odasrvmgr.rules"
install -T -m 644  -o root -g root "$bash_completion_src" "/usr/share/bash-completion/completions/odasrvmgr"
install -T -D -m 644 -o root -g root "$script_dir/odasrvargs.sh" "$install_dir/bin/odasrvargs.sh"
install -T -D -m 644 -o root -g root "$script_dir/tomlconfig.py" "$install_dir/bin/tomlconfig.py"
install -T -D -m 644 -o root -g root "$script_dir/wadfetch.py" "$install_dir/bin/wadfetch.py"
if [[ ! -f "/etc/odasrvmgr/odasrvmgr.toml" ]]; then
  install -T -D -m 664 -o root -g odasrvmgr "$script_dir/odasrvmgr.toml" "/etc/odasrvmgr/odasrvmgr.toml"
fi

# Enable systemd services
echo "Enabling servers..."
install -T -m 644 -o root -g root "$script_dir/systemd-units/odasrv.target" "/etc/systemd/system/odasrv.target"
install -T -m 644 -o root -g root "$script_dir/systemd-units/odasrv@.service" "/etc/systemd/system/odasrv@.service"
systemctl enable "odasrv.target"
systemctl daemon-reload
systemctl restart polkit.service

# Install manager script
echo "Installing odasrvmgr..."
echo "$script_dir" > /opt/odasrv/.repo_path
install -T -D -m 755 -o root -g odasrvmgr "$script_dir/odasrvmgr.sh"  /usr/local/bin/odasrvmgr
