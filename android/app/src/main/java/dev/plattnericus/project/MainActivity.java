package dev.plattnericus.project;

import android.content.ComponentName;
import android.content.pm.PackageManager;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    private static final String CHANNEL = "pokyh/app_icon";
    private static final String PKG = "dev.plattnericus.project";

    // Maps iconName (dart side) → activity-alias class name suffix.
    // null key = default icon → MainActivityDefault alias.
    private static final Map<String, String> ALIASES = new HashMap<String, String>() {{
        put(null,               "MainActivityDefault");
        put("AppIconKlassisch", "MainActivityKlassisch");
        put("AppIconNexor",     "MainActivityNexor");
        put("AppIconNexor2",    "MainActivityNexor2");
        put("AppIconSpez",      "MainActivitySpez");
    }};

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("setIcon")) {
                    String iconName = call.argument("iconName");
                    setAppIcon(iconName);
                    result.success(null);
                } else if (call.method.equals("getIcon")) {
                    result.success(getActiveIcon());
                } else {
                    result.notImplemented();
                }
            });
    }

    private void setAppIcon(String iconName) {
        PackageManager pm = getPackageManager();
        // Never touch MainActivity itself — it must always stay enabled so
        // flutter run / adb am start .MainActivity always works.
        // Only toggle aliases: exactly one is enabled at a time.
        for (Map.Entry<String, String> e : ALIASES.entrySet()) {
            ComponentName cn = new ComponentName(PKG, PKG + "." + e.getValue());
            boolean enable = (iconName == null)
                ? (e.getKey() == null)
                : iconName.equals(e.getKey());
            pm.setComponentEnabledSetting(
                cn,
                enable
                    ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    : PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            );
        }
    }

    private String getActiveIcon() {
        PackageManager pm = getPackageManager();
        for (Map.Entry<String, String> e : ALIASES.entrySet()) {
            if (e.getKey() == null) continue; // skip default alias
            ComponentName cn = new ComponentName(PKG, PKG + "." + e.getValue());
            int state = pm.getComponentEnabledSetting(cn);
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return e.getKey();
            }
        }
        return null; // default icon active
    }
}
