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
    if not text: return "untitled"
    # Remove XML tags like <USER_REQUEST>
    text = re.sub(r'<[^>]+>', '', text)
    text = text.lower()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[\s]+', '-', text)
    return text.strip('-')[:50]

def classify_sidebar_status(sources):
    has_conv = "conversations" in sources
    has_impl = "implicit" in sources
    has_brain = "brain" in sources

    if has_conv and not has_impl:
        return "📌 Active Sidebar (Original)"
    elif has_conv and has_impl:
        return "🔄 Restored from Background"
    elif has_impl and not has_conv:
        return "⚙️ Background / Implicit"
    elif has_brain and not has_conv and not has_impl:
        return "📁 Brain Storage Only"
    else:
        return "❓ Unknown Origin"

def classify_activity_state(last_updated, last_line_content):
    now = datetime.now(timezone.utc)
    delta = now - last_updated
    delta_hours = delta.total_seconds() / 3600.0

    if not last_line_content:
        if delta_hours < 1:
            return "🟢 Active Now"
        elif delta_hours < 24:
            return "⏳ In Progress (Recent)"
        elif delta_hours < 24 * 7:
            return "🔄 Active (This Week)"
        else:
            return "📁 Inactive / Archived"

    try:
        if last_line_content.startswith('{'):
            data = json.loads(last_line_content)
            source = data.get("source", "")
            msg_type = data.get("type", "")
            status = data.get("status", "")
            content = data.get("content", "")
            tool_calls = data.get("tool_calls", [])

            if source == "USER" or msg_type == "USER_REQUEST":
                if delta_hours < 4:
                    return "⏳ In Progress (Waiting on AI)"
                else:
                    return "⏳ In Progress (Pending AI Response)"

            if tool_calls and not content:
                if delta_hours < 4:
                    return "⚡ In Progress (Running Tools)"
                else:
                    return "⚡ In Progress (Tool Execution)"

            if source == "MODEL" and content:
                content_lower = content.lower()
                completion_keywords = ["successfully", "summary of the work", "accomplishments", "resolved", "completed the task", "all checks passed", "finalizing"]
                if any(kw in content_lower for kw in completion_keywords):
                    if delta_hours < 24:
                        return "✅ Completed (Recent)"
                    else:
                        return "✅ Completed"
                else:
                    if delta_hours < 1:
                        return "🟢 Active Now (AI Responded)"
                    elif delta_hours < 24:
                        return "🔄 Active / Follow-up"
                    elif delta_hours < 24 * 7:
                        return "🔄 Active (This Week)"
                    else:
                        return "✅ Completed / Inactive"
        else:
            # Legacy text format
            if delta_hours < 1:
                return "🟢 Active Now"
            elif delta_hours < 24:
                return "⏳ In Progress (Recent)"
            elif delta_hours < 24 * 7:
                return "🔄 Active (This Week)"
            else:
                return "📁 Inactive / Archived"
    except Exception:
        pass

    # Fallback
    if delta_hours < 1:
        return "🟢 Active Now"
    elif delta_hours < 24:
        return "⏳ In Progress (Recent)"
    elif delta_hours < 24 * 7:
        return "🔄 Active (This Week)"
    else:
        return "📁 Inactive / Archived"

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
                "sources": ["brain"],
                "last_line_content": None
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
            last_line_content = None
            if os.path.exists(overview_path):
                mtime = datetime.fromtimestamp(os.path.getmtime(overview_path), tz=timezone.utc)
                if mtime > conv_data["last_updated"]:
                    conv_data["last_updated"] = mtime
                
                first_line = None
                last_line = None
                try:
                    with open(overview_path, 'r', encoding='utf-8', errors='ignore') as f:
                        for line in f:
                            line_str = line.strip()
                            if not line_str: continue
                            if first_line is None:
                                first_line = line_str
                            last_line = line_str
                except Exception:
                    pass

                # Parse first_line for summary
                if first_line and not conv_data["summaries"]:
                    if first_line.startswith('{'):
                        try:
                            msg_data = json.loads(first_line)
                            content = msg_data.get("content", "")
                            match = re.search(r'<USER_REQUEST>(.*?)</USER_REQUEST>', content, re.DOTALL)
                            if match:
                                summary = match.group(1).strip().split('\n')[0]
                            else:
                                summary = content.strip().split('\n')[0]
                            if summary:
                                conv_data["summaries"].append(summary)
                        except Exception:
                            pass
                    else:
                        first_line_clean = re.sub(r'^USER: ', '', first_line)
                        if first_line_clean:
                            conv_data["summaries"].append(first_line_clean)

                # Store last_line for activity state classification
                if last_line:
                    last_line_content = last_line

            conv_data["last_line_content"] = last_line_content
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
                            "sources": [label],
                            "last_line_content": None
                        }

    return convs

def sync_missing_to_app(convs):
    """Restore implicit sessions to the main conversation folder to help the UI see them."""
    if not os.path.exists(CONVERSATIONS_DIR):
        print(f"⚠️ Conversations directory not found: {CONVERSATIONS_DIR}")
        return 0
        
    count = 0
    print(f"Checking {len(convs)} conversations for sync...")
    for conv_id, data in convs.items():
        if "implicit" in data["sources"] and "conversations" not in data["sources"]:
            src = os.path.join(IMPLICIT_DIR, f"{conv_id}.pb")
            dst = os.path.join(CONVERSATIONS_DIR, f"{conv_id}.pb")
            if os.path.exists(src) and not os.path.exists(dst):
                try:
                    shutil.copy2(src, dst)
                    print(f"  [SYNC] Restored session {conv_id[:8]}... to UI sidebar")
                    count += 1
                except Exception as e:
                    print(f"  [ERROR] Failed syncing {conv_id}: {e}")
    return count

def generate_markdown(convs):
    sorted_convs = sorted(convs.values(), key=lambda x: x["last_updated"], reverse=True)
    
    lines = [
        "# Rebuilt Conversation History & Status Center",
        f"\nGenerated on: {datetime.now(timezone.utc).isoformat()}\n",
        "| Last Updated | ID | Summary | Sidebar Status | Activity State | Artifacts |",
        "| :--- | :--- | :--- | :--- | :--- | :--- |"
    ]
    
    for c in sorted_convs:
        date_str = c["last_updated"].strftime("%Y-%m-%d %H:%M")
        summary = " / ".join(list(set(c["summaries"]))) if c["summaries"] else "*(No summary)*"
        if len(summary) > 90: summary = summary[:87] + "..."
        
        sidebar = classify_sidebar_status(c["sources"])
        activity = classify_activity_state(c["last_updated"], c.get("last_line_content"))
        
        row = f"| {date_str} | `{c['id'][:8]}...` | {summary} | {sidebar} | {activity} | {c['artifactsCount']} |"
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
        content += f"- **Sources**: {', '.join(c['sources'])}\n"
        
        sidebar = classify_sidebar_status(c["sources"])
        activity = classify_activity_state(c["last_updated"], c.get("last_line_content"))
        content += f"- **Sidebar Status**: {sidebar}\n"
        content += f"- **Activity State**: {activity}\n\n"
        
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
