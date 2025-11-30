//
//  SiriPlusPlusApp.swift
//  SiriPlusPlus
//
//  Created by Ved Panse on 11/28/25.
//

import SwiftUI

@main
struct SiriPlusPlusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 900)
        #endif
    }
}
