#!/usr/bin/env python3
"""Resume the long-lived GUI sandboxes and enforce no expiration."""

import json
import time
import urllib.error
import urllib.request
from pathlib import Path


SANDBOX_IDS = (
    "01a0cf25-ddab-7d22-bc4d-7e7059b46bae",  # zzs_cclab / cclab_pku
    "01a0cf25-df65-7e32-8788-53a17482b77a",  # zzs_ccops / ccops_pku
    "01a0cf25-dfd5-7eb1-bcdb-b1101016e790",  # ytj_ccops / ccops_pku
)
CONTEXT = {
    "envVars": {
        "HOME": "/home/ubuntu",
        "USER": "ubuntu",
        "SHELL": "/bin/bash",
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin",
        "DISPLAY": ":1",
        "XAUTHORITY": "/home/ubuntu/.Xauthority",
        "XDG_RUNTIME_DIR": "/run/user/1000",
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
        "XDG_SESSION_TYPE": "x11",
        "XDG_CURRENT_DESKTOP": "XFCE",
    },
    "defaultUser": "ubuntu",
    "defaultWorkdir": "/home/ubuntu",
}


def load_credentials():
    values = {}
    for line in Path("/home/thezzisu/.config/aenv/credentials").read_text().splitlines():
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"')
    return values["url"].rstrip("/"), values["api_key"]


def main():
    base, api_key = load_credentials()
    headers = {"X-API-Key": api_key, "Content-Type": "application/json"}

    def request(path, method="GET", body=None, extra_headers=None):
        request_headers = dict(headers)
        request_headers.update(extra_headers or {})
        request = urllib.request.Request(
            base + path, headers=request_headers, method=method
        )
        if body is not None:
            request.data = json.dumps(body).encode()
        with urllib.request.urlopen(request, timeout=180) as response:
            data = response.read()
            return json.loads(data) if data else {}

    for attempt in range(60):
        try:
            for sandbox_id in SANDBOX_IDS:
                detail = request(f"/sandboxes/{sandbox_id}")
                if detail.get("state") == "paused":
                    request(f"/sandboxes/{sandbox_id}/resume", "POST", {"timeout": 0})
                    detail = request(f"/sandboxes/{sandbox_id}")
                if detail.get("state") != "running":
                    raise RuntimeError(
                        f"sandbox {sandbox_id} is {detail.get('state')}, not running"
                    )

                # timeout=0 is the explicit API spelling for no expiration.
                request(f"/sandboxes/{sandbox_id}/timeout", "POST", {"timeout": 0})
                detail = request(f"/sandboxes/{sandbox_id}")
                token = detail.get("envdAccessToken")
                if not token:
                    raise RuntimeError(f"sandbox {sandbox_id} has no envd token")
                payload = dict(CONTEXT, accessToken=token)
                request(
                    "/proxy/init",
                    "POST",
                    payload,
                    {
                        "x-agentenv-sandbox-id": sandbox_id,
                        "x-agentenv-target-port": "49983",
                        "X-Access-Token": token,
                    },
                )
            return
        except (OSError, RuntimeError, urllib.error.URLError):
            if attempt == 59:
                raise
            time.sleep(2)


if __name__ == "__main__":
    main()
