package com.bach.sms;

import org.json.JSONException;
import org.json.JSONObject;

final class Job {
    final String id;
    final String cif;
    final String contract;
    final String name;
    final String phone;

    Job(String id, String cif, String contract, String name, String phone) {
        this.id = value(id);
        this.cif = value(cif);
        this.contract = value(contract);
        this.name = value(name);
        this.phone = value(phone);
    }

    static Job fromJson(JSONObject object) {
        return new Job(
            object.optString("id"),
            object.optString("cif"),
            object.optString("contract_number"),
            object.optString("customer_name"),
            object.optString("phone")
        );
    }

    JSONObject toJson() throws JSONException {
        JSONObject object = new JSONObject();
        object.put("id", id);
        object.put("cif", cif);
        object.put("contract_number", contract);
        object.put("customer_name", name);
        object.put("phone", phone);
        return object;
    }

    String display() {
        String customer = name.isEmpty() ? "Khách hàng" : name;
        String extra = contract.isEmpty() ? cif : cif + " · " + contract;
        return customer + "\n" + phone + "   " + extra;
    }

    String applyTemplate(String template) {
        return value(template)
            .replace("{ten}", name.isEmpty() ? "anh/chị" : name)
            .replace("{cif}", cif)
            .replace("{hopdong}", contract);
    }

    private static String value(String input) {
        return input == null ? "" : input.trim();
    }
}
