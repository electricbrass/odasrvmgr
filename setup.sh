#!/bin/bash

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
service_group="odasrvgroup"

configs_src="$script_dir/configs"
banlist_src="$script_dir/banlist.json"
ports_src="$script_dir/ports.env"
wads_src="$script_dir/wads"

# Create user if missing
if ! id -u "$service_user" >/dev/null 2>&1; then
  echo "Creating user $service_user..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$service_user"
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
echo "Adding $serivce_user and $admin_user to $service_group..."
usermod -aG "$service_group" "$service_user"
usermod -aG "$service_group" "$admin_user"

# Prepare directories
echo "Setting up $install_dir and subdirectories..."
mkdir -p "$install_dir/configs" "$install_dir/logs" "$install_dir/wads"

# Copy files
echo "Copying configs, wads, banlist, and ports.env..."
cp -r "$configs_src/"* "$install_dir/configs/"
cp -r "$wads_src/"* "$install_dir/wads/"
cp "$banlist_src" "$install_dir/"
cp "$ports_src" "$install_dir/"

# Set ownership and permissions
echo "Setting ownership and permissions..."
chown -R "$admin_user:$service_group" "$install_dir"
# Make directories rwx for me, r-x for the group
find "$install_dir" -type d -exec chmod 750 {} +
# Make files rw- for me, r-- for the group
find "$install_dir" -type f -exec chmod 640 {} +
# Except the log directory needs to be writable
chmod 770 "$install_dir/logs"
find "$install_dir" -type d -exec chmod g+s {} +

# Enable systemd services
echo "Enabling servers..."
systemctl link "$script_dir/systemd-units/odasrv@.service"
systemctl enable "$script_dir/systemd-units/odasrv.target"
