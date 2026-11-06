package com.max.crpg.documents;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;

import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class CrpgDocumentExchangePlugin extends GodotPlugin {
    private static final int REQUEST_CREATE = 8101;
    private static final int REQUEST_OPEN = 8102;
    private static final String MIME_TYPE = "application/octet-stream";

    private final ExecutorService ioExecutor = Executors.newSingleThreadExecutor();
    private String pendingContents = "";
    private String pendingFilename = "crpg_game.crpggame";
    private int maximumImportBytes = 16 * 1024 * 1024;

    public CrpgDocumentExchangePlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "CrpgDocumentExchange";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("document_saved", String.class));
        signals.add(new SignalInfo("document_opened", String.class, String.class));
        signals.add(new SignalInfo("document_shared", String.class));
        signals.add(new SignalInfo("operation_cancelled", String.class));
        signals.add(new SignalInfo("operation_failed", String.class, String.class));
        return signals;
    }

    @UsedByGodot
    public void saveDocument(String filename, String contents) {
        Activity activity = getActivity();
        if (activity == null) {
            fail("save", "Android activity is unavailable.");
            return;
        }
        pendingFilename = sanitizeFilename(filename);
        pendingContents = contents;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(MIME_TYPE);
        intent.putExtra(Intent.EXTRA_TITLE, pendingFilename);
        activity.startActivityForResult(intent, REQUEST_CREATE);
    }

    @UsedByGodot
    public void openDocument(int maxBytes) {
        Activity activity = getActivity();
        if (activity == null) {
            fail("open", "Android activity is unavailable.");
            return;
        }
        maximumImportBytes = Math.max(1, maxBytes);
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        activity.startActivityForResult(intent, REQUEST_OPEN);
    }

    @UsedByGodot
    public void shareDocument(String filename, String contents) {
        Activity activity = getActivity();
        if (activity == null) {
            fail("share", "Android activity is unavailable.");
            return;
        }
        String safeFilename = sanitizeFilename(filename);
        ioExecutor.execute(() -> {
            try {
                File directory = new File(activity.getFilesDir(), "shared_games");
                if (!directory.exists() && !directory.mkdirs()) {
                    throw new IllegalStateException("Could not create the sharing cache.");
                }
                File[] staleFiles = directory.listFiles();
                if (staleFiles != null) {
                    for (File stale : staleFiles) stale.delete();
                }
                File sharedFile = new File(directory, safeFilename);
                try (FileOutputStream output = new FileOutputStream(sharedFile)) {
                    output.write(contents.getBytes(StandardCharsets.UTF_8));
                }
                Uri uri = FileProvider.getUriForFile(
                    activity,
                    activity.getPackageName() + ".fileprovider",
                    sharedFile
                );
                activity.runOnUiThread(() -> {
                    try {
                        Intent send = new Intent(Intent.ACTION_SEND);
                        send.setType(MIME_TYPE);
                        send.putExtra(Intent.EXTRA_STREAM, uri);
                        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                        activity.startActivity(Intent.createChooser(send, "Share CRPG game"));
                        emitSafe("document_shared", safeFilename);
                    } catch (Exception error) {
                        fail("share", message(error));
                    }
                });
            } catch (Exception error) {
                fail("share", message(error));
            }
        });
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQUEST_CREATE) {
            if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
                pendingContents = "";
                emitSafe("operation_cancelled", "save");
                return;
            }
            Uri uri = data.getData();
            String contents = pendingContents;
            String fallbackName = pendingFilename;
            pendingContents = "";
            ioExecutor.execute(() -> writeDocument(uri, contents, fallbackName));
            return;
        }
        if (requestCode == REQUEST_OPEN) {
            if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
                emitSafe("operation_cancelled", "open");
                return;
            }
            Uri uri = data.getData();
            ioExecutor.execute(() -> readDocument(uri));
        }
    }

    private void writeDocument(Uri uri, String contents, String fallbackName) {
        Activity activity = getActivity();
        if (activity == null) {
            fail("save", "Android activity is unavailable.");
            return;
        }
        try (OutputStream output = activity.getContentResolver().openOutputStream(uri, "wt")) {
            if (output == null) throw new IllegalStateException("The selected document cannot be written.");
            output.write(contents.getBytes(StandardCharsets.UTF_8));
            emitSafe("document_saved", displayName(uri, fallbackName));
        } catch (Exception error) {
            fail("save", message(error));
        }
    }

    private void readDocument(Uri uri) {
        Activity activity = getActivity();
        if (activity == null) {
            fail("open", "Android activity is unavailable.");
            return;
        }
        try (InputStream input = activity.getContentResolver().openInputStream(uri);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            if (input == null) throw new IllegalStateException("The selected document cannot be read.");
            byte[] buffer = new byte[8192];
            int total = 0;
            int count;
            while ((count = input.read(buffer)) >= 0) {
                total += count;
                if (total > maximumImportBytes) throw new IllegalStateException("Selected file exceeds the 16 MiB import limit.");
                output.write(buffer, 0, count);
            }
            String contents = output.toString(StandardCharsets.UTF_8.name());
            emitSafe("document_opened", contents, displayName(uri, "selected.crpggame"));
        } catch (Exception error) {
            fail("open", message(error));
        }
    }

    private String displayName(Uri uri, String fallback) {
        Activity activity = getActivity();
        if (activity == null) return fallback;
        ContentResolver resolver = activity.getContentResolver();
        try (Cursor cursor = resolver.query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (column >= 0) return cursor.getString(column);
            }
        } catch (Exception ignored) { }
        return fallback;
    }

    private String sanitizeFilename(String filename) {
        String safe = filename == null ? "" : filename.trim().replaceAll("[\\\\/:*?\"<>|]", "_");
        if (safe.isEmpty()) safe = "crpg_game.crpggame";
        if (!safe.toLowerCase().endsWith(".crpggame")) safe += ".crpggame";
        return safe;
    }

    private void fail(String operation, String detail) {
        emitSafe("operation_failed", operation, detail);
    }

    private void emitSafe(String signal, Object... arguments) {
        Activity activity = getActivity();
        if (activity == null) {
            emitSignal(signal, arguments);
            return;
        }
        activity.runOnUiThread(() -> emitSignal(signal, arguments));
    }

    private String message(Exception error) {
        String detail = error.getMessage();
        return detail == null || detail.isEmpty() ? error.getClass().getSimpleName() : detail;
    }
}
