# Data Management

## What gets stored where

Relagent stores data in the engine and in the apps.

### Engine data

The Relagent engine stores session data in its configured data directory. By default this is `./data` relative to where the engine is started, but it can be configured via the `persistence.data_dir` setting. Check `~/.local/share/org.venkado.relagent-engine/settings.ini` for your actual location.

### App settings (SharedPreferences)

Non-sensitive settings such as the API endpoint URL, model name, prime message, voice settings, and boolean flags indicating whether credentials are saved. This data is stored in the platform's standard app preferences store.

### App credentials (secure storage)

Passwords and API keys are stored separately in platform-specific secure storage — never in SharedPreferences:

- **Android**: Android Keystore / Encrypted SharedPreferences
- **iOS**: iOS Keychain
- **Linux**: GNOME Keyring or KWallet via the Secret Service API (requires `gnome-keyring` or `kwallet` to be running)

## Removing Engine Data

To remove all data, you need to delete the `data_dir` and `settings.ini`. If you used the defaults:

```shell
rm -rf ~/.local/share/org.venkado.relagent-engine
```

Depending on your setup, you also want to remove systems services and unit files:

```shell
# Remove systemd relagent-engine
systemctl --user disable --now relagent-engine.service
rm ~/.config/containers/systemd/relagent-engine.container

# Remove auto update timer changes
rm ~/.config/systemd/user/podman-auto-update.timer.d/override.conf
systemctl --user daemon-reload
systemctl --user restart podman-auto-update.timer
```

## Removing App Data and Credentials

### Android

To clear all app settings and saved credentials:

1. Open **Settings** → **Apps** (or Application Manager)
2. Find **Relagent** in the list
3. Tap **Storage**
4. Tap **Clear Data** (removes all settings and credentials)

Alternatively, uninstalling the app also removes all stored credentials.

### iOS

iOS does not provide a way to clear app data without uninstalling. To remove all settings and credentials:

1. Open **Settings** → **General** → **iPhone Storage**
2. Find **Relagent** and tap it
3. Tap **Delete App**
4. Reinstall from the App Store if needed

Note: On iOS, Keychain items may persist after uninstall in some configurations. If credentials need to be fully removed, reset the device or use the app's built-in **Clear Credentials** button before uninstalling.

### Linux

App settings are stored as a JSON file. To remove it run:

```shell
rm ~/.local/share/org.venkado.relagent/shared_preferences.json
```

Confidential secrets are stored in the Secret Service (GNOME Keyring / KWallet). To remove them run:

```shell
secret-tool clear account org.venkado.relagent.secureStorage
```

Or use a keyring manager like `Seahorse`.
