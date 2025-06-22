import os, sys, tomllib, argparse

parser = argparse.ArgumentParser()
parser.add_argument("instance")
parser.add_argument('-c', action='store_true')
args = parser.parse_args()

with open('/etc/odasrvmgr/odasrvmgr.toml', 'rb') as f:
  data = tomllib.load(f)

match data:
  case {
    'settings': {
      'odasrvpath': str(odasrvpath),
      'configdir': str(configdir),
      'wadpaths': list(wadpaths),
      'waddownloaddir': str(waddownloaddir)
    },
    'servers': dict(servers)
  } if all(isinstance(p, str) for p in wadpaths):
    match servers[args.instance]:
      case {'config': str(config), 'port': int(port)}:
        if args.c:
          print(f'{configdir + "/" + config}')
        else:
          print(f'odasrvpath={odasrvpath}')
          print(f'wadpaths={":".join(wadpaths)}')
          print(f'config={configdir + "/" + config}')
          print(f'port={port}')
      case _:
        sys.exit(2)
  case _:
    sys.exit(1)