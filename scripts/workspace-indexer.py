#!/usr/bin/env python3
import os
import json
import requests
import sys

# ATLAS Infrastructure AI - Semantic Indexer V1.0
# Indexes the Obsidian vault using Ollama embeddings.

VAULT_PATH = "/home/martin/Documents/Notes"
INDEX_PATH = "/home/martin/Develop/github.com/kleinbem/nix/scratch/semantic_index.json"
MODEL = "nomic-embed-text"

def get_ollama_url():
    """Find the active Ollama API endpoint."""
    import subprocess
    # Default fallback endpoints
    endpoints = [
        "http://localhost:11434/api/embeddings",
        "http://10.85.46.104:11434/api/embeddings",
        "http://10.85.46.126:11434/api/embeddings"
    ]
    
    # Try to extract the Orin IP from the inventory if possible
    try:
        inv_path = "/home/martin/Develop/github.com/kleinbem/nix/nix-config/inventory.nix"
        if os.path.exists(inv_path):
            result = subprocess.run(["nix", "eval", "--json", "--file", inv_path], capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                inv = json.loads(result.stdout)
                orin_ip = inv.get("network", {}).get("nodes", {}).get("ollama-orin", {}).get("ip")
                if orin_ip and f"http://{orin_ip}:11434/api/embeddings" not in endpoints:
                    endpoints.insert(1, f"http://{orin_ip}:11434/api/embeddings")
    except Exception:
        pass

    for url in endpoints:
        try:
            # Quick check if endpoint is online
            base_url = url.rsplit('/', 1)[0]
            resp = requests.get(f"{base_url}/tags", timeout=0.5)
            if resp.status_code == 200:
                return url
        except Exception:
            pass
            
    return "http://localhost:11434/api/embeddings" # Default fallback

OLLAMA_URL = get_ollama_url()
print(f"🤖 Using Ollama embedding endpoint: {OLLAMA_URL}")

def get_embedding(text):
    try:
        response = requests.post(OLLAMA_URL, json={"model": MODEL, "prompt": text}, timeout=5)
        if response.status_code == 200:
            return response.json().get("embedding")
    except Exception:
        pass
    return None


def index_vault():
    print(f"🔍 Indexing vault: {VAULT_PATH}")
    index = []
    
    if not os.path.exists(VAULT_PATH):
        print(f"❌ Vault path not found: {VAULT_PATH}")
        return

    for root, _, files in os.walk(VAULT_PATH):
        for file in files:
            if file.endswith(".md"):
                path = os.path.join(root, file)
                with open(path, "r") as f:
                    content = f.read()
                
                print(f"  - Processing {file}...")
                embedding = get_embedding(content[:1000]) # Embed first 1000 chars
                
                index.append({
                    "title": file,
                    "path": path,
                    "excerpt": content[:200],
                    "embedding": embedding
                })
    
    os.makedirs(os.path.dirname(INDEX_PATH), exist_ok=True)
    with open(INDEX_PATH, "w") as f:
        json.dump(index, f)
    print(f"✅ Index saved to {INDEX_PATH} ({len(index)} documents)")

if __name__ == "__main__":
    index_vault()
