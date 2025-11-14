import Foundation
import Combine
//timer
class TimerManager: ObservableObject {
    @Published private(set) var elapsedSeconds: Int = 0
    
    private var timer: Timer? = nil
    
    func start() {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
    }
  
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    
    func reset() {
        stop()
        elapsedSeconds = 0
    }
    
    
    func getSeconds() -> Int {
        return elapsedSeconds
    }
}
//standard deviation
extension Array where Element == Int {
    func standardDeviation(from reference: Double) -> Double {
        guard !self.isEmpty else { return 0.0 }
        let doubleArray = self.map { Double($0) }
        let variance = doubleArray.reduce(0) { $0 + pow($1 - reference, 2) } / Double(doubleArray.count)
        return sqrt(variance)
    }
}


