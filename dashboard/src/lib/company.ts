// The fictional company, as shown on the site. Matches supabase/seed.sql,
// which is what the agent itself reads.

export const COMPANY = {
  name: "Copperline Plumbing & Air",
  area: "Plumbing, heating and cooling in central and south Denver",
  phone: "(303) 555-0142",
  emergencyPhone: "(303) 555-0199",
  hours: "Mon to Fri 7am to 6pm, Sat 8am to 2pm",
  services: [
    "Drain and sewer clearing",
    "Leak and pipe repair",
    "Toilets, faucets and fixtures",
    "Water heaters (tank and tankless)",
    "Garbage disposals",
    "Furnace repair, tune-ups and replacement",
    "AC repair, tune-ups and replacement",
  ],
};

// Ready-made leads for the "Try a scenario" buttons. Each one shows a
// different decision the agent has to make.
export type Scenario = {
  id: string;
  label: string;
  shows: string;
  name: string;
  email: string;
  zip: string;
  message: string;
};

export const SCENARIOS: Scenario[] = [
  {
    id: "burst-pipe",
    label: "Burst pipe",
    shows: "Treats it as an emergency: gives the 24/7 line and alerts the owner.",
    name: "Dana Whitfield",
    email: "dana@example.com",
    zip: "80209",
    message: "Water is spraying out of a pipe under the kitchen sink and I can't find the shutoff. Can someone come right now?",
  },
  {
    id: "tune-up",
    label: "Book a tune-up",
    shows: "Offers real open times, then books the one you pick.",
    name: "Jordan Ellis",
    email: "jordan@example.com",
    zip: "80206",
    message: "Can I get a furnace tune-up sometime next week? Mornings work best for me.",
  },
  {
    id: "price",
    label: "Price shopper",
    shows: "Drafts a price from the price sheet, but the owner has to approve it first.",
    name: "Sam Ortega",
    email: "sam@example.com",
    zip: "80210",
    message: "Roughly how much do you charge to replace a 50 gallon gas water heater? Just looking for a ballpark.",
  },
  {
    id: "out-of-area",
    label: "Out of the area",
    shows: "Checks the zip against the service area and declines politely.",
    name: "Riley Chen",
    email: "riley@example.com",
    zip: "80504",
    message: "Our AC stopped blowing cold air. We're up in Longmont. Do you come out this far?",
  },
  {
    id: "vague",
    label: "Vague message",
    shows: "Asks one short question instead of guessing.",
    name: "Alex Moreno",
    email: "alex@example.com",
    zip: "",
    message: "Hi, I need some help with something at the house.",
  },
];
