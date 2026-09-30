#!/usr/bin/env python3
"""Fail closed for the retired, unevaluated standalone adapter entry point."""

import sys


def main() -> int:
    print(
        "Recitation analysis unavailable: this legacy adapter did not run "
        "inference. Use the authenticated recitation API instead.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
