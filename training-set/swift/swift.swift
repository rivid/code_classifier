import UIKit
import EventKit

class ViewController: UIViewController, UITextFieldDelegate {
    
    var eventStore : EKEventStore!
    var calendar: EKCalendar!
    
    
    @IBOutlet weak var datePicker: UIDatePicker!
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var eventCalendario: UITextField!
    @IBOutlet weak var titleEvent: UITextField!
    
    @IBAction func saveCalendar(sender: UIButton) {
        var date = datePicker.date
        var name = textField.text
        var localSource: EKSource
//        var calendar = EKCalendar(eventStore: eventStore)
        var calendar = EKCalendar(forEntityType: EKEntityType.Event, eventStore: eventStore)
        eventStore.requestAccessToEntityType(EKEntityType.Event, completion: {(granted,error) in
            if(granted == false){
                print("Access Denied")
            }
            else{
                var auxiliar = self.eventStore.sources 
                calendar.source = auxiliar[0]
                calendar.title = self.textField.text!
                print(calendar.title)
                var error:NSError?
                self.eventStore.saveCalendar(calendar, commit: true, error: &error)
            }
        })
    }
    
    @IBAction func saveEvent(sender: UIButton) {
        
        eventStore.requestAccessToEntityType(EKEntityType.Event, completion: {(granted,error) in
            if(granted == false){
                print("Access Denied")
            }
            else{
                var arrayCalendars = self.eventStore.calendarsForEntityType(EKEntityType.Event)
                var theCalendar: EKCalendar!
                for calendario in arrayCalendars{
                    if(calendario.title == self.eventCalendario.text){
                        theCalendar = calendario 
                        print(theCalendar.title)
                    }
                }
                if(theCalendar != nil){
                    var event = EKEvent(eventStore: self.eventStore)
                    event.title = self.titleEvent.text!
                    event.startDate = self.datePicker.date
                    event.endDate = self.datePicker.date.dateByAddingTimeInterval(3600)
                    event.calendar = theCalendar
                    var error:NSError?
                    if(self.eventStore.saveEvent(event, span: .ThisEvent, error: &error)){
                        var alert = UIAlertController(title: "Calendar", message: "Event created \(event.title) in \(theCalendar.title)", preferredStyle: UIAlertControllerStyle.Alert)
                        alert.addAction(UIAlertAction(title: "Accept", style: UIAlertActionStyle.Default, handler: nil))
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.presentViewController(alert, animated: true, completion: nil)
                        })
                    }
                }
                else{
                    print("No calendar with that name")
                }
            }
        })
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        eventStore = EKEventStore()
        
        let tapGestureRecognizer : UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: "dismissKeyBoard")
        
        self.view.addGestureRecognizer(tapGestureRecognizer)
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func dismissKeyBoard() {
        self.textField.resignFirstResponder()
    }
    
    func textFieldShouldReturn(textField: UITextField) -> Bool // called when 'return' key pressed. return NO to ignore.
    {
        textField.resignFirstResponder()
        return true;
    }
    
    //called when users tap out of textfield
    override func touchesBegan(touches: Set<NSObject>, withEvent event: UIEvent) {
        self.view.endEditing(true)
    }
    

    
import UIKit
import CoreLocation
import MapKit


class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    
    @IBOutlet weak var myMap: MKMapView!
    let locationManager: CLLocationManager = CLLocationManager()
    var myLatitude: CLLocationDegrees!
    var myLongitude: CLLocationDegrees!
    var finalLatitude: CLLocationDegrees!
    var finalLongitude: CLLocationDegrees!
    var distance: CLLocationDistance!
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        
        
        let tap = UITapGestureRecognizer(target: self, action: "action:")
        
        myMap.addGestureRecognizer(tap)
        
        
    }
    
    func action(gestureRecognizer:UIGestureRecognizer) {
        let touchPoint = gestureRecognizer.locationInView(self.myMap)
        let newCoord:CLLocationCoordinate2D = myMap.convertPoint(touchPoint, toCoordinateFromView: self.myMap)
        
        let getLat: CLLocationDegrees = newCoord.latitude
        let getLon: CLLocationDegrees = newCoord.longitude
        
        //Convert to points to CLLocation. In this way we can measure distanceFromLocation
        let newCoord2: CLLocation = CLLocation(latitude: getLat, longitude: getLon)
        
        let newCoord3: CLLocation = CLLocation(latitude: myLatitude, longitude: myLongitude)
        
        finalLatitude = newCoord2.coordinate.latitude
        finalLongitude = newCoord2.coordinate.longitude
        print("Original Latitude: \(myLatitude)")
        print("Original Longitude: \(myLongitude)")
        print("Final Latitude: \(finalLatitude)")
        print("Final Longitude: \(finalLongitude)")
        
        
        
        //distance between our position and the new point created
        let distance = newCoord2.distanceFromLocation(newCoord3)
        print("Distance between two points: \(distance)")
        
        
        let newAnnotation = MKPointAnnotation()
        newAnnotation.coordinate = newCoord
        newAnnotation.title = "My target"
        newAnnotation.subtitle = ""
        myMap.addAnnotation(newAnnotation)
        
    }
    
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        CLGeocoder().reverseGeocodeLocation(manager.location!, completionHandler: {(placemarks, error)->Void in
            
            if (error != nil) {
                print("Reverse geocoder failed with error" + error!.localizedDescription)
                return
            }
            
            if placemarks!.count > 0 {
                let pm = placemarks![0] as CLPlacemark
                self.displayLocationInfo(pm)
            } else {
                print("Problem with the data received from geocoder")
            }
        })
    }
    
    func displayLocationInfo(placemark: CLPlacemark?) {
        if let containsPlacemark = placemark {
            //stop updating location to save battery life
            locationManager.stopUpdatingLocation()
            
            //get data from placemark
            let locality = (containsPlacemark.locality != nil) ? containsPlacemark.locality : ""
            let postalCode = (containsPlacemark.postalCode != nil) ? containsPlacemark.postalCode : ""
            let administrativeArea = (containsPlacemark.administrativeArea != nil) ? containsPlacemark.administrativeArea : ""
            let country = (containsPlacemark.country != nil) ? containsPlacemark.country : ""
            myLongitude = (containsPlacemark.location!.coordinate.longitude)
            myLatitude = (containsPlacemark.location!.coordinate.latitude)
            
            
            // testing show data
            print("Locality: \(locality)")
            print("PostalCode: \(postalCode)")
            print("Area: \(administrativeArea)")
            print("Country: \(country)")
            print(myLatitude)
            print(myLongitude)
            
            //update map with my location
            let theSpan:MKCoordinateSpan = MKCoordinateSpanMake(0.1 , 0.1)
            let location:CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: myLatitude, longitude: myLongitude)
            let theRegion:MKCoordinateRegion = MKCoordinateRegionMake(location, theSpan)
            
            myMap.setRegion(theRegion, animated: true)
            
        }
        
    }
    
    func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        print("Error while updating location " + error.localizedDescription)
    }
    
    //distance between two points
    
    func degreesToRadians(degrees: Double) -> Double { return degrees * M_PI / 180.0 }
    func radiansToDegrees(radians: Double) -> Double { return radians * 180.0 / M_PI }
    
    func getBearingBetweenTwoPoints1(point1 : CLLocation, point2 : CLLocation) -> Double {
        
        let lat1 = degreesToRadians(point1.coordinate.latitude)
        let lon1 = degreesToRadians(point1.coordinate.longitude)
        
        let lat2 = degreesToRadians(point2.coordinate.latitude);
        let lon2 = degreesToRadians(point2.coordinate.longitude);
        
        print("Start latitude: \(point1.coordinate.latitude)")
        print("Start longitude: \(point1.coordinate.longitude)")
        print("Final latitude: \(point2.coordinate.latitude)")
        print("Final longitude: \(point2.coordinate.longitude)")
        
        let dLon = lon2 - lon1;
        
        let y = sin(dLon) * cos(lat2);
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
        let radiansBearing = atan2(y, x);
        
        return radiansToDegrees(radiansBearing)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
}


    
}