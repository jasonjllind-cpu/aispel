package se.johan.stlviewer;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int OPEN_STL = 1001;

    private final ExecutorService ioExecutor = Executors.newSingleThreadExecutor();

    private StlGLSurfaceView glView;
    private TextView status;
    private LinearLayout topBar;
    private TextView bottomHelp;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        buildUi();

        if (!handleIncomingIntent(getIntent())) {
            loadDemo();
        }
    }

    private void buildUi() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.rgb(14, 17, 23));

        glView = new StlGLSurfaceView(this);
        root.addView(glView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));

        topBar = new LinearLayout(this);
        topBar.setOrientation(LinearLayout.VERTICAL);
        topBar.setPadding(dp(12), dp(10), dp(12), dp(10));
        topBar.setBackgroundColor(Color.argb(220, 22, 25, 32));

        TextView title = new TextView(this);
        title.setText("STL Viewer");
        title.setTextColor(Color.WHITE);
        title.setTextSize(19f);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        topBar.addView(title);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.CENTER_VERTICAL);

        Button open = new Button(this);
        open.setText("Öppna STL");
        open.setOnClickListener(v -> openFilePicker());
        buttons.addView(open);

        Button demo = new Button(this);
        demo.setText("Demo");
        demo.setOnClickListener(v -> loadDemo());
        buttons.addView(demo);

        Button reset = new Button(this);
        reset.setText("Återställ vy");
        reset.setOnClickListener(v -> glView.resetView());
        buttons.addView(reset);

        topBar.addView(buttons);

        status = new TextView(this);
        status.setText("Ingen modell laddad");
        status.setTextColor(Color.rgb(215, 220, 230));
        status.setTextSize(13f);
        topBar.addView(status);

        FrameLayout.LayoutParams topLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
        );
        root.addView(topBar, topLp);

        bottomHelp = new TextView(this);
        bottomHelp.setText("Dra med ett finger = rotera   •   Nyp med två fingrar = zoom");
        bottomHelp.setTextColor(Color.WHITE);
        bottomHelp.setTextSize(13f);
        bottomHelp.setGravity(Gravity.CENTER);
        bottomHelp.setPadding(dp(12), dp(10), dp(12), dp(10));
        bottomHelp.setBackgroundColor(Color.argb(205, 22, 25, 32));

        FrameLayout.LayoutParams bottomLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
        );
        root.addView(bottomHelp, bottomLp);

        root.setOnApplyWindowInsetsListener((v, insets) -> {
            int topInset = insets.getSystemWindowInsetTop();
            int bottomInset = insets.getSystemWindowInsetBottom();

            topBar.setPadding(dp(12), dp(10) + topInset, dp(12), dp(10));
            bottomHelp.setPadding(dp(12), dp(10), dp(12), dp(10) + bottomInset);
            return insets;
        });

        setContentView(root);
    }

    private void openFilePicker() {
        // Vissa Android-filhanterare rapporterar .stl med olika MIME-typer
        // (t.ex. application/vnd.ms-pki.stl). Om vi MIME-filtrerar här kan
        // filen synas i sökningen men ändå inte vara valbar. Därför låter vi
        // systemväljaren returnera vilken öppningsbar fil som helst och
        // validerar innehållet i STL-parsern efter valet.
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);

        try {
            startActivityForResult(intent, OPEN_STL);
        } catch (Exception ex) {
            Toast.makeText(this, "Kunde inte öppna Androids filväljare.", Toast.LENGTH_LONG).show();
        }
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode == OPEN_STL && resultCode == RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri == null) {
                setStatus("Ingen fil valdes.");
                return;
            }

            int takeFlags = data.getFlags() &
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            try {
                getContentResolver().takePersistableUriPermission(uri, takeFlags);
            } catch (Exception ignored) {
                // Tillfällig läsrättighet räcker för denna visning.
            }

            setStatus("Öppnar " + displayName(uri) + "…");
            loadUri(uri);
        }
    }

    private boolean handleIncomingIntent(Intent intent) {
        if (intent == null) return false;

        Uri uri = intent.getData();
        if (uri == null) return false;

        String action = intent.getAction();
        if (Intent.ACTION_VIEW.equals(action) || Intent.ACTION_EDIT.equals(action)) {
            loadUri(uri);
            return true;
        }
        return false;
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIncomingIntent(intent);
    }

    private void loadUri(Uri uri) {
        setStatus("Läser " + displayName(uri) + "…");

        ioExecutor.execute(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri)) {
                if (input == null) {
                    throw new IllegalStateException("Kunde inte öppna filen.");
                }

                Mesh mesh = StlParser.parse(input);
                runOnUiThread(() -> showMesh(mesh, displayName(uri)));
            } catch (Exception ex) {
                runOnUiThread(() ->
                        setStatus("Fel: " + (ex.getMessage() != null ? ex.getMessage() : ex.getClass().getSimpleName()))
                );
            }
        });
    }

    private void loadDemo() {
        setStatus("Läser demo…");

        ioExecutor.execute(() -> {
            try (InputStream input = getAssets().open("sample_cube.stl")) {
                Mesh mesh = StlParser.parse(input);
                runOnUiThread(() -> showMesh(mesh, "Demo: kub"));
            } catch (Exception ex) {
                runOnUiThread(() -> setStatus("Demo kunde inte laddas: " + ex.getMessage()));
            }
        });
    }

    private void showMesh(Mesh mesh, String name) {
        glView.setMesh(mesh);

        String text = String.format(
                Locale.US,
                "%s  •  %,d trianglar  •  X %.2f × Y %.2f × Z %.2f",
                name,
                mesh.triangleCount,
                mesh.sizeX(),
                mesh.sizeY(),
                mesh.sizeZ()
        );
        setStatus(text);
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(
                uri,
                new String[] { OpenableColumns.DISPLAY_NAME },
                null,
                null,
                null
        )) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    String name = cursor.getString(index);
                    if (name != null && !name.trim().isEmpty()) return name;
                }
            }
        } catch (Exception ignored) {
            // Fallback till URI-namnet nedan.
        }

        String last = uri.getLastPathSegment();
        if (last == null || last.trim().isEmpty()) return "STL-modell";

        int slash = Math.max(last.lastIndexOf('/'), last.lastIndexOf(':'));
        if (slash >= 0 && slash + 1 < last.length()) {
            last = last.substring(slash + 1);
        }
        return last;
    }

    private void setStatus(String text) {
        status.setText(text);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (glView != null) glView.onResume();
    }

    @Override
    protected void onPause() {
        if (glView != null) glView.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        ioExecutor.shutdownNow();
        super.onDestroy();
    }
}
