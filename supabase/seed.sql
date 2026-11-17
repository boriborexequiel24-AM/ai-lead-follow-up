-- Demo data for the fictional company. Everything here is made up.
-- Phone numbers use the 555-01xx range, which is reserved for fiction.
-- Safe to run more than once: it replaces the previous contents.

-- Company profile ----------------------------------------------------------
insert into leads.company_profile (
  id, name, phone, emergency_phone, email, timezone, business_hours,
  service_area_name, service_area_zips, services_offered, services_not_offered
) values (
  1,
  'Copperline Plumbing & Air',
  '(303) 555-0142',
  '(303) 555-0199',
  'hello@copperline.example',  -- display only; real mail goes through GMAIL_INTAKE_ADDRESS
  'America/Denver',
  'Monday to Friday 7am to 6pm, Saturday 8am to 2pm. Emergency line answered 24/7.',
  'Central and south Denver',
  array[
    '80202','80203','80204','80205','80206','80207','80209','80210','80211',
    '80212','80218','80219','80220','80222','80223','80224','80230','80231',
    '80237','80238','80246','80247'
  ],
  array[
    'Drain and sewer clearing', 'Leak and pipe repair', 'Toilets, faucets and fixtures',
    'Water heaters (tank and tankless)', 'Garbage disposals',
    'Furnace repair, tune-ups and replacement', 'AC repair, tune-ups and replacement'
  ],
  array[
    'Commercial or restaurant work', 'Septic tanks', 'Well pumps',
    'Appliance repair (fridges, washers, dishwashers)', 'Electrical work', 'Roofing'
  ]
)
on conflict (id) do update set
  name = excluded.name, phone = excluded.phone, emergency_phone = excluded.emergency_phone,
  email = excluded.email, timezone = excluded.timezone, business_hours = excluded.business_hours,
  service_area_name = excluded.service_area_name, service_area_zips = excluded.service_area_zips,
  services_offered = excluded.services_offered, services_not_offered = excluded.services_not_offered,
  updated_at = now();

-- FAQ (no dollar amounts allowed) -------------------------------------------
delete from leads.faq;
insert into leads.faq (topic, answer) values
  ('hours', 'We''re open Monday to Friday 7am to 6pm and Saturday 8am to 2pm. Our emergency line is answered 24/7.'),
  ('service area', 'We cover central and south Denver. Share your zip code and we''ll confirm we can get to you.'),
  ('brands', 'We service all major furnace, AC and water heater brands, including Carrier, Trane, Lennox, Rheem, A.O. Smith, Bradford White and Rinnai.'),
  ('warranty', 'All our work comes with a 1-year labor warranty. New equipment also carries the manufacturer''s parts warranty.'),
  ('financing', 'Financing is available on larger jobs like water heater, furnace and AC replacements, subject to approval.'),
  ('licensing', 'We''re licensed and insured, and every technician is background-checked.'),
  ('payment', 'We accept all major cards, checks and ACH. Payment is due when the job is finished.'),
  ('estimates', 'Estimates for replacements and new installs are free and done in your home. For repairs, the service call fee is credited toward the repair if you go ahead.'),
  ('commercial', 'We only work on homes, not commercial properties or restaurants.'),
  ('same day', 'We often have same-day or next-day openings for repairs. Emergencies are handled around the clock.');

-- Sample price sheet ----------------------------------------------------------
delete from leads.price_items;
insert into leads.price_items (code, trade, job, low_price, high_price, notes) values
  ('service_call',        'plumbing', 'Service call and diagnosis',                 89,    89, 'Credited toward the repair if the customer goes ahead. Same fee for HVAC.'),
  ('drain_clearing',      'plumbing', 'Sink, tub or shower drain clearing',        150,   300, null),
  ('sewer_clearing',      'plumbing', 'Main sewer line clearing',                  250,   600, 'Camera inspection extra if needed.'),
  ('leak_repair',         'plumbing', 'Leak repair on an accessible pipe',         200,   550, 'Pipes inside walls or slabs need an in-person look.'),
  ('toilet_repair',       'plumbing', 'Toilet repair (running, leaking, clogged)', 125,   350, null),
  ('toilet_replacement',  'plumbing', 'Toilet replacement, standard model',        450,   900, 'Includes removing the old toilet.'),
  ('faucet_replacement',  'plumbing', 'Faucet replacement',                        200,   450, 'Customer-supplied faucets at the low end.'),
  ('disposal_replacement','plumbing', 'Garbage disposal replacement',              300,   550, null),
  ('water_heater_tank',   'plumbing', 'Water heater replacement, 40-50 gal tank', 1400,  2200, 'Includes haul-away and permit.'),
  ('water_heater_tankless','plumbing','Tankless water heater install',            3200,  5500, 'Gas line or venting upgrades can add to this.'),
  ('furnace_tuneup',      'hvac',     'Furnace tune-up',                            99,   149, null),
  ('ac_tuneup',           'hvac',     'AC tune-up',                                 99,   149, null),
  ('furnace_repair',      'hvac',     'Furnace repair, common parts',              250,   900, null),
  ('ac_repair',           'hvac',     'AC repair, common parts',                   250,  1000, null),
  ('furnace_replacement', 'hvac',     'Furnace replacement',                      4500,  8000, 'Free in-home estimate first.'),
  ('ac_replacement',      'hvac',     'Central AC replacement',                   5500, 10000, 'Free in-home estimate first.');
