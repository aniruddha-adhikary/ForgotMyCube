//
//  DeviceIDView.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import SwiftUI
import UIKit

/// View for editing and displaying the device ID
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

/// Custom text field that limits length and validates input
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