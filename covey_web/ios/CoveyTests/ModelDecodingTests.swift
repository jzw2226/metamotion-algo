import XCTest
@testable import Covey

final class ModelDecodingTests: XCTestCase {

    func test_Plan_decodesFromSupabaseRow() throws {
        let json = #"""
        {
          "id": "aaaaaaaa-1111-1111-1111-111111111111",
          "host_id": "11111111-1111-1111-1111-111111111111",
          "title": "TEST: Public Open Plan",
          "description": "A casual evening.",
          "cover_url": null,
          "plan_date": "2026-05-17",
          "start_time": null,
          "end_time": null,
          "timezone": "America/Los_Angeles",
          "city": "San Francisco",
          "status": "published",
          "visibility": "public",
          "hangout_type": "casual",
          "join_mode": "open",
          "capacity": 4,
          "min_age": null,
          "max_age": null,
          "gender_filter": null,
          "dress_code": null,
          "theme": null,
          "pet_friendly": false,
          "kid_friendly": false,
          "accessibility_notes": null,
          "language": null,
          "byo_notes": null,
          "created_at": "2026-05-14T03:24:00Z",
          "updated_at": "2026-05-14T03:24:00Z",
          "published_at": "2026-05-14T03:24:00Z",
          "cancelled_at": null,
          "completed_at": null
        }
        """#.data(using: .utf8)!

        // plan_date is a Postgres `date`, served as "YYYY-MM-DD".
        // `JSONDecoder.supabase` must accept that shape so Plan rows decode.
        let plan = try JSONDecoder.supabase.decode(Plan.self, from: json)
        XCTAssertEqual(plan.title, "TEST: Public Open Plan")
        XCTAssertEqual(plan.status, .published)
        XCTAssertEqual(plan.visibility, .public)
        XCTAssertEqual(plan.hangoutType, .casual)
        XCTAssertEqual(plan.joinMode, .open)
        XCTAssertEqual(plan.capacity, 4)
        XCTAssertNotNil(plan.planDate)
        XCTAssertNotNil(plan.publishedAt)
        XCTAssertNil(plan.cancelledAt)
    }

    func test_HangoutType_enumDecoding() throws {
        let json = #""date""#.data(using: .utf8)!
        let value = try JSONDecoder.supabase.decode(HangoutType.self, from: json)
        XCTAssertEqual(value, .date)
    }

    func test_PlanVisibility_inviteOnly_decodesFromUnderscoreString() throws {
        let json = #""invite_only""#.data(using: .utf8)!
        let value = try JSONDecoder.supabase.decode(PlanVisibility.self, from: json)
        XCTAssertEqual(value, .inviteOnly)
    }

    func test_JoinMode_enumRoundtrip() throws {
        let values: [JoinMode] = [.open, .request, .invite]
        for v in values {
            let encoded = try JSONEncoder.supabase.encode(v)
            let decoded = try JSONDecoder.supabase.decode(JoinMode.self, from: encoded)
            XCTAssertEqual(decoded, v)
        }
    }

    func test_ArrivalStatusKind_decodes_on_the_way() throws {
        let json = #""on_the_way""#.data(using: .utf8)!
        let value = try JSONDecoder.supabase.decode(ArrivalStatusKind.self, from: json)
        XCTAssertEqual(value, .onTheWay)
    }
}
