# ForgotMyCube

ForgotMyCube is an iOS app that broadcasts heart rate data over Bluetooth using the standard Heart Rate Measurement profile. It's designed to connect Apple Watch heart rate data to gym equipment or other Bluetooth receivers that support the Heart Rate Monitor (HRM) service.

![ForgotMyCube 001](https://github.com/user-attachments/assets/6750440d-0069-4cfb-9e7d-2b7e4f068f12)

## Features

- Reads real-time heart rate data from Apple Watch (requires HealthKit setup)
- Falls back to simulated heart rate data if HealthKit is not available
- Broadcasts as a standard Bluetooth Heart Rate Monitor
- Configurable device ID (BFT-xxxxxxx format)
- Persists settings between app launches

## Requirements

- iOS 16.0 or later
- Xcode 14.0 or later
- Apple Watch paired with iPhone (for real heart rate data)
- Device with Bluetooth capabilities

## Installation

1. Clone the repository
   ```
   git clone https://github.com/aniruddha-adhikary/ForgotMyCube.git
   ```

2. Open the project in Xcode
   ```
   cd ForgotMyCube
   open ForgotMyCube.xcodeproj
   ```

3. Configure the project:
   - Select your development team in Signing & Capabilities
   - Add HealthKit capability
   - Add Bluetooth capability
   - Ensure the Info.plist has the required privacy descriptions

4. Build and run on your device (simulator won't support Bluetooth broadcasting)

## Usage

1. Launch the app
2. (Optional) Tap the pencil icon to set your custom device ID
3. Tap "Start Broadcasting" to begin transmitting heart rate data
4. Connect your gym equipment or other Bluetooth device to "BFT-xxxxxxx"
5. Your heart rate will be displayed on the connected device

## How It Works

The app uses CoreBluetooth to create a peripheral manager that advertises the standard Heart Rate Service (UUID: 0x180D). It implements the Heart Rate Measurement characteristic (UUID: 0x2A37) according to the Bluetooth SIG specifications.

When your Apple Watch is connected, the app reads heart rate data through HealthKit. If HealthKit is unavailable or unauthorized, the app simulates realistic heart rate data.

## Privacy

ForgotMyCube requires the following permissions:
- Bluetooth access to broadcast heart rate data
- HealthKit access to read heart rate from Apple Watch

No data is sent to external servers. All processing happens locally on your device.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Apple Developer Documentation for CoreBluetooth and HealthKit
- Bluetooth SIG for the Heart Rate Service specification
