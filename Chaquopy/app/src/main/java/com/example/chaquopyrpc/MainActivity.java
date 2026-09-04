package com.example.chaquopyrpc;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.view.Gravity;
import android.view.Window;
import android.view.WindowManager;
import android.view.ViewGroup;
import android.text.InputType;
import android.widget.ScrollView;
import android.widget.EditText;

import com.chaquo.python.PyObject;
import com.chaquo.python.Python;
import com.chaquo.python.android.AndroidPlatform;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.io.FileWriter;
import java.io.IOException;

public class MainActivity extends Activity {
    private static MainActivity instance;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private EditText logView;
    private ScrollView logScrollView;
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

        logView = new EditText(this);
        logView.setTextColor(0xffd7f9f1);
        logView.setTextSize(12);
        logView.setTypeface(android.graphics.Typeface.MONOSPACE);
        logView.setPadding(24, 24, 24, 24);
        logView.setFocusable(true);
        logView.setFocusableInTouchMode(true);
        logView.setLongClickable(true);
        logView.setCursorVisible(false);
        logView.setSingleLine(false);
        logView.setInputType(
            InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        );
        logView.setKeyListener(null);
        logView.setMovementMethod(ScrollingMovementMethod.getInstance());
        logView.setGravity(Gravity.TOP | Gravity.START);
        logView.setTextIsSelectable(true);
        logView.setHorizontallyScrolling(true);
        logView.setVerticalScrollBarEnabled(true);
        logView.setText("Starting Chaquopy RPC...\n");
        logScrollView = new ScrollView(this);
        logScrollView.setFillViewport(false);
        logScrollView.setBackgroundColor(0xff101418);
        logView.setLayoutParams(new ScrollView.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ));
        logScrollView.addView(logView);
        setContentView(logScrollView);

        logFile = new File(getFilesDir(), "rpc.log");
        startRpc();
        handler.post(logPoller);
    }

    public static void setLogBackgroundColor(final String color) {
        if (instance == null) {
            return;
        }
        final int parsedColor;
        try {
            parsedColor = android.graphics.Color.parseColor(color);
        } catch (IllegalArgumentException error) {
            instance.appendLogFile("[RPC ERROR] Invalid background color '" + color
                    + "'. Use #RRGGBB or #AARRGGBB. Details: " + error + "\n");
            return;
        }
        instance.runOnUiThread(() -> {
            instance.logView.setBackgroundColor(parsedColor);
            instance.logScrollView.setBackgroundColor(parsedColor);
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

    private void appendLogFile(String message) {
        try (FileWriter writer = new FileWriter(logFile, true)) {
            writer.write(message);
            writer.flush();
        } catch (IOException error) {
            appendLog("[JAVA] Cannot write RPC error: " + error + "\n");
        }
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacks(logPoller);
        instance = null;
        super.onDestroy();
    }
}
