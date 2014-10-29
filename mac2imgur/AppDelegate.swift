/* This file is part of mac2imgur.
*
* mac2imgur is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.

* mac2imgur is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with mac2imgur.  If not, see <http://www.gnu.org/licenses/>.
*/

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, ScreenshotMonitorDelegate, UploadControllerDelegate {
    
    @IBOutlet weak var menu: NSMenu!
    @IBOutlet weak var accountItem: NSMenuItem!
    
    var prefs: PreferencesManager!
    var imgurClient: ImgurClient!
    var monitor: ScreenshotMonitor!
    var uploadController: ImgurUploadController!
    var authController: ImgurAuthWindowController!
    var statusItem: NSStatusItem!
    var lastLink: String = ""
    var paused = false
    
    // Delegate methods
    
    func applicationDidFinishLaunching(aNotification: NSNotification?) {
        NSApp.activateIgnoringOtherApps(true)
        
        NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self
        
        prefs = PreferencesManager()
        imgurClient = ImgurClient(preferences: prefs)
        uploadController = ImgurUploadController(imgurClient: imgurClient)
        
        // Create status bar icon
        let statusIcon = NSImage(named: "StatusIcon")!
        statusIcon.setTemplate(true)
        
        // Set account menu item to relevant title
        updateAccountItemTitle()
        
        // Add about and quit items to menu
        menu.addItemWithTitle("About mac2imgur", action: NSSelectorFromString("orderFrontStandardAboutPanel:"), keyEquivalent: "")
        menu.addItemWithTitle("Quit", action: NSSelectorFromString("terminate:"), keyEquivalent: "")
        
        // Add menu to status bar
        statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(-1) // NSVariableStatusItemLength
        statusItem.menu = menu
        statusItem.button?.image = statusIcon
        statusItem.button?.toolTip = "mac2imgur"
        
        // Start monitoring for screenshots
        monitor = ScreenshotMonitor(delegate: self)
    }
    
    func applicationWillTerminate(aNotification: NSNotification?) {
        monitor.query.stopQuery()
    }
    
    func screenshotDetected(pathToImage: String) {
        if !paused {
            let upload = ImgurUpload(pathToImage: pathToImage, isScreenshot: true, client: imgurClient, delegate: self)
            uploadController.addToQueue(upload)
        }
    }
    
    func uploadAttemptCompleted(successful: Bool, isScreenshot: Bool, link: String, pathToImage: String) {
        let type = isScreenshot ? "Screenshot" : "Image"
        if successful {
            lastLink = link
            copyToClipboard(lastLink)
            displayNotification("\(type) uploaded successfully!", informativeText: self.lastLink)
            
            if isScreenshot && prefs.getBool(PreferencesConstant.deleteScreenshotAfterUpload.rawValue, def: false) {
                println("Deleting screenshot @ \(pathToImage)")
                deleteFile(pathToImage)
            }
        } else {
            displayNotification("\(type) upload failed...", informativeText: "")
        }
    }
    
    func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification!) {
        if notification.informativeText != "" {
            openURL(notification.informativeText!)
        }
    }
    
    // Selector methods
    
    @IBAction func selectImages(sender: NSMenuItem) {
        var panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["jpg", "jpeg", "gif", "png", "apng", "tiff", "bmp", "pdf", "xcf"]
        if panel.runModal() == NSOKButton {
            for imageURL in panel.URLs {
                if let path = (imageURL as NSURL).path? {
                    let upload = ImgurUpload(pathToImage: path, isScreenshot: false, client: imgurClient, delegate: self)
                    uploadController.addToQueue(upload)
                }
            }
        }
    }
    
    @IBAction func copyLastLink(sender: NSMenuItem) {
        copyToClipboard(lastLink)
    }
    
    @IBAction func accountAction(sender: NSMenuItem) {
        if imgurClient.authenticated {
            imgurClient.deleteCredentials()
            updateAccountItemTitle()
        } else {
            authController = ImgurAuthWindowController(windowNibName: "ImgurAuthWindow")
            authController.imgurClient = imgurClient
            authController.prefs = prefs
            authController.callback = {
                self.displayNotification("Signed in as \(self.imgurClient.username!)", informativeText: "")
                self.updateAccountItemTitle()
            }
            authController.showWindow(self)
        }
    }
    
    @IBAction func deleteAfterUploadOption(sender: NSMenuItem) {
        if sender.state == NSOnState {
            prefs.setBool(PreferencesConstant.deleteScreenshotAfterUpload.rawValue, value: false)
            sender.state = NSOffState
        } else {
            prefs.setBool(PreferencesConstant.deleteScreenshotAfterUpload.rawValue, value: true)
            sender.state = NSOnState
        }
    }
    
    @IBAction func pauseDetectionOption(sender: NSMenuItem) {
        if sender.state == NSOnState {
            paused = false
            sender.state = NSOffState
        } else {
            paused = true
            sender.state = NSOnState
        }
        statusItem.button?.appearsDisabled = paused
    }
    
    // Utility methods
    
    func copyToClipboard(string: String) {
        let pasteBoard = NSPasteboard.generalPasteboard()
        pasteBoard.clearContents()
        pasteBoard.setString(string, forType: NSStringPboardType)
    }
    
    func deleteFile(pathToFile: String) {
        var error: NSError?
        NSFileManager.defaultManager().removeItemAtPath(pathToFile, error: &error)
        if error != nil {
            NSLog(error!.localizedDescription)
        }
    }
    
    func openURL(url: String) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: url)!)
    }
    
    func displayNotification(title: String, informativeText: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = informativeText
        NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
    }
    
    func updateAccountItemTitle() {
        accountItem.title = imgurClient.authenticated ? "Sign out (\(imgurClient.username!))" : "Sign in"
    }
}