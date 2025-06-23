set -euo pipefail

instance="$1"
declare -A odasrvargs

while IFS="=" read -r key value; do
  odasrvargs["$key"]="$value"
done < <(/usr/bin/python3 /opt/odasrv/tomlconfig.py parse $instance)

odasrvpath="${odasrvargs[odasrvpath]}"
wadpaths="${odasrvargs[wadpaths]}"
config="${odasrvargs[config]}"
port="${odasrvargs[port]}"

"$odasrvpath" \
  -port "$port" \
  -config "$config" \
  -waddir "$wadpaths" \
  -confile "/opt/odasrv/con/$instance" \
  +logfile "/var/log/odasrv/$instance.log" \
  -crashdir "/opt/odasrv/crash-dumps"
