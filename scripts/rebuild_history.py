#!/usr/bin/env python3
import os
import json
import glob
import sys
import re
import shutil
import sqlite3
import base64
import subprocess
from datetime import datetime, timezone

BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")
CONVERSATIONS_DIR = os.path.expanduser("~/.gemini/antigravity/conversations")
IMPLICIT_DIR = os.path.expanduser("~/.gemini/antigravity/implicit")
KNOWLEDGE_DIR = ".agent/knowledge"
OUTPUT_FILE = "conversation_history.md"


def sanitize_filename(text):
    if not text:
        return "untitled"
    # Remove XML tags like <USER_REQUEST>
    text = re.sub(r"<[^>]+>", "", text)
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s]+", "-", text)
    return text.strip("-")[:50]


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
        if last_line_content.startswith("{"):
            data = json.loads(last_line_content)
            source = data.get("source", "")
            msg_type = data.get("type", "")
            data.get("status", "")
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
                completion_keywords = [
                    "successfully",
                    "summary of the work",
                    "accomplishments",
                    "resolved",
                    "completed the task",
                    "all checks passed",
                    "finalizing",
                ]
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
                "last_updated": datetime.fromtimestamp(
                    os.path.getmtime(path), tz=timezone.utc
                ),
                "artifactsCount": 0,
                "sources": ["brain"],
                "last_line_content": None,
            }

            # Look for metadata files
            meta_files = glob.glob(os.path.join(path, "*.metadata.json"))
            for meta_file in meta_files:
                try:
                    with open(meta_file, "r") as f:
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
            overview_path = os.path.join(
                path, ".system_generated", "logs", "overview.txt"
            )
            last_line_content = None
            if os.path.exists(overview_path):
                mtime = datetime.fromtimestamp(
                    os.path.getmtime(overview_path), tz=timezone.utc
                )
                if mtime > conv_data["last_updated"]:
                    conv_data["last_updated"] = mtime

                first_line = None
                last_line = None
                try:
                    with open(
                        overview_path, "r", encoding="utf-8", errors="ignore"
                    ) as f:
                        for line in f:
                            line_str = line.strip()
                            if not line_str:
                                continue
                            if first_line is None:
                                first_line = line_str
                            last_line = line_str
                except Exception:
                    pass

                # Parse first_line for summary
                if first_line and not conv_data["summaries"]:
                    if first_line.startswith("{"):
                        try:
                            msg_data = json.loads(first_line)
                            content = msg_data.get("content", "")
                            match = re.search(
                                r"<USER_REQUEST>(.*?)</USER_REQUEST>",
                                content,
                                re.DOTALL,
                            )
                            if match:
                                summary = match.group(1).strip().split("\n")[0]
                            else:
                                summary = content.strip().split("\n")[0]
                            if summary:
                                conv_data["summaries"].append(summary)
                        except Exception:
                            pass
                    else:
                        first_line_clean = re.sub(r"^USER: ", "", first_line)
                        if first_line_clean:
                            conv_data["summaries"].append(first_line_clean)

                # Store last_line for activity state classification
                if last_line:
                    last_line_content = last_line

            conv_data["last_line_content"] = last_line_content
            conv_data["artifactsCount"] = len(
                [f for f in os.listdir(path) if not f.startswith(".")]
            )
            convs[conv_id] = conv_data

    # 2. Merge with Conversations & Implicit folders
    for folder, label in [
        (CONVERSATIONS_DIR, "conversations"),
        (IMPLICIT_DIR, "implicit"),
    ]:
        if os.path.exists(folder):
            for pb_file in os.listdir(folder):
                if pb_file.endswith(".pb"):
                    conv_id = pb_file[:-3]
                    full_pb_path = os.path.join(folder, pb_file)
                    pb_mtime = datetime.fromtimestamp(
                        os.path.getmtime(full_pb_path), tz=timezone.utc
                    )

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
                            "last_line_content": None,
                        }

    return convs


def sync_missing_to_app(convs):
    """Clean up UI sidebar by removing duplicate implicit/subagent sessions from conversations directory."""
    if not os.path.exists(CONVERSATIONS_DIR) or not os.path.exists(IMPLICIT_DIR):
        return 0

    count = 0
    print("Checking for subagent session clutter in UI sidebar...")
    for conv_id, data in convs.items():
        if "implicit" in data["sources"] and "conversations" in data["sources"]:
            conv_path = os.path.join(CONVERSATIONS_DIR, f"{conv_id}.pb")
            if os.path.exists(conv_path):
                try:
                    os.remove(conv_path)
                    print(
                        f"  [CLEAN] Removed subagent session {conv_id[:8]}... from UI sidebar"
                    )
                    count += 1
                except Exception as e:
                    print(f"  [ERROR] Failed cleaning {conv_id}: {e}")
    return count


def decode_varint(data, pos):
    val = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return val, pos


def encode_varint(val):
    out = bytearray()
    while True:
        towrite = val & 0x7F
        val >>= 7
        if val > 0:
            out.append(towrite | 0x80)
        else:
            out.append(towrite)
            break
    return bytes(out)


def encode_length_delimited(field_number, data):
    key = (field_number << 3) | 2
    return encode_varint(key) + encode_varint(len(data)) + data


def encode_varint_field(field_number, val):
    key = (field_number << 3) | 0
    return encode_varint(key) + encode_varint(val)


def parse_trajectory_summaries(data):
    entries = []
    pos = 0
    while pos < len(data):
        try:
            tag_var, pos = decode_varint(data, pos)
            field = tag_var >> 3
            wire = tag_var & 0x07

            if field == 1 and wire == 2:
                length, pos = decode_varint(data, pos)
                entry_bytes = data[pos : pos + length]
                pos += length

                uuid_val = None
                meta_b64 = None
                field2_val = None
                other_fields = []

                sub_pos = 0
                while sub_pos < len(entry_bytes):
                    sub_tag, sub_pos = decode_varint(entry_bytes, sub_pos)
                    sub_field = sub_tag >> 3
                    sub_wire = sub_tag & 0x07

                    if sub_field == 1 and sub_wire == 2:
                        length, sub_pos = decode_varint(entry_bytes, sub_pos)
                        uuid_val = entry_bytes[sub_pos : sub_pos + length].decode(
                            "utf-8"
                        )
                        sub_pos += length
                    elif sub_field == 2 and sub_wire == 2:
                        length, sub_pos = decode_varint(entry_bytes, sub_pos)
                        meta_bytes = entry_bytes[sub_pos : sub_pos + length]
                        sub_pos += length

                        m_pos = 0
                        while m_pos < len(meta_bytes):
                            m_tag, m_pos = decode_varint(meta_bytes, m_pos)
                            m_field = m_tag >> 3
                            m_wire = m_tag & 0x07

                            if m_field == 1 and m_wire == 2:
                                l_str, m_pos = decode_varint(meta_bytes, m_pos)
                                meta_b64 = meta_bytes[m_pos : m_pos + l_str].decode(
                                    "utf-8"
                                )
                                m_pos += l_str
                            elif m_field == 2 and m_wire == 0:
                                field2_val, m_pos = decode_varint(meta_bytes, m_pos)
                            else:
                                if m_wire == 0:
                                    _, m_pos = decode_varint(meta_bytes, m_pos)
                                elif m_wire == 2:
                                    l_s, m_pos = decode_varint(meta_bytes, m_pos)
                                    m_pos += l_s
                    else:
                        if sub_wire == 0:
                            v, sub_pos = decode_varint(entry_bytes, sub_pos)
                            other_fields.append((sub_field, sub_wire, v))
                        elif sub_wire == 2:
                            length, sub_pos = decode_varint(entry_bytes, sub_pos)
                            v = entry_bytes[sub_pos : sub_pos + length]
                            sub_pos += length
                            other_fields.append((sub_field, sub_wire, v))

                if uuid_val:
                    entries.append(
                        {
                            "uuid": uuid_val,
                            "meta_b64": meta_b64,
                            "field2": field2_val,
                            "other_fields": other_fields,
                        }
                    )
            else:
                if wire == 0:
                    _, pos = decode_varint(data, pos)
                elif wire == 2:
                    length, pos = decode_varint(data, pos)
                    pos += length
        except Exception:
            break
    return entries


def serialize_trajectory_summaries(entries):
    out = bytearray()
    for entry in entries:
        wrapper_bytes = bytearray()
        if entry["meta_b64"] is not None:
            wrapper_bytes.extend(
                encode_length_delimited(1, entry["meta_b64"].encode("utf-8"))
            )
        if entry["field2"] is not None:
            wrapper_bytes.extend(encode_varint_field(2, entry["field2"]))

        entry_bytes = bytearray()
        entry_bytes.extend(encode_length_delimited(1, entry["uuid"].encode("utf-8")))
        entry_bytes.extend(encode_length_delimited(2, bytes(wrapper_bytes)))
        for field, wire, val in entry["other_fields"]:
            if wire == 0:
                entry_bytes.extend(encode_varint_field(field, val))
            elif wire == 2:
                entry_bytes.extend(encode_length_delimited(field, val))

        out.extend(encode_length_delimited(1, bytes(entry_bytes)))
    return bytes(out)


def encode_timestamp(seconds, nanos=0):
    return encode_varint_field(1, seconds) + encode_varint_field(2, nanos)


def build_workspace_msg():
    w_sub = encode_length_delimited(1, b"kleinbem/nix") + encode_length_delimited(
        2, b"https://github.com/kleinbem/nix.git"
    )
    return (
        encode_length_delimited(
            1, b"file:///home/martin/Develop/github.com/kleinbem/nix"
        )
        + encode_length_delimited(
            2, b"file:///home/martin/Develop/github.com/kleinbem/nix"
        )
        + encode_length_delimited(3, w_sub)
        + encode_length_delimited(4, b"main")
    )


def build_trajectory_metadata_b64(uuid, title, steps_count, start_sec, mod_sec):
    workspace_msg = build_workspace_msg()
    metadata_bytes = (
        encode_length_delimited(1, title.encode("utf-8"))
        + encode_varint_field(2, steps_count)
        + encode_length_delimited(3, encode_timestamp(mod_sec))
        + encode_length_delimited(4, uuid.encode("utf-8"))
        + encode_varint_field(5, 1)
        + encode_length_delimited(7, encode_timestamp(start_sec))
        + encode_length_delimited(9, workspace_msg)
        + encode_length_delimited(10, encode_timestamp(mod_sec))
    )
    return base64.b64encode(metadata_bytes).decode("utf-8")


def sync_database_index(convs):
    """Sync the Antigravity IDE global SQLite database with the authoritative conversations on disk."""
    db_path = os.path.expanduser(
        "~/.config/antigravity/data/User/globalStorage/state.vscdb"
    )
    if not os.path.exists(db_path):
        print(f"⚠️ SQLite database not found at {db_path}. Skipping DB index sync.")
        return False

    is_running = False
    try:
        proc = subprocess.run(
            ["pgrep", "-f", "antigravity"], capture_output=True, text=True
        )
        if proc.returncode == 0:
            is_running = True
    except Exception:
        pass

    if is_running:
        print("⚠️ WARNING: Antigravity IDE is currently running!")
        print(
            "  Please restart/reopen the IDE after the sync completes to load the updated sidebar."
        )

    backup_path = db_path + ".backup"
    try:
        shutil.copy2(db_path, backup_path)
        print(f"💾 Backed up global storage database to {backup_path}")
    except Exception as e:
        print(f"❌ Failed to back up SQLite database: {e}")
        return False

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT value FROM ItemTable WHERE key='antigravityUnifiedStateSync.trajectorySummaries';"
        )
        row = cursor.fetchone()

        original_bytes = b""
        if row:
            original_bytes = base64.b64decode(row[0])

        existing_entries = parse_trajectory_summaries(original_bytes)
        existing_dict = {entry["uuid"]: entry for entry in existing_entries}

        disk_uuids = set()
        if os.path.exists(CONVERSATIONS_DIR):
            for f in os.listdir(CONVERSATIONS_DIR):
                if f.endswith(".pb"):
                    disk_uuids.add(f[:-3])

        print(
            f"📊 Disk has {len(disk_uuids)} sessions. DB index currently has {len(existing_dict)} sessions."
        )

        new_entries = []
        injected_count = 0
        removed_count = 0

        for uuid in sorted(list(disk_uuids)):
            if uuid in existing_dict:
                new_entries.append(existing_dict[uuid])
            else:
                title = "Restored Conversation"
                steps_count = 1
                start_sec = int(datetime.now(timezone.utc).timestamp())
                mod_sec = start_sec

                c_data = convs.get(uuid)
                if c_data:
                    if c_data["summaries"]:
                        title = c_data["summaries"][0]
                    mod_sec = int(c_data["last_updated"].timestamp())
                    start_sec = mod_sec

                brain_path = os.path.expanduser(f"~/.gemini/antigravity/brain/{uuid}")
                overview_path = os.path.join(
                    brain_path, ".system_generated/logs/overview.txt"
                )
                if os.path.exists(overview_path):
                    try:
                        with open(
                            overview_path, "r", encoding="utf-8", errors="ignore"
                        ) as f:
                            lines = f.readlines()
                            steps_count = len([line for line in lines if line.strip()])
                    except Exception:
                        pass

                if os.path.exists(overview_path):
                    try:
                        with open(
                            overview_path, "r", encoding="utf-8", errors="ignore"
                        ) as f:
                            first_line = f.readline()
                            if first_line.startswith("{"):
                                f_data = json.loads(first_line)
                                if "created_at" in f_data:
                                    dt = datetime.fromisoformat(
                                        f_data["created_at"].replace("Z", "+00:00")
                                    )
                                    start_sec = int(dt.timestamp())
                    except Exception:
                        pass

                meta_b64 = build_trajectory_metadata_b64(
                    uuid, title, steps_count, start_sec, mod_sec
                )

                new_entry = {
                    "uuid": uuid,
                    "meta_b64": meta_b64,
                    "field2": None,
                    "other_fields": [],
                }
                new_entries.append(new_entry)
                injected_count += 1

        final_entries = []
        for entry in new_entries:
            if entry["uuid"] in disk_uuids:
                final_entries.append(entry)
            else:
                removed_count += 1

        serialized_bytes = serialize_trajectory_summaries(final_entries)
        new_b64 = base64.b64encode(serialized_bytes).decode("utf-8")

        cursor.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.trajectorySummaries', ?);",
            (new_b64,),
        )
        conn.commit()
        conn.close()

        print("✅ DB Index Synced successfully:")
        print(
            f"  - Injected {injected_count} new conversations into the sidebar index."
        )
        print(
            f"  - Removed {removed_count} stale/deleted conversations from the sidebar index."
        )
        print(f"  - Total sidebar entries now: {len(final_entries)}")
        return True
    except Exception as e:
        print(f"❌ Failed to sync SQLite database index: {e}")
        return False


def generate_markdown(convs):
    sorted_convs = sorted(convs.values(), key=lambda x: x["last_updated"], reverse=True)

    lines = [
        "# Rebuilt Conversation History & Status Center",
        f"\nGenerated on: {datetime.now(timezone.utc).isoformat()}\n",
        "| Last Updated | ID | Summary | Sidebar Status | Activity State | Artifacts |",
        "| :--- | :--- | :--- | :--- | :--- | :--- |",
    ]

    for c in sorted_convs:
        date_str = c["last_updated"].strftime("%Y-%m-%d %H:%M")
        summary = (
            " / ".join(list(set(c["summaries"])))
            if c["summaries"]
            else "*(No summary)*"
        )
        if len(summary) > 90:
            summary = summary[:87] + "..."

        sidebar = classify_sidebar_status(c["sources"])
        activity = classify_activity_state(
            c["last_updated"], c.get("last_line_content")
        )

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
        activity = classify_activity_state(
            c["last_updated"], c.get("last_line_content")
        )
        content += f"- **Sidebar Status**: {sidebar}\n"
        content += f"- **Activity State**: {activity}\n\n"

        content += "## Summaries Found\n"
        for s in set(c["summaries"]):
            content += f"- {s}\n"

        with open(filepath, "w") as f:
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
        cleaned = sync_missing_to_app(data)
        if cleaned > 0:
            print(
                f"🧹 Cleaned {cleaned} subagent sessions from Antigravity UI sidebar."
            )
            # Refresh data after cleaning
            data = get_conversation_data()
        else:
            print("✨ UI sidebar is clean (no subagent clutter found).")

        # Sync to SQLite database
        sync_database_index(data)

    md = generate_markdown(data)
    with open(OUTPUT_FILE, "w") as f:
        f.write(md)
    print(f"📄 History written to {OUTPUT_FILE}")

    if do_distill:
        distill_to_knowledge(data)
