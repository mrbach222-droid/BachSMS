package com.bach.sms;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

final class CrmClient {
    private CrmClient() {}

    static String pair(String baseUrl, String crmCode, String deviceId, String deviceName) throws Exception {
        JSONObject body = new JSONObject();
        body.put("crm_code", crmCode);
        body.put("device_id", deviceId);
        body.put("device_name", deviceName);
        JSONObject response = new JSONObject(request(baseUrl, "POST", "/api/v1/pair", body, null, null));
        String token = response.optString("token");
        if (token.isEmpty()) throw new IllegalStateException("CRM không trả mã ghép nối.");
        return token;
    }

    static JSONArray jobs(String baseUrl, String token, String deviceId) throws Exception {
        String path = "/api/v1/jobs?device_id=" + java.net.URLEncoder.encode(deviceId, "UTF-8");
        JSONObject response = new JSONObject(request(baseUrl, "GET", path, null, token, deviceId));
        return response.optJSONArray("jobs") == null ? new JSONArray() : response.getJSONArray("jobs");
    }

    static void received(String baseUrl, String token, JSONArray jobs) throws Exception {
        JSONArray ids = new JSONArray();for(int i=0;i<jobs.length();i++)ids.put(jobs.getJSONObject(i).getString("id"));
        request(baseUrl,"POST","/api/v1/received",new JSONObject().put("job_ids",ids),token,null);
    }

    static synchronized void postStatus(
        android.content.Context context,
        String baseUrl,
        String token,
        String deviceId,
        Job job,
        String status
    ) throws Exception {
        JSONObject event = new JSONObject();
        event.put("id", java.util.UUID.randomUUID().toString());
        event.put("job_id", job.id);
        event.put("device_id", deviceId);
        event.put("status", status);
        event.put("occurred_at", isoNow());
        event.put("message_fingerprint", "");

        android.content.SharedPreferences prefs=context.getSharedPreferences("bach_sms_status_outbox",0);
        String key=statusScope(baseUrl,token);
        JSONArray events=new JSONArray(prefs.getString(key,"[]"));events.put(event);
        if(!prefs.edit().putString(key,events.toString()).commit())throw new Exception("Chưa lưu được trạng thái SMS trên điện thoại.");
        flushStatuses(context,baseUrl,token,deviceId);
    }

    private static String statusScope(String base,String token) throws Exception {
        byte[] hash=java.security.MessageDigest.getInstance("SHA-256").digest((base+"|"+token).getBytes(StandardCharsets.UTF_8));
        StringBuilder out=new StringBuilder();for(byte b:hash)out.append(String.format("%02x",b&255));return out.toString();
    }
    static synchronized void flushStatuses(android.content.Context context,String base,String token,String deviceId) throws Exception {
        android.content.SharedPreferences prefs=context.getSharedPreferences("bach_sms_status_outbox",0);String key=statusScope(base,token);
        JSONArray events=new JSONArray(prefs.getString(key,"[]"));
        while(events.length()>0){JSONArray sending=new JSONArray();for(int i=0;i<Math.min(20,events.length());i++)sending.put(events.getJSONObject(i));
            JSONObject result=new JSONObject(request(base,"POST","/api/v1/statuses",new JSONObject().put("events",sending),token,deviceId));
            JSONArray accepted=result.optJSONArray("accepted_ids");if(accepted==null||accepted.length()==0)throw new Exception("CRM chưa xác nhận trạng thái SMS.");
            java.util.HashSet<String> ids=new java.util.HashSet<>();for(int i=0;i<accepted.length();i++)ids.add(accepted.getString(i));JSONArray remaining=new JSONArray();
            for(int i=0;i<events.length();i++)if(!ids.contains(events.getJSONObject(i).getString("id")))remaining.put(events.getJSONObject(i));
            if(remaining.length()==events.length())throw new Exception("CRM chưa xác nhận đúng trạng thái SMS.");
            if(!prefs.edit().putString(key,remaining.toString()).commit())throw new Exception("Chưa lưu được xác nhận trạng thái SMS.");events=remaining;
        }
    }

    private static String request(
        String baseUrl,
        String method,
        String path,
        JSONObject body,
        String token,
        String deviceId
    ) throws Exception {
        String base = baseUrl == null ? "" : baseUrl.trim();
        while (base.endsWith("/")) base = base.substring(0, base.length() - 1);
        if (!base.startsWith("http://") && !base.startsWith("https://")) base = "http://" + base;

        HttpURLConnection connection = (HttpURLConnection)new URL(base + path).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setRequestMethod(method);
        connection.setConnectTimeout(8000);
        connection.setReadTimeout(12000);
        connection.setRequestProperty("Accept", "application/json");
        if (token != null && !token.isEmpty())
            connection.setRequestProperty("Authorization", "Bearer " + token);
        if (deviceId != null && !deviceId.isEmpty())
            connection.setRequestProperty("X-BachSMS-Device", deviceId);

        if (body != null) {
            byte[] data = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setFixedLengthStreamingMode(data.length);
            try (OutputStream output = connection.getOutputStream()) {
                output.write(data);
            }
        }

        int code = connection.getResponseCode();
        InputStream stream = code >= 200 && code < 300
            ? connection.getInputStream() : connection.getErrorStream();
        String text = read(stream);
        connection.disconnect();
        if (code < 200 || code >= 300)
            throw new IllegalStateException("CRM trả lỗi " + code + (text.isEmpty() ? "" : ": " + text));
        return text.isEmpty() ? "{}" : text;
    }

    private static String read(InputStream stream) throws Exception {
        if (stream == null) return "";
        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) builder.append(line);
        }
        return builder.toString();
    }

    private static String isoNow() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }
}

