"""Create the sample leads shown in the public owner view.

Each one is a real conversation with the live agent (workflow 1), not
hand-written rows, so the owner view shows genuine decisions and reasons.
The leads are marked is_sample; visitor leads never appear in the owner view.
Running it again replaces the previous sample leads.

What it makes:
  - a furnace tune-up that gets booked
  - a burst pipe (emergency: alert to #lead-alerts)
  - a water heater price that the "owner" approves (signed Slack click)
  - an out-of-area AC repair that is declined
  - a vague message that gets a question, an answer, then goes quiet
  - an SEO sales pitch closed as spam
  - a lead who found someone else
  - an AC lead who goes quiet, gets follow-up 1, then books

Makes real AI calls and posts a few messages to Slack. The quiet leads get
their follow-ups (and close as no_response) on the demo clock over the next
10 minutes. Takes about 4 minutes.

Uses only the Python standard library. Usage (from the project root):
    python scripts/seed_demo_leads.py
"""

from __future__ import annotations

import time

from test_approval import click
from test_guardrails import request, table
from test_n8n_agent import post


def say(lead_id: str, message: str) -> dict:
    status, body = post({"source": "form", "lead_id": lead_id, "message": message})
    print(f"    reply -> {status} {body.get('final_action')}")
    return body


def start(name: str, email: str, zip_code: str, message: str, phone: str = "") -> str | None:
    status, body = post({"source": "form", "name": name, "email": email, "phone": phone, "zip": zip_code,
                         "message": message, "subject": "Quote request from the website"})
    lead_id = body.get("lead_id")
    print(f"  {name}: {status} {body.get('final_action')}")
    if lead_id:
        request("PATCH", f"leads?id=eq.{lead_id}", {"is_sample": True})
    return lead_id


def wait_for(check, seconds: int = 150):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(5)
    return None


def main() -> None:
    old = table("leads", "is_sample=eq.true&select=id")
    if old:
        request("DELETE", "leads?is_sample=eq.true")
        print(f"Deleted {len(old)} old sample leads.")

    print("Creating sample leads:")
    lead = start("Jordan Ellis", "jordan.ellis@example.com", "80206",
                 "Hi, can I get a furnace tune-up sometime next week? Mornings work best.")
    if lead:
        say(lead, "The first morning you listed works for me.")

    start("Dana Whitfield", "dana.whitfield@example.com", "80209",
          "Water is spraying out of a pipe under the kitchen sink and I can't find the shutoff!!", phone="(303) 555-0117")

    lead = start("Sam Ortega", "sam.ortega@example.com", "80210",
                 "Roughly how much to replace a 50 gallon gas water heater? It's about 14 years old.")
    if lead:
        approval = wait_for(lambda: (rows := table("approvals", f"lead_id=eq.{lead}&select=id,slack_ts"))
                            and rows[0]["slack_ts"] and rows[0], 30)
        if approval:
            print(f"    owner approves the price -> {click(approval['id'], True, approval['slack_ts'], user='Mike (owner)')}")
            time.sleep(3)
            say(lead, "That's about what I expected. Could someone come out this week to take a look?")

    start("Riley Chen", "riley.chen@example.com", "80504",
          "Our AC stopped blowing cold air. We're up in Longmont, do you come out this far?")

    lead = start("Alex Moreno", "alex.moreno@example.com", "",
                 "Hi, I need some help with something at the house.")
    if lead:
        say(lead, "Sorry, it's the kitchen sink. It drains really slowly and gurgles. We're in 80218.")

    start("Brightpath Digital", "growth@brightpath.example", "",
          "Hi! We help home service companies get 3x more leads with SEO and Google Ads. Do you have 15 minutes this week for a quick call?")

    lead = start("Priya Natarajan", "priya.n@example.com", "80222",
                 "Our toilet keeps running all night. Can someone fix it this week?")
    if lead:
        say(lead, "Actually my brother-in-law fixed it last night, so we're all set. Thanks anyway!")

    lead = start("Chris Baker", "chris.baker@example.com", "80220",
                 "The AC upstairs runs all day but the bedrooms are still warm. Can someone take a look?")
    if lead:
        print("    going quiet, waiting for follow-up 1 (about a minute on the demo clock)...")
        sent = wait_for(lambda: table("leads", f"id=eq.{lead}&select=follow_ups_sent")[0]["follow_ups_sent"] >= 1)
        if sent:
            say(lead, "Sorry, busy week! Yes please, the second time you offered works.")
        else:
            print("    no follow-up arrived in time; left as is")

    samples = table("leads", "is_sample=eq.true&select=name,status,end_state")
    print(f"\n{len(samples)} sample leads:")
    for s in samples:
        print(f"  {s['name']}: {s['status']}{' / ' + s['end_state'] if s['end_state'] else ''}")


if __name__ == "__main__":
    main()
