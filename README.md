# odasrvmgr

This is a tool for managing multiple instances of odasrv with systemd that
I ended up creating for my own use to make it easier to set up and use.

# Installation

Make sure you have all necessary dependencies installed:

- tmux
- Python 3.11 or newer
- python3-jsonschema

Then just clone this repo and run the setup script:

```bash
git clone https://github.com/electricbrass/odasrvmgr.git
cd odasrvmgr
./setup.sh
```

# Configuring `odasrvmgr.toml`

After install, you can configure `odasrvmgr` with the TOML file found at `/etc/odasrvmgr.toml`.

## `[settings]`

- `odasrvpath`: The path to your odasrv executable. This may be removed in the future.
- `configdir`: The path to your odasrv config files.
- `wadpaths`: An array of paths containing wad files. At least one of these must be a directory
directly containing an IWAD, unless IWADs are present in one of odasrv's default search directories.
- `waddownloaddir`: The directory where `odasrvmgr fetch` downloads wads to,
and where the `doomfetch.lock` file is maintained to track downloaded wads.

## `[servers]`

Each entry in this section defines a server instance. The key specifies the name the instance will be
referred to in `odasrvmgr` commands. The values consist of tables with 2 properties: `config` and `port`.

- `config`: A path to the odasrv config that should be loaded by this instance on start and reload.
The path is relative to `configdir`.
- `port`: The UDP port that this instance should be bound to.

## `odasrvmgr validate`

Use this command after editing your `odasrvmgr.toml` to verify that your configuration is still valid.

## Example

```TOML
[settings]
odasrvpath = "/usr/local/bin/odasrv"
configdir = "/path/to/configs"
wadpaths = [
  "/path/to/wads",
  "/other/path/to/wads"
]
waddownloaddir = "/path/to/wads"

[servers]
server1 = { config = "example.cfg", port = 10666 }
server2 = { config = "anotherexample.cfg", port = 10667 }
```

When `odasrvmgr new server1` is used to create an instance named `server1`, that instance will use the
following settings:

- odasrv executable: `/usr/local/bin/odasrv`
- Config file: `/path/to/configs/example.cfg`
- WAD search paths: `/path/to/wads:/other/path/to/wads`
- UDP port: 10666

Using `odasrvmgr new` to create an instance that isn't defined in `odasrvmgr.toml` will result in an instance that fails to start.

# Updating odasrvmgr

To update, pull the latest changes from the repo and then inside the local copy of the repo,
run `./odasrvmgr update`. Hopefully I'll get around to improving the update process in the future.

