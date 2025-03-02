//
//  HeartRateView.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI
import HealthKit

/// View for displaying heart rate and broadcasting controls
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