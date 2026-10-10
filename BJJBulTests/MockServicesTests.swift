import XCTest
@testable import BJJBul

final class MockServicesTests: XCTestCase {
    func testGymsFilterByCity() async throws {
        let service = MockGymService()
        let all = try await service.gyms(cityId: nil)
        let sofia = try await service.gyms(cityId: MockData.sofiaId)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(sofia.count, 1)
    }

    func testCoachesForGym() async throws {
        let service = MockCoachService()
        let coaches = try await service.coaches(gymId: MockData.gym3Id)
        XCTAssertEqual(coaches.count, 1)
    }
}
