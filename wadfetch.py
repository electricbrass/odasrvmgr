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

import os, sys, grp, argparse, tomllib, hashlib, random, enum
from pathlib import Path
from typing import Iterator
from urllib import request, error
from contextlib import contextmanager

DOWNLOAD_SITES = [
  'https://static.allfearthesentinel.com/wads/',
  'https://doomshack.org/wads/',
  'http://grandpachuck.org/files/wads/',
  'https://wads.doomleague.org/',
  'http://files.funcrusher.net/wads/',
  'https://doomshack.org/uploads/',
  'https://doom.dogsoft.net/getwad.php?search=',
  'https://doomshack.org/wadlist.php/',
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
    raise InvalidDownloadDirError('waddownloaddir not found in odasrvmgr.toml or is not a valid string.')
  
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

@contextmanager
def hidden_cursor() -> Iterator[None]:
  print('\033[?25l', end='', flush=True)
  try:
    yield
  finally:
    print('\033[?25h', end='', flush=True)

def sizeof_fmt(num: int | float, suffix: str = "B") -> str:
  for unit in ("", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"):
      if abs(num) < 1024.0:
          return f"{num:3.1f} {unit}{suffix}"
      num /= 1024.0
  return f"{num:.1f} Yi{suffix}"

def urlretrieve_with_progress(url: str, filename: Path) -> None:
  def hook(block_num: int, block_size: int, total_size: int) -> None:
    if total_size > 0:
      downloaded = block_num * block_size
      percent = float(downloaded) / total_size
      percent = round(percent * 100, 1)
      if percent > 100: percent = 100
      print(f'{sizeof_fmt(downloaded)} / {sizeof_fmt(total_size)} {percent}%'.ljust(32), end='\r', flush=True)
  request.urlretrieve(url, filename, reporthook=hook)
  print()

def download_from_wad_name(downloaddir: Path, wad: str) -> WadDownloadResult:
  # need better handling of case, but idk what's best since this is expecting names typed by hand
  wad = wad.lower().strip()
  if not wad.endswith('.wad'):
    wad += '.wad'
  if (downloaddir / wad).exists():
    return WadDownloadResult.ALREADY_EXISTS
  lockfile_path = downloaddir / 'wadfetch.lock'
  if not lockfile_path.exists():
    lockfile_path.touch()
    os.chmod(lockfile_path, 0o660)
    os.chown(lockfile_path, -1, grp.getgrnam('odasrvmgr').gr_gid)
  for url in random.sample(DOWNLOAD_SITES, len(DOWNLOAD_SITES)):
    print(f"Attempting to download {wad} from {url}")
    try:
      urlretrieve_with_progress(url + wad, downloaddir / wad)
      break
    except error.HTTPError as e:
      print(f"HTTP error: {e.code}, trying next site.")
      continue
    except (error.URLError, error.ContentTooShortError) as e:
      print(f"Error: {e}, trying next site.")
      continue
  else:
    return WadDownloadResult.ERROR
  with open(lockfile_path, 'a') as lockfile, open((downloaddir / wad), 'rb') as wadfile:
    lockfile.write(f"{wad} {hashlib.file_digest(wadfile, 'md5').hexdigest()}\n")
  return WadDownloadResult.SUCCESS

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
      wadpath = downloaddir / wadname
      if wadpath.exists():
        # see how slow hashing them is as my wad directory grows, if its too slow, we can just worry about hashing on download
        with open(wadpath, 'rb') as wadfile:
          # use md5 because its what odamex uses and its often listed on doomwiki
          if hashlib.file_digest(wadfile, 'md5').hexdigest() == md5:
            print(f'[Skipping] {wadname} already exists in download directory.')
          else:
            print(f'[Skipping] Hash Mismatch: {wadname} found in download directory but hash does not match.')
        continue
      for url in random.sample(DOWNLOAD_SITES, len(DOWNLOAD_SITES)):
        print(f"Attempting to download {wadname} from {url}")
        try:
          tempwadpath = downloaddir / (wadname + '.tmp')
          urlretrieve_with_progress(url + wadname, tempwadpath)
          with open(tempwadpath, 'rb') as tempwadfile:
            if hashlib.file_digest(tempwadfile, 'md5').hexdigest() != md5:
              print(f"Hash mismatch for {wadname}, deleting temporary file.")
              os.remove(tempwadpath)
              continue
            else:
              os.rename(tempwadpath, wadpath)
              break
        except error.HTTPError as e:
          print(f"HTTP error: {e.code}, trying next site.")
          continue
        except (error.URLError, error.ContentTooShortError) as e:
          print(f"Error: {e}, trying next site.")
          continue

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
    with hidden_cursor():
      match download_from_wad_name(downloaddir, args.wad):
        case WadDownloadResult.SUCCESS:
          print(f"Successfully downloaded {args.wad} to {downloaddir / args.wad}")
        case WadDownloadResult.ALREADY_EXISTS:
          # should this return non-zero?
          print(f"{args.wad} already exists in {downloaddir}")
        case WadDownloadResult.ERROR:
          print(f"Error downloading {args.wad}.", file=sys.stderr)
          return 1
  else:
    try:
      with hidden_cursor():
        download_from_lockfile(downloaddir)
    except FileNotFoundError as e:
      print(f"Error: {e}", file=sys.stderr)
      return 1
  return 0

if __name__ == '__main__':
  sys.exit(main())

__all__ = ['download_from_wad_name', 'download_from_lockfile', 'get_download_dir', 'InvalidDownloadDirError', 'WadDownloadResult']