import Cocoa
import FlutterMacOS
import app_links

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  // Handle universal links
  public override func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
    guard let url = AppLinks.shared.getUniversalLink(userActivity) else {
      return false
    }
    
    AppLinks.shared.handleLink(link: url.absoluteString)
    
    return false // Returning true will stop the propagation to other packages
  }
  
  // Handle custom URL schemes
  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    AppLinks.shared.handleLink(link: url.absoluteString)
  }
}
