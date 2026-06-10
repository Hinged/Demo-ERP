# Clinic BD — Getting Started

You now have the v0.1 skeleton of your product. This guide takes you from these files to a
running system with a printed prescription in your hand, in order, without skipped steps.

## 1. What you have

Three things sit in this package. `clinic_bd.zip` is your actual product: a custom Frappe app
that installs on top of ERPNext + Frappe Health and never touches their code. `setup.sh` is a
bootstrap script that builds the entire stack on a fresh Ubuntu machine. This guide is the map.

Inside the app, the working features are: Bangladesh-specific fields (NID number and Bangla
name on Patient, BMDC registration number and a degree summary on Healthcare Practitioner),
a "Clinic Prescription" print format for Patient Encounter that becomes the default print
automatically on install, a "Medicines Expiring Soon" report that lists batches with stock on
hand expiring within N days, and a starter Bangla translation file showing the localization
mechanism. Small, but each one is a real selling point you'll demo to a clinic.

## 2. Set up your environment

You need Ubuntu 22.04 or 24.04. Three ways to get it, pick one:

1. **Windows machine (most likely your case):** install WSL2. In PowerShell as admin run
   `wsl --install -d Ubuntu-24.04`, reboot, create your Linux username. All remaining steps
   happen inside the Ubuntu terminal.
2. **A cheap VPS** (1-2k BDT/month tier from DigitalOcean, Hetzner, or a local provider) with
   at least 4 GB RAM. This doubles later as your demo server for clinics.
3. **Mac/Linux laptop:** a Multipass or VirtualBox Ubuntu VM with 4 GB RAM works fine.

## 3. Install the stack

Clone this repository (or copy it) into your home directory — `setup.sh` and the `clinic_bd/`
folder must sit side by side, which is exactly how the repo is laid out. Then, from the
repo root:

    chmod +x setup.sh
    ./setup.sh

It will ask you to choose two passwords (database root, site Administrator), then run for
20-40 minutes. The slow part is the JavaScript asset build — that's normal. If a step fails,
read the error, fix it, and re-run; every stage is a plain command you can also run by hand.

When it finishes:

    cd ~/frappe-bench
    bench start

Open http://clinic.localhost:8000 and log in as `Administrator` with your chosen password.
The setup wizard appears once: pick country Bangladesh, currency BDT, and your clinic's name
as the company. Domain/module selection can stay default — Healthcare is already installed.

## 4. The smoke test — run your product end to end

Do this full loop once. It is the same loop you will later demo to a clinic owner, so knowing
it cold matters more than any feature. Use the search bar (top) to jump to each doctype.

1. **Healthcare Practitioner:** create one — a fictional Dr. Rahman. Fill in the two fields
   your app added: BMDC Registration No and Degrees. These print on the prescription.
2. **Patient:** create one. Note your custom NID Number and Patient Name (Bangla) fields.
3. **Item (the medicine):** create e.g. "Napa 500mg". Tick "Has Batch No" and
   "Has Expiry Date", and set "Include Item In Manufacturing" off. Unit: Nos or Strip.
4. **Stock Entry (receive stock):** type Material Receipt, add the item, qty 100, target
   warehouse Stores, and create a new Batch with an expiry date ~2 months out. Submit.
5. **Patient Appointment:** book the patient with Dr. Rahman, today.
6. **Patient Encounter:** create from the appointment (or directly). Add a symptom, a
   diagnosis, and 2-3 rows in Drug Prescription with dosage and duration. Save, then Submit.
7. **Print it:** the print button should already show **Clinic Prescription** — doctor block
   with BMDC number top-left, your clinic top-right, complaints and diagnosis in the left
   rail, Rx list on the right, signature line at the bottom.
8. **The inventory payoff:** open the **Medicines Expiring Soon** report, set days to 90.
   Your Napa batch appears with quantity on hand and days left. This single screen — "which
   medicines will I lose money on" — is something most small pharmacies track in a notebook.

If all eight steps work, you have a functioning product core.

## 5. Where everything lives (your Phase 2 map)

All your code is in `apps/clinic_bd` inside the bench. The pieces:

- `clinic_bd/hooks.py` — the app's wiring: dependencies, fixtures, install hook.
- `clinic_bd/fixtures/custom_field.json` — the extra fields. To add more: make the field in
  the UI (Customize Form), set its Module to "Clinic BD", then run
  `bench --site clinic.localhost export-fixtures` and commit the updated JSON.
- `clinic_bd/fixtures/prescription_source.html` — the editable prescription layout. After
  editing, regenerate the installable fixture from inside the `fixtures/` folder:
  `python3 -c "import json;h=open('prescription_source.html').read();d=json.load(open('print_format.json'));d[0]['html']=h;json.dump(d,open('print_format.json','w'),indent=1,ensure_ascii=False)"`
  then `bench --site clinic.localhost migrate`. (During development it's even easier to edit
  the Print Format directly in the UI and export-fixtures afterward.)
- `clinic_bd/clinic_bd/report/medicines_expiring_soon/` — the report. The `.py` is the
  logic, the `.js` is the filter UI. Copy this folder as a template for every future report.
- `clinic_bd/translations/bn.csv` — add `English text,বাংলা` lines, then run
  `bench --site clinic.localhost migrate` and switch the user's language to Bangla to test.

The golden rule from our design stands: nothing ever gets edited inside `apps/erpnext`,
`apps/frappe`, or `apps/healthcare`. If you feel the urge, the answer is a custom field,
property setter, hook, or override in `clinic_bd` instead.

## 6. Sharp edges to know about

Field names in the prescription template target Frappe Health version-15. If a child-table
column prints blank (for example a drug name), the field name drifted between releases: open
the doctype in the UI, check the real fieldname, and fix it in `prescription_source.html` —
the template already falls back gracefully instead of crashing. The Ubuntu-packaged
wkhtmltopdf renders this layout fine but has known quirks with repeating headers on multi-page
PDFs; ignore until a clinic actually needs 2-page prescriptions. Bench needs ~4 GB RAM —
asset builds die mysteriously below that. And the licensing note from our design discussion
applies: this stack is GPL-3.0, which is fine for selling hosted access and services; get
proper advice before distributing modified code to a customer's own servers.

## 7. Phase 2 backlog (in priority order)

First, full Bangla print: collect the real phrases a clinic uses and extend `bn.csv` plus the
prescription layout. Second, a reorder-shortage report (same template as the expiry report,
driven by Item reorder levels). Third, simplified role setup: a Receptionist role that can
register patients and book appointments but cannot open clinical notes. Fourth, a one-page
"daily collections" report for the owner. Fifth — only after a pilot clinic asks — SMS
appointment reminders via a local gateway. Resist building any of these before the smoke test
above runs clean on your machine.
