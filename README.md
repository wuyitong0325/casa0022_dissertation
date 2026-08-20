# Park Life Monitor

**Interactive Bird and Bat Monitoring System for Urban Biodiversity**

Park Life Monitor is a dissertation project that explores how automated
bioacoustic monitoring can be connected to a public-facing mobile application
to make urban wildlife activity more accessible and understandable to
non-specialist users.

The system combines a Raspberry Pi 5, an ultrasonic microphone, automated bird
and bat classification, MQTT communication, and a Flutter mobile application.

This repository contains both:

- the complete Flutter application; and
- the Raspberry Pi scripts used for bird and bat monitoring and MQTT control.

---

## Project Website

A public landing page for the project, including the app download and project
materials, is available here:

**https://wuyitong0325.github.io/casa0022_dissertation/**

---

## System Overview

The implemented data path is:

```text
Bird / Bat sound
      ↓
Dodotronic Ultramic 384K EVO
      ↓
Raspberry Pi 5
      ↓
BirdNET / BatDetect2
      ↓
MQTT
      ↓
Flutter App
      ↓
Live feedback / Diary / Atlas / Discover / Device control
```

The Raspberry Pi records audio locally and performs classification at the edge.
Detection metadata is then transmitted to the application through MQTT.

Raw audio recordings are not transmitted to the mobile application. MQTT
messages contain structured detection information such as species name,
confidence, timestamp, and device status.

---

## Main Features

### Bird Monitoring

`raspberry_pi/live_bird.py`

- Records 3-second audio windows
- Uses 192 kHz, 16-bit mono recording
- Uses BirdNET through `birdnetlib`
- Applies confidence and non-bird filtering
- Publishes valid detections and detector status through MQTT
- Records processing-time information for evaluation

### Bat Monitoring

`raspberry_pi/live_bat.py`

- Records 4-second ultrasonic audio windows
- Uses 192 kHz, 16-bit mono recording
- Runs BatDetect2 locally on the Raspberry Pi
- Applies confidence, frequency, call-duration, and call-count filtering
- Publishes valid bat detections and detector status through MQTT
- Removes temporary audio and model-output files after processing

### App-Controlled Monitoring

`raspberry_pi/exhibition_monitor.py`

The Flutter application can remotely select:

```text
Bird Mode
Bat Mode
Stop
```

Commands are transmitted through MQTT. The controller starts or stops the
corresponding detector process and publishes the current device state back to
the application.

`raspberry_pi/main_monitor.py` is an alternative time-based controller that
switches between bird monitoring during the day and bat monitoring at night.

---

## Flutter Application

The Flutter application is implemented mainly under:

```text
lib/
├── main.dart
├── models/
├── pages/
├── services/
└── widgets/
```

The application contains five main interfaces.

### Live

Displays recent bird or bat detections and near-real-time detection feedback.

### Diary

Stores recent detection events so that wildlife activity can be revisited
rather than disappearing after a live notification.

### Atlas

Provides an educational species exploration interface and contextual
biodiversity information.

### Discover

Maintains a persistent species collection based on received detections.

### Device

Displays connection and device status and allows the user to select Bird Mode,
Bat Mode, or stop monitoring.

The application also supports:

- local notifications;
- persistent detection history;
- confidence display;
- species information;
- online species images;
- online bird audio lookup; and
- MQTT-based monitoring control.

---

## Repository Structure

```text
casa0022_dissertation/
│
├── lib/                         # Flutter application source code
│   ├── main.dart
│   ├── models/
│   ├── pages/
│   ├── services/
│   └── widgets/
│
├── raspberry_pi/                # Raspberry Pi monitoring scripts
│   ├── live_bird.py
│   ├── live_bat.py
│   ├── exhibition_monitor.py
│   ├── main_monitor.py
│   ├── compare_spectrogram_pc.py
│   ├── receive_bird_log.py
│   ├── mqtt_config.example.py
│   └── livebird.service
│
├── android/                     # Flutter Android platform files
├── ios/                         # Flutter iOS platform files
├── web/                         # Flutter Web platform files
├── windows/                     # Flutter Windows platform files
├── linux/                       # Flutter Linux platform files
├── macos/                       # Flutter macOS platform files
│
├── docs/                        # GitHub Pages / app distribution material
├── pubspec.yaml                 # Flutter dependencies
└── README.md
```

---

## MQTT Communication

The prototype uses:

```text
Broker: mqtt.cetools.org
Port:   1884
Base topic:
student/wuyitong0325/park_life_monitor
```

Main topics include:

| Topic | Purpose |
|---|---|
| `/command/mode` | App → Raspberry Pi monitoring command |
| `/status/mode` | Current monitoring mode |
| `/status/bird` | Bird detector status |
| `/status/bat` | Bat detector status |
| `/detections/bird` | Bird detection events |
| `/detections/bat` | Bat detection events |

For example:

```text
student/wuyitong0325/park_life_monitor/detections/bird
```

The application subscribes to the Park Life Monitor topic hierarchy and updates
its interface when new detections or device-status messages arrive.

---

## Flutter Setup

Install Flutter and retrieve the project dependencies:

```bash
git clone https://github.com/wuyitong0325/casa0022_dissertation.git
cd casa0022_dissertation

flutter pub get
```

Private credentials are not stored directly in the repository.

Run the application with runtime configuration.

### Windows PowerShell

```powershell
flutter run -d YOUR_DEVICE `
  --dart-define=MQTT_PASSWORD=your-mqtt-password `
  --dart-define=XENO_CANTO_API_KEY=your-xeno-canto-api-key
```

### macOS / Linux

```bash
flutter run -d YOUR_DEVICE \
  --dart-define=MQTT_PASSWORD=your-mqtt-password \
  --dart-define=XENO_CANTO_API_KEY=your-xeno-canto-api-key
```

The Xeno-canto API key is used for online bird recording lookup and playback.
Without it, MQTT monitoring can still operate, but online bird audio lookup may
not be available.

---

## Raspberry Pi Configuration

The monitoring scripts are contained in:

```text
raspberry_pi/
```

Create the local MQTT configuration from the supplied example:

```bash
cd raspberry_pi
cp mqtt_config.example.py mqtt_config.py
```

Then edit the local configuration:

```python
MQTT_PASSWORD = "YOUR_MQTT_PASSWORD"
```

Do not commit the real password to GitHub.

The implementation used a Dodotronic Ultramic 384K EVO configured as:

```text
Sample rate: 192000 Hz
Channels:    1
Format:      16-bit PCM
ALSA device: hw:2,0
```

Bird monitoring requires BirdNET through `birdnetlib`.

Bat monitoring requires BatDetect2 and the Python/audio dependencies used by
`live_bat.py`.

The paths in the Raspberry Pi scripts correspond to the dissertation prototype
installation under:

```text
/home/wuyitong0325/
```

These paths should be changed if the project is installed under another user or
directory.

---

## Running the Monitoring System

For direct bird-monitoring testing:

```bash
python3 raspberry_pi/live_bird.py
```

For direct bat-monitoring testing:

```bash
python3 raspberry_pi/live_bat.py
```

For the dissertation exhibition configuration, the manual MQTT controller is:

```bash
python3 raspberry_pi/exhibition_monitor.py
```

The controller waits for commands from the Flutter application and launches the
corresponding bird or bat detector.

---

## Detection Workflow

### Bird Mode

```text
Ultramic recording
      ↓
3-second WAV
      ↓
BirdNET analysis
      ↓
confidence / non-bird filtering
      ↓
MQTT detection payload
      ↓
Flutter application
```

### Bat Mode

```text
Ultramic recording
      ↓
4-second ultrasonic WAV
      ↓
BatDetect2 analysis
      ↓
confidence + frequency + call filtering
      ↓
MQTT detection payload
      ↓
Flutter application
```

Bird and bat recording and inference are performed sequentially. This means
that the detector is not actively recording while the current audio segment is
being analysed.

---

## Evaluation Scope

The dissertation prototype was evaluated primarily through controlled physical
playback.

Reference wildlife recordings were played through external speakers, travelled
through the air, and were re-recorded by the Ultramic before classification.

Therefore, the evaluation tested the complete physical and software path:

```text
reference recording
→ speaker
→ acoustic environment
→ Ultramic
→ Raspberry Pi
→ classifier
→ MQTT
→ Flutter application
```

The reference WAV files were not directly supplied to BirdNET or BatDetect2
during these end-to-end tests.

The prototype was not used as a long-term ecological survey of Queen Elizabeth
Olympic Park. The evaluation therefore demonstrates system integration and
technical feasibility rather than field-survey accuracy.

---

## Application Data Flow

When a valid detection is received by the Flutter application, it can be used
to update several parts of the interface:

```text
MQTT detection
      ↓
Live feedback
      ↓
Detection history / Diary
      ↓
Persistent species collection
      ↓
Species information and media
      ↓
Local notification
```

The application therefore acts not only as a live display but also as a
persistent public-facing interface for revisiting and interpreting detected
wildlife activity.

---

## External Services

The application uses several external services for species information and
media.

These may include:

- Xeno-canto for bird audio;
- Wikipedia for species information;
- biodiversity data services;
- online species-image sources; and
- OpenStreetMap tiles for map display.

Availability of online content depends on network connectivity and the
corresponding external service.

Local application content and previously stored detection information can still
remain available when some online resources are unavailable.

---

## Technologies

- Raspberry Pi 5
- Raspberry Pi OS / Linux
- Python 3
- Flutter
- Dart
- BirdNET
- `birdnetlib`
- BatDetect2
- Dodotronic Ultramic 384K EVO
- MQTT
- Xeno-canto
- OpenStreetMap
- Flutter Map
- GitHub Pages

---

## Security and API Keys

Private MQTT passwords and API keys must not be committed to this repository.

The Flutter application accepts sensitive configuration through
`--dart-define`, while the Raspberry Pi code provides
`mqtt_config.example.py` as a template.

Before publishing changes, check that no real:

- MQTT passwords;
- Xeno-canto API keys; or
- other private credentials

are included in tracked files.

---

## Important Limitations

This repository contains a working research prototype rather than a production
wildlife-monitoring platform.

Important limitations include:

- evaluation was based mainly on controlled playback rather than long-term
  outdoor deployment;
- bat detection was sensitive to ultrasonic speaker/microphone orientation and
  high-frequency interference;
- bird and bat recording and inference are sequential, creating non-recording
  periods during analysis;
- the MQTT prototype connection is not intended as a production-grade secure
  deployment;
- external species images and audio depend on network availability; and
- the application has not yet been evaluated through a formal participant study.

These limitations are discussed in the accompanying dissertation.

---

## Dissertation

This repository accompanies the MSc dissertation:

**Park Life Monitor: An Interactive Bird and Bat Monitoring System for Urban
Biodiversity**

The project modernises an existing wildlife-monitoring concept into a
Raspberry Pi-based dual-mode monitoring system and connects automated
detections to a public-facing Flutter application.

The main implementation combines:

```text
audio capture
+ automated classification
+ MQTT communication
+ application feedback
+ persistent detection records
+ monitoring control
```

The project focuses on the complete system and user-facing interaction rather
than the development of new machine-learning classifiers.

---

## Author

**Yitong Wu**

MSc Connected Environments  
University College London