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

set -euo pipefail

instance="$1"
declare -A odasrvargs

while IFS="=" read -r key value; do
  odasrvargs["$key"]="$value"
done < <(/usr/bin/python3 /opt/odasrv/bin/tomlconfig.py parse $instance)

odasrvpath="${odasrvargs[odasrvpath]}"
wadpaths="${odasrvargs[wadpaths]}"
configpath="${odasrvargs[configpath]}"
config="${odasrvargs[config]}"
port="${odasrvargs[port]}"

if ! [[ -d $configpath && -r $configpath && -x $configpath ]]; then
  echo "Error: Config directory '$configpath' is unable to be accessed." 1>&2
  exit 1
fi

if [[ ! -r "$config" ]]; then
  echo "Error: Config file '$config' is unable to be accessed." 1>&2
  exit 1
fi

if [[ ! -x "$odasrvpath" ]]; then
  echo "Error: odasrv executable '$odasrvpath' is unable to be executed." 1>&2
  exit 1
fi

IFS=':'
for dir in $wadpaths; do
  if ! [[ -d $dir && -r $dir && -x $dir ]]; then
    echo "Error: WAD directory '$dir' is unable to be accessed." 1>&2
    exit 1
  fi
done

"$odasrvpath" \
  -port "$port" \
  -config "$config" \
  -cfgdir "$configpath" \
  -waddir "$wadpaths" \
  -confile "/run/odasrv/con/$instance" \
  +logfile "/var/log/odasrv/logs/$instance.log" \
  -crashdir "/var/log/odasrv/crash-dumps" \
  +sv_banfile "/var/lib/odasrv/banlist.json"
