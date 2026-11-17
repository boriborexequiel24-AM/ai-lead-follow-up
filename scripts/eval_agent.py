"""Score the lead agent against the labelled sample leads.

Runs every case in sample-leads/ through the same two steps n8n will run,
using the prompts and schemas in agent/:
  1. read:   turn the lead into fixed facts (agent/read_*)
  2. rule:   check the zip against the service area (code, not AI)
  3. decide: pick one action from the menu and write the reply (agent/decide_*)

The company profile, FAQ and price sheet are read live from Supabase (leads
schema), so the eval tests the real data.

Reports, per model: action accuracy, fact accuracy, reply checks, speed and
cost. Writes a summary to docs/agent-eval.md and raw output to
scripts/eval-results/ (not committed).

Uses only the Python standard library. Usage (from the project root):
    python scripts/eval_agent.py --models gpt-5.4-nano gpt-5.4-mini
    python scripts/eval_agent.py --models gpt-5.4-mini --only L02 C05
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent"
SAMPLES = ROOT / "sample-leads"
RESULTS_DIR = ROOT / "scripts" / "eval-results"
REPORT = ROOT / "docs" / "agent-eval.md"

READ_PROMPT = (AGENT / "read_prompt.md").read_text(encoding="utf-8")
READ_SCHEMA = json.loads((AGENT / "read_schema.json").read_text(encoding="utf-8"))
DECIDE_PROMPT = (AGENT / "decide_prompt.md").read_text(encoding="utf-8")
DECIDE_SCHEMA = json.loads((AGENT / "decide_schema.json").read_text(encoding="utf-8"))

# USD per 1M tokens: (input, cached input, output).
# Source: developers.openai.com/api/docs/pricing, standard tier, checked 2026-11-13.
PRICES = {
    "gpt-5.5": (5.00, 0.50, 30.00),
    "gpt-5.4-mini": (0.75, 0.075, 4.50),
    "gpt-5.4-nano": (0.20, 0.02, 1.25),
    "gpt-4.1-mini": (0.40, 0.10, 1.60),
}

FACT_FIELDS = ["is_real_lead", "trade", "job_type", "urgency", "wants_price"]


def load_env() -> dict[str, str]:
    values = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        match = re.match(r"^\s*([A-Z0-9_]+)=(.*)$", line)
        if match:
            values[match.group(1)] = match.group(2).strip().strip('"').strip("'")
    return values


# ---------- Company data (Supabase) ----------

def fetch_company(env: dict) -> dict:
    """Read the profile, FAQ and price sheet from the leads schema."""
    def get(table: str, query: str) -> list:
        request = urllib.request.Request(
            f"{env['SUPABASE_URL']}/rest/v1/{table}?{query}",
            headers={
                "apikey": env["SUPABASE_SERVICE_ROLE_KEY"],
                "Authorization": f"Bearer {env['SUPABASE_SERVICE_ROLE_KEY']}",
                "Accept-Profile": env.get("SUPABASE_SCHEMA", "leads"),
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())

    profile = get("company_profile", "select=*")[0]
    return {
        "company": {
            key: profile[key] for key in (
                "name", "phone", "emergency_phone", "business_hours", "service_area_name",
                "services_offered", "services_not_offered", "timezone",
            )
        },
        "service_area_zips": set(profile["service_area_zips"]),
        "faq": get("faq", "select=topic,answer&order=id"),
        "price_sheet": get("price_items", "select=code,trade,job,low_price,high_price,notes&order=id"),
    }


# ---------- Building the inputs ----------

def make_slots(after: datetime, days: int = 6) -> list[str]:
    """Fake open visit slots on the next few working days (Mon-Sat), as the slots table will hold."""
    slots, day = [], after
    while len({s[:10] for s in slots}) < days:
        day = (day + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        if day.weekday() == 6:  # closed Sunday
            continue
        hours = [8, 10] if day.weekday() == 5 else [8, 10, 13, 15]
        slots += [day.replace(hour=h).isoformat() for h in hours]
    return slots


def case_inputs(case: dict) -> dict:
    """Normalise a single lead or a conversation into the lead record, conversation and 'now'."""
    if "turns" in case:
        lead = dict(case["lead"])
        conversation = [dict(t) for t in case["turns"]]
    else:
        lead = {k: case[k] for k in ("source", "name", "email", "phone", "zip", "subject") if case.get(k)}
        conversation = [{"from": "lead", "at": case["received_at"], "text": case["message"]}]
    now = conversation[-1]["at"]
    offered = [s for t in conversation for s in t.get("offered_slots", [])]
    open_slots = sorted(set(make_slots(datetime.fromisoformat(now)) + offered))
    return {"lead": lead, "conversation": conversation, "now": now, "open_slots": open_slots}


# ---------- Calling OpenAI ----------

def call_openai(api_key: str, model: str, effort: str, instructions: str, payload: dict,
                schema: dict, name: str) -> dict:
    body = {
        "model": model,
        "instructions": instructions,
        "input": [{"role": "user", "content": [{"type": "input_text", "text": json.dumps(payload, ensure_ascii=False)}]}],
        "text": {"format": {"type": "json_schema", "name": name, "schema": schema, "strict": True}},
    }
    if model.startswith(("gpt-5", "o")):
        body["reasoning"] = {"effort": effort}
    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    started = time.monotonic()
    for attempt in range(4):  # retries only on rate limits and server errors, never on success
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                result = json.loads(response.read())
            break
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:500]
            if error.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(2 ** attempt * 3)
                continue
            raise RuntimeError(f"HTTP {error.code}: {detail}") from None
    text = next(
        part["text"]
        for item in result["output"] if item.get("type") == "message"
        for part in item["content"] if part.get("type") == "output_text"
    )
    return {"data": json.loads(text), "usage": result.get("usage", {}), "seconds": time.monotonic() - started}


def cost_usd(model: str, usage: dict) -> float | None:
    if model not in PRICES:
        return None
    price_in, price_cached, price_out = PRICES[model]
    cached = usage.get("input_tokens_details", {}).get("cached_tokens", 0)
    fresh = usage.get("input_tokens", 0) - cached
    return (fresh * price_in + cached * price_cached + usage.get("output_tokens", 0) * price_out) / 1_000_000


def run_agent(api_key: str, model: str, effort: str, company: dict, case: dict) -> dict:
    """The full agent turn: read, service-area rule, decide."""
    inputs = case_inputs(case)
    read = call_openai(api_key, model, effort, READ_PROMPT,
                       {"lead": inputs["lead"], "conversation": inputs["conversation"]}, READ_SCHEMA, "lead_facts")
    facts = dict(read["data"])
    zip_code = facts.get("zip")
    facts["in_service_area"] = None if not zip_code else zip_code in company["service_area_zips"]

    decide = call_openai(api_key, model, effort, DECIDE_PROMPT, {
        "company": company["company"],
        "faq": company["faq"],
        "price_sheet": company["price_sheet"],
        "now": inputs["now"],
        "facts": facts,
        "open_slots": inputs["open_slots"],
        "conversation": inputs["conversation"],
    }, DECIDE_SCHEMA, "next_step")
    return {
        "facts": facts,
        "decision": decide["data"],
        "open_slots": inputs["open_slots"],
        "seconds": read["seconds"] + decide["seconds"],
        "cost": sum(c for c in (cost_usd(model, read["usage"]), cost_usd(model, decide["usage"])) if c is not None),
    }


# ---------- Scoring ----------

def matches(want, got) -> bool:
    return got in want if isinstance(want, list) else got == want


def score(case: dict, result: dict) -> dict:
    """Pass/fail per check. Conversations are scored on the action (and slot) only."""
    expected, facts, decision = case["expected"], result["facts"], result["decision"]
    checks = {"action": decision["action"] in [expected["action"], *expected.get("also_ok", [])]}

    if "turns" not in case:
        checks["is_real_lead"] = facts["is_real_lead"] == expected["is_real_lead"]
        if expected["is_real_lead"]:  # trade and job type mean little for spam
            for field in FACT_FIELDS[1:]:
                checks[field] = matches(expected[field], facts[field])
            checks["missing_info"] = set(expected["missing_info"]) <= set(facts["missing_info"])
        if "zip" in expected:
            checks["zip"] = facts["zip"] == expected["zip"]
        if "language" in expected:
            checks["language"] = facts["language"] == expected["language"]

    if "price_code" in expected and decision["action"] == "draft_price":
        checks["price_code"] = decision["price_code"] == expected["price_code"]
    if "slot" in expected and decision["action"] == "confirm_booking":
        checks["slot"] = decision["slot"] == expected["slot"]
    if "end_state" in expected and decision["action"] == expected["action"]:
        checks["end_state"] = decision["end_state"] == expected["end_state"]

    for rule in expected.get("reply_checks", []):
        found = re.search(rule["pattern"], decision["reply"], re.IGNORECASE) is not None
        checks[f"reply: {rule['label']}"] = not found if rule.get("must_not") else found

    # Checks every case gets. The phase 4 guardrails enforce these too; here
    # they show how often the model would have needed stopping.
    if decision["action"] != "draft_price":
        checks["no unapproved price"] = re.search(r"\$\s?\d", decision["reply"]) is None
    checks["no em dashes"] = "—" not in decision["reply"]
    if decision["offered_slots"] or decision["slot"]:
        offered = set(decision["offered_slots"]) | ({decision["slot"]} if decision["slot"] else set())
        checks["slots are real"] = offered <= set(result["open_slots"])
    return checks


# ---------- Running ----------

def run_one(api_key: str, model: str, effort: str, company: dict, case: dict) -> dict:
    try:
        result = run_agent(api_key, model, effort, company, case)
    except Exception as error:  # report the failure and keep going
        return {"model": model, "id": case["id"], "error": str(error)}
    checks = score(case, result)
    return {
        "model": model,
        "id": case["id"],
        "expected_action": case["expected"]["action"],
        "checks": checks,
        "passed": sum(checks.values()),
        "total_checks": len(checks),
        **result,
    }


def summarize(model: str, rows: list[dict]) -> dict:
    ok = [r for r in rows if "error" not in r]
    return {
        "model": model,
        "cases": len(rows),
        "errors": len(rows) - len(ok),
        "action_right": sum(r["checks"]["action"] for r in ok),
        "all_checks": sum(r["passed"] for r in ok) / max(1, sum(r["total_checks"] for r in ok)),
        "perfect": sum(r["passed"] == r["total_checks"] for r in ok),
        "avg_seconds": sum(r["seconds"] for r in ok) / max(1, len(ok)),
        "cost_per_lead": sum(r["cost"] for r in ok) / max(1, len(ok)),
    }


def write_report(summaries: list[dict], rows: list[dict], effort: str) -> None:
    lines = [
        "# Agent accuracy test",
        "",
        f"Run on {datetime.now():%Y-%m-%d %H:%M} with `scripts/eval_agent.py` (reasoning effort: {effort}).",
        "Each case runs the full agent turn: read the lead, check the service area, pick the next step.",
        "The answer key is in `sample-leads/` (22 first messages, 7 conversations).",
        "",
        "| Model | Right action | All checks | Perfect cases | Avg time | Cost per lead turn | Errors |",
        "|---|---|---|---|---|---|---|",
    ]
    for s in summaries:
        lines.append(
            f"| {s['model']} | {s['action_right']} / {s['cases'] - s['errors']} | {s['all_checks']:.1%} "
            f"| {s['perfect']} / {s['cases'] - s['errors']} | {s['avg_seconds']:.1f}s "
            f"| ${s['cost_per_lead']:.4f} | {s['errors']} |"
        )
    lines += ["", "## Misses", ""]
    misses = [r for r in rows if "error" in r or r["passed"] < r["total_checks"]]
    if not misses:
        lines.append("None. Every model passed every check.")
    for r in sorted(misses, key=lambda r: (r["model"], r["id"])):
        if "error" in r:
            lines.append(f"- **{r['model']}, {r['id']}:** error: {r['error'][:200]}")
            continue
        failed = ", ".join(k for k, v in r["checks"].items() if not v)
        lines.append(
            f"- **{r['model']}, {r['id']}:** failed {failed}. Picked `{r['decision']['action']}` "
            f"(expected `{r['expected_action']}`): {r['decision']['reason']}"
        )
    # Keep the hand-written notes below the marker across reruns.
    marker = "## How the model was chosen"
    old = REPORT.read_text(encoding="utf-8") if REPORT.exists() else ""
    notes = old[old.index(marker):] if marker in old else ""
    REPORT.write_text("\n".join(lines) + "\n" + ("\n" + notes if notes else ""), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--models", nargs="+", default=["gpt-5.4-mini"])
    parser.add_argument("--effort", default="low", help="reasoning effort for gpt-5 models")
    parser.add_argument("--only", nargs="*", help="case id prefixes, e.g. L02 C05")
    parser.add_argument("--no-report", action="store_true", help="don't overwrite docs/agent-eval.md")
    args = parser.parse_args()

    env = load_env()
    company = fetch_company(env)
    cases = [*json.loads((SAMPLES / "leads.json").read_text(encoding="utf-8")),
             *json.loads((SAMPLES / "conversations.json").read_text(encoding="utf-8"))]
    if args.only:
        cases = [c for c in cases if any(c["id"].startswith(p) for p in args.only)]

    jobs = [(m, c) for m in args.models for c in cases]
    print(f"Running {len(cases)} cases on {', '.join(args.models)}...")
    with ThreadPoolExecutor(max_workers=8) as pool:
        rows = list(pool.map(lambda job: run_one(env["OPENAI_API_KEY"], job[0], args.effort, company, job[1]), jobs))

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    (RESULTS_DIR / f"agent-{stamp}.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False), encoding="utf-8")

    summaries = [summarize(m, [r for r in rows if r["model"] == m]) for m in args.models]
    for s in summaries:
        print(f"{s['model']}: action {s['action_right']}/{s['cases'] - s['errors']}, all checks {s['all_checks']:.1%}, "
              f"perfect {s['perfect']}, {s['avg_seconds']:.1f}s, ${s['cost_per_lead']:.4f}/lead, errors {s['errors']}")
    for r in rows:
        if "error" in r:
            print(f"  ERROR {r['model']} {r['id']}: {r['error'][:200]}")
        elif r["passed"] < r["total_checks"]:
            failed = ", ".join(k for k, v in r["checks"].items() if not v)
            print(f"  MISS {r['model']} {r['id']}: {failed} | got {r['decision']['action']} | {r['decision']['reason']}")
    if not args.no_report:
        write_report(summaries, rows, args.effort)
        print(f"Report: {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
