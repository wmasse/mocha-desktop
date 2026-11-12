// The weather widget's city picker: type a city and pick it from a list that says
// which state and country each match is in, see them all on a big, plain map, or
// just click the map anywhere. "Use My Location" follows wherever the Mac is
// (through bin/MochaLocation.app, which asks macOS for permission the first time).

import AppKit
import MapKit

struct Place {
    var name: String, detail: String, lat: Double, lon: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

final class PlacePin: NSObject, MKAnnotation {
    let place: Place
    init(_ place: Place) { self.place = place }
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name }
    var subtitle: String? { place.detail }
}

final class CityPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, MKMapViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let search = NSSearchField()
    private let table = NSTableView()
    private let map = MKMapView()
    private let chosenName = NSTextField(labelWithString: "")
    private let chosenDetail = NSTextField(labelWithString: "")
    private let note = NSTextField(labelWithString: "")
    private let useButton = NSButton(title: "Use This City", target: nil, action: nil)
    private let hereButton = NSButton(title: "Use My Location", target: nil, action: nil)
    private var results: [Place] = []
    private var chosen: Place?
    private var searchTimer: Timer?
    private var searchSerial = 0

    /// Picked a place, or "my location"
    var onPick: (Place) -> Void = { _ in }
    var onUseLocation: () -> Void = {}
    var onClose: () -> Void = {}

    init(current: Place?, followingLocation: Bool) {
        super.init()
        build()
        if let current {
            choose(current, zoom: true)
            search.stringValue = current.name
            runSearch(current.name)
        } else {
            map.setRegion(MKCoordinateRegion(center: .init(latitude: 39, longitude: -96), span: .init(latitudeDelta: 40, longitudeDelta: 60)), animated: false)
            chosenName.stringValue = "No city yet"
            chosenDetail.stringValue = "Search above, or click the map"
            useButton.isEnabled = false
        }
        if followingLocation { note.stringValue = "Following your location now. Pick a city to stop." }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(search)
    }

    // MARK: layout

    private func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Choose Your City"
        window.minSize = NSSize(width: 700, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let root = NSView()
        window.contentView = root

        // Search, big and first
        search.placeholderString = "Search for a city, like “Middletown” or “Paris”"
        search.font = .systemFont(ofSize: 17)
        search.controlSize = .large
        search.delegate = self
        search.target = self; search.action = #selector(searchChanged)
        search.sendsSearchStringImmediately = true

        hereButton.image = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
        hereButton.imagePosition = .imageLeading
        hereButton.bezelStyle = .rounded; hereButton.controlSize = .large
        hereButton.target = self; hereButton.action = #selector(useHere)

        // The matches, each with its state and country
        let column = NSTableColumn(identifier: .init("place"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 54
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .sourceList
        table.dataSource = self; table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        // A plain, easy-to-read map: no businesses or landmarks, just places and roads
        map.delegate = self
        map.pointOfInterestFilter = .excludingAll
        map.showsZoomControls = true
        map.showsCompass = false
        map.wantsLayer = true; map.layer?.cornerRadius = 10; map.layer?.masksToBounds = true
        map.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(mapClicked(_:))))

        // What you've picked, and the button that keeps it
        chosenName.font = .boldSystemFont(ofSize: 18)
        chosenDetail.font = .systemFont(ofSize: 14); chosenDetail.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "Tip: click anywhere on the map to pick that spot.")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .tertiaryLabelColor
        useButton.bezelStyle = .rounded; useButton.controlSize = .large; useButton.keyEquivalent = "\r"
        useButton.target = self; useButton.action = #selector(useChosen)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded; cancel.controlSize = .large; cancel.keyEquivalent = "\u{1b}"

        for v in [search, hereButton, scroll, map, chosenName, chosenDetail, note, hint, useButton, cancel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        let pad: CGFloat = 18
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: pad),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            search.trailingAnchor.constraint(equalTo: hereButton.leadingAnchor, constant: -10),
            search.heightAnchor.constraint(equalToConstant: 32),
            hereButton.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            hereButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),

            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad - 6),
            scroll.widthAnchor.constraint(equalToConstant: 300),
            scroll.bottomAnchor.constraint(equalTo: chosenName.topAnchor, constant: -14),

            map.topAnchor.constraint(equalTo: scroll.topAnchor),
            map.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 10),
            map.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            map.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),

            chosenName.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            chosenName.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -12),
            chosenDetail.leadingAnchor.constraint(equalTo: chosenName.leadingAnchor),
            chosenDetail.topAnchor.constraint(equalTo: chosenName.bottomAnchor, constant: 2),
            chosenDetail.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -12),
            note.leadingAnchor.constraint(equalTo: chosenName.leadingAnchor),
            note.topAnchor.constraint(equalTo: chosenDetail.bottomAnchor, constant: 4),
            note.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -pad),
            hint.trailingAnchor.constraint(equalTo: map.trailingAnchor),
            hint.topAnchor.constraint(equalTo: map.bottomAnchor, constant: 6),

            useButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            useButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -pad),
            cancel.trailingAnchor.constraint(equalTo: useButton.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: useButton.centerYAnchor),
        ])
    }

    // MARK: search

    @objc private func searchChanged() {
        searchTimer?.invalidate()
        let text = search.stringValue
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in self?.runSearch(text) }
    }

    /// "Paris, France" or "Middletown NY" → matches, the most likely first
    private func runSearch(_ query: String) {
        var parts = query.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 1, let last = parts[0].split(separator: " ").last, last.count == 2, last == last.uppercased(), parts[0].contains(" ") {
            parts = [String(parts[0].dropLast(3)), String(last)]   // "Middletown NY" → "Middletown", "NY"
        }
        guard let name = parts.first, name.count >= 2 else { results = []; table.reloadData(); showPins(); return }
        searchSerial += 1
        let serial = searchSerial
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "20"),
                        .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, _ in
            // matches in the state or country you typed after a comma come first, then the rest, biggest first
            var matched: [Place] = [], rest: [Place] = []
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let found = json["results"] as? [[String: Any]] {
                let hint = parts.dropFirst().joined(separator: " ").lowercased()
                for r in found {
                    guard let n = r["name"] as? String, let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { continue }
                    // "New Jersey · Monmouth": the state first, then the county; the country only when it isn't yours
                    let code = (r["country_code"] as? String ?? "").lowercased()
                    let home = (Locale.current.region?.identifier ?? "").lowercased()
                    var words: [String] = []
                    for w in [r["admin1"], r["admin2"], code == home ? nil : r["country"]].compactMap({ $0 as? String })
                        where !w.isEmpty && w != n && !words.contains(w) { words.append(w) }
                    let place = Place(name: n, detail: words.joined(separator: " · "), lat: lat, lon: lon)
                    // "NY" for New York: a state's initials count too
                    let initials = (r["admin1"] as? String ?? "").split(separator: " ").compactMap { $0.first.map { String($0).lowercased() } }.joined()
                    if hint.isEmpty || place.detail.lowercased().contains(hint) || code == hint || initials == hint { matched.append(place) } else { rest.append(place) }
                }
            }
            let places = matched + rest
            DispatchQueue.main.async {
                guard let self, serial == self.searchSerial else { return }
                self.results = places
                // the saved city from before the picker had no state; take it from the match it came from
                if let c = self.chosen, c.detail.isEmpty,
                   let same = places.first(where: { abs($0.lat - c.lat) < 0.05 && abs($0.lon - c.lon) < 0.05 }) {
                    self.choose(same, zoom: false)
                    if let row = places.firstIndex(where: { $0.lat == same.lat && $0.lon == same.lon }) {
                        self.table.selectRowIndexes([row], byExtendingSelection: false)
                    }
                }
                self.table.reloadData()
                self.showPins()
            }
        }.resume()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Return in the search field picks the top match
        if (obj.userInfo?["NSTextMovement"] as? Int) == NSReturnTextMovement, let first = results.first {
            table.selectRowIndexes([0], byExtendingSelection: false)
            choose(first, zoom: true)
        }
    }

    // MARK: list

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let place = results[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: "mappin.circle.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemRed
        icon.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        let name = NSTextField(labelWithString: place.name)
        name.font = .boldSystemFont(ofSize: 15); name.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: place.detail.isEmpty ? " " : place.detail)
        detail.font = .systemFont(ofSize: 12.5); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        for v in [icon, name, detail] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            name.bottomAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1),
            detail.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            detail.topAnchor.constraint(equalTo: cell.centerYAnchor, constant: 2),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < results.count else { return }
        choose(results[table.selectedRow], zoom: true)
    }

    // MARK: map

    /// Every match as a pin; the map fits them (or stays on the one you picked)
    private func showPins() {
        map.removeAnnotations(map.annotations.filter { ($0 as? PlacePin)?.place.name != chosen?.name || ($0 as? PlacePin)?.place.lat != chosen?.lat })
        let pins = results.map(PlacePin.init)
        map.addAnnotations(pins)
        guard chosen == nil || table.selectedRow < 0, !pins.isEmpty else { return }
        if chosen == nil {
            map.showAnnotations(pins, animated: true)
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let pin = annotation as? PlacePin else { return nil }
        let v = MKMarkerAnnotationView(annotation: pin, reuseIdentifier: nil)
        let isChosen = chosen.map { $0.lat == pin.place.lat && $0.lon == pin.place.lon } ?? false
        v.markerTintColor = isChosen ? .systemRed : .systemGray
        v.glyphImage = NSImage(systemSymbolName: isChosen ? "star.fill" : "circle.fill", accessibilityDescription: nil)
        v.titleVisibility = .visible
        v.subtitleVisibility = isChosen ? .visible : .hidden
        v.displayPriority = isChosen ? .required : .defaultHigh
        v.canShowCallout = false
        return v
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let pin = view.annotation as? PlacePin else { return }
        if let row = results.firstIndex(where: { $0.lat == pin.place.lat && $0.lon == pin.place.lon }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        choose(pin.place, zoom: false)
    }

    /// A click on the map (not on a pin) picks that spot, named after the town there
    @objc private func mapClicked(_ g: NSClickGestureRecognizer) {
        let point = g.location(in: map)
        if map.annotations.contains(where: { a in
            let p = map.convert(a.coordinate, toPointTo: map)
            return hypot(p.x - point.x, p.y - point.y) < 22
        }) { return }
        let coordinate = map.convert(point, toCoordinateFrom: map)
        let spot = Place(name: "Dropped pin", detail: String(format: "%.3f, %.3f", coordinate.latitude, coordinate.longitude),
                         lat: coordinate.latitude, lon: coordinate.longitude)
        table.deselectAll(nil)
        choose(spot, zoom: false)
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { [weak self] marks, _ in
            guard let self, let m = marks?.first, self.chosen?.lat == spot.lat else { return }
            let name = m.locality ?? m.subAdministrativeArea ?? m.name ?? "Dropped pin"
            let detail = [m.administrativeArea, m.country].compactMap { $0 }.joined(separator: ", ")
            self.choose(Place(name: name, detail: detail, lat: spot.lat, lon: spot.lon), zoom: false)
        }
    }

    private func choose(_ place: Place, zoom: Bool) {
        chosen = place
        chosenName.stringValue = place.name
        chosenDetail.stringValue = place.detail
        useButton.title = "Use \(place.name)"
        useButton.isEnabled = true
        // redraw the pins so the chosen one is red and labelled
        let others = map.annotations.compactMap { $0 as? PlacePin }.filter { !($0.place.lat == place.lat && $0.place.lon == place.lon) }
        map.removeAnnotations(map.annotations)
        map.addAnnotations(others)
        map.addAnnotation(PlacePin(place))
        if zoom {
            map.setRegion(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000), animated: true)
        }
    }

    // MARK: buttons

    @objc private func useChosen() {
        guard let chosen else { return }
        onPick(chosen)
        window.close()
    }
    @objc private func useHere() {
        onUseLocation()
        window.close()
    }
    @objc private func cancel() { window.close() }
    func close() { window.close() }

    func windowWillClose(_ notification: Notification) { onClose() }
}

// MARK: - Where the Mac is

/// Asks bin/MochaLocation.app (which has the permission) where the Mac is
enum MacLocation {
    static let app = configDir + "/bin/MochaLocation.app"
    static let output = configDir + "/cache/location.json"

    enum Result { case found(Place), denied, failed }

    static func find(_ done: @escaping (Result) -> Void) {
        DispatchQueue.global().async {
            try? FileManager.default.removeItem(atPath: output)
            // through Launch Services, so macOS asks on the app's behalf; -g keeps it in the background
            _ = run("/usr/bin/open", ["-g", "-W", "-n", app, "--args", output])
            var result = Result.failed
            if let data = FileManager.default.contents(atPath: output),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["error"] as? String == "denied" { result = .denied }
                else if let lat = json["lat"] as? Double, let lon = json["lon"] as? Double {
                    result = .found(Place(name: json["city"] as? String ?? "Here", detail: json["detail"] as? String ?? "", lat: lat, lon: lon))
                }
            }
            DispatchQueue.main.async { done(result) }
        }
    }

    static func explainDenied() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Location is off for Mocha"
        a.informativeText = "To show weather where you are, turn on Mocha Location in System Settings → Privacy & Security → Location Services. Until then, pick a city instead."
        a.addButton(withTitle: "Open Location Services"); a.addButton(withTitle: "Not Now")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        }
    }
}
