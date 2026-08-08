import json
import os
import subprocess
from datetime import datetime, timedelta

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

from .core import (
    GOOGLE_OAUTH_SOPS_FILE,
    GOOGLE_OAUTH_SOPS_KEY,
    GOOGLE_SCOPES,
    GOOGLE_TOKEN_PATH,
    mcp,
)


def _load_google_client_config():
    """Decrypt the OAuth client secret from kleinbem-secrets in-memory (never written to disk)."""
    if not os.path.exists(GOOGLE_OAUTH_SOPS_FILE):
        raise Exception(f"kleinbem-secrets not checked out at {GOOGLE_OAUTH_SOPS_FILE}.")
    try:
        result = subprocess.run(
            ["sops", "--decrypt", "--extract", f'["{GOOGLE_OAUTH_SOPS_KEY}"]', GOOGLE_OAUTH_SOPS_FILE],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        raise Exception(
            f"Failed to decrypt {GOOGLE_OAUTH_SOPS_KEY} from {GOOGLE_OAUTH_SOPS_FILE} (touch your YubiKey if prompted): {e.stderr}"
        )
    return json.loads(result.stdout)


def _get_google_creds():
    """Helper to handle Google OAuth2 flow."""
    creds = None
    if os.path.exists(GOOGLE_TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(GOOGLE_TOKEN_PATH, GOOGLE_SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_config(
                _load_google_client_config(), GOOGLE_SCOPES
            )
            creds = flow.run_local_server(port=0)

        os.makedirs(os.path.dirname(GOOGLE_TOKEN_PATH), exist_ok=True)
        with open(GOOGLE_TOKEN_PATH, "w") as token:
            token.write(creds.to_json())
    return creds


@mcp.tool()
def get_calendar_events(days: int = 7):
    """
    Fetch upcoming events from Google Calendar.
    Used to check for meetings or busy periods before scheduling maintenance.
    """
    try:
        creds = _get_google_creds()
        service = build("calendar", "v3", credentials=creds)

        now = datetime.utcnow().isoformat() + "Z"
        end_time = (datetime.utcnow() + timedelta(days=days)).isoformat() + "Z"

        events_result = (
            service.events()
            .list(
                calendarId="primary",
                timeMin=now,
                timeMax=end_time,
                singleEvents=True,
                orderBy="startTime",
            )
            .execute()
        )
        events = events_result.get("items", [])

        if not events:
            return "No upcoming events found."

        summary = []
        for event in events:
            start = event["start"].get("dateTime", event["start"].get("date"))
            summary.append(
                {
                    "start": start,
                    "summary": event.get("summary", "No Title"),
                    "description": event.get("description", ""),
                }
            )
        return summary
    except Exception as e:
        return {"error": str(e)}
