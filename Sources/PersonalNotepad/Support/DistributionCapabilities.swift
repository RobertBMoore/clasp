import Foundation

enum DistributionCapabilities {
#if CLASP_APP_STORE || CLASP_VISUAL_QA
    static let isAppStoreBuild = true
    static let supportsAccessibilitySelectionCapture = false
#else
    static let isAppStoreBuild = false
    static let supportsAccessibilitySelectionCapture = true
#endif
}
