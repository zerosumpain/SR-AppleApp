#!/usr/bin/env python3
"""Throwaway: the latest TestFlight crash and screenshot feedback, with crash logs, as JSON."""
import importlib.util, json, os, sys, urllib.request
spec = importlib.util.spec_from_file_location("asc", "scripts/asc-watch-profiles.py")
asc = importlib.util.module_from_spec(spec); spec.loader.exec_module(asc)
c = asc.Client(asc.token(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_PRIVATE_KEY"]))
app = c.call("GET", "/apps", query={"filter[bundleId]": "com.strangeramblings.com.appleapp"})["data"][0]["id"]
out = {"crashes": [], "screenshots": []}
crashes = c.call("GET", f"/apps/{app}/betaFeedbackCrashSubmissions", query={"limit": 15, "sort": "-createdDate"})
for item in crashes.get("data", []):
    entry = {"id": item["id"], "attributes": item["attributes"]}
    try:
        log = c.call("GET", f"/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
        entry["log"] = log["data"]["attributes"]
        url = entry["log"].get("logText") or None
    except Exception as e:
        entry["logError"] = str(e)
    out["crashes"].append(entry)
shots = c.call("GET", f"/apps/{app}/betaFeedbackScreenshotSubmissions", query={"limit": 15, "sort": "-createdDate"})
for item in shots.get("data", []):
    out["screenshots"].append({"id": item["id"], "attributes": item["attributes"]})
json.dump(out, sys.stdout)
