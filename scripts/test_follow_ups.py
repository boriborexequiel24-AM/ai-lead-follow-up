"""End-to-end test of follow-ups (workflow 4) and the cleanup.

Creates a lead through the live agent, pretends it went quiet by moving its
clock back, and waits for the scheduler (it runs every minute) to follow up.
Then checks a lead with 3 unanswered follow-ups gets closed, and that the
cleanup deletes visitor leads past their retention. Needs the demo clock.
Makes real AI calls. Every test lead is deleted at the end.

Uses only the Python standard library. Usage (from the project root):
    python scripts/test_follow_ups.py
"""

from __future__ import annotations

import re
import time
import urllib.parse
from datetime import datetime, timedelta, timezone

from test_guardrails import TEST_NAME, new_lead, request, rpc, table
from test_n8n_agent import form_lead


def ago(minutes: float) -> str:
    return (datetime.now(timezone.utc) - timedelta(minutes=minutes)).isoformat()


def wait_for(check, seconds: int = 150):
    """The scheduler runs once a minute, so give it a couple of runs."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(5)
    return check()


def run_tests() -> list[tuple[str, bool, str]]:
    results = []

    def test(name: str, ok: bool, detail=""):
        results.append((name, bool(ok), str(detail)[:400]))

    settings = table("settings", "id=eq.1&select=clock_mode,demo_minutes_per_day,follow_up_gaps_days")[0]
    test("the clock is in demo mode", settings["clock_mode"] == "demo", settings)
    if settings["clock_mode"] != "demo":
        return results

    # A lead that goes quiet gets a follow-up.
    status, body = form_lead("Could someone look at our furnace? It's making a rattling noise. Weekday mornings are best.")
    lead_id = body.get("lead_id")
    test("the lead gets a first reply that waits for an answer",
         status == 200 and body.get("final_action") in ("offer_booking", "ask_question"), (status, body))
    if lead_id:
        request("PATCH", f"leads?id=eq.{lead_id}", {"awaiting_reply_since": ago(5)})
        lead = wait_for(lambda: (row := table("leads", f"id=eq.{lead_id}&select=follow_ups_sent,status")[0])
                        ["follow_ups_sent"] >= 1 and row)
        test("the scheduler sends follow-up 1 once the lead has been quiet a (demo) day",
             lead and lead["follow_ups_sent"] == 1 and lead["status"] == "active", lead)
        decisions = table("decisions", f"lead_id=eq.{lead_id}&trigger=eq.follow_up&select=final_action,reply,violations")
        out = table("messages", f"lead_id=eq.{lead_id}&direction=eq.out&select=body,status&order=created_at")
        test("the follow-up is a new message with no price and no em dash",
             decisions and decisions[0]["final_action"] in ("offer_booking", "ask_question") and len(out) == 2
             and not re.search(r"\$\s?\d", out[-1]["body"]) and chr(0x2014) not in out[-1]["body"], (decisions, out))
        time.sleep(70)
        again = table("leads", f"id=eq.{lead_id}&select=follow_ups_sent")[0]["follow_ups_sent"]
        test("no second follow-up before its gap is up", again == 1, again)
        # Follow-up 2 is due 2 demo days (2 minutes) after follow-up 1. It used
        # to wait for the 5-minute claim from follow-up 1 to run out.
        second = wait_for(lambda: table("leads", f"id=eq.{lead_id}&select=follow_ups_sent")[0]["follow_ups_sent"] >= 2, 120)
        test("follow-up 2 arrives on time (the claim from follow-up 1 is released)", second, second)

    # After 3 unanswered follow-ups the lead is closed, with no AI call.
    status, body = form_lead("Need a toilet repaired, it rocks when you sit on it.")
    lead_id = body.get("lead_id")
    if lead_id:
        request("PATCH", f"leads?id=eq.{lead_id}", {"follow_ups_sent": 3, "awaiting_reply_since": ago(30)})
        lead = wait_for(lambda: (row := table("leads", f"id=eq.{lead_id}&select=status,end_state")[0])
                        ["status"] == "closed" and row)
        test("after 3 follow-ups the scheduler closes the lead as no_response",
             lead and lead["end_state"] == "no_response", lead)

    # The cleanup deletes visitor leads past their retention, and only those.
    old = new_lead("Old visitor lead")
    fresh = new_lead("Fresh visitor lead")
    request("PATCH", f"leads?id=eq.{old}", {"created_at": ago(25 * 60)})
    result = rpc("cleanup")
    remaining = {r["id"] for r in table("leads", f"id=in.({old},{fresh})&select=id")}
    test("the cleanup deletes visitor leads older than 24 hours and keeps newer ones",
         old not in remaining and fresh in remaining and result["visitor_leads_deleted"] >= 1, (result, remaining))
    return results


def main() -> None:
    try:
        results = run_tests()
    finally:
        request("DELETE", f"leads?name=eq.{urllib.parse.quote(TEST_NAME)}")
    passed = sum(ok for _, ok, _ in results)
    for name, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"\n      {detail}"))
    print(f"\n{passed} / {len(results)} passed. Test leads deleted.")
    raise SystemExit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
