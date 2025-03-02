# Development Guidelines for ForgotMyCube

## Build & Run Commands
- Open project in Xcode: `open ForgotMyCube.xcodeproj`
- Build: Product > Build (⌘B)
- Run on simulator: Product > Run (⌘R)
- Run on device: Select device from target dropdown, then ⌘R

## Project Configuration
- Required capabilities: HealthKit, Bluetooth
- Info.plist needs: NSHealthShareUsageDescription, NSBluetoothAlwaysUsageDescription

## Code Style
- Struct/class names: PascalCase (e.g., `HeartRateManager`)
- Variables/functions: camelCase (e.g., `deviceId`, `startAdvertising()`)
- Include type annotations for properties but let Swift infer function return types
- Group related properties and methods together
- Use Apple's Swift API Design Guidelines: https://swift.org/documentation/api-design-guidelines/
- Use SwiftUI's declarative syntax; avoid imperative UIKit patterns
- For error handling, use `guard` statements with early returns
- For optionals, prefer optional chaining (`?.`) over force unwrapping (`!`)

## Theme Colors
- Primary: RGB(3, 177, 199) - Use AppTheme.primaryColor
- Stop actions: RGB(230, 76, 76) - Use AppTheme.stopColor