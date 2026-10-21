package com.bach.sms;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.telephony.SmsManager;

import org.json.JSONArray;

import java.util.ArrayList;
import java.util.Random;

public final class SmsSendService extends Service {
    public static final String ACTION_START = "com.bach.sms.START";
    public static final String ACTION_STOP = "com.bach.sms.STOP";
    public static final String ACTION_PROGRESS = "com.bach.sms.PROGRESS";
    private static final String ACTION_PART_SENT = "com.bach.sms.PART_SENT";

    public static final String EXTRA_JOBS = "jobs";
    public static final String EXTRA_TEMPLATE = "template";
    public static final String EXTRA_SERVER = "server";
    public static final String EXTRA_TOKEN = "token";
    public static final String EXTRA_DEVICE_ID = "device_id";
    public static final String EXTRA_SUBSCRIPTION_ID = "subscription_id";
    public static final String EXTRA_CURRENT = "current";
    public static final String EXTRA_TOTAL = "total";
    public static final String EXTRA_DETAIL = "detail";
    public static final String EXTRA_FINISHED = "finished";

    private static final int NOTIFICATION_ID = 2602;
    private static final String CHANNEL_ID = "bach_sms_sending";

    private final ArrayList<Job> queue = new ArrayList<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Random random = new Random();

    private String template = "";
    private String server = "";
    private String token = "";
    private String deviceId = "";
    private int subscriptionId = -1;
    private int index;
    private int expectedParts;
    private int completedParts;
    private boolean partFailed;
    private boolean stopped;
    private int generation;
    private PowerManager.WakeLock wakeLock;

    private final BroadcastReceiver sentReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            String jobId = intent.getStringExtra("job_id");
            int eventGeneration = intent.getIntExtra("generation", -1);
            if (stopped || index >= queue.size() || eventGeneration != generation) return;
            if (!queue.get(index).id.equals(jobId)) return;
            completedParts++;
            if (getResultCode() != Activity.RESULT_OK) partFailed = true;
            if (completedParts >= expectedParts) finishCurrent(!partFailed,
                partFailed ? "Nhà mạng/thiết bị báo gửi lỗi" : "Đã chuyển SMS tới nhà mạng");
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        IntentFilter filter = new IntentFilter(ACTION_PART_SENT);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(sentReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(sentReceiver, filter);
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? "" : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopQueue("Đã dừng theo yêu cầu.");
            return START_NOT_STICKY;
        }
        if (!ACTION_START.equals(action)) return START_NOT_STICKY;

        try {
            queue.clear();
            JSONArray data = new JSONArray(intent.getStringExtra(EXTRA_JOBS));
            for (int i = 0; i < data.length(); i++) queue.add(Job.fromJson(data.getJSONObject(i)));
            template = value(intent.getStringExtra(EXTRA_TEMPLATE));
            server = value(intent.getStringExtra(EXTRA_SERVER));
            token = value(intent.getStringExtra(EXTRA_TOKEN));
            deviceId = value(intent.getStringExtra(EXTRA_DEVICE_ID));
            subscriptionId = intent.getIntExtra(EXTRA_SUBSCRIPTION_ID, -1);
            index = 0;
            stopped = false;
            acquireWakeLock();

            startForeground(NOTIFICATION_ID, notification("Chuẩn bị gửi", 0, queue.size(), false));
            broadcast(0, queue.size(), "Đã nhận danh sách gửi.", false);
            handler.post(this::sendNext);
        } catch (Exception error) {
            stopQueue("Không khởi động được: " + error.getMessage());
        }
        return START_NOT_STICKY;
    }

    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        try { unregisterReceiver(sentReceiver); } catch (Exception ignored) {}
        releaseWakeLock();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) {
        return null;
    }

    private void sendNext() {
        if (stopped) return;
        if (index >= queue.size()) {
            completeQueue();
            return;
        }

        Job job = queue.get(index);
        String message = job.applyTemplate(template);
        if (job.phone.isEmpty() || message.trim().isEmpty()) {
            finishCurrent(false, "Thiếu SĐT hoặc nội dung: " + job.name);
            return;
        }

        try {
            SmsManager manager = smsManager();
            ArrayList<String> parts = manager.divideMessage(message);
            if (parts == null || parts.isEmpty()) {
                parts = new ArrayList<>();
                parts.add(message);
            }

            generation++;
            expectedParts = parts.size();
            completedParts = 0;
            partFailed = false;

            ArrayList<PendingIntent> sentIntents = new ArrayList<>();
            for (int part = 0; part < parts.size(); part++) {
                Intent sent = new Intent(ACTION_PART_SENT);
                sent.setPackage(getPackageName());
                sent.putExtra("job_id", job.id);
                sent.putExtra("part", part);
                sent.putExtra("generation", generation);
                int requestCode = Math.abs((job.id + ":" + part + ":" + generation).hashCode());
                int pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT;
                if (Build.VERSION.SDK_INT >= 23) pendingFlags |= PendingIntent.FLAG_IMMUTABLE;
                sentIntents.add(PendingIntent.getBroadcast(
                    this, requestCode, sent, pendingFlags));
            }

            updateNotification("Đang gửi cho " + displayName(job), index, queue.size(), true);
            broadcast(index, queue.size(), "Đang gửi: " + displayName(job) + " · " + job.phone, false);

            if (parts.size() == 1) {
                manager.sendTextMessage(job.phone, null, parts.get(0), sentIntents.get(0), null);
            } else {
                manager.sendMultipartTextMessage(job.phone, null, parts, sentIntents, null);
            }

            final int timeoutGeneration = generation;
            handler.postDelayed(() -> {
                if (!stopped && index < queue.size() && timeoutGeneration == generation
                    && completedParts < expectedParts) {
                    finishCurrent(false, "Hết thời gian chờ kết quả gửi");
                }
            }, 45000);
        } catch (Exception error) {
            finishCurrent(false, "Gửi lỗi: " + error.getMessage());
        }
    }

    private SmsManager smsManager() {
        if (subscriptionId >= 0) {
            if (Build.VERSION.SDK_INT >= 31) {
                SmsManager base = getSystemService(SmsManager.class);
                return base.createForSubscriptionId(subscriptionId);
            }
            return SmsManager.getSmsManagerForSubscriptionId(subscriptionId);
        }
        return SmsManager.getDefault();
    }

    private void finishCurrent(boolean success, String detail) {
        if (stopped || index >= queue.size()) return;
        Job job = queue.get(index);
        int completed = index + 1;
        generation++;
        String status = success ? "confirmed_sent" : "failed";
        if(success){
            android.content.SharedPreferences prefs=getSharedPreferences("bach_sms",MODE_PRIVATE);
            java.util.Set<String> done=new java.util.HashSet<>(prefs.getStringSet("completed_cloud_jobs",new java.util.HashSet<>()));
            done.add(job.id);prefs.edit().putStringSet("completed_cloud_jobs",done).commit();
        }

        new Thread(() -> {
            try {
                CrmClient.postStatus(this, server, token, deviceId, job, status);
            } catch (Exception ignored) {}
        }).start();

        broadcast(completed, queue.size(),
            (success ? "Đã gửi: " : "Gửi lỗi: ") + displayName(job) + " — " + detail, false);
        updateNotification(success ? "Đã gửi " + displayName(job) : "Gửi lỗi " + displayName(job),
            completed, queue.size(), false);
        index++;
        if (index >= queue.size()) {
            handler.postDelayed(this::completeQueue, 700);
            return;
        }
        long delay = 5000L + random.nextInt(5001);
        handler.postDelayed(this::sendNext, delay);
    }

    private void completeQueue() {
        if (stopped) return;
        stopped = true;
        updateNotification("Đã hoàn tất " + queue.size() + "/" + queue.size(),
            queue.size(), queue.size(), false);
        broadcast(queue.size(), queue.size(), "Đã hoàn tất danh sách.", true);
        releaseWakeLock();
        stopForeground(false);
        stopSelf();
    }

    private void stopQueue(String detail) {
        stopped = true;
        generation++;
        handler.removeCallbacksAndMessages(null);
        broadcast(index, queue.size(), detail, true);
        releaseWakeLock();
        stopForeground(true);
        stopSelf();
    }

    private void broadcast(int current, int total, String detail, boolean finished) {
        Intent intent = new Intent(ACTION_PROGRESS);
        intent.setPackage(getPackageName());
        intent.putExtra(EXTRA_CURRENT, current);
        intent.putExtra(EXTRA_TOTAL, total);
        intent.putExtra(EXTRA_DETAIL, detail);
        intent.putExtra(EXTRA_FINISHED, finished);
        sendBroadcast(intent);
    }

    private void updateNotification(String detail, int current, int total, boolean ongoing) {
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.notify(NOTIFICATION_ID, notification(detail, current, total, ongoing));
    }

    private Notification notification(String detail, int current, int total, boolean ongoing) {
        Intent open = new Intent(this, MainActivity.class);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent content = PendingIntent.getActivity(this, 0, open, flags);

        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL_ID)
            : new Notification.Builder(this);
        builder.setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle("Bách SMS · " + current + "/" + total)
            .setContentText(detail)
            .setContentIntent(content)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setCategory(Notification.CATEGORY_SERVICE);
        if (total > 0) builder.setProgress(total, Math.min(current, total), false);
        return builder.build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID, "Đang gửi SMS", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Hiển thị tiến độ gửi SMS tự động.");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private void acquireWakeLock() {
        try {
            PowerManager manager = (PowerManager)getSystemService(POWER_SERVICE);
            wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BachSMS:Sending");
            wakeLock.acquire(30 * 60 * 1000L);
        } catch (Exception ignored) {}
    }

    private void releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        } catch (Exception ignored) {}
        wakeLock = null;
    }

    private static String displayName(Job job) {
        return job.name.isEmpty() ? job.phone : job.name;
    }

    private static String value(String input) {
        return input == null ? "" : input.trim();
    }
}

