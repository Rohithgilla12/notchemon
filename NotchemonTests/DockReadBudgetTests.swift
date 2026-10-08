import Foundation
import Testing
@testable import Notchemon

struct DockReadBudgetTests {
    let start: TimeInterval = 1000

    @Test func eachCallWaitsOnlyForWhatIsLeftOfTheRead() {
        let budget = DockReadBudget(startingAt: start)
        #expect(budget.timeout(at: start) == Float(DockReadBudget.total))
        #expect(budget.timeout(at: start + 0.3) == Float(DockReadBudget.total - 0.3))
    }

    @Test func noCallStartsOnceTheReadIsOutOfTime() {
        let budget = DockReadBudget(startingAt: start)
        #expect(budget.timeout(at: start + DockReadBudget.total) == nil)
        #expect(budget.timeout(at: start + DockReadBudget.total + 2) == nil)
    }

    @Test func aCallIsNeverGivenAZeroTimeoutWhichWouldMeanTheSixSecondDefault() {
        let budget = DockReadBudget(startingAt: start)
        #expect(budget.timeout(at: start + DockReadBudget.total - 0.000_001) == nil)
    }
}
