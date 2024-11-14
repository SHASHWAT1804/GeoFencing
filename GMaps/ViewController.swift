import UIKit
import MapKit
import CoreLocation

class ViewController: UIViewController, MKMapViewDelegate, UISearchBarDelegate, CLLocationManagerDelegate, FenceDataManagerDelegate {
    
    @IBOutlet weak var mapView: MKMapView!
    
    var fenceDataManager = FenceDataManager()
    var searchBar: UISearchBar!
    var fenceCreated = false
    var createFenceIcon: UIBarButtonItem!
    
    let locationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mapView.delegate = self
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        let initialLocation = CLLocationCoordinate2D(latitude: 12.823782, longitude: 80.046156)
        let region = MKCoordinateRegion(center: initialLocation, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: true)
        
        setupSearchBar()
        setupIcons()
        
        fenceDataManager.delegate = self
    }
    
    private func setupSearchBar() {
        searchBar = UISearchBar()
        searchBar.delegate = self
        searchBar.placeholder = "Search for places"
        self.navigationItem.titleView = searchBar
    }
    
    // MARK: - UISearchBarDelegate
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder() // Dismiss the keyboard
        guard let searchText = searchBar.text, !searchText.isEmpty else { return }
        
        performLocationSearch(query: searchText)
    }
    
    // Perform location search using MKLocalSearch
    private func performLocationSearch(query: String) {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        searchRequest.region = mapView.region // Search within the current map region
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            if let error = error {
                self.showAlert(title: "Search Error", message: error.localizedDescription)
                return
            }
            
            guard let response = response else {
                self.showAlert(title: "Error", message: "No locations found.")
                return
            }
            
            // Remove any existing annotations
            self.mapView.removeAnnotations(self.mapView.annotations)
            
            // Process search results
            let mapItems = response.mapItems
            for item in mapItems {
                let annotation = MKPointAnnotation()
                annotation.coordinate = item.placemark.coordinate
                annotation.title = item.name
                self.mapView.addAnnotation(annotation)
            }
            
            // Center the map on the first search result
            if let firstItem = mapItems.first {
                let newRegion = MKCoordinateRegion(center: firstItem.placemark.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
                self.mapView.setRegion(newRegion, animated: true)
            }
        }
    }
    
    private func setupIcons() {
        let addPointIcon = UIBarButtonItem(image: UIImage(systemName: "plus.circle"), style: .plain, target: self, action: #selector(addPointTapped))
        createFenceIcon = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle.fill"), style: .plain, target: self, action: #selector(createFenceTapped))
        createFenceIcon.isEnabled = false
        let clearFenceIcon = UIBarButtonItem(image: UIImage(systemName: "xmark.circle.fill"), style: .plain, target: self, action: #selector(clearFenceTapped))
        let recenterIcon = UIBarButtonItem(image: UIImage(systemName: "location.north.fill"), style: .plain, target: self, action: #selector(recenterTapped))
        let satelliteIcon = UIBarButtonItem(image: UIImage(systemName: "globe.americas.fill"), style: .plain, target: self, action: #selector(toggleMapTypeTapped))
        
        self.navigationItem.leftBarButtonItems = [addPointIcon, createFenceIcon]
        self.navigationItem.rightBarButtonItems = [recenterIcon, clearFenceIcon, satelliteIcon]
    }
    
    @objc func addPointTapped() {
        guard !fenceCreated else {
            showAlert(title: "Fence Created", message: "Clear the existing fence to add new points.")
            return
        }
        
        let location = mapView.centerCoordinate
        addFencePoint(at: location)
    }
    
    @objc func createFenceTapped() {
        guard fenceDataManager.points.count > 2 else {
            showAlert(title: "Error", message: "Need at least 3 points to create a fence.")
            return
        }
        
        let sortedFencePoints = sortPointsInClockwiseOrder(points: fenceDataManager.points.map { $0.coordinate })
        let polygon = MKPolygon(coordinates: sortedFencePoints, count: sortedFencePoints.count)
        mapView.addOverlay(polygon)
        
        fenceCreated = true
        disableDraggableAnnotations()
        createFenceIcon.isEnabled = false
    }
    
    @objc func clearFenceTapped() {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        fenceDataManager.resetPoints()
        fenceCreated = false
        createFenceIcon.isEnabled = false
    }
    
    @objc func recenterTapped() {
        guard let userLocation = locationManager.location?.coordinate else {
            showAlert(title: "Error", message: "Unable to get the current location.")
            return
        }

        let region = MKCoordinateRegion(center: userLocation, latitudinalMeters: 1000, longitudinalMeters: 1000)
        mapView.setRegion(region, animated: true)
    }
    
    @objc func toggleMapTypeTapped() {
        mapView.mapType = mapView.mapType == .standard ? .hybrid : .standard
    }
    
    private func addFencePoint(at coordinate: CLLocationCoordinate2D) {
        let pointNumber = fenceDataManager.points.count + 1
        let newPoint = FencePoint(coordinate: coordinate, pointNumber: pointNumber)
        
        fenceDataManager.addPoint(newPoint)
        
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Point \(pointNumber)"
        mapView.addAnnotation(annotation)
        
        if fenceDataManager.points.count >= 3 {
            createFenceIcon.isEnabled = true
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    private func sortPointsInClockwiseOrder(points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let center = CLLocationCoordinate2D(
            latitude: points.map { $0.latitude }.reduce(0, +) / Double(points.count),
            longitude: points.map { $0.longitude }.reduce(0, +) / Double(points.count)
        )
        
        return points.sorted { (a, b) -> Bool in
            let angleA = atan2(a.latitude - center.latitude, a.longitude - center.longitude)
            let angleB = atan2(b.latitude - center.latitude, b.longitude - center.longitude)
            return angleA < angleB
        }
    }
    
    private func disableDraggableAnnotations() {
        for annotation in mapView.annotations {
            if let view = mapView.view(for: annotation) {
                view.isDraggable = false
            }
        }
    }
    
    func didUpdateFencePoints(points: [FencePoint]) {
        print("Updated points:", points.map { $0.coordinate })
    }
    
    // Update points' coordinates when dragged to a new location
    func mapView(_ mapView: MKMapView, annotationView: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        guard newState == .ending, let annotation = annotationView.annotation as? MKPointAnnotation,
              let title = annotation.title, title.starts(with: "Point") == true else { return }
        
        if let pointNumber = Int(title.replacingOccurrences(of: "Point ", with: "")) {
            let newCoordinate = annotation.coordinate
            fenceDataManager.updatePoint(at: pointNumber - 1, with: newCoordinate)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polygon = overlay as? MKPolygon {
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.fillColor = UIColor.blue.withAlphaComponent(0.5)
            renderer.strokeColor = UIColor.blue
            renderer.lineWidth = 2
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let pointAnnotation = annotation as? MKPointAnnotation else { return nil }

        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "draggableAnnotation") as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "draggableAnnotation")
        } else {
            annotationView?.annotation = annotation
        }

        annotationView?.canShowCallout = true
        annotationView?.isDraggable = !fenceCreated
        annotationView?.markerTintColor = UIColor.systemBlue
        annotationView?.glyphText = "\(pointAnnotation.title ?? "")"
        
        return annotationView
    }
}
