import os
import requests
from .core import mcp, PAPERLESS_TOKEN_PATH
from .inventory import _get_inventory_cached


def _get_paperless_url():
    inv = _get_inventory_cached()
    try:
        node = inv.get("network", {}).get("nodes", {}).get("paperless", {})
        ip = node.get("ip", "10.85.47.131")
        port = node.get("port", 28981)
        return f"http://{ip}:{port}"
    except Exception:
        return "http://10.85.47.131:28981"


def _get_paperless_headers():
    """Helper to load Paperless API token."""
    if not os.path.exists(PAPERLESS_TOKEN_PATH):
        return None
    try:
        with open(PAPERLESS_TOKEN_PATH, "r") as f:
            token = f.read().strip()
        return {"Authorization": f"Token {token}"}
    except Exception:
        return None


@mcp.tool()
def search_paperless(query: str):
    """Search for documents in Paperless-ngx matching a query."""
    headers = _get_paperless_headers()
    if not headers:
        return "Error: Paperless token not found. Add it to nix-secrets/paperless_token.txt"

    try:
        paperless_url = _get_paperless_url()
        resp = requests.get(
            f"{paperless_url}/api/documents/?query={query}", headers=headers, timeout=5
        )
        if resp.status_code == 200:
            results = resp.json().get("results", [])
            return [
                {"id": d["id"], "title": d["title"], "created": d["created"]}
                for d in results[:10]
            ]
        return f"Error: Paperless API returned {resp.status_code}"
    except Exception as e:
        return str(e)


@mcp.tool()
def get_paperless_document(doc_id: int):
    """Get the full details and OCR text content of a Paperless document."""
    headers = _get_paperless_headers()
    if not headers:
        return "Error: Paperless token not found."

    try:
        paperless_url = _get_paperless_url()
        resp = requests.get(
            f"{paperless_url}/api/documents/{doc_id}/", headers=headers, timeout=5
        )
        if resp.status_code != 200:
            return f"Error: Could not find document {doc_id}"
        doc = resp.json()

        return {
            "title": doc.get("title"),
            "content": doc.get("content", "No text content available."),
            "date": doc.get("created"),
            "tags": doc.get("tags"),
            "correspondent": doc.get("correspondent"),
        }
    except Exception as e:
        return str(e)
