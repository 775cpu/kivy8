package com.example.chaquopyrpc;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Window;
import android.view.WindowManager;
import android.widget.TextView;

import com.chaquo.python.PyObject;
import com.chaquo.python.Python;
import com.chaquo.python.android.AndroidPlatform;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

public class MainActivity extends Activity {
    private static MainActivity instance;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView logView;
    private File logFile;
    private Python python;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        instance = this;
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN
        );

        logView = new TextView(this);
        logView.setTextColor(0xffd7f9f1);
        logView.setTextSize(12);
        logView.setTypeface(android.graphics.Typeface.MONOSPACE);
        logView.setPadding(24, 24, 24, 24);
        logView.setBackgroundColor(0xff101418);
        logView.setText("Starting Chaquopy RPC...\n");
        setContentView(logView);

        logFile = new File(getFilesDir(), "rpc.log");
        startRpc();
        handler.post(logPoller);
    }

    public static void setLogBackgroundColor(final String color) {
        if (instance == null) {
            throw new IllegalStateException("MainActivity is not running");
        }
        instance.runOnUiThread(() -> {
            try {
                instance.logView.setBackgroundColor(
                        android.graphics.Color.parseColor(color)
                );
            } catch (IllegalArgumentException error) {
                throw new RuntimeException("Invalid color: " + color, error);
            }
        });
    }

    private void startRpc() {
        try {
            if (!Python.isStarted()) {
                Python.start(new AndroidPlatform(this));
            }
            python = Python.getInstance();
            PyObject module = python.getModule("app");
            module.callAttr("start", logFile.getAbsolutePath());
        } catch (Exception error) {
            appendLog("[JAVA] RPC startup failed: " + error + "\n");
        }
    }

    private final Runnable logPoller = new Runnable() {
        @Override
        public void run() {
            if (logFile != null && logFile.isFile()) {
                try {
                        String text = new String(
                            Files.readAllBytes(logFile.toPath()),
                            StandardCharsets.UTF_8
                        );
                    logView.setText(text);
                } catch (Exception error) {
                    appendLog("[JAVA] Log read failed: " + error + "\n");
                }
            }
            handler.postDelayed(this, 500);
        }
    };

    private void appendLog(String message) {
        logView.append(message);
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacks(logPoller);
        instance = null;
        super.onDestroy();
    }
}
