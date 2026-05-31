## API Keys and Runtime Configuration

This project uses MQTT for Raspberry Pi communication and xeno-canto API v3 for online bird sound lookup.

Do not hard-code private keys in the source code.

Run the Flutter app with:

```powershell
flutter run -d YOUR_DEVICE --dart-define=MQTT_PASSWORD=your-mqtt-password --dart-define=XENO_CANTO_API_KEY=your-xeno-canto-api-key

To obtain a xeno-canto API key, create an account on xeno-canto, verify your email, and copy the API key from your account page.

The xeno-canto key is required for real online bird recording search and playback. Without it, the app can still receive MQTT detections, but online bird sound lookup may fail.