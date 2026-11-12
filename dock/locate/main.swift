// Mocha Location: finds where the Mac is, once, for the weather widget, then quits.
// It's a tiny app of its own (built into bin/MochaLocation.app by install.sh) because
// macOS only gives location to apps that ask for it by name; the dock helper runs it
// with `open` and reads the answer from the file named on the command line:
//   {"lat":..,"lon":..,"city":"..","detail":".."}  or  {"error":"denied"|"failed"}
import AppKit
import CoreLocation

let output = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("/") })
    ?? NSHomeDirectory() + "/.config/sketchybar-dock/cache/location.json"

func finish(_ json: [String: Any]) -> Never {
    if let data = try? JSONSerialization.data(withJSONObject: json) {
        try? data.write(to: URL(fileURLWithPath: output))
    }
    exit(0)
}

final class Finder: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // a town is plenty for weather
        Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in finish(["error": "failed"]) }
        decide()
    }

    private func decide() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()   // macOS asks you; the answer comes back below
        case .denied, .restricted: finish(["error": "denied"])
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { decide() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let here = locations.last else { return }
        manager.delegate = nil
        CLGeocoder().reverseGeocodeLocation(here) { marks, _ in
            let m = marks?.first
            finish(["lat": here.coordinate.latitude, "lon": here.coordinate.longitude,
                    "city": m?.locality ?? m?.subAdministrativeArea ?? m?.name ?? "Here",
                    "detail": [m?.administrativeArea, m?.country].compactMap { $0 }.joined(separator: ", ")])
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { finish(["error": "denied"]) }
        if (error as? CLError)?.code == .locationUnknown { return }   // still looking
        finish(["error": "failed"])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let finder = Finder()
finder.start()
app.run()
