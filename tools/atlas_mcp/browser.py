import os
import shutil
import sqlite3
import tempfile

from .core import FIREFOX_PATH, mcp


@mcp.tool()
def firefox_search(query: str, profile: str = "standard"):
    """Search Firefox history for a keyword in a specific profile (standard, laboratory, temp)."""
    try:
        profiles = [d for d in os.listdir(FIREFOX_PATH) if d.endswith(f".{profile}")]
        if not profiles:
            return f"Error: Profile {profile} not found."
        db_path = os.path.join(FIREFOX_PATH, profiles[0], "places.sqlite")
        if not os.path.exists(db_path):
            return f"Error: Places database not found for {profile}."
        # Firefox locks places.sqlite while it runs: query a private copy.
        with tempfile.TemporaryDirectory(prefix="firefox-search-") as tmp:
            temp_db = os.path.join(tmp, "places.sqlite")
            shutil.copy2(db_path, temp_db)
            conn = sqlite3.connect(temp_db)
            cursor = conn.cursor()
            sql = "SELECT title, url FROM moz_places WHERE (title LIKE ? ESCAPE '\\' OR url LIKE ? ESCAPE '\\') ORDER BY last_visit_date DESC LIMIT 10"
            literal = (
                query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            )
            cursor.execute(sql, (f"%{literal}%", f"%{literal}%"))
            results = cursor.fetchall()
            conn.close()
        return [{"title": r[0], "url": r[1]} for r in results]
    except Exception as e:
        return str(e)
