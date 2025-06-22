import sys, tomllib, argparse

parser = argparse.ArgumentParser()
subparsers = parser.add_argument("instance")
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
        print(f'odasrvpath={odasrvpath}')
        print(f'wadpaths={":".join(wadpaths)}')
        print(f'config={configdir + "/" + config}')
        print(f'port={port}')
      case _:
        sys.exit(2)
  case _:
    sys.exit(1)