#!/usr/bin/env python3
import sys, argparse
from argparse import Namespace
from pystemd.systemd1 import Unit, Manager

def list_instances(_: None) -> None:
    unit = Unit('odasrv.target')
    unit.load()
    print(unit.Unit.Wants)
    unit = Unit('odasrv@friends.service')
    unit.load()
    print(unit.Unit.WantedBy)

def start_instance(args: Namespace) -> None:
    unit = Unit(f'odasrv@{args.instance}.service')
    unit.load()
    unit.Unit.Start(b'replace')

def stop_instance(args: Namespace) -> None:
    unit = Unit(f'odasrv@{args.instance}.service')
    unit.load()
    unit.Unit.Stop(b'replace')

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
    start_parser.set_defaults(func=start_instance)
    stop_parser = subparsers.add_parser(
        'stop',
        help='Stop an odasrv instance')
    stop_parser.add_argument(
        'instance',
        help='The name of the odasrv instance to start')
    stop_parser.set_defaults(func=stop_instance)
    restart_parser = subparsers.add_parser(
        'restart',
        help='Restart an odasrv instance')
    reload_parser = subparsers.add_parser(
        'reload',
        help='Reload an odasrv instance')
    console_parser = subparsers.add_parser(
        'console',
        help='Open a console to an odasrv instance')
    args = parser.parse_args()
    args.func(args)
    return 0

if __name__ == '__main__':
    sys.exit(main())