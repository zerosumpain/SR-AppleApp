import HealthKit

/// What JSON cannot say: which HealthKit type and unit feed each catalogue
/// kind. The UNIT here must produce the catalogue's unit string — a percentage
/// from `.percent()` is a 0–1 fraction, hence `scale: 100`.
enum Reading {
    case sample(HKQuantityTypeIdentifier, HKUnit, scale: Double)
    case hourly(HKQuantityTypeIdentifier, HKUnit, HKStatisticsOptions, scale: Double)
    case standHour, mindful, stateOfMind, dailySteps, sleep, workout, workoutPart
}

enum HealthReadings {
    static let bpm = HKUnit.count().unitDivided(by: .minute())
    static let metresPerSecond = HKUnit.meter().unitDivided(by: .second())
    /// ml/(kg·min), built explicitly rather than parsed from a string — HKUnit's
    /// grammar can read "ml/kg*min" as (ml/kg)*min, which is a different unit
    /// and compiling would never catch it.
    static let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    static func reading(for kind: String) -> Reading? {
        switch kind {
        case "steps": return .dailySteps
        case "step_count": return .hourly(.stepCount, .count(), .cumulativeSum, scale: 1)
        case "active_energy": return .hourly(.activeEnergyBurned, .jouleUnit(with: .kilo), .cumulativeSum, scale: 1)
        case "basal_energy": return .hourly(.basalEnergyBurned, .jouleUnit(with: .kilo), .cumulativeSum, scale: 1)
        case "walking_running_distance": return .hourly(.distanceWalkingRunning, .meterUnit(with: .kilo), .cumulativeSum, scale: 1)
        case "distance_cycling": return .hourly(.distanceCycling, .meterUnit(with: .kilo), .cumulativeSum, scale: 1)
        case "flights_climbed": return .hourly(.flightsClimbed, .count(), .cumulativeSum, scale: 1)
        case "apple_exercise_time": return .hourly(.appleExerciseTime, .minute(), .cumulativeSum, scale: 1)
        case "time_in_daylight": return .hourly(.timeInDaylight, .minute(), .cumulativeSum, scale: 1)
        case "environmental_audio_exposure": return .hourly(.environmentalAudioExposure, .decibelAWeightedSoundPressureLevel(), .discreteAverage, scale: 1)
        case "headphone_audio_exposure": return .hourly(.headphoneAudioExposure, .decibelAWeightedSoundPressureLevel(), .discreteAverage, scale: 1)
        case "apple_stand_hour": return .standHour
        case "mindful_minutes": return .mindful
        case "state_of_mind_valence": return .stateOfMind
        case "heart_rate": return .sample(.heartRate, bpm, scale: 1)
        case "resting_heart_rate": return .sample(.restingHeartRate, bpm, scale: 1)
        case "walking_heart_rate_average": return .sample(.walkingHeartRateAverage, bpm, scale: 1)
        case "heart_rate_recovery_one_minute": return .sample(.heartRateRecoveryOneMinute, bpm, scale: 1)
        case "heart_rate_variability": return .sample(.heartRateVariabilitySDNN, .secondUnit(with: .milli), scale: 1)
        case "oxygen_saturation": return .sample(.oxygenSaturation, .percent(), scale: 100)
        case "respiratory_rate": return .sample(.respiratoryRate, bpm, scale: 1)
        case "apple_sleeping_wrist_temperature": return .sample(.appleSleepingWristTemperature, .degreeCelsius(), scale: 1)
        case "vo2_max": return .sample(.vo2Max, vo2Unit, scale: 1)
        case "six_minute_walk_distance": return .sample(.sixMinuteWalkTestDistance, .meter(), scale: 1)
        case "walking_speed": return .sample(.walkingSpeed, metresPerSecond, scale: 1)
        case "walking_step_length": return .sample(.walkingStepLength, .meterUnit(with: .centi), scale: 1)
        case "walking_asymmetry": return .sample(.walkingAsymmetryPercentage, .percent(), scale: 100)
        case "walking_double_support": return .sample(.walkingDoubleSupportPercentage, .percent(), scale: 100)
        case "walking_steadiness": return .sample(.appleWalkingSteadiness, .percent(), scale: 100)
        case "stair_ascent_speed": return .sample(.stairAscentSpeed, metresPerSecond, scale: 1)
        case "stair_descent_speed": return .sample(.stairDescentSpeed, metresPerSecond, scale: 1)
        case "body_mass": return .sample(.bodyMass, .gramUnit(with: .kilo), scale: 1)
        case "body_fat_percentage": return .sample(.bodyFatPercentage, .percent(), scale: 100)
        case "sleep": return .sleep
        case "workout": return .workout
        case "workout_route", "workout_series": return .workoutPart
        default: return nil
        }
    }

    /// The type to authorise and observe. nil = nothing to observe on this OS.
    ///
    /// Uses the `quantityType(forIdentifier:)` / `categoryType(forIdentifier:)`
    /// factories (force-unwrapped, as `HealthCollector.type(_:)` already does
    /// for its own identifiers) rather than the bare `HKQuantityType(_:)`
    /// initializer the brief used verbatim — see the task report for why.
    static func sampleType(for kind: String) -> HKSampleType? {
        switch reading(for: kind) {
        case .sample(let id, _, _), .hourly(let id, _, _, _): return HKQuantityType.quantityType(forIdentifier: id)!
        case .dailySteps: return HKQuantityType.quantityType(forIdentifier: .stepCount)!
        case .standHour: return HKCategoryType.categoryType(forIdentifier: .appleStandHour)!
        case .mindful: return HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        case .stateOfMind:
            if #available(iOS 18.0, *) { return HKSampleType.stateOfMindType() }
            return nil
        case .sleep: return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        case .workout: return HKObjectType.workoutType()
        case .workoutPart: return kind == "workout_route" ? HKSeriesType.workoutRoute() : nil
        case nil: return nil
        }
    }

    /// Series read per workout. Two HealthKit types may share a metric name
    /// (running vs cycling power): a workout only ever has one of them.
    static let workoutSeries: [(metric: String, type: HKQuantityTypeIdentifier, unit: HKUnit)] = [
        ("heart_rate", .heartRate, bpm),
        ("speed", .runningSpeed, metresPerSecond),
        ("speed", .cyclingSpeed, metresPerSecond),
        ("power", .runningPower, .watt()),
        ("power", .cyclingPower, .watt()),
        ("stride_length", .runningStrideLength, .meter()),
        ("vertical_oscillation", .runningVerticalOscillation, .meterUnit(with: .centi)),
        ("ground_contact_time", .runningGroundContactTime, .secondUnit(with: .milli)),
        ("cycling_cadence", .cyclingCadence, bpm),
    ]

    static func workoutName(_ w: HKWorkout) -> String {
        name(for: w.workoutActivityType, indoor: (w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) == true,
             openWater: (w.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber)?.intValue == HKWorkoutSwimmingLocationType.openWater.rawValue)
    }

    /// Apple's own display names — the names Health Auto Export stored.
    static func name(for type: HKWorkoutActivityType, indoor: Bool, openWater: Bool = false) -> String {
        switch type {
        case .walking: return indoor ? "Indoor Walk" : "Outdoor Walk"
        case .running: return indoor ? "Indoor Run" : "Outdoor Run"
        case .cycling: return indoor ? "Indoor Cycling" : "Outdoor Cycling"
        case .hiking: return "Hiking"
        case .swimming: return openWater ? "Open Water Swim" : "Pool Swim"
        case .highIntensityIntervalTraining: return "High Intensity Interval Training"
        case .mixedCardio: return "Mixed Cardio"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .traditionalStrengthTraining: return "Traditional Strength Training"
        case .coreTraining: return "Core Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .surfingSports: return "Surfing Sports"
        case .paddleSports: return "Paddle Sports"
        case .golf: return "Golf"
        case .tennis: return "Tennis"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        default: return "Other"
        }
    }

    static func eventName(_ t: HKWorkoutEventType) -> String? {
        switch t {
        case .pause: return "pause"
        case .resume: return "resume"
        case .lap: return "lap"
        case .segment: return "segment"
        case .marker: return "marker"
        case .motionPaused: return "motion_paused"
        case .motionResumed: return "motion_resumed"
        case .pauseOrResumeRequest: return "pause_or_resume_request"
        @unknown default: return nil
        }
    }
}
