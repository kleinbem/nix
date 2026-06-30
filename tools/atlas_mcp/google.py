import os
from datetime import datetime, timedelta
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from .core import (
    mcp,
    GOOGLE_SCOPES,
    GOOGLE_TOKEN_PATH,
    GOOGLE_CREDS_PATH,
)


def _get_google_creds():
    """Helper to handle Google OAuth2 flow."""
    creds = None
    if os.path.exists(GOOGLE_TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(GOOGLE_TOKEN_PATH, GOOGLE_SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(GOOGLE_CREDS_PATH):
                raise Exception(
                    f"Google credentials not found at {GOOGLE_CREDS_PATH}. Please download credentials.json from Google Cloud Console."
                )
            flow = InstalledAppFlow.from_client_secrets_file(
                GOOGLE_CREDS_PATH, GOOGLE_SCOPES
            )
            creds = flow.run_local_server(port=0)

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
