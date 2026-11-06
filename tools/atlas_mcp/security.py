from .core import mcp


@mcp.tool()
def get_security_audit_summary():
    """
    Read and summarize the latest Lynis security audit report.
    Provides a count of warnings and suggestions for hardening.
    """
    # Written by nix-config's lynis-audit.service; wheel can read it through an ACL.
    report_path = "/var/log/security-audit/lynis-report.txt"
    try:
        try:
            with open(report_path, "r") as f:
                lines = f.readlines()
        except FileNotFoundError:
            return "Security audit report not found. It comes from nix-config's lynis-audit.service (weekly): sudo systemctl start lynis-audit.service"
        except PermissionError:
            return f"{report_path} is not readable: the wheel ACL comes from nix-config's audit.nix (apply it)."

        summary = {"warnings": [], "suggestions": [], "hardening_index": "Unknown"}

        for line in lines:
            if "Warning:" in line:
                summary["warnings"].append(line.split("Warning:")[1].strip())
            elif "Suggestion:" in line:
                summary["suggestions"].append(line.split("Suggestion:")[1].strip())
            elif "Hardening index" in line:
                # Format:  - Hardening index : 84 [###########         ]
                parts = line.split(":")
                if len(parts) > 1:
                    summary["hardening_index"] = parts[1].split("[")[0].strip()

        return {
            "status": "Audit Complete",
            "hardening_index": summary["hardening_index"],
            "warning_count": len(summary["warnings"]),
            "suggestion_count": len(summary["suggestions"]),
            "top_warnings": summary["warnings"][:5],
            "top_suggestions": summary["suggestions"][:5],
        }
    except Exception as e:
        return {"error": str(e)}
