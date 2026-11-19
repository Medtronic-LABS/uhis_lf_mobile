#!/usr/bin/env python3
"""
Promotes a build that is already on a Play listing's Internal testing track to
its Production track, as a staged rollout. The bundle is not rebuilt or
re-uploaded: Play moves the exact build that testers received.

Run it again with a higher --rollout to widen a staged rollout (20 -> 50 -> 100).

Required env var:
  PLAY_SERVICE_ACCOUNT_JSON   Service account key with release permission on the app

Usage:
  scripts/play_promote.py --package com.example.app --version-code 17 --rollout 20
  scripts/play_promote.py --package com.example.app --version-code 17 --rollout 100 --dry-run
"""

import argparse
import json
import os
import re
import sys

API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
API_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
SOURCE_TRACK = "internal"
TARGET_TRACK = "production"
STATUS_COMPLETED = "completed"
STATUS_IN_PROGRESS = "inProgress"
FULL_ROLLOUT = 100


class PromotionError(Exception):
    """The promotion cannot go ahead; the message says why."""


def find_release(track, version_code):
    """Returns the release on `track` that contains `version_code`, or None."""
    for release in track.get("releases", []):
        if version_code in release.get("versionCodes", []):
            return release
    return None


def rollout_percent(release):
    """The share of users a release reaches, as a whole percentage."""
    if release.get("status") == STATUS_COMPLETED:
        return FULL_ROLLOUT
    return round(float(release.get("userFraction", 0)) * FULL_ROLLOUT)


def plan_promotion(source_track, target_track, version_code, percent):
    """
    Decides what to set on the target track.

    Returns the release to write, or None when the build is already fully
    rolled out. Raises PromotionError when the promotion must not happen.
    """
    if not 1 <= percent <= FULL_ROLLOUT:
        raise PromotionError("Rollout must be between 1 and 100 percent.")

    source = find_release(source_track, version_code)
    if source is None or source.get("status") != STATUS_COMPLETED:
        raise PromotionError(
            "Build %s is not a completed release on the %s track." % (version_code, SOURCE_TRACK))

    current = find_release(target_track, version_code)
    if current is not None:
        if current.get("status") == STATUS_COMPLETED:
            return None
        if current.get("status") == STATUS_IN_PROGRESS and percent <= rollout_percent(current):
            raise PromotionError(
                "Build %s is already rolled out to %d%%; choose a higher percentage."
                % (version_code, rollout_percent(current)))

    live_codes = [
        int(code)
        for release in target_track.get("releases", [])
        if release.get("status") == STATUS_COMPLETED
        for code in release.get("versionCodes", [])
    ]
    if live_codes and int(version_code) < max(live_codes):
        raise PromotionError(
            "Build %s is older than build %d, which is already live." % (version_code, max(live_codes)))

    release = {"name": source.get("name", version_code), "versionCodes": [version_code]}
    if source.get("releaseNotes"):
        release["releaseNotes"] = source["releaseNotes"]
    if percent == FULL_ROLLOUT:
        release["status"] = STATUS_COMPLETED
    else:
        release["status"] = STATUS_IN_PROGRESS
        release["userFraction"] = percent / FULL_ROLLOUT
    return release


def redact(text):
    """Keeps account email addresses out of public workflow logs."""
    return re.sub(r"[\w.+-]+@[\w.-]+", "<email>", str(text))[:400]


def call(session, method, url, **kwargs):
    """Performs one Play API request and returns its JSON, or raises PromotionError."""
    response = session.request(method, url, **kwargs)
    if response.status_code >= 300:
        try:
            message = response.json().get("error", {}).get("message", response.text)
        except ValueError:
            message = response.text
        raise PromotionError("Play API %s failed with HTTP %d: %s"
                             % (method, response.status_code, redact(message)))
    return response.json() if response.content else {}


def open_session():
    """Authenticates with the service account key from the environment."""
    from google.auth.exceptions import GoogleAuthError
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account

    raw_key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "")
    if not raw_key:
        raise PromotionError("PLAY_SERVICE_ACCOUNT_JSON is not set.")
    try:
        credentials = service_account.Credentials.from_service_account_info(
            json.loads(raw_key), scopes=[API_SCOPE])
    except (ValueError, KeyError) as error:
        raise PromotionError("PLAY_SERVICE_ACCOUNT_JSON is not a service account key: "
                             + redact(error)) from error
    except GoogleAuthError as error:
        raise PromotionError("Google rejected the service account key: " + redact(error)) from error
    return AuthorizedSession(credentials)


def promote(session, package, version_code, percent, dry_run):
    """Opens a Play edit, applies the planned release, and commits or discards it."""
    base = API_ROOT + package
    edit_id = call(session, "POST", base + "/edits")["id"]
    edit = "%s/edits/%s" % (base, edit_id)
    committed = False
    try:
        source_track = call(session, "GET", "%s/tracks/%s" % (edit, SOURCE_TRACK))
        target_track = call(session, "GET", "%s/tracks/%s" % (edit, TARGET_TRACK))
        release = plan_promotion(source_track, target_track, version_code, percent)
        if release is None:
            print("Build %s is already fully rolled out on %s. Nothing to do."
                  % (version_code, TARGET_TRACK))
            return
        print("Plan: build %s -> %s track at %d%% (%s)"
              % (version_code, TARGET_TRACK, percent, release["status"]))
        if dry_run:
            print("Dry run: nothing was changed on Play.")
            return
        call(session, "PUT", "%s/tracks/%s" % (edit, TARGET_TRACK),
             json={"track": TARGET_TRACK, "releases": [release]})
        call(session, "POST", edit + ":commit")
        committed = True
        print("Done: build %s is on the %s track at %d%%." % (version_code, TARGET_TRACK, percent))
    finally:
        if not committed:
            session.request("DELETE", edit)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package", required=True, help="Play package name of the app")
    parser.add_argument("--version-code", required=True, help="Build number to promote")
    parser.add_argument("--rollout", required=True, type=int, help="Percentage of users, 1-100")
    parser.add_argument("--dry-run", action="store_true", help="Show the plan without changing Play")
    args = parser.parse_args()

    if not args.version_code.isdigit():
        sys.exit("✗ --version-code must be a whole number, e.g. 17.")

    from google.auth.exceptions import GoogleAuthError
    from requests.exceptions import RequestException

    try:
        promote(open_session(), args.package, args.version_code, args.rollout, args.dry_run)
    except PromotionError as error:
        sys.exit("✗ %s" % error)
    except GoogleAuthError as error:
        sys.exit("✗ Google sign-in failed: %s" % redact(error))
    except RequestException as error:
        sys.exit("✗ Could not reach the Play API: %s" % redact(error))


if __name__ == "__main__":
    main()
