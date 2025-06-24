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
doomtools_dir="$script_dir/DoomTools"
downloads_dir="$script_dir/downloads"

admin_user="$SUDO_USER"
service_user="odasrv"
service_group="odasrvmgr"

configs_src="$script_dir/configs"
wads_src="$script_dir/wads"
polkit_src="$script_dir/odasrvmgr.rules"
bash_completion_src="$script_dir/odasrvmgr-completions"

# Install java and DoomTools
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y default-jre
curl -L -o 'doomtools.tar.gz' 'https://github.com/MTrop/DoomTools/releases/download/2025.05.10-RELEASE/doomtools-bash-2025.05.10.194013274.tar.gz'
mkdir -p "$doomtools_dir"
tar -xzf 'doomtools.tar.gz' -C "$doomtools_dir"
rm 'doomtools.tar.gz'

# Download wads with DoomTools
echo "Downloading wads..."
mkdir -p "$downloads_dir"
"$doomtools_dir/doomtools" --update && "$doomtools_dir/doomtools" --update-cleanup && "$doomtools_dir/doomtools" --update-shell
"$doomtools_dir/doomfetch" --target "$downloads_dir" --lockfile "$script_dir/doomfetch.lock"
for zip_file in "$downloads_dir"/*.zip; do
  echo "Extracting $zip_file"
  unzip -j -o "$zip_file" '*.wad' -d "$script_dir/wads/PWAD"
done

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
#echo "Adding $service_user and $admin_user to $service_group..."
#usermod -aG "$service_group" "$service_user"
usermod -aG "$service_group" "$admin_user"

# Prepare directories
echo "Setting up $install_dir and subdirectories..."
mkdir -p "$install_dir/configs" "$install_dir/wads"

# Copy files
echo "Copying configs and wads..."
cp -r "$configs_src/"* "$install_dir/configs/"
cp -r "$wads_src/"* "$install_dir/wads/"
install -m 644 "$polkit_src" "/usr/share/polkit-1/rules.d/50-odasrvmgr.rules"
install -T -m 644 "$bash_completion_src" "/usr/share/bash-completion/completions/odasrvmgr"
# TODO: make sure these permissions are correct
# TODO: get the owners right here
sudo install -T -D -m 644 -o root -g root "$script_dir/odasrvargs.sh" "$install_dir/bin/odasrvargs.sh"
sudo install -T -D -m 644 -o root -g root "$script_dir/tomlconfig.py" "$install_dir/bin/tomlconfig.py"
# TODO: this should instead update a .sample and only setup.sh should overwrite the actual config
sudo install -T -D -m 664 -o root -g odasrvmgr "$script_dir/odasrvmgr.toml" "/etc/odasrvmgr/odasrvmgr.toml"

# Set ownership and permissions
echo "Setting ownership and permissions..."
chown -R "$service_user:$service_group" "$install_dir"
# Make directories r-x for odasrv, rwx for the group
find "$install_dir" -type d -exec chmod 570 {} +
# Make files r-- for odasrv, rw- for the group
find "$install_dir" -type f -exec chmod 460 {} +
# Except the log directory needs to be writable
chmod 770 "$install_dir/con"
# And the crash dumps directory
chmod 770 "$install_dir/crash-dumps"
find "$install_dir" -type d -exec chmod g+s {} +

# Enable systemd services
echo "Enabling servers..."
systemctl link "$script_dir/systemd-units/odasrv@.service"
systemctl enable --now "$script_dir/systemd-units/odasrv.target"
systemctl restart polkit.service

# Install manager script
echo "Installing odasrvmgr..."
echo "$script_dir" > /opt/odasrv/.repo_path
install -m 755 "$script_dir/odasrvmgr.sh"  /usr/local/bin/odasrvmgr
