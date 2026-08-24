import Foundation

struct OnboardingPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isComplete: Bool {
        defaults.bool(forKey: PreferenceKeys.onboardingComplete)
    }

    func markComplete() {
        defaults.set(true, forKey: PreferenceKeys.onboardingComplete)
    }

    func reset() {
        defaults.set(false, forKey: PreferenceKeys.onboardingComplete)
    }
}
