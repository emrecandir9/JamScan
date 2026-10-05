"""Run opt-in external API checks and print a credential-free JSON report."""

import argparse
import json
import os
from dataclasses import asdict
from datetime import UTC, datetime

import httpx

from scripts.discogs import validate_discogs
from scripts.itunes import validate_itunes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--provider", choices=("all", "discogs", "itunes"), default="all"
    )
    parser.add_argument("--query", default="Daft Punk Random Access Memories")
    parser.add_argument("--track-query", default="Daft Punk Get Lucky")
    parser.add_argument(
        "--country", default="FR", help="Two-letter iTunes storefront code"
    )
    args = parser.parse_args()
    if not args.query.strip() or not args.track_query.strip():
        parser.error("Search queries must not be blank")
    country = args.country.upper()
    if len(country) != 2 or not country.isascii() or not country.isalpha():
        parser.error("--country must be a two-letter storefront code")
    checks = []
    with httpx.Client() as client:
        if args.provider in ("all", "discogs"):
            checks.extend(
                validate_discogs(
                    client, os.environ.get("DISCOGS_TOKEN", ""), args.query
                )
            )
        if args.provider in ("all", "itunes"):
            checks.extend(validate_itunes(client, args.track_query, country))
    report = {
        "story": "S1-05",
        "checked_at": datetime.now(UTC).isoformat(),
        "provider": args.provider,
        "inputs": {
            "discogs_query": args.query,
            "itunes_query": args.track_query,
            "country": country,
        },
        "scope": "Discogs and iTunes previews; visual search excluded.",
        "checks": [asdict(check) for check in checks],
    }
    print(json.dumps(report, indent=2))
    return 0 if all(check.status == "passed" for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
