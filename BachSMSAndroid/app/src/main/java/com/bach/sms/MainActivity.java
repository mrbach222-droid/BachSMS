package com.bach.sms;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public final class MainActivity extends Activity {
    private static final int PERMISSION_REQUEST = 44;

    private final ArrayList<Job> jobs = new ArrayList<>();
    private final ArrayList<Integer> subscriptionIds = new ArrayList<>();

    private SharedPreferences preferences;
    private EditText serverInput;
    private EditText codeInput;
    private EditText messageInput;
    private TextView statusView;
    private TextView progressView;
    private ListView customerList;
    private Spinner simSpinner;
    private Button startButton;
    private ArrayAdapter<String> customerAdapter;
    private ArrayAdapter<String> simAdapter;
    private String deviceId;
    private String token;
    private volatile boolean networkBusy;

    private final BroadcastReceiver progressReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            int current = intent.getIntExtra(SmsSendService.EXTRA_CURRENT, 0);
            int total = intent.getIntExtra(SmsSendService.EXTRA_TOTAL, 0);
            String detail = intent.getStringExtra(SmsSendService.EXTRA_DETAIL);
            boolean finished = intent.getBooleanExtra(SmsSendService.EXTRA_FINISHED, false);
            progressView.setText((finished ? "Hoàn tất" : "Đang gửi") + "  " + current + "/" + total
                + (detail == null || detail.isEmpty() ? "" : "\n" + detail));
            startButton.setEnabled(finished);
            if (finished) fetchJobs();
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        preferences = getSharedPreferences("bach_sms", MODE_PRIVATE);
        deviceId = preferences.getString("device_id", "");
        if (deviceId.isEmpty()) {
            deviceId = UUID.randomUUID().toString();
            preferences.edit().putString("device_id", deviceId).apply();
        }
        token = preferences.getString("token", "");
        buildUi();
        restoreSettings();
        loadSims();
    }

    @Override protected void onStart() {
        super.onStart();
        IntentFilter filter = new IntentFilter(SmsSendService.ACTION_PROGRESS);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(progressReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(progressReceiver, filter);
        }
    }

    @Override protected void onStop() {
        super.onStop();
        try { unregisterReceiver(progressReceiver); } catch (Exception ignored) {}
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(12));
        root.setBackgroundColor(Color.rgb(244, 247, 246));
        setContentView(root);

        TextView title = text("BÁCH SMS · ANDROID", 23, true, Color.rgb(20, 58, 52));
        root.addView(title, matchWrap());

        TextView subtitle = text(
            "Nhận khách từ Bách CRM và gửi SMS tự động bằng SIM điện thoại",
            13, false, Color.rgb(80, 103, 98));
        subtitle.setPadding(0, dp(2), 0, dp(10));
        root.addView(subtitle, matchWrap());

        serverInput = input("Địa chỉ Cloudflare tự điền sau khi liên kết");
        root.addView(serverInput, match(dp(46)));

        LinearLayout pairRow = row();
        codeInput = input("Dán mã bachsms1.… từ PC");
        pairRow.addView(codeInput, weight(1, dp(46)));
        Button pairButton = button("GHÉP CRM", Color.rgb(20, 105, 160));
        pairButton.setOnClickListener(v -> pair());
        pairRow.addView(pairButton, fixed(dp(112), dp(46)));
        root.addView(pairRow, matchWrap());

        LinearLayout syncRow = row();
        Button refreshButton = button("TẢI KHÁCH TỪ CRM", Color.rgb(18, 122, 94));
        refreshButton.setOnClickListener(v -> fetchJobs());
        syncRow.addView(refreshButton, weight(1, dp(44)));
        Button allButton = button("CHỌN TẤT CẢ", Color.rgb(82, 102, 97));
        allButton.setOnClickListener(v -> {
            for (int i = 0; i < jobs.size(); i++) customerList.setItemChecked(i, true);
        });
        syncRow.addView(allButton, fixed(dp(120), dp(44)));
        root.addView(syncRow, matchWrap());

        statusView = text("Chưa kết nối CRM.", 12, false, Color.rgb(80, 103, 98));
        statusView.setPadding(dp(2), dp(6), 0, dp(6));
        root.addView(statusView, matchWrap());

        TextView listTitle = text("KHÁCH ĐÃ CHUYỂN TỪ CRM", 12, true, Color.rgb(20, 58, 52));
        root.addView(listTitle, matchWrap());

        customerList = new ListView(this);
        customerList.setChoiceMode(ListView.CHOICE_MODE_MULTIPLE);
        customerList.setDividerHeight(1);
        customerList.setBackgroundColor(Color.WHITE);
        customerAdapter = new ArrayAdapter<>(
            this, android.R.layout.simple_list_item_multiple_choice, new ArrayList<>());
        customerList.setAdapter(customerAdapter);
        LinearLayout.LayoutParams listParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        listParams.setMargins(0, dp(4), 0, dp(8));
        root.addView(customerList, listParams);

        TextView composeTitle = text("NỘI DUNG SMS", 12, true, Color.rgb(20, 58, 52));
        root.addView(composeTitle, matchWrap());

        messageInput = input("Nhập nội dung. Dùng {ten}, {cif}, {hopdong} để tự thay.");
        messageInput.setMinLines(3);
        messageInput.setGravity(Gravity.TOP | Gravity.START);
        root.addView(messageInput, match(dp(82)));

        LinearLayout options = row();
        simSpinner = new Spinner(this);
        simAdapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
            new ArrayList<>());
        simSpinner.setAdapter(simAdapter);
        options.addView(simSpinner, weight(1, dp(44)));
        TextView delay = text("Nghỉ ngẫu nhiên\n5–10 giây", 12, true, Color.rgb(139, 91, 0));
        delay.setGravity(Gravity.CENTER);
        delay.setBackgroundColor(Color.rgb(255, 244, 214));
        options.addView(delay, fixed(dp(126), dp(44)));
        root.addView(options, matchWrap());

        progressView = text("Tiến độ: 0/0", 13, true, Color.rgb(20, 105, 160));
        progressView.setPadding(0, dp(7), 0, dp(7));
        root.addView(progressView, matchWrap());

        LinearLayout actions = row();
        Button stopButton = button("DỪNG", Color.rgb(170, 65, 60));
        stopButton.setOnClickListener(v -> stopSending());
        actions.addView(stopButton, fixed(dp(92), dp(48)));
        startButton = button("BẮT ĐẦU GỬI TỰ ĐỘNG", Color.rgb(18, 122, 94));
        startButton.setTextSize(14);
        startButton.setOnClickListener(v -> prepareSending());
        actions.addView(startButton, weight(1, dp(48)));
        root.addView(actions, matchWrap());

        TextView note = text(
            "Ứng dụng chỉ gửi sau khi anh bấm BẮT ĐẦU. Cước SMS do nhà mạng tính; nên gửi đúng khách được phép nhận.",
            11, false, Color.rgb(105, 112, 110));
        note.setPadding(0, dp(7), 0, 0);
        root.addView(note, matchWrap());
    }

    private void restoreSettings() {
        serverInput.setText(preferences.getString("server_url", ""));
        codeInput.setText(preferences.getString("crm_code", ""));
        messageInput.setText(preferences.getString("message_template", ""));
        if (preferences.getBoolean("cloud", false)) {
            serverInput.setEnabled(false);
            try { showJsonJobs(CloudInbox.read(this, cloudScope())); } catch(Exception e) { statusView.setText("Chưa đọc được danh sách lưu trên máy."); }
        }
        if (!token.isEmpty()) statusView.setText("Đã lưu ghép nối. Bấm TẢI KHÁCH TỪ CRM.");
    }

    private void pair() {
        String server = serverInput.getText().toString().trim();
        String code = codeInput.getText().toString().trim();
        if(code.startsWith("bachsms1.")){
            statusView.setText("Đang liên kết Cloudflare...");
            runNetwork(() -> {
                JSONObject link=CloudInbox.link(code);String base=link.getString("url"), reader=link.getString("token"), channel=link.getString("channel");
                CrmClient.jobs(base, reader, deviceId);
                if(!preferences.edit().putString("server_url",base).putString("crm_code","CF-"+channel).putString("token",reader).putBoolean("cloud",true).commit())throw new Exception("Không lưu được kết nối trên điện thoại.");
                runOnUiThread(() -> {token=reader;serverInput.setText(base);serverInput.setEnabled(false);codeInput.setText("CF-"+channel);jobs.clear();try{showJsonJobs(CloudInbox.read(this,cloudScope()));}catch(Exception ignored){showJobs(new ArrayList<>());}fetchJobs();});
            });return;
        }
        if (server.isEmpty() || code.isEmpty()) {
            toast("Nhập địa chỉ CRM và mã CRM.");
            return;
        }
        statusView.setText("Đang ghép với CRM...");
        runNetwork(() -> {
            String newToken = CrmClient.pair(server, code, deviceId, "Android · " + Build.MODEL);
            token = newToken;
            preferences.edit()
                .putString("server_url", server)
                .putString("crm_code", code)
                .putString("token", newToken)
                .apply();
            runOnUiThread(() -> {
                statusView.setText("Đã ghép CRM thành công.");
                fetchJobs();
            });
        });
    }

    private void fetchJobs() {
        String server = serverInput.getText().toString().trim();
        if (server.isEmpty() || token.isEmpty()) {
            toast("Hãy ghép CRM trước.");
            return;
        }
        statusView.setText("Đang tải khách...");
        runNetwork(() -> {
            CrmClient.flushStatuses(this,server,token,deviceId);
            JSONArray array = CrmClient.jobs(server, token, deviceId);
            if(preferences.getBoolean("cloud",false)){
                String scope=cloudScope();int pages=0;
                while(array.length()>0 && pages++<250){
                    CloudInbox.merge(this, scope, array);
                    CrmClient.received(server, token, array);
                    array=CrmClient.jobs(server, token, deviceId);
                }
                array=CloudInbox.read(this, scope);
            }
            ArrayList<Job> loaded = new ArrayList<>();
            for (int i = 0; i < array.length(); i++) loaded.add(Job.fromJson(array.getJSONObject(i)));
            runOnUiThread(() -> showJobs(loaded));
        });
    }

    private String cloudScope(){return preferences.getString("server_url","")+"|"+preferences.getString("crm_code","");}
    private void showJsonJobs(JSONArray array) throws Exception {ArrayList<Job> loaded=new ArrayList<>();for(int i=0;i<array.length();i++)loaded.add(Job.fromJson(array.getJSONObject(i)));showJobs(loaded);}

    private void showJobs(List<Job> loaded) {
        jobs.clear();
        java.util.Set<String> done=preferences.getStringSet("completed_cloud_jobs",new java.util.HashSet<>());
        for(Job job:loaded)if(!done.contains(job.id))jobs.add(job);
        ArrayList<String> labels = new ArrayList<>();
        for (Job job : jobs) labels.add(job.display());
        customerAdapter.clear();
        customerAdapter.addAll(labels);
        customerAdapter.notifyDataSetChanged();
        for (int i = 0; i < jobs.size(); i++) customerList.setItemChecked(i, true);
        statusView.setText(jobs.isEmpty()
            ? "CRM chưa có khách mới."
            : "Đã nhận " + jobs.size() + " khách. Tất cả đang được chọn.");
        progressView.setText("Tiến độ: 0/" + jobs.size());
    }

    private void prepareSending() {
        if (!ensurePermissions()) return;
        ArrayList<Job> selected = new ArrayList<>();
        for (int i = 0; i < jobs.size(); i++) {
            if (customerList.isItemChecked(i)) selected.add(jobs.get(i));
        }
        String template = messageInput.getText().toString().trim();
        if (selected.isEmpty()) {
            toast("Chọn ít nhất một khách.");
            return;
        }
        if (template.isEmpty()) {
            toast("Nhập nội dung SMS.");
            return;
        }
        preferences.edit().putString("message_template", template).apply();

        new AlertDialog.Builder(this)
            .setTitle("Xác nhận gửi tự động")
            .setMessage("Gửi " + selected.size() + " SMS bằng SIM đã chọn?\n\n"
                + "Ứng dụng sẽ nghỉ ngẫu nhiên 5–10 giây giữa mỗi khách.")
            .setNegativeButton("Hủy", null)
            .setPositiveButton("Bắt đầu gửi", (dialog, which) -> startSending(selected, template))
            .show();
    }

    private void startSending(List<Job> selected, String template) {
        try {
            JSONArray array = new JSONArray();
            for (Job job : selected) array.put(job.toJson());
            int subId = subscriptionIds.isEmpty() ? -1
                : subscriptionIds.get(Math.max(0, simSpinner.getSelectedItemPosition()));
            Intent intent = new Intent(this, SmsSendService.class);
            intent.setAction(SmsSendService.ACTION_START);
            intent.putExtra(SmsSendService.EXTRA_JOBS, array.toString());
            intent.putExtra(SmsSendService.EXTRA_TEMPLATE, template);
            intent.putExtra(SmsSendService.EXTRA_SERVER, serverInput.getText().toString().trim());
            intent.putExtra(SmsSendService.EXTRA_TOKEN, token);
            intent.putExtra(SmsSendService.EXTRA_DEVICE_ID, deviceId);
            intent.putExtra(SmsSendService.EXTRA_SUBSCRIPTION_ID, subId);
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent); else startService(intent);
            startButton.setEnabled(false);
            progressView.setText("Đang bắt đầu gửi 0/" + selected.size());
        } catch (Exception error) {
            showError(error);
        }
    }

    private void stopSending() {
        Intent intent = new Intent(this, SmsSendService.class);
        intent.setAction(SmsSendService.ACTION_STOP);
        startService(intent);
        startButton.setEnabled(true);
    }

    private boolean ensurePermissions() {
        ArrayList<String> missing = new ArrayList<>();
        if (checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED)
            missing.add(Manifest.permission.SEND_SMS);
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED)
            missing.add(Manifest.permission.READ_PHONE_STATE);
        if (Build.VERSION.SDK_INT >= 33
            && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            missing.add(Manifest.permission.POST_NOTIFICATIONS);
        if (!missing.isEmpty()) {
            requestPermissions(missing.toArray(new String[0]), PERMISSION_REQUEST);
            toast("Cấp quyền rồi bấm BẮT ĐẦU lại.");
            return false;
        }
        return true;
    }

    @Override public void onRequestPermissionsResult(
        int requestCode, String[] permissions, int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQUEST) loadSims();
    }

    private void loadSims() {
        subscriptionIds.clear();
        ArrayList<String> labels = new ArrayList<>();
        subscriptionIds.add(-1);
        labels.add("SIM SMS mặc định");

        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            try {
                SubscriptionManager manager = SubscriptionManager.from(this);
                List<SubscriptionInfo> active = manager.getActiveSubscriptionInfoList();
                if (active != null) {
                    for (SubscriptionInfo info : active) {
                        subscriptionIds.add(info.getSubscriptionId());
                        CharSequence carrier = info.getCarrierName();
                        labels.add("SIM " + (info.getSimSlotIndex() + 1) + " · "
                            + (carrier == null ? "" : carrier.toString()));
                    }
                }
            } catch (Exception ignored) {}
        }
        simAdapter.clear();
        simAdapter.addAll(labels);
        simAdapter.notifyDataSetChanged();
    }

    private void runNetwork(ThrowingAction action) {
        if(networkBusy){toast("Đang kết nối, anh đợi một chút.");return;}
        networkBusy=true;
        new Thread(() -> {
            try {
                action.run();
            } catch (Exception error) {
                runOnUiThread(() -> showError(error));
            } finally {networkBusy=false;}
        }).start();
    }

    private void showError(Exception error) {
        String message = error.getMessage() == null ? error.toString() : error.getMessage();
        statusView.setText("Lỗi: " + message);
        new AlertDialog.Builder(this)
            .setTitle("Bách SMS")
            .setMessage(message)
            .setPositiveButton("Đóng", null)
            .show();
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private EditText input(String hint) {
        EditText view = new EditText(this);
        view.setHint(hint);
        view.setTextSize(14);
        view.setSingleLine(false);
        view.setPadding(dp(10), dp(6), dp(10), dp(6));
        view.setBackgroundColor(Color.WHITE);
        return view;
    }

    private Button button(String label, int color) {
        Button view = new Button(this);
        view.setText(label);
        view.setTextColor(Color.WHITE);
        view.setTextSize(12);
        view.setAllCaps(false);
        view.setBackgroundColor(color);
        return view;
    }

    private TextView text(String value, int size, boolean bold, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams match(int height) {
        return new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height);
    }

    private LinearLayout.LayoutParams fixed(int width, int height) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(width, height);
        params.setMargins(dp(5), dp(3), 0, dp(3));
        return params;
    }

    private LinearLayout.LayoutParams weight(float weight, int height) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, height, weight);
        params.setMargins(0, dp(3), 0, dp(3));
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private interface ThrowingAction { void run() throws Exception; }
}

