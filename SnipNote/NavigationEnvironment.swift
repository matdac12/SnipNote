//
//  NavigationEnvironment.swift
//  SnipNote
//
//  Created by Claude Code on 19/09/25.
//

import SwiftUI

// Environment key for navigating to Eve with a specific meeting
private struct NavigateToEveKey: EnvironmentKey {
    static let defaultValue: (UUID) -> Void = { _ in
        // Default implementation does nothing
        print("Warning: navigateToEve called but no handler provided")
    }
}

extension EnvironmentValues {
    var navigateToEve: (UUID) -> Void {
        get { self[NavigateToEveKey.self] }
        set { self[NavigateToEveKey.self] = newValue }
    }
}