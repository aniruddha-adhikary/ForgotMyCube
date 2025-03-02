//
//  ContentView.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI

/// Main content view for the application
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