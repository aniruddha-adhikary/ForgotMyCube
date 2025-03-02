//
//  ContentView.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI
import HealthKit
import CoreBluetooth

// App theme colors
struct AppTheme {
    static let primaryColor = Color(red: 3/255, green: 177/255, blue: 199/255)
    static let stopColor = Color(red: 0.9, green: 0.3, blue: 0.3)
}

// Heart Rate Bluetooth Service & Characteristic UUIDs
fileprivate let heartRateServiceUUID = CBUUID(string: "180D")
fileprivate let heartRateCharacteristicUUID = CBUUID(string: "2A37")
fileprivate let deviceInformationServiceUUID = CBUUID(string: "180A")
fileprivate let deviceNameCharacteristicUUID = CBUUID(string: "2A00")

// For storing user preferences
class UserPreferences {
    private static let defaults = UserDefaults.standard
    
    // Device ID keys
    private static let deviceIdKey = "com.forgotmycube.deviceId"
    
    // Default device ID
    private static let defaultDeviceId = "0139305"
    
    // Get current device ID or default
    static func getDeviceId() -> String {
        return defaults.string(forKey: deviceIdKey) ?? defaultDeviceId
    }
    
    // Save device ID
    static func saveDeviceId(_ id: String) {
        defaults.set(id, forKey: deviceIdKey)
    }
}

class HeartRatePeripheral: NSObject, CBPeripheralManagerDelegate, ObservableObject {
    @Published var isAdvertising = false
    @Published var status: String = "Not initialized"
    @Published var deviceId: String = UserPreferences.getDeviceId() {
        didSet {
            // Only update if valid and different
            if deviceId != oldValue, isValidDeviceId(deviceId) {
                UserPreferences.saveDeviceId(deviceId)
                if isAdvertising {
                    // Restart advertising with new ID
                    stopAdvertising()
                    startAdvertising()
                }
            }
        }
    }
    
    private var peripheralManager: CBPeripheralManager!
    private var heartRateService: CBMutableService!
    private var heartRateCharacteristic: CBMutableCharacteristic!
    private var deviceNameCharacteristic: CBMutableCharacteristic!
    private var currentHeartRate: UInt8 = 72
    
    // Format the full device name with prefix
    var fullDeviceName: String {
        return "BFT-\(deviceId)"
    }
    
    // Validate device ID (must be 7 digits)
    func isValidDeviceId(_ id: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: "^\\d{7}$")
        return regex.firstMatch(in: id, range: NSRange(location: 0, length: id.count)) != nil
    }
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            status = "Bluetooth powered on"
            setupServices()
        case .poweredOff:
            status = "Bluetooth is off - enable Bluetooth in settings"
            stopAdvertising()
        case .unauthorized, .unsupported:
            status = "Bluetooth LE is not supported or unauthorized"
        case .resetting:
            status = "Bluetooth is resetting"
        case .unknown:
            status = "Bluetooth state unknown"
        @unknown default:
            status = "Unknown Bluetooth state"
        }
    }
    
    private func setupServices() {
        // Heart Rate Measurement Characteristic
        heartRateCharacteristic = CBMutableCharacteristic(
            type: heartRateCharacteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        
        // Heart Rate Service
        heartRateService = CBMutableService(type: heartRateServiceUUID, primary: true)
        heartRateService.characteristics = [heartRateCharacteristic]
        
        // Device Name Characteristic
        let nameData = fullDeviceName.data(using: .utf8)
        deviceNameCharacteristic = CBMutableCharacteristic(
            type: deviceNameCharacteristicUUID,
            properties: [.read],
            value: nameData,
            permissions: [.readable]
        )
        
        // Add services to peripheral manager
        peripheralManager.add(heartRateService)
        
        let deviceInfoService = CBMutableService(type: deviceInformationServiceUUID, primary: true)
        deviceInfoService.characteristics = [deviceNameCharacteristic]
        peripheralManager.add(deviceInfoService)
    }
    
    func startAdvertising() {
        if peripheralManager.state != .poweredOn {
            status = "Bluetooth not powered on"
            return
        }
        
        // Update device name characteristic with current ID
        if let deviceNameChar = deviceNameCharacteristic {
            let nameData = fullDeviceName.data(using: .utf8)
            _ = peripheralManager.updateValue(nameData!, for: deviceNameChar, onSubscribedCentrals: nil)
        }
        
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [heartRateServiceUUID],
            CBAdvertisementDataLocalNameKey: fullDeviceName
        ])
        
        isAdvertising = true
        status = "Broadcasting as \(fullDeviceName)"
    }
    
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        status = "Stopped broadcasting"
    }
    
    func updateHeartRate(_ heartRate: UInt8) {
        guard isAdvertising else { return }
        
        currentHeartRate = heartRate
        
        // Format heart rate measurement as per HRM profile
        // The first byte is a flags field
        // Bit 0 is set to 0 for UINT8 heart rate value (set to 1 for UINT16)
        let heartRateValue: [UInt8] = [0x00, currentHeartRate]
        let data = Data(heartRateValue)
        
        let didSend = peripheralManager.updateValue(
            data,
            for: heartRateCharacteristic,
            onSubscribedCentrals: nil
        )
        
        if !didSend {
            status = "Failed to send update"
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            status = "Error adding service: \(error.localizedDescription)"
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            status = "Error advertising: \(error.localizedDescription)"
            isAdvertising = false
        }
    }
    
    deinit {
        stopAdvertising()
    }
}

class HeartRateManager: ObservableObject {
    private var healthStore = HKHealthStore()
    @Published var heartRate: Double = 72
    @Published var lastUpdated = Date()
    @Published var authorizationStatus: String = "Requesting authorization..."
    @Published var isSimulationMode = false
    
    private var heartRateQuery: HKQuery?
    private var simulationTimer: Timer?
    
    // Bluetooth peripheral
    var peripheral = HeartRatePeripheral()
    
    init() {
        // Start in simulation mode first to avoid crashes
        startSimulation()
        
        // After a brief delay, try to connect to HealthKit
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.requestAuthorization()
        }
    }
    
    func requestAuthorization() {
        // Check if HealthKit is available
        guard HKHealthStore.isHealthDataAvailable() else {
            self.authorizationStatus = "HealthKit not available on this device"
            startSimulation()
            return
        }
        
        // Define the types we want to read from HealthKit
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            self.authorizationStatus = "Heart rate type is no longer available in HealthKit"
            startSimulation()
            return
        }
        
        // Important Note: If your app crashes here with an error about NSHealthShareUsageDescription,
        // you need to:
        // 1. Open the project in Xcode
        // 2. Go to Project Settings > Info tab
        // 3. Add "Privacy - Health Share Usage Description" with a description
        // 4. Add "Privacy - Health Update Usage Description" with a description
        // 5. Enable HealthKit in Signing & Capabilities tab
        
        // Use do-catch to handle Info.plist related errors gracefully
        do {
            // Use a wrapped call to handle possible exceptions
            try self.requestHealthKitAuthorization(for: heartRateType)
        } catch {
            DispatchQueue.main.async {
                let errorMessage = error.localizedDescription
                
                if errorMessage.contains("healthkit entitlement") {
                    self.authorizationStatus = "Missing HealthKit entitlement. Please add HealthKit capability in Xcode:\n1. Open project in Xcode\n2. Select target\n3. Go to Signing & Capabilities\n4. Add HealthKit capability"
                } else if errorMessage.contains("NSHealthShareUsageDescription") {
                    self.authorizationStatus = "Missing privacy descriptions in Info.plist"
                } else {
                    self.authorizationStatus = "HealthKit error: \(errorMessage)"
                }
                
                self.startSimulation()
            }
        }
    }
    
    private func requestHealthKitAuthorization(for heartRateType: HKQuantityType) throws {
        // Request authorization, but handle possible exceptions
        healthStore.requestAuthorization(toShare: nil, read: [heartRateType]) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.authorizationStatus = "Error: \(error.localizedDescription)"
                    self.startSimulation()
                    return
                }
                
                if success {
                    self.authorizationStatus = "Authorization successful"
                    self.startHeartRateQuery()
                } else {
                    self.authorizationStatus = "Authorization denied"
                    self.startSimulation()
                }
            }
        }
    }
    
    func startHeartRateQuery() {
        // Define the sample type for heart rate
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { 
            startSimulation()
            return 
        }
        
        // Create a predicate for samples from the last 24 hours
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-24 * 60 * 60),
            end: Date(),
            options: .strictEndDate
        )
        
        // Order the samples by date descending (most recent first)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        // Create a query to get the most recent heart rate
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] (_, samples, error) in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.authorizationStatus = "Error querying heart rate: \(error.localizedDescription)"
                    self.startSimulation()
                }
                return
            }
            
            if let sample = samples?.first as? HKQuantitySample {
                self.processHeartRateSample(sample)
            } else {
                DispatchQueue.main.async {
                    self.authorizationStatus = "No recent heart rate data available"
                    self.startSimulation()
                }
            }
            
            // Start observing heart rate updates
            self.startHeartRateObserver()
        }
        
        // Execute the query
        healthStore.execute(query)
    }
    
    func startHeartRateObserver() {
        // Define the sample type for heart rate
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        
        // Create a query to observe heart rate changes
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] (query, completionHandler, error) in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.authorizationStatus = "Error observing heart rate: \(error.localizedDescription)"
                }
                completionHandler()
                return
            }
            
            // Create a query to get the most recent heart rate
            let sampleQuery = HKSampleQuery(
                sampleType: heartRateType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { [weak self] (_, samples, error) in
                guard let self = self else {
                    completionHandler()
                    return
                }
                
                if let sample = samples?.first as? HKQuantitySample {
                    self.processHeartRateSample(sample)
                }
                
                completionHandler()
            }
            
            // Execute the sample query
            self.healthStore.execute(sampleQuery)
        }
        
        // Save the query for later
        self.heartRateQuery = query
        
        // Execute the query
        healthStore.execute(query)
        
        // Enable background delivery for heart rate updates
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { (success, error) in
            if let error = error {
                print("Failed to enable background delivery: \(error.localizedDescription)")
            }
        }
    }
    
    func processHeartRateSample(_ sample: HKQuantitySample) {
        // Convert the sample to beats per minute (BPM)
        let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let heartRate = sample.quantity.doubleValue(for: heartRateUnit)
        
        // Update the published properties on the main thread
        DispatchQueue.main.async {
            self.heartRate = heartRate
            self.lastUpdated = Date()
            self.isSimulationMode = false
            
            // Update Bluetooth broadcast with real heart rate data
            self.peripheral.updateHeartRate(UInt8(Int(heartRate)))
            
            // Start broadcasting if not already
            if !self.peripheral.isAdvertising {
                self.peripheral.startAdvertising()
            }
        }
    }
    
    func startSimulation() {
        DispatchQueue.main.async {
            self.isSimulationMode = true
            
            // Stop any existing simulation
            self.stopSimulation()
            
            // Create a timer that simulates heart rate changes
            self.simulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // Generate a realistic heart rate with some variation
                let baseHeartRate = 72.0
                let variation = Double.random(in: -10...10)
                let newHeartRate = max(50, min(120, baseHeartRate + variation))
                self.heartRate = newHeartRate
                self.lastUpdated = Date()
                
                // Update Bluetooth broadcast
                self.peripheral.updateHeartRate(UInt8(Int(newHeartRate)))
            }
            
            // Trigger initial update
            self.heartRate = Double.random(in: 65...80)
            self.lastUpdated = Date()
            
            // Start broadcasting if not already
            if !self.peripheral.isAdvertising {
                self.peripheral.startAdvertising()
            }
        }
    }
    
    func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
    
    deinit {
        stopSimulation()
        
        // Stop heart rate query if active
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
    }
}

struct DeviceIDView: View {
    @ObservedObject var peripheral: HeartRatePeripheral
    @State private var deviceIdInput: String = ""
    @State private var showingEditor = false
    @State private var sheetErrorMessage: String?
    
    var body: some View {
        VStack {
            HStack {
                Text("Device ID: BFT-")
                    .font(.caption)
                
                Text(peripheral.deviceId)
                    .font(.caption.bold())
                
                Button(action: {
                    deviceIdInput = peripheral.deviceId
                    sheetErrorMessage = nil
                    showingEditor = true
                }) {
                    Image(systemName: "pencil.circle")
                        .font(.caption)
                }
            }
            .padding(.vertical, 3)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationView {
                Form {
                    Section(header: Text("Enter 7-digit Device ID")) {
                        HStack {
                            Text("BFT-")
                                .foregroundColor(.secondary)
                            
                            // Custom text field with length limit of 7 and numeric validation
                            LimitedTextField(
                                text: $deviceIdInput,
                                placeholder: "Device ID",
                                limit: 7,
                                allowedCharacters: "0123456789",
                                keyboardType: .numberPad
                            )
                        }
                        
                        if let error = sheetErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(AppTheme.stopColor)
                                .padding(.top, 4)
                        }
                    }
                    
                    Section {
                        Button("Save") {
                            if peripheral.isValidDeviceId(deviceIdInput) {
                                peripheral.deviceId = deviceIdInput
                                sheetErrorMessage = nil
                                showingEditor = false
                            } else {
                                sheetErrorMessage = "ID must be exactly 7 digits"
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(deviceIdInput.count == 7 ? .blue : .gray)
                        .disabled(deviceIdInput.count != 7)
                    }
                }
                .navigationTitle("Edit Device ID")
                .navigationBarItems(trailing: Button("Cancel") {
                    showingEditor = false
                })
            }
        }
    }
}

// Custom text field that limits length and validates input
struct LimitedTextField: View {
    @Binding var text: String
    var placeholder: String
    var limit: Int
    var allowedCharacters: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        TextField(placeholder, text: Binding(
            get: { self.text },
            set: { newValue in
                // Limit length
                let limitedText = String(newValue.prefix(limit))
                
                // Filter allowed characters
                self.text = limitedText.filter { allowedCharacters.contains($0) }
            }
        ))
        .keyboardType(keyboardType)
    }
}

struct HeartRateView: View {
    @ObservedObject var heartRateManager: HeartRateManager
    
    var body: some View {
        VStack {
            Text("Heart Rate")
                .font(.headline)
                .padding(.bottom, 5)
                
            DeviceIDView(peripheral: heartRateManager.peripheral)
                .padding(.bottom, 10)
            
            ZStack {
                Circle()
                    .fill(AppTheme.primaryColor.opacity(0.1))
                    .frame(width: 200, height: 200)
                
                Circle()
                    .stroke(AppTheme.primaryColor, lineWidth: 2)
                    .frame(width: 200, height: 200)
                
                VStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(AppTheme.primaryColor)
                        .font(.system(size: 50))
                        .scaleEffect(1.0 + 0.1 * sin(Double(heartRateManager.heartRate) / 10))
                        .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: heartRateManager.heartRate)
                    
                    Text("\(Int(heartRateManager.heartRate))")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(AppTheme.primaryColor)
                    
                    Text("BPM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Space between heart rate and status
            Spacer()
                .frame(height: 20)
                
            HStack {
                Circle()
                    .fill(heartRateManager.peripheral.isAdvertising ? AppTheme.primaryColor : Color.gray)
                    .frame(width: 10, height: 10)
                
                Text(heartRateManager.peripheral.isAdvertising ? 
                     "Broadcasting as BFT-\(heartRateManager.peripheral.deviceId)" : 
                     "Not broadcasting")
                    .font(.caption)
                    .foregroundColor(heartRateManager.peripheral.isAdvertising ? AppTheme.primaryColor : .secondary)
            }
            .padding(.top, 5)
            
            if heartRateManager.isSimulationMode {
                Text("SIMULATION MODE")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 5)
            }
            
            Text(heartRateManager.authorizationStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 5)
                
            Text(heartRateManager.peripheral.status)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
                
            if !heartRateManager.peripheral.isAdvertising {
                Button(action: {
                    heartRateManager.peripheral.startAdvertising()
                }) {
                    Text("Start Broadcasting")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.primaryColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            } else {
                Button(action: {
                    heartRateManager.peripheral.stopAdvertising()
                }) {
                    Text("Stop Broadcasting")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.stopColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 10)
            }
        }
        .padding()
        .onAppear {
            // Start simulation on appear
            heartRateManager.startSimulation()
        }
    }
}

struct ContentView: View {
    var heartRateManager = HeartRateManager()
    
    var body: some View {
        VStack {
            Text("ForgotMyCube")
                .font(.title2)
                .padding(.top)
            
            Text("BFT-\(heartRateManager.peripheral.deviceId)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HeartRateView(heartRateManager: heartRateManager)
            
            Spacer()
        }
    }
}

#Preview {
    ContentView(heartRateManager: HeartRateManager())
}