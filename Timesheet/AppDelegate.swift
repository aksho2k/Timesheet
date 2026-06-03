import AppKit
import SwiftUI
import Combine
import GoogleSignIn

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let viewModel = TimesheetViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var lastDismissTime: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureGoogleSignIn()
        setupStatusItem()
        setupPopover()
        observeViewModel()
    }

    // MARK: - Google Sign-In

    private func configureGoogleSignIn() {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.hasPrefix("YOUR_") else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            GIDSignIn.sharedInstance.handle(url)
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timesheet")
        button.imagePosition = .imageLeading
        button.action = #selector(handleStatusItemClick)
        button.target = self
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
                .environmentObject(viewModel)
        )
    }

    private func observeViewModel() {
        viewModel.$statusBarTitle
            .sink { [weak self] title in
                self?.updateStatusItem(title: title)
            }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard Date().timeIntervalSince(lastDismissTime) > 0.15 else { return }
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateStatusItem(title: String?) {
        guard let button = statusItem.button else { return }
        if let title = title {
            button.image = nil
            // Monospaced digits prevent the button from resizing as seconds tick over
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ]
            button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timesheet")
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        lastDismissTime = Date()
    }
}
