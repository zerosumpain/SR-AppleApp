#!/usr/bin/env python3
"""Throwaway: the latest TestFlight crash and screenshot feedback, with crash logs, as JSON."""
import importlib.util, json, os, sys, urllib.request
spec = importlib.util.spec_from_file_location("asc", "scripts/asc-watch-profiles.py")
asc = importlib.util.module_from_spec(spec); spec.loader.exec_module(asc)
c = asc.Client(asc.token(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_PRIVATE_KEY"]))
apps = c.call("GET", "/apps", query={"limit": 50})["data"]
out = {"crashes": [], "screenshots": [], "apps": [(a["id"], a["attributes"].get("bundleId")) for a in apps]}
items = []
for a in apps:
    items += c.call("GET", f"/apps/{a['id']}/betaFeedbackCrashSubmissions", query={"limit": 15, "sort": "-createdDate"}).get("data", [])
for item in items:
    entry = {"id": item["id"], "attributes": item["attributes"]}
    try:
        log = c.call("GET", f"/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
        entry["log"] = log["data"]["attributes"]
        url = entry["log"].get("logText") or None
    except Exception as e:
        entry["logError"] = str(e)
    out["crashes"].append(entry)
shots = []
for a in apps:
    shots += c.call("GET", f"/apps/{a['id']}/betaFeedbackScreenshotSubmissions", query={"limit": 15, "sort": "-createdDate"}).get("data", [])
for item in shots:
    out["screenshots"].append({"id": item["id"], "attributes": item["attributes"]})
json.dump(out, sys.stdout)
