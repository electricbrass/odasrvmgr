import os, sys, grp, argparse, tomllib, enum
from pathlib import Path
from hashlib import md5 # md5 because its whats odamex uses + listed on the doomwiki

DOWNLOAD_SITES = [
  'https://static.allfearthesentinel.com/wads/',
  'https://doomshack.org/wads/',
  'http://grandpachuck.org/files/wads/',
  'https://wads.doomleague.org/',
  'http://files.funcrusher.net/wads/',
  'https://doomshack.org/uploads/',
  'https://doom.dogsoft.net/getwad.php?search=',
  'https://doomshack.org/wadlist.php',
  'https://wads.firestick.games/',
  'https://euroboros.net/zandronum/wads/',
  'https://static.audrealms.org/wads/',
  'https://downloadbox.captainpollutiontv.de/DooM/WADSEEKER/'
]

class InvalidDownloadDirError(Exception):
  """waddownloaddir in odasrvmgr.toml is not a valid directory."""

def get_download_dir() -> Path:
  with open('/etc/odasrvmgr/odasrvmgr.toml', 'rb') as f:
    config = tomllib.load(f)
  
  try:
    path = config["settings"]["waddownloaddir"]
  except (KeyError, TypeError):
    raise InvalidDownloadDirError("waddownloaddir not found in odasrvmgr.toml or is not a valid string.")
  
  try:
    path = Path(path).resolve(strict=True)
  except (OSError):
    raise InvalidDownloadDirError(f"waddownloaddir '{path}' could not be found.")
  
  if not path.is_dir() or not path.exists():
    raise InvalidDownloadDirError(f"waddownloaddir '{path}' is not a valid directory.")
  
  if not os.access(path, os.R_OK):
    raise InvalidDownloadDirError(f"waddownloaddir '{path}' is not readable.")

  if not os.access(path, os.W_OK):
    raise InvalidDownloadDirError(f"waddownloaddir '{path}' is not writable.")

  return path

class WadDownloadResult(enum.Enum):
  SUCCESS = enum.auto()
  ALREADY_EXISTS = enum.auto()
  ERROR = enum.auto()

def download_from_wad_name(downloaddir: Path, wad: str) -> WadDownloadResult:
  if (downloaddir / wad).exists():
    return WadDownloadResult.ALREADY_EXISTS
  lockfile_path = downloaddir / 'wadfetch.lock'
  if not lockfile_path.exists():
    lockfile_path.touch()
    os.chmod(lockfile_path, 0o660)
    os.chown(lockfile_path, -1, grp.getgrnam('odasrvmgr').gr_gid)
  return WadDownloadResult.ERROR

def download_from_lockfile(downloaddir: Path) -> None:
  lockfile_path = downloaddir / 'wadfetch.lock'
  if not lockfile_path.exists():
    raise FileNotFoundError(f"Lockfile '{lockfile_path}' does not exist.")
  with open(downloaddir / 'wadfetch.lock', 'r') as f:
    for line in f:
      stripped = line.strip()
      if not stripped or stripped.startswith('#'):
        continue
      wadname, md5 = stripped.split() # Wanna throw in more error handling here if I distribute this

def main() -> int:
  try:
    downloaddir = get_download_dir()
  except InvalidDownloadDirError as e:
    print(f"Error: {e}", file=sys.stderr)
    return 1
  parser = argparse.ArgumentParser(
      prog='wadfetch',
      description='Download WAD files for odasrvmgr')
  parser.add_argument('wad', nargs='?', help='WAD name to download')
  args = parser.parse_args()
  if args.wad:
      match download_from_wad_name(downloaddir, args.wad):
        case WadDownloadResult.SUCCESS:
          print(f"Successfully downloaded {args.wad} to {downloaddir / args.wad}")
        case WadDownloadResult.ALREADY_EXISTS:
          print(f"{args.wad} already exists in {downloaddir}")
        case WadDownloadResult.ERROR:
          print(f"Error downloading {args.wad}.", file=sys.stderr)
          return 1
  else:
    try:
      download_from_lockfile(downloaddir)
    except FileNotFoundError as e:
      print(f"Error: {e}", file=sys.stderr)
      return 1
  return 0

if __name__ == '__main__':
  sys.exit(main())

__all__ = ['download_from_wad_name', 'download_from_lockfile', 'get_download_dir', 'InvalidDownloadDirError', 'WadDownloadResult']