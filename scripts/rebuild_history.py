#!/usr/bin/env python3
import os
import json
import glob
import sys
import re
from datetime import datetime, timezone

BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")
CONVERSATIONS_DIR = os.path.expanduser("~/.gemini/antigravity/conversations")
KNOWLEDGE_DIR = ".agent/knowledge"
OUTPUT_FILE = "conversation_history.md"

def sanitize_filename(text):
    text = text.lower()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s]+', '-', text)
    return text[:50]

def get_conversation_data():
    convs = {}
    
    # Scan brain directories
    if not os.path.exists(BRAIN_DIR):
        print(f"⚠️ Brain directory not found: {BRAIN_DIR}")
        return {}

    for conv_id in os.listdir(BRAIN_DIR):
        path = os.path.join(BRAIN_DIR, conv_id)
        if not os.path.isdir(path):
            continue
            
        conv_data = {
            "id": conv_id,
            "summaries": [],
            "last_updated": None,
            "artifactsCount": 0
        }
        
        # Look for metadata files
        meta_files = glob.glob(os.path.join(path, "*.metadata.json"))
        for meta_file in meta_files:
            try:
                with open(meta_file, 'r') as f:
                    data = json.load(f)
                    summary = data.get("summary")
                    updated = data.get("updatedAt")
                    
                    if summary:
                        conv_data["summaries"].append(summary)
                    if updated:
                        dt = datetime.fromisoformat(updated.replace("Z", "+00:00"))
                        if not conv_data["last_updated"] or dt > conv_data["last_updated"]:
                            conv_data["last_updated"] = dt
            except Exception:
                continue
        
        conv_data["artifactsCount"] = len(os.listdir(path))
        
        if not conv_data["last_updated"]:
            conv_data["last_updated"] = datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc)
            
        convs[conv_id] = conv_data

    # Check for missing conversations from PB files
    if os.path.exists(CONVERSATIONS_DIR):
        for pb_file in os.listdir(CONVERSATIONS_DIR):
            if pb_file.endswith(".pb"):
                conv_id = pb_file[:-3]
                if conv_id not in convs:
                    full_pb_path = os.path.join(CONVERSATIONS_DIR, pb_file)
                    convs[conv_id] = {
                        "id": conv_id,
                        "summaries": ["(No brain logs found - raw conversation data only)"],
                        "last_updated": datetime.fromtimestamp(os.path.getmtime(full_pb_path), tz=timezone.utc),
                        "artifactsCount": 0,
                        "pb_only": True
                    }

    return convs

def generate_markdown(convs):
    sorted_convs = sorted(convs.values(), key=lambda x: x["last_updated"], reverse=True)
    
    lines = [
        "# Rebuilt Conversation History",
        f"\nGenerated on: {datetime.now(timezone.utc).isoformat()}\n",
        "| Last Updated | Conversation ID | Summary | Artifacts |",
        "| :--- | :--- | :--- | :--- |"
    ]
    
    for c in sorted_convs:
        date_str = c["last_updated"].strftime("%Y-%m-%d %H:%M")
        summary = " / ".join(list(set(c["summaries"]))) if c["summaries"] else "*(No summary available)*"
        if len(summary) > 150:
            summary = summary[:147] + "..."
        
        row = f"| {date_str} | `{c['id']}` | {summary} | {c['artifactsCount']} |"
        lines.append(row)
        
    return "\n".join(lines)

def distill_to_knowledge(convs):
    if not os.path.exists(KNOWLEDGE_DIR):
        os.makedirs(KNOWLEDGE_DIR)
        print(f"📁 Created directory: {KNOWLEDGE_DIR}")

    count = 0
    for c in convs.values():
        if not c["summaries"] or "No brain logs found" in c["summaries"][0]:
            continue
            
        date_prefix = c["last_updated"].strftime("%Y-%m-%d")
        main_summary = c["summaries"][0]
        safe_title = sanitize_filename(main_summary)
        
        filename = f"{date_prefix}-title={safe_title}.md"
        filepath = os.path.join(KNOWLEDGE_DIR, filename)
        
        content = f"# History: {main_summary}\n\n"
        content += f"- **Date**: {c['last_updated'].isoformat()}\n"
        content += f"- **Conversation ID**: `{c['id']}`\n"
        content += f"- **Brain Path**: `~/.gemini/antigravity/brain/{c['id']}`\n\n"
        content += "## Summaries Found\n"
        for s in set(c["summaries"]):
            content += f"- {s}\n"
            
        with open(filepath, 'w') as f:
            f.write(content)
        count += 1
        
    print(f"✨ Distilled {count} Knowledge Items to {KNOWLEDGE_DIR}")

if __name__ == "__main__":
    do_distill = "--distill" in sys.argv
    
    print("🔍 Scanning conversation data...")
    data = get_conversation_data()
    print(f"✅ Found {len(data)} conversations.")
    
    md = generate_markdown(data)
    with open(OUTPUT_FILE, 'w') as f:
        f.write(md)
    print(f"📄 History written to {OUTPUT_FILE}")
    
    if do_distill:
        distill_to_knowledge(data)
