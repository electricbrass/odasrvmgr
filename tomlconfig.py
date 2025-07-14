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

import sys, tomllib, argparse
from pathlib import Path
from jsonschema import validate, ValidationError

parser = argparse.ArgumentParser()
subcommands = parser.add_subparsers(dest='subcommand', required=True)
parse_parser = subcommands.add_parser('parse')
parse_parser.add_argument('instance')
parse_parser.add_argument('-c', action='store_true')
subcommands.add_parser('validate').add_argument('-q', action='store_true')
args = parser.parse_args()

with open('/etc/odasrvmgr/odasrvmgr.toml', 'rb') as f:
  try:
    data = tomllib.load(f)
  except tomllib.TOMLDecodeError as e:
    print(f"TOML parse error: {e}", file=sys.stderr)
    sys.exit(1)
  except Exception as e:
    print(f"Failed to load config: {e}", file=sys.stderr)
    sys.exit(2)

match args.subcommand:
  case 'parse':
    match data:
      case {
        'settings': {
          'odasrvpath': str(odasrvpath),
          'configdir': str(configdir),
          'wadpaths': list(wadpaths),
          'waddownloaddir': str(_)
        },
        'servers': {args.instance: {'config': str(config), 'port': int(port), 'branch': str(branch)}, **_other_servers},
        'branches': dict(branches)
      } if (
          all(isinstance(p, str) for p in wadpaths) and
          branch in branches and
          isinstance(branches[branch], str)
        ):
        if args.c:
          print(f'{Path(configdir) / config}')
        else:
          print(f'odasrvpath={branches[branch]}')
          print(f'wadpaths={":".join(wadpaths)}')
          print(f'configpath={configdir}')
          print(f'config={Path(configdir) / config}')
          print(f'port={port}')
      case {
        'settings': {
          'odasrvpath': str(odasrvpath),
          'configdir': str(configdir),
          'wadpaths': list(wadpaths),
          'waddownloaddir': str(_)
        },
        'servers': {args.instance: {'config': str(config), 'port': int(port)}, **_other_servers}
      } if all(isinstance(p, str) for p in wadpaths):
        if args.c:
          print(f'{Path(configdir) / config}')
        else:
          print(f'odasrvpath={odasrvpath}')
          print(f'wadpaths={":".join(wadpaths)}')
          print(f'configpath={configdir}')
          print(f'config={Path(configdir) / config}')
          print(f'port={port}')
      case _:
        print("Error reading odasrvmgr.toml. Server instance likely missing from [servers].", file=sys.stderr)
        sys.exit(1)
  case 'validate':
    schema = {
      "type": "object",
      "properties": {
        "settings": {
          "type": "object",
          "properties": {
            "odasrvpath": { "type": "string" },
            "configdir": { "type": "string" },
            "wadpaths": {
              "type": "array",
              "items": { "type": "string" }
            },
            "waddownloaddir": { "type": "string" }
          },
          "required": [ "odasrvpath", "configdir", "wadpaths", "waddownloaddir" ],
          "additionalProperties": False
        },
        "servers": {
          "type": "object",
          "patternProperties": {
            "^[A-Za-z0-9_-]+$": {
              "type": "object",
              "properties": {
                "config": { "type": "string" },
                "port": {
                  "type": "integer",
                  "minimum": 1,
                  "maximum": 65535
                },
                "branch": { "type": "string" }
              },
              "required": [ "config", "port" ],
              "additionalProperties": False
            }
          },
          "additionalProperties": False
        },
        "branches": {
          "patternProperties": {
            "^[A-Za-z0-9_-]+$": { "type": "string" }
          }
        }
      },
      "required": [ "settings", "servers" ],
      "additionalProperties": False
    }

    try:
      validate(instance=data, schema=schema)
    except ValidationError as e:
      if not args.q:
        print(f"Validation error: {e.message}", file=sys.stderr)
      sys.exit(1)

    errormsg = None

    ports: list[int] = []
    for server in data['servers'].values():
      ports.append(server['port'])
    if len(ports) != len(set(ports)):
      errormsg = 'Duplicate ports found in odasrvmgr.toml'

    if errormsg:
      if not args.q:
        print(errormsg, file=sys.stderr)
      sys.exit(1)
    else:
      if not args.q:
        print('No errors found in odasrvmgr.toml')
      sys.exit(0)