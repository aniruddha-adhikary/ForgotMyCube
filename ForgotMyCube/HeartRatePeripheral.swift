//
//  HeartRatePeripheral.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI
import CoreBluetooth

// Heart Rate Bluetooth Service & Characteristic UUIDs
fileprivate let heartRateServiceUUID = CBUUID(string: "180D")
fileprivate let heartRateCharacteristicUUID = CBUUID(string: "2A37")
fileprivate let deviceInformationServiceUUID = CBUUID(string: "180A")
fileprivate let deviceNameCharacteristicUUID = CBUUID(string: "2A00")

/// Class responsible for Bluetooth heart rate broadcasting
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