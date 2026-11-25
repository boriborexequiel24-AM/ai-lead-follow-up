"""Test the guardrails and the conversation loop in Supabase.

Calls the database functions from supabase/migrations/20261118000100_agent_functions.sql
the way n8n will, with hand-written decisions (no AI calls, so it's free and
the results are exact). Every test lead is deleted at the end, even if a test fails.

Uses only the Python standard library. Usage (from the project root):
    python scripts/test_guardrails.py
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_NAME = "TEST guardrails"  # every test lead gets this name, so cleanup can find them


def load_env() -> dict[str, str]:
    values = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        match = re.match(r"^\s*([A-Z0-9_]+)=(.*)$", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip('"').strip("'")
    return values


ENV = load_env()
SCHEMA = ENV.get("SUPABASE_SCHEMA", "leads")
HEADERS = {
    "apikey": ENV["SUPABASE_SERVICE_ROLE_KEY"],
    "Authorization": f"Bearer {ENV['SUPABASE_SERVICE_ROLE_KEY']}",
    "Content-Type": "application/json",
    "Accept-Profile": SCHEMA,
    "Content-Profile": SCHEMA,
}


def request(method: str, path: str, body=None):
    req = urllib.request.Request(
        f"{ENV['SUPABASE_URL']}/rest/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers=HEADERS, method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            text = response.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{method} {path}: HTTP {error.code} {error.read().decode()[:400]}") from None


def rpc(name: str, **params):
    return request("POST", f"rpc/{name}", params)


def table(name: str, query: str):
    return request("GET", f"{name}?{query}")


# ---------- Helpers for building cases ----------

def new_lead(message: str = "Toilet keeps running, can someone come this week?", **extra) -> str:
    params = {"p_source": "form", "p_channel": "form", "p_body": message, "p_name": TEST_NAME,
              "p_email": f"guardrails-{uuid.uuid4().hex[:8]}@mail.example", "p_zip": "80210",
              "p_is_visitor": True, **extra}
    return rpc("receive_message", **params)["lead_id"]


def decision(action: str, reply: str = "Hi, happy to help. Copperline Plumbing & Air", **extra) -> dict:
    return {"action": action, "reason": "test", "reply": reply, "price_code": None,
            "offered_slots": [], "slot": None, "end_state": None, "owner_note": "", **extra}


def check(lead_id: str, dec: dict, trigger: str = "message", now: str | None = None) -> dict:
    params = {"p_lead_id": lead_id, "p_trigger": trigger, "p_decision": dec}
    if now:
        params["p_now"] = now
    return rpc("check_decision", **params)


FACTS = {"is_real_lead": True, "trade": "plumbing", "job_type": "repair", "urgency": "this_week",
         "wants_price": False, "missing_info": [], "zip": "80210", "language": "en",
         "summary": "Test lead", "in_service_area": True}


def apply(lead_id: str, dec: dict, trigger: str = "message") -> dict:
    return rpc("apply_decision", p_lead_id=lead_id, p_trigger=trigger, p_facts=FACTS, p_decision=dec, p_model="test")


# ---------- The tests ----------

def run_tests() -> list[tuple[str, bool, str]]:
    results = []

    def test(name: str, ok: bool, detail=""):
        results.append((name, bool(ok), str(detail)[:300]))

    rpc("refresh_slots")
    context_lead = new_lead()
    context = rpc("get_agent_context", p_lead_id=context_lead)
    slots = [s["time"] for s in context["open_slots"]]
    test("every open slot comes with a label", all(s.get("label") for s in context["open_slots"]) and context.get("today"),
         context["open_slots"][:2])
    test("context has company, prices and open slots",
         context["company"]["name"] == "Copperline Plumbing & Air" and len(context["price_sheet"]) == 16 and len(slots) >= 6,
         f"{len(slots)} slots")
    test("context has the lead's message as the conversation",
         len(context["conversation"]) == 1 and context["conversation"][0]["from"] == "lead", context["conversation"])

    # Slots
    r = check(new_lead(), decision("offer_booking", offered_slots=slots[:2]))
    test("offering real open slots is allowed", r["final_action"] == "offer_booking" and not r["violations"], r)
    r = check(new_lead(), decision("offer_booking", offered_slots=[slots[0], "2026-01-03T13:00:00-07:00"]))
    test("offering a made-up slot becomes hand_off", r["final_action"] == "hand_off" and r["violations"], r["violations"])
    r = check(new_lead(), decision("offer_booking", offered_slots=["Wednesday at 3pm"]))
    test("a slot that isn't a timestamp becomes hand_off", r["final_action"] == "hand_off", r["violations"])
    r = check(new_lead(), decision("offer_booking", offered_slots=[]))
    test("offer_booking with no slots becomes hand_off", r["final_action"] == "hand_off", r["violations"])

    # Prices
    r = check(new_lead(), decision("offer_booking", reply="It's only $89 to come out.", offered_slots=slots[:1]))
    test("a dollar amount outside draft_price becomes hand_off",
         r["final_action"] == "hand_off" and "dollar amount without owner approval" in r["violations"], r["violations"])
    good_price = decision("draft_price", reply="A 50 gallon replacement usually runs $1,400 to $2,200.",
                          price_code="water_heater_tank")
    r = check(new_lead(), good_price)
    test("a price inside the sheet range goes to approval",
         r["final_action"] == "draft_price" and r["needs_approval"] and not r["violations"], r)
    r = check(new_lead(), decision("draft_price", reply="Sure, $100 total.", price_code="water_heater_tank"))
    test("a price below the sheet becomes hand_off",
         r["final_action"] == "hand_off" and any("outside" in v for v in r["violations"]), r["violations"])
    r = check(new_lead(), decision("draft_price", reply="About $500.", price_code="made_up_job"))
    test("an unknown price_code becomes hand_off", r["final_action"] == "hand_off", r["violations"])

    # Reply rules
    em_dash = chr(0x2014)
    r = check(new_lead(), decision("answer_question", reply=f"We're open Saturdays {em_dash} 8am to 2pm."))
    test("em dashes are replaced", em_dash not in r["reply"] and r["final_action"] == "answer_question", r["reply"])
    r = check(new_lead(), decision("ask_question", reply="  "))
    test("an empty reply becomes hand_off", r["final_action"] == "hand_off", r["violations"])
    r = check(new_lead(), decision("escalate_emergency", reply="Call us, it costs $89."))
    test("a blocked emergency still gives the emergency line",
         r["final_action"] == "hand_off" and "555-0199" in r["reply"], r["reply"])

    r = check(new_lead(), decision("escalate_emergency", reply="Leave the house now. The owner will call you."))
    test("an emergency reply without the emergency line is replaced by one that has it",
         r["final_action"] == "hand_off" and "555-0199" in r["reply"], r)
    r = check(new_lead(), decision("escalate_emergency", reply="Leave now, then call 303-555-0199."))
    test("an emergency reply with the line goes out, however it's punctuated", r["final_action"] == "escalate_emergency", r)
    for text in ("A visit is 89 dollars.", "It's about 1,400 for that.", "Son unos 1400 d\u00f3lares.", "USD 89."):
        r = check(new_lead(), decision("answer_question", reply=text))
        test(f"a price without a dollar sign is caught: {text}", r["final_action"] == "hand_off", r["violations"])
    for text in ("Call (303) 555-0142.", "A 50 gallon tank, with a 1-year warranty.", "Fine for a 2,000 square foot home."):
        r = check(new_lead(), decision("answer_question", reply=text))
        test(f"not a price: {text}", r["final_action"] == "answer_question", r["violations"])
    r = check(new_lead(), {**good_price, "reply": "Usually $1,400 to 9,900."})
    test("the second half of a price range is checked too", r["final_action"] == "hand_off", r["violations"])

    # Stop requests
    for text in ("Please stop", "Please don\u2019t email me", "stop sending me emails"):
        r = check(new_lead(text), decision("ask_question"))
        test(f"a stop request: {text}", r["end_state"] == "unsubscribed" and r["reply"] == "", r)
    r = check(new_lead("Don't text me, call me, water is coming through the ceiling"),
              decision("escalate_emergency", reply="Call 303-555-0199 now."))
    test("an emergency is never cut off by the stop rule", r["final_action"] == "escalate_emergency", r)
    r = check(new_lead("Please don't email me, call me on 303 555 0111"), decision("ask_question"))
    test("'don't email me, call me' goes to a person with no message", r["final_action"] == "hand_off" and r["reply"] == "", r)
    lead = new_lead()
    rpc("receive_message", p_source="form", p_channel="web", p_body="please stop emailing me", p_lead_id=lead)
    r = check(lead, decision("offer_booking", offered_slots=slots[:1]))
    test("'please stop emailing me' forces close + unsubscribed with no reply",
         r["final_action"] == "close" and r["end_state"] == "unsubscribed" and r["reply"] == "", r)
    r = check(new_lead("The water won't stop leaking under the sink"), decision("offer_booking", offered_slots=slots[:1]))
    test("'won't stop leaking' is not a stop request", r["final_action"] == "offer_booking", r)

    # Follow-ups: quiet hours and the limit
    # These pass a fixed "now", so they offer the latest open slot, which is after it.
    lead = new_lead()
    r = check(lead, decision("offer_booking", offered_slots=slots[-1:]), trigger="follow_up", now="2026-11-18T22:30:00-07:00")
    test("on the demo clock, quiet hours don't apply", r["final_action"] == "offer_booking" and r["send_after"] is None, r)
    clock = table("settings", "id=eq.1&select=clock_mode")[0]["clock_mode"]
    request("PATCH", "settings?id=eq.1", {"clock_mode": "real"})
    try:
        r = check(lead, decision("offer_booking", offered_slots=slots[-1:]), trigger="follow_up", now="2026-11-18T22:30:00-07:00")
    finally:
        request("PATCH", "settings?id=eq.1", {"clock_mode": clock})
    test("on the real clock, a follow-up at 10:30pm waits until 8am",
         r["final_action"] == "offer_booking" and r["send_after"] is not None and r["send_after"].startswith("2026-11-19T15:00:00"), r["send_after"])
    r = check(lead, decision("offer_booking", offered_slots=slots[-1:]), trigger="follow_up", now="2026-11-18T11:00:00-07:00")
    test("a follow-up at 11am goes now", r["final_action"] == "offer_booking" and r["send_after"] is None, r)
    r = check(lead, decision("offer_booking", offered_slots=slots[-1:]), trigger="message", now="2026-11-18T23:00:00-07:00")
    test("a reply to a message the lead just sent ignores quiet hours",
         r["final_action"] == "offer_booking" and r["send_after"] is None, r)
    request("PATCH", f"leads?id=eq.{lead}", {"follow_ups_sent": 3})
    r = check(lead, decision("offer_booking", offered_slots=slots[:1]), trigger="follow_up")
    test("after 3 follow-ups the lead is closed as no_response",
         r["final_action"] == "close" and r["end_state"] == "no_response" and r["reply"] == "", r)

    for action in ("draft_price", "answer_question", "confirm_booking"):
        r = check(new_lead(), decision(action, price_code="water_heater_tank"), trigger="follow_up")
        test(f"a follow-up cannot use {action}", r["final_action"] == "hand_off" and r["reply"] == "", r)
    lead = new_lead()
    apply(lead, decision("offer_booking", offered_slots=slots[:1]))
    request("PATCH", f"leads?id=eq.{lead}", {"follow_up_claimed_at": "2099-01-01T00:00:00Z"})
    rpc("receive_message", p_source="form", p_channel="web", p_body="Yes please", p_lead_id=lead)
    out = apply(lead, decision("offer_booking", offered_slots=slots[:1]), trigger="follow_up")
    test("a follow-up is dropped if the lead replied while it was being written",
         out["stale"] and out["message_status"] is None, out)

    # The full loop: offer, the lead picks a slot, book it
    lead = new_lead()
    out = apply(lead, decision("offer_booking", offered_slots=slots[:2]))
    row = table("leads", f"id=eq.{lead}&select=status,awaiting_reply_since")[0]
    test("apply offer_booking: reply sent, lead active, waiting for a reply",
         out["message_status"] == "sent" and row["status"] == "active" and row["awaiting_reply_since"], (out, row))
    rpc("receive_message", p_source="form", p_channel="web", p_body="The first one works", p_lead_id=lead)
    row = table("leads", f"id=eq.{lead}&select=awaiting_reply_since")[0]
    test("the lead's reply clears the follow-up clock", row["awaiting_reply_since"] is None, row)
    context = rpc("get_agent_context", p_lead_id=lead)
    test("the conversation shows the offered slots",
         context["conversation"][1].get("offered_slots") == slots[:2], context["conversation"])
    out = apply(lead, decision("confirm_booking", slot=slots[0]))
    row = table("leads", f"id=eq.{lead}&select=status,end_state")[0]
    booked = table("slots", f"booked_lead_id=eq.{lead}&select=starts_at")
    test("apply confirm_booking: slot booked, lead booked",
         out["final_action"] == "confirm_booking" and row["status"] == "booked" and len(booked) == 1, (out, row))
    test("a booked slot is no longer offered", slots[0] not in rpc("open_slots"), "")
    out = apply(lead, decision("confirm_booking", slot=slots[0]))
    test("confirming the slot the lead already holds is fine", out["final_action"] == "confirm_booking", out)
    out = apply(lead, decision("confirm_booking", slot=slots[1]))
    booked = [b["starts_at"] for b in table("slots", f"booked_lead_id=eq.{lead}&select=starts_at")]
    test("picking another offered slot moves the booking (one slot per lead)",
         out["final_action"] == "confirm_booking" and len(booked) == 1 and slots[0] in rpc("open_slots"), (out, booked))
    for dec in (decision("answer_question"), decision("ask_question"), decision("decline"),
                decision("offer_booking", offered_slots=slots[2:3])):
        rpc("receive_message", p_source="form", p_channel="web", p_body="Another question", p_lead_id=lead)
        apply(lead, dec)
        row = table("leads", f"id=eq.{lead}&select=status,end_state,awaiting_reply_since")[0]
        test(f"a booked lead stays booked after {dec['action']}, with no follow-ups",
             row == {"status": "booked", "end_state": "booked", "awaiting_reply_since": None}, row)
    rpc("receive_message", p_source="form", p_channel="web", p_body="We don't need it any more", p_lead_id=lead)
    apply(lead, decision("close", end_state="not_interested"))
    test("cancelling frees the visit time", not table("slots", f"booked_lead_id=eq.{lead}&select=starts_at"), "")
    r = check(new_lead(), decision("confirm_booking", slot=slots[2]))
    test("booking a slot the lead was never offered becomes hand_off",
         r["final_action"] == "hand_off" and "slot was never offered to this lead" in r["violations"], r["violations"])

    # Prices wait for approval
    lead = new_lead()
    out = apply(lead, good_price)
    row = table("leads", f"id=eq.{lead}&select=status")[0]
    approval = table("approvals", f"lead_id=eq.{lead}&select=status")
    test("apply draft_price: message waits for approval, approval row created",
         out["message_status"] == "pending_approval" and out["approval_id"] and row["status"] == "waiting_approval"
         and approval and approval[0]["status"] == "pending", (out, row))
    context = rpc("get_agent_context", p_lead_id=lead)
    test("an unapproved price is not in the conversation", len(context["conversation"]) == 1, context["conversation"])

    rpc("receive_message", p_source="form", p_channel="web", p_body="What are your hours?", p_lead_id=lead)
    apply(lead, decision("answer_question"))
    row = table("leads", f"id=eq.{lead}&select=status,awaiting_reply_since")[0]
    test("a lead waiting on a price isn't chased for chatting meanwhile",
         row == {"status": "waiting_approval", "awaiting_reply_since": None}, row)
    newer = apply(lead, good_price)
    statuses = [a["status"] for a in table("approvals", f"lead_id=eq.{lead}&select=status&order=id")]
    test("a newer price withdraws the older one", statuses == ["withdrawn", "pending"], statuses)
    apply(lead, decision("close", end_state="not_interested"))
    done = rpc("resolve_approval", p_approval_id=newer["approval_id"], p_approved=True, p_decided_by="test")
    test("a price is never sent into a conversation that has ended", done["status"] == "withdrawn" and not done.get("send"), done)

    # Hand-offs and emergencies stop the agent
    lead = new_lead()
    apply(lead, decision("escalate_emergency", reply="Call (303) 555-0199 now.", owner_note="Burst pipe"))
    again = rpc("receive_message", p_source="form", p_channel="web", p_body="Are you coming?", p_lead_id=lead)
    test("after an emergency hand-off the agent stops replying", again["agent_should_reply"] is False, again)
    r = check(lead, decision("ask_question"))
    test("check on a handed-off lead sends nothing", r["final_action"] == "hand_off" and r["reply"] == "", r)

    # Finding the same person again
    email = f"guardrails-{uuid.uuid4().hex[:8]}@mail.example"
    first = rpc("receive_message", p_source="email", p_channel="email", p_body="Hi", p_name=TEST_NAME, p_email=email)
    second = rpc("receive_message", p_source="email", p_channel="email", p_body="Me again", p_name=TEST_NAME, p_email=email.upper())
    test("the same email within 30 days continues the same lead",
         first["lead_id"] == second["lead_id"] and second["is_new"] is False, (first, second))
    a = new_lead(p_email="same@mail.example")
    b = new_lead(p_email="same@mail.example")
    test("two visitors with the same email get separate leads", a != b, "")
    message_id = f"<{uuid.uuid4().hex}@mail.example>"
    rpc("receive_message", p_source="email", p_channel="email", p_body="Hi", p_name=TEST_NAME,
        p_email=f"guardrails-{uuid.uuid4().hex[:8]}@mail.example", p_external_id=message_id)
    again = rpc("receive_message", p_source="email", p_channel="email", p_body="Hi", p_name=TEST_NAME,
                p_email="x@mail.example", p_external_id=message_id)
    test("the same email message is never processed twice", again == {"duplicate": True}, again)
    state = lambda: rpc("email_states", p_ids=[message_id, "not-stored"])  # noqa: E731
    test("an email the agent just started on is busy", state() == [{"external_id": message_id, "state": "busy"}], state())
    stored = urllib.parse.quote(message_id)
    request("PATCH", f"messages?external_id=eq.{stored}", {"agent_attempted_at": "2026-01-01T00:00:00Z"})
    test("an email the agent failed on is due another try", state()[0]["state"] == "retry", state())
    again = rpc("receive_message", p_source="email", p_channel="email", p_body="Hi", p_name=TEST_NAME,
                p_email="x@mail.example", p_external_id=message_id)
    test("the second try continues the same lead", again["duplicate"] is False and again["attempts"] == 2, again)
    request("PATCH", f"messages?external_id=eq.{stored}", {"agent_attempted_at": "2026-01-01T00:00:00Z", "agent_attempts": 3})
    test("it gives up after 3 tries", state()[0]["state"] == "done", state())

    # Privacy: the public key can't read anything
    anon = urllib.request.Request(
        f"{ENV['SUPABASE_URL']}/rest/v1/leads?select=id&limit=1",
        headers={"apikey": ENV["SUPABASE_ANON_KEY"], "Authorization": f"Bearer {ENV['SUPABASE_ANON_KEY']}",
                 "Accept-Profile": SCHEMA})
    try:
        urllib.request.urlopen(anon, timeout=30)
        test("the public key can't read leads", False, "it could")
    except urllib.error.HTTPError as error:
        test("the public key can't read leads", error.code in (401, 403), error.code)

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
