frappe.query_reports["Medicines Expiring Soon"] = {
	filters: [
		{
			fieldname: "days",
			label: __("Expiring Within (Days)"),
			fieldtype: "Int",
			default: 90,
			reqd: 1,
		},
		{
			fieldname: "warehouse",
			label: __("Warehouse"),
			fieldtype: "Link",
			options: "Warehouse",
		},
	],
};
