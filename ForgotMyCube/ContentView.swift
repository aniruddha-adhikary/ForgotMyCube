//
//  ContentView.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI

struct HeartRateView: View {
    @State private var heartRate: Int = 72
    
    // Timer to simulate heart rate changes
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
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
                        .scaleEffect(1.0 + 0.1 * sin(Double(heartRate) / 10))
                        .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: heartRate)
                    
                    Text("\(heartRate)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.red)
                    
                    Text("BPM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Last updated: \(Date().formatted(.dateTime))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 20)
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
            
            Text("Connect your Apple Watch to see live heart rate data")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
