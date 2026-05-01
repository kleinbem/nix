#!/usr/bin/env python3
import time
import json
import os
import sys
import requests
from authlib.jose import jwt

# Identity Exchanger for GitHub Apps
# Trades a Private Key for a 1-hour Installation Access Token

def generate_token():
    app_id = os.environ.get("GITHUB_APP_ID")
    install_id = os.environ.get("GITHUB_INSTALL_ID")
    private_key = os.environ.get("GITHUB_PRIVATE_KEY")

    if not all([app_id, install_id, private_key]):
        print("Error: Missing GITHUB_APP_ID, GITHUB_INSTALL_ID, or GITHUB_PRIVATE_KEY", file=sys.stderr)
        sys.exit(1)

    # 1. Create JWT
    now = int(time.time())
    payload = {
        "iat": now - 60,
        "exp": now + (10 * 60),
        "iss": app_id
    }
    
    # Sign JWT with the private key
    header = {"alg": "RS256"}
    token = jwt.encode(header, payload, private_key).decode("utf-8")

    # 2. Request Installation Access Token
    url = f"https://api.github.com/app/installations/{install_id}/access_tokens"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json"
    }
    
    response = requests.post(url, headers=headers)
    if response.status_code != 201:
        print(f"Error: Failed to get token ({response.status_code}): {response.text}", file=sys.stderr)
        sys.exit(1)

    return response.json()["token"]

if __name__ == "__main__":
    try:
        print(generate_token())
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)
