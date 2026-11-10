import XCTest

final class GoalTests: StoreTestCase {
    func testGoalsKeepTheOrderYouGiveThem() {
        store.addGoal(name: "Computer", cost: 1200)
        store.addGoal(name: "Van repair", cost: 800)
        store.addGoal(name: "Vacation", cost: 2000, priority: .urgent)
        XCTAssertEqual(store.activeGoals.map(\.name), ["Vacation", "Computer", "Van repair"])
        store.makeTopPriority(store.activeGoals[2].id)
        XCTAssertEqual(store.activeGoals.map(\.name), ["Van repair", "Vacation", "Computer"])
        store.moveGoals(from: IndexSet(integer: 2), to: 1)
        XCTAssertEqual(store.activeGoals.map(\.name), ["Van repair", "Computer", "Vacation"])
    }

    func testBlankOrFreeGoalsAreRefusedAndSavedIsCapped() {
        XCTAssertNil(store.addGoal(name: "  ", cost: 50))
        XCTAssertNil(store.addGoal(name: "Free", cost: 0))
        let goal = store.addGoal(name: "Bike", cost: 300, saved: 500)
        XCTAssertEqual(goal?.saved, 300)
        XCTAssertEqual(goal?.remaining, 0)
    }

    func testPuttingMoneyAsideIsCappedAtTheCostAndNeverBelowZero() throws {
        let goal = try XCTUnwrap(store.addGoal(name: "Computer", cost: 1000))
        store.setAside(400, for: goal.id)
        store.setAside(800, for: goal.id)
        XCTAssertEqual(store.goals[0].saved, 1000)
        store.setAside(-1500, for: goal.id)
        XCTAssertEqual(store.goals[0].saved, 0)
        XCTAssertEqual(store.goals[0].progress, 0)
    }

    func testBoughtGoalsMoveToTheDonePileAndCanComeBack() throws {
        let a = try XCTUnwrap(store.addGoal(name: "A", cost: 10))
        store.addGoal(name: "B", cost: 20)
        store.markBought(a.id)
        XCTAssertEqual(store.activeGoals.map(\.name), ["B"])
        XCTAssertEqual(store.doneGoals.map(\.name), ["A"])
        store.addGoal(name: "C", cost: 30, priority: .urgent)
        XCTAssertEqual(store.goals.map(\.name), ["C", "B", "A"], "done goals stay at the end")
        store.reopen(a.id)
        XCTAssertEqual(store.activeGoals.map(\.name), ["C", "B", "A"])
        store.deleteGoal(a.id)
        XCTAssertEqual(store.goals.count, 2)
    }

    func testTheForecastFundsGoalsInPriorityOrder() {
        let now = Date()
        let goals = [Goal(name: "Van", cost: 600, saved: 100), Goal(name: "Computer", cost: 1000), Goal(name: "Done", cost: 5, saved: 5)]
        let forecast = GoalPlanner.forecast(goals, monthly: 250, from: now)
        XCTAssertEqual(forecast.count, 3)
        // 500 left on the van at 250 a month is two months; the computer's 1000 on top of that is six.
        let months = { (f: GoalForecast) -> Double in f.date!.timeIntervalSince(now) / 86_400 / GoalPlanner.daysPerMonth }
        XCTAssertEqual(months(forecast[0]), 2, accuracy: 0.05)
        XCTAssertEqual(months(forecast[1]), 6, accuracy: 0.05)
        XCTAssertTrue(forecast[2].isFunded)
        XCTAssertEqual(forecast[2].date, now)
    }

    func testNoMonthlyAmountMeansNoDates() {
        let forecast = GoalPlanner.forecast([Goal(name: "Van", cost: 600)], monthly: 0)
        XCTAssertNil(forecast[0].date)
        XCTAssertFalse(forecast[0].isFunded)
    }

    func testDoneGoalsAreLeftOutOfTheForecast() {
        var done = Goal(name: "Done", cost: 100)
        done.completed = Date()
        XCTAssertEqual(GoalPlanner.forecast([done, Goal(name: "Next", cost: 100)], monthly: 100).count, 1)
    }

    func testDelayFromASurpriseExpense() {
        XCTAssertEqual(GoalPlanner.delayDays(adding: 250, monthly: 250), 31)
        XCTAssertNil(GoalPlanner.delayDays(adding: 250, monthly: 0))
        XCTAssertNil(GoalPlanner.delayDays(adding: 0, monthly: 250))
        XCTAssertEqual(GoalPlanner.delayText(days: 3), "less than a week")
        XCTAssertEqual(GoalPlanner.delayText(days: 7), "about 1 week")
        XCTAssertEqual(GoalPlanner.delayText(days: 21), "about 3 weeks")
        XCTAssertEqual(GoalPlanner.delayText(days: 90), "about 3 months")
    }

    func testOnlyOneRainyDayFund() {
        XCTAssertNotNil(store.addGoal(name: "Rainy-day fund", cost: 500, isReserve: true))
        store.addGoal(name: "Second fund", cost: 500, isReserve: true)
        XCTAssertEqual(store.activeGoals.filter(\.reserve).count, 1)
        XCTAssertEqual(store.reserveGoal?.name, "Rainy-day fund")
    }

    func testAnUnexpectedExpenseIsPaidFromTheRainyDayFundWhenItCoversIt() throws {
        let fund = try XCTUnwrap(store.addGoal(name: "Rainy-day fund", cost: 500, saved: 400, isReserve: true))
        store.addGoal(name: "Computer", cost: 1000)
        let paid = store.addUnexpected(name: "Vet bill", cost: 150, priority: .urgent, useReserve: true)
        XCTAssertTrue(paid)
        XCTAssertEqual(store.goals.first { $0.id == fund.id }?.saved, 250)
        XCTAssertEqual(store.activeGoals.map(\.name), ["Rainy-day fund", "Computer"], "the other goals don't move")
        XCTAssertEqual(store.doneGoals.map(\.name), ["Vet bill"], "and the expense is logged")
    }

    func testAnUnexpectedExpenseTheFundCantCoverBecomesAnUrgentGoal() throws {
        store.addGoal(name: "Rainy-day fund", cost: 500, saved: 100, isReserve: true)
        store.addGoal(name: "Computer", cost: 1000)
        XCTAssertFalse(store.addUnexpected(name: "Van repair", cost: 800, priority: .urgent, useReserve: true))
        XCTAssertEqual(store.activeGoals.first?.name, "Van repair")
        XCTAssertEqual(store.reserveGoal?.saved, 100, "the fund is untouched")
        XCTAssertFalse(store.addUnexpected(name: "Later thing", cost: 50, priority: .normal, useReserve: false))
        XCTAssertEqual(store.activeGoals.last?.name, "Later thing")
        XCTAssertFalse(store.addUnexpected(name: "", cost: 50, priority: .normal, useReserve: false))
    }

    func testTotalsCoverOnlyWhatIsStillToDo() throws {
        store.addGoal(name: "A", cost: 100, saved: 40)
        let b = try XCTUnwrap(store.addGoal(name: "B", cost: 300, saved: 100))
        store.markBought(b.id)
        let totals = store.goalTotals
        XCTAssertEqual(totals.cost, 100)
        XCTAssertEqual(totals.saved, 40)
        XCTAssertEqual(totals.remaining, 60)
    }

    func testGoalsAreSavedBackedUpAndSynced() throws {
        store.addGoal(name: "Computer", cost: 1000, saved: 250)
        XCTAssertEqual(GroceryStore().goals.map(\.name), ["Computer"], "saved to disk")
        XCTAssertEqual(store.makeBackup().goals?.count, 1)
        let backup = store.makeBackup()
        store.goals = []
        store.restore(backup)
        XCTAssertEqual(store.goals.first?.saved, 250)
        XCTAssertNotNil(store.cloudData(for: "goals"))
        XCTAssertTrue(GroceryStore.cloudFileNames.contains("goals"))
    }

    func testGoalsSavedBeforeNewFieldsStillLoad() throws {
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Computer","cost":1000,"saved":0,"added":0}"#
        let goal = try JSONDecoder().decode(Goal.self, from: Data(old.utf8))
        XCTAssertFalse(goal.reserve)
        XCTAssertFalse(goal.isDone)
    }
}

final class RunningTotalTests: XCTestCase {
    private func item(_ name: String, _ price: Double?, qty: Int = 1, checked: Bool = false, travel: Bool = false) -> GroceryItem {
        var item = GroceryItem(name: name, quantity: qty, aisle: .pantry, price: price)
        item.isChecked = checked
        item.isTravel = travel ? true : nil
        return item
    }

    func testTotalsEverythingPricedAndWhatIsInTheCart() {
        let items = [item("Milk", 3, qty: 2), item("Eggs", 4, checked: true), item("Bread", nil)]
        let total = RunningTotal(visible: items, everyday: items)
        XCTAssertEqual(total.all, 10)
        XCTAssertEqual(total.inCart, 4)
        XCTAssertEqual(total.pricedCount, 2)
        XCTAssertEqual(total.count, 3)
        XCTAssertNil(total.everywhere, "same as the list on screen, so nothing extra to show")
    }

    func testAStoreListAlsoShowsTheTotalForAllLists() {
        let kroger = [item("Milk", 3)]
        let all = kroger + [item("Screws", 5)]
        let total = RunningTotal(visible: kroger, everyday: all)
        XCTAssertEqual(total.all, 3)
        XCTAssertEqual(total.everywhere, 8)
    }

    func testNothingPricedMeansNothingToShow() {
        let total = RunningTotal(visible: [item("Milk", nil)], everyday: [item("Milk", nil)])
        XCTAssertEqual(total.pricedCount, 0)
        XCTAssertEqual(total.all, 0)
    }
}
