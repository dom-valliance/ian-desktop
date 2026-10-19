import Contract
import Testing

@testable import Features

@Suite("Selection both ways")
struct SelectionTests {
  private let today = TodayScenario.today

  @Test("a Now pillar selects the row of its first item")
  func nowPillarSelectsFirstItem() {
    let pillar = FieldCellRef(unitID: "unit_a", horizon: .now)
    #expect(
      TodaySelectionModel.selection(forPillar: pillar, in: today) == .item("prop_a1"))
  }

  @Test("a week pillar selects its unit's week group")
  func weekPillarSelectsGroup() {
    let pillar = FieldCellRef(unitID: "unit_a", horizon: .week)
    #expect(TodaySelectionModel.selection(forPillar: pillar, in: today) == .week(unitID: "unit_a"))
  }

  @Test("a later pillar selects its unit's later group")
  func laterPillarSelectsGroup() {
    let pillar = FieldCellRef(unitID: "unit_b", horizon: .later)
    #expect(
      TodaySelectionModel.selection(forPillar: pillar, in: today) == .later(unitID: "unit_b"))
  }

  @Test("selects nothing for a pillar the field does not hold")
  func unknownPillarSelectsNothing() {
    #expect(
      TodaySelectionModel.selection(
        forPillar: FieldCellRef(unitID: "unit_b", horizon: .week), in: today) == nil)
    #expect(
      TodaySelectionModel.selection(
        forPillar: FieldCellRef(unitID: "unit_z", horizon: .now), in: today) == nil)
  }

  @Test("a Now row selects the pillar holding its item, even when it is not the first item")
  func nowRowSelectsHoldingPillar() {
    #expect(
      TodaySelectionModel.pillar(for: .item("cmt_a2"), in: today)
        == FieldCellRef(unitID: "unit_a", horizon: .now))
    #expect(
      TodaySelectionModel.pillar(for: .item("alrt_b1"), in: today)
        == FieldCellRef(unitID: "unit_b", horizon: .now))
  }

  @Test("an item inside a week group selects the week pillar")
  func weekItemSelectsWeekPillar() {
    #expect(
      TodaySelectionModel.pillar(for: .item("cmt_a4"), in: today)
        == FieldCellRef(unitID: "unit_a", horizon: .week))
  }

  @Test("a week group selects its unit's week pillar")
  func weekRowSelectsWeekPillar() {
    #expect(
      TodaySelectionModel.pillar(for: .week(unitID: "unit_a"), in: today)
        == FieldCellRef(unitID: "unit_a", horizon: .week))
  }

  @Test("a later group selects its unit's later pillar")
  func laterRowSelectsLaterPillar() {
    #expect(
      TodaySelectionModel.pillar(for: .later(unitID: "unit_b"), in: today)
        == FieldCellRef(unitID: "unit_b", horizon: .later))
  }

  @Test("selects no pillar for a group whose unit is not in the field")
  func unknownUnitSelectsNoPillar() {
    #expect(TodaySelectionModel.pillar(for: .week(unitID: "unit_z"), in: today) == nil)
    #expect(TodaySelectionModel.pillar(for: .later(unitID: "unit_b"), in: today) != nil)
    #expect(TodaySelectionModel.pillar(for: .item("task_unknown"), in: today) == nil)
  }

  @Test("every selection a pillar makes comes back to the same pillar")
  func roundTrip() {
    for cell in today.field.cells {
      let pillar = TodaySelectionModel.ref(cell)
      let selection = TodaySelectionModel.selection(forPillar: pillar, in: today)
      #expect(selection != nil)
      #expect(selection.flatMap { TodaySelectionModel.pillar(for: $0, in: today) } == pillar)
    }
  }

  @Test("every unit a group names is one of the field's units")
  func groupsNameFieldUnits() {
    let units = Set(today.field.units.map(\.id))
    #expect(today.lists.week.allSatisfy { units.contains($0.unitId) })
    #expect(today.lists.later.allSatisfy { units.contains($0.unitId) })
  }
}
