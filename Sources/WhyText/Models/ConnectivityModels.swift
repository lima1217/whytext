import Foundation
import WhyTextCore

enum ConnectivityCheckState: Equatable {
    case available
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .available:
            L10n.t("可用")
        case .unavailable:
            L10n.t("不可用")
        case .unknown:
            L10n.t("待确认")
        }
    }
}

struct ProviderConnectivityReport: Equatable {
    var baseURL: ConnectivityCheckState
    var apiKey: ConnectivityCheckState
    var model: ConnectivityCheckState
    var message: String
}
