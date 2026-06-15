# Demo-ERP — Clinic BD

A custom ERP for small hospitals and clinics in Bangladesh, built as a thin overlay app
(`clinic_bd/`) on top of [ERPNext](https://github.com/frappe/erpnext) +
[Frappe Health](https://github.com/frappe/health) on Frappe Framework v15. Core apps are
never modified — everything ships as custom fields, fixtures, reports, and hooks, so
upstream updates stay clean.

## What's in this repo

| Path | What it is |
| --- | --- |
| `clinic_bd/` | The Frappe app: NID + Bangla-name fields on Patient, BMDC reg. no + degrees on Healthcare Practitioner, the "Clinic Prescription" print format (default on install), the "Medicines Expiring Soon" report, and starter Bangla translations |
| `setup.sh` | One-shot bootstrap for fresh Ubuntu 22.04/24.04 (bare metal, VPS, or WSL2): MariaDB, Redis, frappe-bench, ERPNext, Frappe Health, this app, and a `clinic.localhost` site |
| `GETTING_STARTED.md` | Environment options, the 8-step end-to-end smoke test, a map of the code for Phase 2, and the prioritized backlog |

## Quick start

    git clone <this-repo> && cd Demo-ERP
    chmod +x setup.sh
    ./setup.sh                          # 20-40 minutes; needs ~4 GB RAM
    cd ~/frappe-bench && bench start    # then open http://clinic.localhost:8000

Read `GETTING_STARTED.md` first — it walks the whole loop from install to a printed
prescription and an expiry report.

## License

GPL-3.0 (see `clinic_bd/license.txt`), matching the apps this extends.
