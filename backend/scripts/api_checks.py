"""Shared transport checks for the opt-in API validation tools."""

from dataclasses import dataclass, field
from time import perf_counter
from typing import Any, Literal

import httpx

USER_AGENT = "JamSCAN/0.1 (+https://github.com/emrecandir9/JamScan)"
RATE_HEADERS = (
    "x-discogs-ratelimit",
    "x-discogs-ratelimit-used",
    "x-discogs-ratelimit-remaining",
    "retry-after",
)


@dataclass
class Check:
    name: str
    status: Literal["passed", "failed", "blocked", "inconclusive"]
    detail: str
    http_status: int | None = None
    elapsed_ms: int | None = None
    rate_limits: dict[str, int] = field(default_factory=dict)
    observations: dict[str, Any] = field(default_factory=dict)


def request_json(
    client: httpx.Client,
    checks: list[Check],
    name: str,
    url: str,
    token: str = "",
    params: dict[str, str | int] | None = None,
) -> tuple[Check, dict[str, Any] | None]:
    """Record transport evidence without storing bodies, URLs, or credentials."""
    check = Check(name, "failed", "Request did not complete.")
    checks.append(check)
    started = perf_counter()
    try:
        response = client.get(
            url,
            params=params,
            headers={
                **({"Authorization": f"Discogs token={token}"} if token else {}),
                "User-Agent": USER_AGENT,
                "Accept": "application/json",
            },
            timeout=15,
            follow_redirects=False,
        )
    except httpx.TimeoutException:
        check.detail = "Request timed out; no automatic retry was attempted."
        return check, None
    except httpx.RequestError:
        check.detail = "Network request failed; check connectivity and TLS settings."
        return check, None
    finally:
        check.elapsed_ms = round((perf_counter() - started) * 1000)

    check.http_status = response.status_code
    for header in RATE_HEADERS:
        value = response.headers.get(header, "")
        if value.isascii() and value.isdecimal() and len(value) <= 10:
            check.rate_limits[header] = int(value)
    if response.status_code != 200:
        check.detail = {
            401: "Authentication rejected; check provider credentials.",
            403: "Access forbidden; check account permissions and provider access.",
            429: "Rate limited; respect Retry-After before rerunning.",
        }.get(response.status_code, "Unexpected HTTP status; see http_status.")
        return check, None
    try:
        payload = response.json()
    except ValueError:
        check.detail = "Response was not valid JSON."
        return check, None
    if not isinstance(payload, dict):
        check.detail = "Expected a JSON object."
        return check, None
    check.detail = "JSON received; response contract has not passed yet."
    return check, payload


def positive_integer(value: Any) -> bool:
    return type(value) is int and value > 0
