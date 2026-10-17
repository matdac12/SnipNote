import UIKit

/// Sends the user back to the app they were typing in, after the keyboard opened SnipNote
/// to start a dictation session. iOS has no public API for this (Apple DTS confirmed);
/// this personal build tries two workarounds, selectable on the Dictation screen:
///
/// - `urlScheme`: opens the host's own URL scheme from a hand-checked table. Approach from
///   Dictus (MIT, https://github.com/getdictus/dictus-ios, KnownAppSchemes.swift), verified
///   there on iOS 26.6.1.
/// - `bundleID`: opens the host by bundle identifier through the private
///   `LSApplicationWorkspace`. Unverified on recent iOS. Never ship this to the App Store.
enum DictationHostReturn {
  enum Method: String, CaseIterable, Identifiable {
    case urlScheme, bundleID, off
    var id: String { rawValue }
    var title: String {
      switch self {
      case .urlScheme: "URL scheme"
      case .bundleID: "Bundle ID (private)"
      case .off: "Off"
      }
    }
  }

  static let methodKey = "dictation.returnMethod"

  static var method: Method {
    UserDefaults.standard.string(forKey: methodKey).flatMap(Method.init(rawValue:)) ?? .urlScheme
  }

  /// Apps whose scheme resumes the screen the user left. Keep it to apps checked by hand.
  private static let schemes = [
    "com.apple.mobilenotes": "mobilenotes://",
  ]

  @MainActor
  static func returnTo(_ bundleID: String?) {
    guard let bundleID, !bundleID.isEmpty else {
      print("↩️ [Dictation] No host app known; swipe back by hand")
      return
    }
    switch method {
    case .off:
      print("↩️ [Dictation] Auto-return is off (host \(bundleID))")
    case .urlScheme:
      guard let scheme = schemes[bundleID], let url = URL(string: scheme) else {
        print("↩️ [Dictation] No return scheme for \(bundleID)")
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        print("↩️ [Dictation] \(scheme) → \(opened ? "returned" : "open failed")")
      }
    case .bundleID:
      let opened = openWithWorkspace(bundleID)
      print("↩️ [Dictation] LSApplicationWorkspace \(bundleID) → \(opened ? "returned YES" : "failed")")
    }
  }

  /// `[[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:]`, resolved at
  /// runtime. It returns a BOOL, so it is called through its IMP rather than `perform`.
  private static func openWithWorkspace(_ bundleID: String) -> Bool {
    guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as AnyObject?,
          workspaceClass.responds(to: NSSelectorFromString("defaultWorkspace")),
          let workspace = workspaceClass.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject
    else { return false }
    let selector = NSSelectorFromString("openApplicationWithBundleID:")
    guard workspace.responds(to: selector), let method = class_getInstanceMethod(type(of: workspace), selector) else {
      return false
    }
    typealias OpenFunction = @convention(c) (AnyObject, Selector, NSString) -> Bool
    let open = unsafeBitCast(method_getImplementation(method), to: OpenFunction.self)
    return open(workspace, selector, bundleID as NSString)
  }
}
