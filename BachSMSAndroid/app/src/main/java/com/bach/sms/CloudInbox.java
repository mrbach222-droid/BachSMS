package com.bach.sms;

import android.content.Context;
import android.util.AtomicFile;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileOutputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.LinkedHashMap;
import java.util.UUID;

final class CloudInbox {
    static JSONObject link(String code) throws Exception {
        String value = code.trim();
        if (!value.startsWith("bachsms1.") || value.length() > 4096) throw new Exception("Dán đầy đủ mã bachsms1.… từ CRM trên PC.");
        JSONObject link = new JSONObject(new String(Base64.decode(value.substring(9), Base64.URL_SAFE | Base64.NO_WRAP), StandardCharsets.UTF_8));
        URI url = new URI(link.getString("url"));
        if (!"https".equals(url.getScheme()) || url.getHost() == null || url.getUserInfo() != null || url.getQuery() != null || url.getFragment() != null || !(url.getPath().isEmpty() || url.getPath().equals("/")) || !link.getString("token").matches("r_[a-f0-9]{64}")) throw new Exception("Mã kết nối Cloudflare chưa hợp lệ.");
        UUID.fromString(link.getString("channel"));
        return link;
    }
    private static AtomicFile file(Context c, String scope) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(scope.getBytes(StandardCharsets.UTF_8));
        StringBuilder name = new StringBuilder();for(byte b:digest)name.append(String.format("%02x", b & 255));
        return new AtomicFile(new File(c.getFilesDir(), "cloud-inbox-" + name + ".json"));
    }
    static synchronized JSONArray read(Context c, String scope) throws Exception {
        AtomicFile file = file(c, scope);if(!file.getBaseFile().exists()) return new JSONArray();
        return new JSONArray(new String(file.readFully(), StandardCharsets.UTF_8));
    }
    static synchronized JSONArray merge(Context c, String scope, JSONArray incoming) throws Exception {
        LinkedHashMap<String,JSONObject> all = new LinkedHashMap<>();
        JSONArray saved = read(c, scope);
        for(int i=0;i<saved.length();i++){JSONObject j=saved.getJSONObject(i);all.put(j.getString("id"), j);}
        for(int i=0;i<incoming.length();i++){JSONObject j=incoming.getJSONObject(i);all.put(j.getString("id"), j);}
        JSONArray result = new JSONArray();for(JSONObject j:all.values())result.put(j);
        AtomicFile file = file(c, scope);FileOutputStream stream=null;
        try{stream=file.startWrite();stream.write(result.toString().getBytes(StandardCharsets.UTF_8));file.finishWrite(stream);}
        catch(Exception e){if(stream!=null)file.failWrite(stream);throw e;}
        return result;
    }
}
