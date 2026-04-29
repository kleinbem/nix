#!/usr/bin/env python3
import os
import json
import glob
import sys
import re
import shutil
from datetime import datetime, timezone

BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")
CONVERSATIONS_DIR = os.path.expanduser("~/.gemini/antigravity/conversations")
IMPLICIT_DIR = os.path.expanduser("~/.gemini/antigravity/implicit")
KNOWLEDGE_DIR = ".agent/knowledge"
OUTPUT_FILE = "conversation_history.md"

def sanitize_filename(text):
    text = text.lower()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s]+', '-', text)
    return text[:50]

def get_conversation_data():
    convs = {}
    
    # 1. Scan brain directories (Primary source of summaries)
    if os.path.exists(BRAIN_DIR):
        for conv_id in os.listdir(BRAIN_DIR):
            path = os.path.join(BRAIN_DIR, conv_id)
            if not os.path.isdir(path):
                continue
                
            conv_data = {
                "id": conv_id,
                "summaries": [],
                "last_updated": datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc),
                "artifactsCount": 0,
                "sources": ["brain"]
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
                            if dt > conv_data["last_updated"]:
                                conv_data["last_updated"] = dt
                except Exception:
                    continue
            
            # Check for overview.txt
            overview_path = os.path.join(path, ".system_generated", "logs", "overview.txt")
            if os.path.exists(overview_path):
                mtime = datetime.fromtimestamp(os.path.getmtime(overview_path), tz=timezone.utc)
                if mtime > conv_data["last_updated"]:
                    conv_data["last_updated"] = mtime
                
                if not conv_data["summaries"]:
                    try:
                        with open(overview_path, 'r') as f:
                            first_line = f.readline().strip()
                            if first_line:
                                first_line = re.sub(r'^USER: ', '', first_line)
                                conv_data["summaries"].append(first_line)
                    except Exception:
                        pass

            conv_data["artifactsCount"] = len([f for f in os.listdir(path) if not f.startswith('.')])
            convs[conv_id] = conv_data

    # 2. Merge with Conversations & Implicit folders
    for folder, label in [(CONVERSATIONS_DIR, "conversations"), (IMPLICIT_DIR, "implicit")]:
        if os.path.exists(folder):
            for pb_file in os.listdir(folder):
                if pb_file.endswith(".pb"):
                    conv_id = pb_file[:-3]
                    full_pb_path = os.path.join(folder, pb_file)
                    pb_mtime = datetime.fromtimestamp(os.path.getmtime(full_pb_path), tz=timezone.utc)
                    
                    if conv_id in convs:
                        convs[conv_id]["sources"].append(label)
                        if pb_mtime > convs[conv_id]["last_updated"]:
                            convs[conv_id]["last_updated"] = pb_mtime
                    else:
                        convs[conv_id] = {
                            "id": conv_id,
                            "summaries": ["*(Raw session data)*"],
                            "last_updated": pb_mtime,
                            "artifactsCount": 0,
                            "sources": [label]
                        }

    return convs

def sync_missing_to_app(convs):
    """Restore implicit sessions to the main conversation folder to help the UI see them."""
    if not os.path.exists(CONVERSATIONS_DIR):
        return 0
        
    count = 0
    for conv_id, data in convs.items():
        if "implicit" in data["sources"] and "conversations" not in data["sources"]:
            src = os.path.join(IMPLICIT_DIR, f"{conv_id}.pb")
            dst = os.path.join(CONVERSATIONS_DIR, f"{conv_id}.pb")
            if os.path.exists(src) and not os.path.exists(dst):
                try:
                    shutil.copy2(src, dst)
                    count += 1
                except Exception as e:
                    print(f"❌ Error syncing {conv_id}: {e}")
    return count

def generate_markdown(convs):
    sorted_convs = sorted(convs.values(), key=lambda x: x["last_updated"], reverse=True)
    
    lines = [
        "# Rebuilt Conversation History",
        f"\nGenerated on: {datetime.now(timezone.utc).isoformat()}\n",
        "| Last Updated | ID | Summary | Sources | Artifacts |",
        "| :--- | :--- | :--- | :--- | :--- |"
    ]
    
    for c in sorted_convs:
        date_str = c["last_updated"].strftime("%Y-%m-%d %H:%M")
        summary = " / ".join(list(set(c["summaries"]))) if c["summaries"] else "*(No summary)*"
        if len(summary) > 100: summary = summary[:97] + "..."
        sources = ", ".join(c["sources"])
        
        row = f"| {date_str} | `{c['id'][:8]}...` | {summary} | {sources} | {c['artifactsCount']} |"
        lines.append(row)
        
    return "\n".join(lines)

def distill_to_knowledge(convs):
    if not os.path.exists(KNOWLEDGE_DIR):
        os.makedirs(KNOWLEDGE_DIR)

    count = 0
    for c in convs.values():
        if not c["summaries"] or "Raw session data" in c["summaries"][0]:
            continue
            
        date_prefix = c["last_updated"].strftime("%Y-%m-%d")
        safe_title = sanitize_filename(c["summaries"][0])
        filepath = os.path.join(KNOWLEDGE_DIR, f"{date_prefix}-title={safe_title}.md")
        
        content = f"# History: {c['summaries'][0]}\n\n"
        content += f"- **Date**: {c['last_updated'].isoformat()}\n"
        content += f"- **ID**: `{c['id']}`\n"
        content += f"- **Sources**: {', '.join(c['sources'])}\n\n"
        content += "## Summaries Found\n"
        for s in set(c["summaries"]):
            content += f"- {s}\n"
            
        with open(filepath, 'w') as f:
            f.write(content)
        count += 1
    print(f"✨ Distilled {count} Knowledge Items.")

if __name__ == "__main__":
    do_distill = "--distill" in sys.argv
    do_sync = "--sync" in sys.argv
    
    print("🔍 Scanning all Antigravity directories...")
    data = get_conversation_data()
    print(f"✅ Found {len(data)} unique conversations.")
    
    if do_sync:
        synced = sync_missing_to_app(data)
        if synced > 0:
            print(f"🔄 Restored {synced} sessions to Antigravity UI sidebar.")
            # Refresh data after sync
            data = get_conversation_data()
        else:
            print("ℹ️ No missing sessions needed restoration.")

    md = generate_markdown(data)
    with open(OUTPUT_FILE, 'w') as f:
        f.write(md)
    print(f"📄 History written to {OUTPUT_FILE}")
    
    if do_distill:
        distill_to_knowledge(data)
