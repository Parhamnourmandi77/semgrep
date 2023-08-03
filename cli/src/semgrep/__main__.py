#!/usr/bin/env python3
import sys

from semgrep.cli import cli


def main() -> int:
    cli(prog_name="semgrep")
    return 0


if __name__ == "__main__":
    sys.exit(main())
