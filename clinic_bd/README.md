# Clinic BD

A Bangladesh-focused clinic management layer that installs on top of ERPNext + Frappe Health.
This app never modifies core code — everything ships as fixtures, reports, and hooks, so
upstream ERPNext / Frappe Health updates remain clean.

What's inside (v0.1.0):

- Custom fields: NID number and Bangla name on Patient; BMDC registration number and a
  printable degree summary on Healthcare Practitioner.
- "Clinic Prescription" print format for Patient Encounter, laid out like a standard
  Dhaka chamber prescription, set as the default automatically on install.
- "Medicines Expiring Soon" report: batches with stock on hand expiring within N days,
  filterable by warehouse. Negative "days left" means already expired.
- A starter Bangla translation file (`clinic_bd/translations/bn.csv`) showing the
  localization mechanism.

Install (assumes a working bench with erpnext + healthcare already fetched):

    bench get-app /path/to/clinic_bd
    bench --site yoursite install-app clinic_bd

See GETTING_STARTED.md (shipped alongside this app) for the full environment setup,
smoke test, and roadmap. License: GPL-3.0, matching the apps this extends.
