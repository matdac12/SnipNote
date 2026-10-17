import UIKit

/// Names the app the keyboard is typing into, so SnipNote can send the user back to it after
/// the keyboard opens SnipNote to start a session. Private API; personal build only.
///
/// Approach from Dictus (MIT, https://github.com/getdictus/dictus-ios, HostAppResolver.swift).
/// The arbiter's `sourceBundleIdentifier` can be stale (it named an app the user had left in
/// about 1 in 4 cases there), so it is never used directly. Each read records the pair
/// (pid → bundle ID); the answer is the entry for our own `_hostProcessIdentifier`, which is
/// always current. The table lives only in memory: pids get recycled.
@MainActor
enum HostAppResolver {
  private static var table: [Int: String] = [:]

  /// Call on every keyboard appearance, text change and before opening SnipNote. The arbiter
  /// fills in about 200 ms after the keyboard appears, so one read is not enough.
  static func harvest() {
    ensureConnection()
    guard let state = clientState(),
          let bundleID = read("sourceBundleIdentifier", from: state) as? String, !bundleID.isEmpty,
          let pid = (read("processIdentifier", from: state) as? NSNumber)?.intValue, pid > 0
    else { return }
    table[pid] = bundleID
  }

  static func currentHost(for controller: UIInputViewController) -> String? {
    harvest()
    guard let pid = (read("_hostProcessIdentifier", from: controller) as? NSNumber)?.intValue, pid > 0 else {
      print("↩️ [Keyboard] Host pid unavailable")
      return nil
    }
    guard let bundleID = table[pid] else {
      print("↩️ [Keyboard] Host pid \(pid) not seen by the arbiter (known: \(table.count))")
      return nil
    }
    return bundleID
  }

  private static func client() -> NSObject? {
    guard let cls = NSClassFromString("_UIKeyboardArbiterClient") as AnyObject?,
          cls.responds(to: NSSelectorFromString("automaticSharedArbiterClient"))
    else { return nil }
    return cls.perform(NSSelectorFromString("automaticSharedArbiterClient"))?.takeUnretainedValue() as? NSObject
  }

  private static func clientState() -> NSObject? {
    client().flatMap { read("currentClientState", from: $0) as? NSObject }
  }

  private static func ensureConnection() {
    guard let client = client(), read("connection", from: client) == nil else { return }
    let start = NSSelectorFromString("startConnection")
    if client.responds(to: start) { _ = client.perform(start) }
  }

  /// `value(forKey:)` on a missing key raises an exception Swift cannot catch; check first.
  private static func read(_ key: String, from object: NSObject) -> Any? {
    guard object.responds(to: NSSelectorFromString(key)) else { return nil }
    return object.value(forKey: key)
  }
}
