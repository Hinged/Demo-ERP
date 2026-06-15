import frappe
from frappe import _
from frappe.utils import add_days, cint, date_diff, nowdate


def execute(filters=None):
    filters = frappe._dict(filters or {})
    # 0 is a valid choice ("already due today or expired"), so only fall
    # back to 90 when the filter is actually absent.
    days = filters.get("days")
    days = 90 if days in (None, "") else cint(days)
    return get_columns(), get_data(days, filters.get("warehouse"))


def get_columns():
    return [
        {"fieldname": "item_code", "label": _("Item"), "fieldtype": "Link", "options": "Item", "width": 140},
        {"fieldname": "item_name", "label": _("Item Name"), "fieldtype": "Data", "width": 200},
        {"fieldname": "batch_no", "label": _("Batch"), "fieldtype": "Link", "options": "Batch", "width": 150},
        {"fieldname": "warehouse", "label": _("Warehouse"), "fieldtype": "Link", "options": "Warehouse", "width": 160},
        {"fieldname": "qty", "label": _("Qty On Hand"), "fieldtype": "Float", "width": 110},
        {"fieldname": "expiry_date", "label": _("Expiry Date"), "fieldtype": "Date", "width": 110},
        {"fieldname": "days_left", "label": _("Days Left"), "fieldtype": "Int", "width": 90},
    ]


def get_data(days, warehouse=None):
    # erpnext's own helper computes batch-wise stock correctly on every
    # supported version, including the v15 serial/batch bundle rework.
    from erpnext.stock.doctype.batch.batch import get_batch_qty

    limit_date = add_days(nowdate(), days)

    batches = frappe.get_all(
        "Batch",
        filters=[
            ["expiry_date", "is", "set"],
            ["expiry_date", "<=", limit_date],
            ["disabled", "=", 0],
        ],
        fields=["name", "item", "expiry_date"],
        order_by="expiry_date asc",
    )

    rows = []
    for batch in batches:
        # Passing item_code spares the helper a per-batch lookup of its item.
        qty_by_warehouse = get_batch_qty(batch_no=batch.name, item_code=batch.item) or []

        # Older versions return a plain number when only batch_no is passed.
        if isinstance(qty_by_warehouse, (int, float)):
            qty_by_warehouse = [{"warehouse": None, "qty": qty_by_warehouse}]

        for entry in qty_by_warehouse:
            qty = entry.get("qty") or 0
            if qty <= 0:
                continue
            if warehouse and entry.get("warehouse") != warehouse:
                continue

            rows.append(
                {
                    "item_code": batch.item,
                    "item_name": frappe.get_cached_value("Item", batch.item, "item_name")
                    if batch.item
                    else None,
                    "batch_no": batch.name,
                    "warehouse": entry.get("warehouse"),
                    "qty": qty,
                    "expiry_date": batch.expiry_date,
                    # Negative means the batch has already expired.
                    "days_left": date_diff(batch.expiry_date, nowdate()),
                }
            )

    return rows
