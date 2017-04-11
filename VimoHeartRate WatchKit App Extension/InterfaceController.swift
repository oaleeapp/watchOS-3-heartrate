//
//  InterfaceController.swift
//  VimoHeartRate WatchKit App Extension
//
//  Created by Ethan Fan on 6/25/15.
//  Copyright © 2015 Vimo Lab. All rights reserved.
//

import Foundation
import HealthKit
import WatchKit


class InterfaceController: WKInterfaceController, HKWorkoutSessionDelegate {
    
    @IBOutlet private weak var label: WKInterfaceLabel!
    @IBOutlet private weak var deviceLabel : WKInterfaceLabel!
    @IBOutlet private weak var heart: WKInterfaceImage!
    @IBOutlet private weak var startStopButton : WKInterfaceButton!
    
    @IBOutlet var calibrateButton: WKInterfaceButton!
    @IBOutlet var stressLevelSliderBar: WKInterfaceSlider!
    let healthStore = HKHealthStore()
    
    //State of the app - is the workout activated
    var workoutActive = false
    
    // define the activity type and location
    var session : HKWorkoutSession?
    let heartRateUnit = HKUnit(from: "count/min")
    //var anchor = HKQueryAnchor(fromValue: Int(HKAnchoredObjectQueryNoAnchor))
    var currenQuery : HKQuery?

    // Calculate 

    // per [count/second]
    var heartRates: [Double] = []
    var timeWindow: Int = 40

    var currentChangeSamples: [Double] = [] {
        didSet {
            if currentChangeSamples.count > timeWindow {
                // enable the button
                calibrateButton.setEnabled(true)
            }
        }
    }
    var staticChangeSamples: [Double] = []
    var stressLevel: Double = 0.0 {
        didSet {
            self.stressLevelSliderBar.setValue(Float(stressLevel))
            self.stressLevelSliderBar.setEnabled(true)
        }
    }
    // Calculate
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
    }
    
    override func willActivate() {
        super.willActivate()
        
        guard HKHealthStore.isHealthDataAvailable() == true else {
            label.setText("not available")
            return
        }
    
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else {
            displayNotAllowed()
            return
        }
        
        let dataTypes = Set(arrayLiteral: quantityType)
        healthStore.requestAuthorization(toShare: nil, read: dataTypes) { (success, error) -> Void in
            if success == false {
                self.displayNotAllowed()
            }
        }
    }
    
    func displayNotAllowed() {
        label.setText("not allowed")
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        switch toState {
        case .running:
            workoutDidStart(date)
        case .ended:
            workoutDidEnd(date)
        default:
            print("Unexpected state \(toState)")
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Do nothing for now
        print("Workout error")
    }
    

    func workoutDidStart(_ date : Date) {
        if let query = createHeartRateStreamingQuery(date) {
            self.currenQuery = query
            healthStore.execute(query)
        } else {
            label.setText("cannot start")
        }
    }
    
    func workoutDidEnd(_ date : Date) {
            healthStore.stop(self.currenQuery!)
            label.setText("---")
            session = nil
    }
    
    // MARK: - Actions
    @IBAction func startBtnTapped() {
        if (self.workoutActive) {
            //finish the current workout
            self.workoutActive = false
            self.startStopButton.setTitle("Start")
            if let workout = self.session {
                healthStore.end(workout)
            }
        } else {
            //start a new workout
            self.workoutActive = true
            self.startStopButton.setTitle("Stop")
            startWorkout()
        }

    }


    @IBAction func calibrateHeartRate() {

        print(#function)
        staticChangeSamples = currentChangeSamples

    }


    
    func startWorkout() {
        
        // If we have already started the workout, then do nothing.
        if (session != nil) {
            return
        }
        
        // Configure the workout session.
        let workoutConfiguration = HKWorkoutConfiguration()
        workoutConfiguration.activityType = .crossTraining
        workoutConfiguration.locationType = .indoor
        
        do {
            session = try HKWorkoutSession(configuration: workoutConfiguration)
            session?.delegate = self
        } catch {
            fatalError("Unable to create the workout session!")
        }
        
        healthStore.start(self.session!)
    }
    
    func createHeartRateStreamingQuery(_ workoutStartDate: Date) -> HKQuery? {

        
        guard let quantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else { return nil }
        let datePredicate = HKQuery.predicateForSamples(withStart: workoutStartDate, end: nil, options: .strictEndDate )
        //let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates:[datePredicate])
        
        
        let heartRateQuery = HKAnchoredObjectQuery(type: quantityType, predicate: predicate, anchor: nil, limit: Int(HKObjectQueryNoLimit)) { (query, sampleObjects, deletedObjects, newAnchor, error) -> Void in
            //guard let newAnchor = newAnchor else {return}
            //self.anchor = newAnchor
            self.updateHeartRate(sampleObjects)
        }
        
        heartRateQuery.updateHandler = {(query, samples, deleteObjects, newAnchor, error) -> Void in
            //self.anchor = newAnchor!
            self.updateHeartRate(samples)
        }
        return heartRateQuery
    }
    
    func updateHeartRate(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample] else {return}
        
        DispatchQueue.main.async {
            guard let sample = heartRateSamples.first else{return}
            let value = sample.quantity.doubleValue(for: self.heartRateUnit)
            self.heartRates.append(60.0 / sample.quantity.doubleValue(for: self.heartRateUnit))
            self.currentChangeSamples = self.changeOfAmptitudes(heartRates: self.heartRates)

            if self.staticChangeSamples.count != 0 {
                self.stressLevel = self.calculateStressLevel(staticChanges: self.staticChangeSamples, currentChanges: self.currentChangeSamples)
                print(self.stressLevel)
            }

            self.label.setText(String(UInt16(value)))
            
            // retrieve source from sample
            let name = sample.sourceRevision.source.name
            self.updateDeviceName(name)
            self.animateHeart()
        }
    }
    
    func updateDeviceName(_ deviceName: String) {
        deviceLabel.setText(deviceName)
    }
    
    func animateHeart() {
        self.animate(withDuration: 0.5) {
            self.heart.setWidth(60)
            self.heart.setHeight(90)
        }
        
        let when = DispatchTime.now() + Double(Int64(0.5 * double_t(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        
        DispatchQueue.global(qos: .default).async {
            DispatchQueue.main.asyncAfter(deadline: when) {
                self.animate(withDuration: 0.5, animations: {
                    self.heart.setWidth(50)
                    self.heart.setHeight(80)
                })            }
            
            
        }
    }
}


extension InterfaceController{

    func changeOfAmptitudes(heartRates: [Double]) -> [Double] {

        if heartRates.count > timeWindow {

            var diffs: [Double] = []
            var averageDiffs: [Double] = []

            let startIndex = heartRates.count - timeWindow + 1
            let endIndex =  heartRates.count

            for n in 1..<timeWindow {

                for i in startIndex..<(endIndex - n) {

                    let diff = abs(heartRates[n + i] - heartRates[i])

                    diffs.append(diff)
                }
                let sum = diffs.reduce(0, +)
                let average = sum / Double(diffs.count)
                averageDiffs.append(average)
            }

            return averageDiffs

        } else {
            return []
        }
    }

    func calculateStressLevel(staticChanges: [Double], currentChanges: [Double]) -> Double{


        var count: Int = 0

        for i in 0..<(timeWindow - 1) {

            if currentChanges[i] > staticChanges[i] {
                count += 1
            }

        }

        let stressLevel = Double(count) / Double(timeWindow + 1)

        return stressLevel
    }
    
}


//extension Array where Element: Double {
//    /// Returns the sum of all elements in the array
//    var total: Element {
//        return reduce(0, +)
//    }
//}
//extension Collection where Iterator.Element == Double, Index == Double {
//    /// Returns the average of all elements in the array
//    var average: Double {
//        return isEmpty ? 0 : Double(reduce(0, +)) / Double(endIndex-startIndex)
//    }
//}
