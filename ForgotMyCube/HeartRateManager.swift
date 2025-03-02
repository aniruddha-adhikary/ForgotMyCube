//
//  HeartRateManager.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI
import HealthKit

/// Class for managing heart rate data (real or simulated)
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
                    self.authorizationStatus = "Missing HealthKit entitlement. Please add HealthKit capability in Xcode"
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
        
        // Stop any existing query
        if let existingQuery = heartRateQuery {
            healthStore.stop(existingQuery)
        }
        
        // First, execute a sample query to get the most recent heart rate
        let samplePredicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-600), end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let initialQuery = HKSampleQuery(
            sampleType: heartRateType,
            predicate: samplePredicate,
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
                self.updateHeartRate(from: sample)
            } else {
                DispatchQueue.main.async {
                    self.authorizationStatus = "No recent heart rate data available"
                    self.startSimulation()
                }
            }
            
            // Set up a long-term observer query
            self.setupHeartRateObserver(for: heartRateType)
        }
        
        // Execute the query
        healthStore.execute(initialQuery)
    }
    
    private func setupHeartRateObserver(for heartRateType: HKQuantityType) {
        // Create a query to observe heart rate changes - without a limit
        let observerQuery = HKObserverQuery(
            sampleType: heartRateType,
            predicate: nil
        ) { [weak self] (_, completionHandler, error) in
            guard let self = self else {
                completionHandler()
                return
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.authorizationStatus = "Error observing heart rate: \(error.localizedDescription)"
                }
                completionHandler()
                return
            }
            
            // When new data is available, execute a sample query to get it
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
                    self.updateHeartRate(from: sample)
                }
                
                completionHandler()
            }
            
            // Execute the sample query
            self.healthStore.execute(sampleQuery)
        }
        
        // Save the query for later cleanup
        self.heartRateQuery = observerQuery
        
        // Execute the observer query
        healthStore.execute(observerQuery)
        
        // Enable background delivery for heart rate updates
        healthStore.enableBackgroundDelivery(
            for: heartRateType,
            frequency: .immediate
        ) { (success, error) in
            if let error = error {
                print("Failed to enable background delivery: \(error.localizedDescription)")
            }
        }
    }
    
    func updateHeartRate(from sample: HKQuantitySample) {
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