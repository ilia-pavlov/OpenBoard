import Foundation

/// USCF class titles derived from the regular rating.
enum ClassTitle: String, CaseIterable, Sendable {
    case seniorMaster = "Senior Master"
    case nationalMaster = "National Master"
    case expert = "Expert"
    case classA = "Class A"
    case classB = "Class B"
    case classC = "Class C"
    case classD = "Class D"
    case classE = "Class E"
    case classF = "Class F"
    case classG = "Class G"
    case classH = "Class H"
    case classI = "Class I"
    case classJ = "Class J"

    init(rating: Int) {
        switch rating {
        case 2400...: self = .seniorMaster
        case 2200..<2400: self = .nationalMaster
        case 2000..<2200: self = .expert
        case 1800..<2000: self = .classA
        case 1600..<1800: self = .classB
        case 1400..<1600: self = .classC
        case 1200..<1400: self = .classD
        case 1000..<1200: self = .classE
        case 800..<1000: self = .classF
        case 600..<800: self = .classG
        case 400..<600: self = .classH
        case 200..<400: self = .classI
        default: self = .classJ
        }
    }
}
