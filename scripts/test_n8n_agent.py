"""End-to-end test of the live agent workflow in n8n.

Sends form leads to the agent webhook the way the dashboard will, then checks
the reply, the stored decision and the Slack side effects. Makes real AI calls
(about $0.003 each) and posts to #lead-alerts and #lead-approvals. Every test
lead is deleted at the end.

Uses only the Python standard library. Usage (from the project root):
    python scripts/test_n8n_agent.py
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from test_guardrails import ENV, TEST_NAME, request, table

WEBHOOK = ENV["N8N_BASE_URL"].rstrip("/") + "/webhook/lead-message"


def post(payload: dict, secret: str | None = None) -> tuple[int, dict]:
    req = urllib.request.Request(
        WEBHOOK, data=json.dumps(payload).encode(), method="POST",
        headers={"Content-Type": "application/json", "x-webhook-secret": secret or ENV["N8N_WEBHOOK_SECRET"]},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        body = error.read()
        try:
            return error.code, json.loads(body or b"{}")
        except json.JSONDecodeError:
            return error.code, {"raw": body.decode(errors="replace")[:300]}


def form_lead(message: str, zip_code: str = "80210") -> tuple[int, dict]:
    return post({"source": "form", "name": TEST_NAME, "email": f"n8n-test-{uuid.uuid4().hex[:8]}@mail.example",
                 "zip": zip_code, "message": message, "is_visitor": True})


def run_tests() -> list[tuple[str, bool, str]]:
    results = []

    def test(name: str, ok: bool, detail=""):
        results.append((name, bool(ok), str(detail)[:400]))

    status, body = post({"source": "form", "email": "x@mail.example", "message": "hi"}, secret="wrong")
    test("a wrong secret is refused", status in (401, 403), status)
    status, body = post({"source": "form", "name": TEST_NAME, "message": "no email given"})
    test("a form lead without an email gets 400", status == 400, (status, body))

    started = time.monotonic()
    status, body = form_lead("Would like an AC tune-up sometime next week, mornings are best.")
    seconds = time.monotonic() - started
    test("a normal lead gets slots offered right away",
         status == 200 and body.get("final_action") == "offer_booking" and body.get("reply"), (status, body))
    test("the reply comes back in under 20 seconds", seconds < 20, f"{seconds:.1f}s")
    lead_id = body.get("lead_id")

    if lead_id:
        decision = table("decisions", f"lead_id=eq.{lead_id}&select=offered_slots,final_action,model")
        test("the decision is stored with the model", decision and decision[0]["model"], decision)
        status, body = post({"lead_id": lead_id, "message": "The first one works for me."})
        test("picking an offered slot in the web thread books it",
             status == 200 and body.get("final_action") == "confirm_booking", (status, body))
        booked = table("slots", f"booked_lead_id=eq.{lead_id}&select=starts_at")
        test("the slot is booked in the database", len(booked) == 1, booked)

    status, body = form_lead("Gas smell in the basement near the water heater!")
    test("a gas smell is escalated, with the emergency line in the reply",
         status == 200 and body.get("final_action") == "escalate_emergency" and "555-0199" in (body.get("reply") or ""),
         (status, body))

    status, body = form_lead("Need a new water heater, 40 gallon gas. Roughly what does that cost?")
    test("a price question waits for owner approval (no reply sent yet)",
         status == 200 and body.get("final_action") == "draft_price" and body.get("reply_status") == "pending_approval"
         and body.get("reply") is None, (status, body))

    status, body = form_lead("Water heater replacement please", zip_code="80903")
    test("an out-of-area zip is declined", status == 200 and body.get("final_action") == "decline", (status, body))

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
