import os
import json
import subprocess
import requests
from datetime import datetime
from .core import mcp, DEFAULT_FLAKE_PATH, KNOWLEDGE_DIR
from .ai_services import _get_ai_base_url


@mcp.tool()
def distill_knowledge(
    title: str, summary: str, context: str, status: str = "active", tags: list = []
):
    """
    Create a new Knowledge Item (KI) in the workspace.
    Used to 'remember' architectural decisions, bug fixes, or complex configurations.
    Status can be: active, experimental, deprecated, or obsolete.
    """
    try:
        os.makedirs(KNOWLEDGE_DIR, exist_ok=True)
        filename = title.lower().replace(" ", "_").replace("/", "_") + ".md"
        filepath = os.path.join(KNOWLEDGE_DIR, filename)

        content = f"""# {title}
*Created: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}*
*Status: {status}*

## Summary
{summary}

## Context / Implementation
{context}

## Tags
{", ".join(tags)}
"""
        with open(filepath, "w") as f:
            f.write(content)

        # Link to obsidian if the script exists
        linker = os.path.join(DEFAULT_FLAKE_PATH, "tools/link-docs-to-obsidian.sh")
        if os.path.exists(linker):
            subprocess.run([linker], capture_output=True)

        return f"Knowledge Item created: {filepath}"
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def semantic_search(query: str):
    """
    Search the Obsidian vault using semantic similarity (embeddings).
    If Ollama is online, it uses vector math to find the closest matches.
    """
    try:
        index_path = os.path.join(DEFAULT_FLAKE_PATH, "scratch/semantic_index.json")
        if not os.path.exists(index_path):
            return "Error: Semantic index not found. Run reindex_vault first."

        with open(index_path, "r") as f:
            index = json.load(f)

        # Try to get query embedding
        query_embedding = None
        ai_info = _get_ai_base_url()
        if ai_info:
            base_url = ai_info["url"]
            engine_type = ai_info["type"]
            try:
                if engine_type == "ollama":
                    resp = requests.post(
                        f"{base_url}/api/embeddings",
                        json={"model": "nomic-embed-text", "prompt": query},
                        timeout=3,
                    )
                else:  # llama-cpp
                    resp = requests.post(
                        f"{base_url}/embedding", json={"content": query}, timeout=3
                    )

                if resp.status_code == 200:
                    # Ollama returns 'embedding', llama.cpp returns 'embedding' inside a list or directly
                    data = resp.json()
                    query_embedding = data.get("embedding")
            except Exception:
                pass

        def dot_product(v1, v2):
            return sum(x * y for x, y in zip(v1, v2))

        def magnitude(v):
            return sum(x * x for x in v) ** 0.5

        def cosine_similarity(v1, v2):
            if not v1 or not v2:
                return 0
            m1, m2 = magnitude(v1), magnitude(v2)
            if m1 == 0 or m2 == 0:
                return 0
            return dot_product(v1, v2) / (m1 * m2)

        results = []
        for doc in index:
            score = 0
            if query_embedding and doc.get("embedding"):
                score = cosine_similarity(query_embedding, doc["embedding"])
            else:
                # Fallback to simple keyword overlap if no embeddings
                if (
                    query.lower() in doc["title"].lower()
                    or query.lower() in doc["excerpt"].lower()
                ):
                    score = 0.5  # Default score for keyword match

            if score > 0.1:
                results.append(
                    {
                        "title": doc["title"],
                        "path": doc["path"],
                        "excerpt": doc["excerpt"],
                        "score": round(score, 3),
                    }
                )

        # Sort by score
        results.sort(key=lambda x: x["score"], reverse=True)
        return results[:5] if results else "No matches found."
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def reindex_vault():
    """
    Run the semantic indexer to refresh the vault index.
    """
    try:
        cmd = [
            "python3",
            os.path.join(DEFAULT_FLAKE_PATH, "tools/workspace-indexer.py"),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return {"stdout": result.stdout, "stderr": result.stderr}
    except Exception as e:
        return {"error": str(e)}
