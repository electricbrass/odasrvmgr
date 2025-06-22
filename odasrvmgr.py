#!/usr/bin/env python3
import sys, argparse, re, subprocess, enum
from argparse import Namespace
from pystemd.systemd1 import Unit

class InstanceCmd(enum.Enum):
  START = enum.auto()
  STOP = enum.auto()
  RESTART = enum.auto()
  RELOAD = enum.auto()

def tail(logfile: str) -> None:
  with subprocess.Popen(
    ["tail", "-F", f'/opt/odasrv/logs/{logfile}.log'],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
  ) as proc:
    if proc.stdout is None:
      raise RuntimeError("Failed to start subprocess or stdout is None")
    for line in proc.stdout:
      print(line, end='')

def list_instances(_: None) -> None:
  unit = Unit('odasrv.target')
  unit.load()
  print(f'{"Servers":<15} {"Status":<10}')
  print(f'{"-------":<15} {"------":<10}')
  for instance in unit.Unit.Wants:
    active = unit.Unit.ActiveState == b'active'
    name = re.sub(r'odasrv@(.*)\.service', r'\1', instance.decode('utf-8'))
    print(f'{name:<15} {"running" if active else "stopped":<10}')

def instance_cmds(args: Namespace, cmd: InstanceCmd) -> None:
  unit = Unit(f'odasrv@{args.instance}.service')
  unit.load()
  match cmd:
    case InstanceCmd.START:
      unit.Unit.Start(b'replace')
    case InstanceCmd.STOP:
      unit.Unit.Stop(b'replace')
    case InstanceCmd.RESTART:
      unit.Unit.Restart(b'replace')
    case InstanceCmd.RELOAD:
      unit.Unit.Reload(b'replace')

def enable_instance(args: Namespace) -> None:
  reg = r'^([a-zA-Z0-9_-]+)$'
  if not re.match(reg, args.instance):
    print(f'Invalid instance name: {args.instance}')
    sys.exit(1) # TODO: dont use sys.exit
  subprocess.run(['systemctl', 'enable', f'odasrv@{args.instance}.service'])

def disable_instance(args: Namespace) -> None:
  subprocess.run(['systemctl', 'disable', f'odasrv@{args.instance}.service'])

def main() -> int:
  parser = argparse.ArgumentParser(
    prog='odasrvmgr',
    description='Odamex server instance manager')
  subparsers = parser.add_subparsers()
  list_parser = subparsers.add_parser(
    'list',
    help='List all odasrv instances')
  list_parser.set_defaults(func=list_instances)
  start_parser = subparsers.add_parser(
    'start',
    help='Start an odasrv instance')
  start_parser.add_argument(
    'instance',
    help='The name of the odasrv instance to start')
  start_parser.set_defaults(func=instance_cmds, cmd=InstanceCmd.START)
  stop_parser = subparsers.add_parser(
    'stop',
    help='Stop an odasrv instance')
  stop_parser.add_argument(
    'instance',
    help='The name of the odasrv instance to stop')
  stop_parser.set_defaults(func=instance_cmds, cmd=InstanceCmd.STOP)
  restart_parser = subparsers.add_parser(
    'restart',
    help='Restart an odasrv instance')
  restart_parser.add_argument(
    'instance',
    help='The name of the odasrv instance to restart')
  restart_parser.set_defaults(func=instance_cmds, cmd=InstanceCmd.RESTART)
  reload_parser = subparsers.add_parser(
    'reload',
    help='Reload an odasrv instance')
  reload_parser.add_argument(
    'instance',
    help='The name of the odasrv instance to reload')
  reload_parser.set_defaults(func=instance_cmds, cmd=InstanceCmd.RELOAD)
  console_parser = subparsers.add_parser(
    'console',
    help='Open a console to an odasrv instance')
  add_parser = subparsers.add_parser(
    'new',
    help='Create a new odasrv instance')
  add_parser.add_argument(
    'instance',
    help='The name of the odasrv instance to create')
  add_parser.set_defaults(func=enable_instance)
  args = parser.parse_args()
  if hasattr(args, 'cmd'):
    args.func(args, args.cmd)
  else:
    args.func(args)
  return 0

if __name__ == '__main__':
  sys.exit(main())