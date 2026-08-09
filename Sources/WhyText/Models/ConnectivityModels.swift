import Foundation

enum ConnectivityCheckState: Equatable {
    case available
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .available:
            "可用"
        case .unavailable:
            "不可用"
        case .unknown:
            "待确认"
        }
    }
}

struct ProviderConnectivityReport: Equatable {
    var baseURL: ConnectivityCheckState
    var apiKey: ConnectivityCheckState
    var model: ConnectivityCheckState
    var message: String
}
