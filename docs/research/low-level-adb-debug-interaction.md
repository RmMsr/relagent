# Flutter Debug App Interaction Guide

## ADB Device Setup

```bash
# Check device connection
adb devices

# Get device info
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release

# Screen info
adb shell dumpsys window displays | grep -A 5 "Display:"
```

## Flutter Debug Build Capabilities

- **UI Hierarchy Inspection**: `adb shell uiautomator dump /sdcard/ui.xml`
- **Element Location**: Parse bounds from XML (e.g., `[21,2151][933,2277]`)
- **Coordinate Calculation**: Center = ((left+right)/2, (top+bottom)/2)

## Interaction Workflow

```bash
# 1. Launch app
adb shell am start -n org.venkado.relagent/.MainActivity

# 2. Dump UI hierarchy
adb shell uiautomator dump /sdcard/ui.xml
adb pull /sdcard/ui.xml /tmp/ui.xml

# 3. Find input field bounds in XML
# Example: bounds="[21,2151][933,2277]"

# 4. Calculate center coordinates
# X: (21 + 933) / 2 = 477
# Y: (2151 + 2277) / 2 = 2214

# 5. Click to focus
adb shell input tap 477 2214

# 6. Input text and submit
adb shell input text "hello"
adb shell input keyevent 66  # Enter key
```

## Key Findings

- Debug builds allow UI hierarchy dumping via `uiautomator`
- Input fields located at bottom of screen (~2100-2300 Y coordinates)
- Precise coordinate calculation enables reliable automation
- Flutter apps respond well to ADB input commands

## Troubleshooting

- Ensure device is connected: `adb devices`
- App must be debug build for full UI inspection
- Pull XML file locally for easier parsing: `adb pull /sdcard/ui.xml /tmp/`
- Test coordinates with `adb shell input tap X Y` before automation

## Related Tools

- `flutter devices` - List Flutter-compatible devices
- `flutter attach` - Connect debugger (may need app restart)
- `adb logcat` - Monitor device logs
- `adb shell screencap` - Capture screenshots

_Documented from Flutter debug interaction session - captures ADB + Flutter integration patterns for future reference._
