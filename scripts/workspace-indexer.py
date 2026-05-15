#!/usr/bin/env python3
import os
import json
import requests
import sys

# ATLAS Infrastructure AI - Semantic Indexer V1.0
# Indexes the Obsidian vault using Ollama embeddings.

VAULT_PATH = "/home/martin/Documents/Notes"
INDEX_PATH = "/home/martin/Develop/github.com/kleinbem/nix/scratch/semantic_index.json"
OLLAMA_URL = "http://localhost:11434/api/embeddings"
MODEL = "nomic-embed-text"

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
