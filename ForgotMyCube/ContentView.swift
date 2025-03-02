//
//  ContentView.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI
import HealthKit

class HeartRateManager: ObservableObject {
    private var healthStore = HKHealthStore()
    @Published var heartRate: Double = 72
    @Published var lastUpdated = Date()
    @Published var authorizationStatus: String = "Requesting authorization..."
    @Published var isSimulationMode = false
    
    private var heartRateQuery: HKQuery?
    private var simulationTimer: Timer?
    
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
                self.heartRate = max(50, min(120, baseHeartRate + variation))
                self.lastUpdated = Date()
            }
            
            // Trigger initial update
            self.heartRate = Double.random(in: 65...80)
            self.lastUpdated = Date()
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

struct HeartRateView: View {
    @ObservedObject var heartRateManager = HeartRateManager()
    
    var body: some View {
        VStack {
            Text("Heart Rate")
                .font(.headline)
                .padding(.bottom, 5)
            
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 200, height: 200)
                
                Circle()
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: 200, height: 200)
                
                VStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 50))
                        .scaleEffect(1.0 + 0.1 * sin(Double(heartRateManager.heartRate) / 10))
                        .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: heartRateManager.heartRate)
                    
                    Text("\(Int(heartRateManager.heartRate))")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.red)
                    
                    Text("BPM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Last updated: \(heartRateManager.lastUpdated.formatted(.dateTime))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 20)
            
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
        }
        .padding()
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Apple Watch Heart Rate Monitor")
                .font(.title2)
                .padding(.top)
            
            HeartRateView()
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}