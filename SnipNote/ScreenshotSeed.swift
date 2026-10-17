#if DEBUG
import Foundation
import SwiftData

/// App Store screenshot mode, debug builds only. Launch with `--screenshot-seed` to skip
/// onboarding, stay in Local mode as a Guest, send no analytics, report the Parakeet model as
/// installed, and fill an in-memory store with sample meetings. Nothing is written to Supabase.
enum ScreenshotSeed {
  static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("--screenshot-seed") }
  /// Shown on the Home balance widget instead of a server balance.
  static let balanceMinutes = 480

  /// Called while the model container is built, which is before any manager or view reads these.
  static func prepareDefaults() {
    let defaults = UserDefaults.standard
    defaults.set(true, forKey: "hasCompletedOnboarding")
    defaults.set(false, forKey: AnalyticsService.enabledDefaultsKey)
    defaults.set(TranscriptionMode.local.rawValue, forKey: "localTranscription.mode")
    defaults.set(true, forKey: "hasSeenVoiceMemosTip")
    let environment = ProcessInfo.processInfo.environment
    if let language = environment["SNIPNOTE_SCREENSHOT_LANGUAGE"] {
      defaults.set(language, forKey: "appLanguage")
    }
    // "Light" or "Dark" (ThemeType raw values); the simulator's own appearance is not reliable.
    defaults.set(environment["SNIPNOTE_SCREENSHOT_THEME"] ?? ThemeType.dark.rawValue, forKey: "selectedTheme")
  }

  @MainActor
  static func populate(_ context: ModelContext) {
    let calendar = Calendar.current
    let now = Date()
    for sample in samples {
      let day = calendar.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
      var start = calendar.date(bySettingHour: sample.hour, minute: sample.minute, second: 0, of: day) ?? day
      // Today's meetings must already be over.
      if start.addingTimeInterval(sample.minutes * 60) > now {
        start = now.addingTimeInterval(-(sample.minutes * 60) - Double(sample.daysAgo + 1) * 3_600)
      }
      let end = start.addingTimeInterval(sample.minutes * 60)

      let meeting = Meeting(
        name: sample.name,
        location: sample.location,
        audioTranscript: sample.transcript,
        shortSummary: sample.overview,
        aiSummary: sample.summary
      )
      meeting.startTime = start
      meeting.endTime = end
      meeting.dateCreated = end
      meeting.dateModified = end
      meeting.sourceAudioDurationSeconds = sample.minutes * 60
      meeting.processingState = .completed
      meeting.processingPhaseRaw = MeetingProcessingPhase.completed.rawValue
      meeting.progressPercent = 100
      meeting.transcriptionBackend = .local
      meeting.localTranscriptionModel = LocalTranscriptionModel.restoredSelection(nil)
      meeting.transcriptionLanguage = "en"
      context.insert(meeting)
    }
    try? context.save()
  }

  private struct Sample {
    let daysAgo: Int
    let hour: Int
    let minute: Int
    let minutes: Double
    let name: String
    let location: String
    let overview: String
    let summary: String
    let transcript: String
  }

  // Newest first. Consecutive days 0...4 give a five-day streak on Home.
  private static let samples: [Sample] = [
    Sample(
      daysAgo: 0, hour: 10, minute: 0, minutes: 34,
      name: "Product Roadmap Q1",
      location: "Studio, 3rd floor",
      overview: "The team agreed on the three Q1 priorities and moved the mobile redesign to February.",
      summary: """
      ## Key Discussion Points
      - Customer feedback points to onboarding as the biggest drop-off, ahead of pricing.
      - The mobile redesign needs two more weeks of research before design starts.
      - Engineering capacity in January is reduced by the infrastructure migration.

      ## Decisions Made
      - Q1 priorities: onboarding refresh, offline mode, and team sharing.
      - The mobile redesign moves to February; Sara owns the research plan.
      - Weekly demos replace the monthly review starting next week.

      ## Next Steps
      - Sara shares the research plan by Friday.
      - Luca estimates offline mode with the platform team.
      - Next roadmap check-in on the 15th.
      """,
      transcript: """
      Okay, let's get started. The goal today is to lock the priorities for the first quarter so everyone can plan around them.

      From the feedback we collected, onboarding is clearly the biggest issue. About forty percent of new users leave before finishing the setup, and pricing comes up much less than we expected.

      That matches what support is seeing. Most tickets in December were about getting started, not about cost.

      Then I'd put the onboarding refresh first. Offline mode second, because it's the most requested feature from teams in the field, and team sharing third.

      What about the mobile redesign? I don't think we're ready. We need at least two more weeks of interviews before design can start.

      Agreed. Let's move it to February. Sara, can you own the research plan?

      Sure, I'll share it by Friday.

      Luca, can you get an estimate for offline mode from the platform team? January is tight because of the migration.

      Yes, I'll talk to them tomorrow.

      One more thing: I'd like to replace the monthly review with a short weekly demo. It keeps everyone closer to the work.

      Works for me. Let's start next week and check the roadmap again on the fifteenth.
      """
    ),
    Sample(
      daysAgo: 0, hour: 8, minute: 30, minutes: 16,
      name: "Morning Stand-up",
      location: "Video call",
      overview: "Quick stand-up covering the release checklist, one blocker on payments, and today's test plan.",
      summary: """
      ## Key Discussion Points
      - The release checklist is 80% done; screenshots and release notes remain.
      - Payments are blocked on a pending agreement in the store dashboard.
      - QA wants a full regression pass on older devices.

      ## Decisions Made
      - Marco signs the pending agreement this morning.
      - Release notes are written today and reviewed tomorrow.

      ## Next Steps
      - Elena runs the regression pass on two older phones.
      - Stand-up tomorrow at 8:30 as usual.
      """,
      transcript: """
      Morning everyone, let's keep it short. Where are we on the release checklist?

      About eighty percent done. What's left is the new screenshots and the release notes.

      Payments are blocked, though. The store dashboard says there's an agreement waiting to be signed.

      I can sign it this morning, I'm the account holder.

      Great. Elena, can QA do a full regression pass on older devices before we submit?

      Yes, I'll use the two older phones we have in the office.

      Then I'll write the release notes today and we review them together tomorrow. Same time tomorrow.
      """
    ),
    Sample(
      daysAgo: 1, hour: 15, minute: 0, minutes: 47,
      name: "Client Kickoff – Northwind",
      location: "Northwind HQ, Milan",
      overview: "Kickoff with Northwind to confirm scope, timeline and the weekly reporting rhythm.",
      summary: """
      ## Key Discussion Points
      - Northwind wants the new booking flow live before their spring campaign.
      - Their team prefers one weekly update instead of ad-hoc emails.
      - Analytics access is needed from day one to measure the baseline.

      ## Decisions Made
      - Launch target: March 28, with a soft launch two weeks earlier.
      - Weekly update every Thursday, owned by Giulia.
      - Scope excludes the loyalty program for this phase.

      ## Next Steps
      - Giulia sends the project plan and contacts list by Monday.
      - Northwind grants analytics access this week.
      - Design workshop scheduled for next Wednesday.
      """,
      transcript: """
      Thanks for having us. Let's start with what success looks like for you.

      For us the key date is the spring campaign. The new booking flow has to be live before it, otherwise the campaign sends people to the old one.

      Understood. Working backwards, a launch on March twenty-eighth with a soft launch two weeks before gives us room to fix things.

      That works. On communication, we'd really prefer one weekly update rather than emails every day.

      Of course. Giulia will send it every Thursday.

      And the loyalty program? Some people internally assumed it was included.

      Let's keep it out of this phase. It deserves its own project once the booking flow is stable.

      Fine. What do you need from us right away?

      Access to analytics, so we can measure the baseline from day one, and a list of contacts for each area.

      We'll get you access this week. Shall we schedule the design workshop for next Wednesday?
      """
    ),
    Sample(
      daysAgo: 2, hour: 11, minute: 30, minutes: 28,
      name: "Design Review",
      location: "Room Galileo",
      overview: "Review of the new onboarding screens, with two changes requested before user testing.",
      summary: """
      ## Key Discussion Points
      - The new onboarding cuts setup from five screens to three.
      - The permissions screen still feels like a wall of text.
      - Dark mode contrast on secondary buttons is too low.

      ## Decisions Made
      - Permissions are explained one at a time, when they are first needed.
      - Secondary buttons get the stronger outline in dark mode.

      ## Next Steps
      - Anna updates the prototype by Thursday.
      - User testing with five participants next week.
      """,
      transcript: """
      So this is the new onboarding. We went from five screens to three, and the account step is gone completely.

      It feels much lighter. My only concern is the permissions screen, it's still a wall of text.

      What if we ask for each permission when it's first needed instead of all at once?

      That's better for trust too. Let's do that.

      One more detail: in dark mode the secondary buttons are hard to see. The contrast is too low.

      Right, we can use the stronger outline we already have in the design system.

      Okay. Anna, can you update the prototype by Thursday? Then we test with five people next week.
      """
    ),
    Sample(
      daysAgo: 3, hour: 9, minute: 30, minutes: 62,
      name: "Quarterly Business Review",
      location: "Boardroom",
      overview: "Revenue grew 18% over the quarter; hiring and the partner program were approved for next quarter.",
      summary: """
      ## Key Discussion Points
      - Revenue grew 18% quarter over quarter, mostly from existing customers.
      - Churn is down to 2.1% after the support changes.
      - The sales cycle for larger teams is getting longer.

      ## Decisions Made
      - Two new hires approved: one support engineer, one account manager.
      - The partner program pilot starts with three agencies.

      ## Next Steps
      - Finance shares the updated budget next week.
      - Marco drafts the partner program terms.
      - Next review at the end of the quarter.
      """,
      transcript: """
      Let's start with the numbers. Revenue grew eighteen percent quarter over quarter, and most of that came from existing customers upgrading.

      Churn is also down, to two point one percent, after we changed how support handles the first week.

      That's great news. What's not going well?

      The sales cycle for larger teams is getting longer. Procurement is asking for more security documentation.

      Then the account manager role becomes more urgent. I'd approve that hire, plus one support engineer.

      Agreed on both. And the partner program?

      Let's pilot it with three agencies we already know. Marco, can you draft the terms?

      Yes. Finance will share the updated budget next week so we can plan the hires.
      """
    ),
    Sample(
      daysAgo: 4, hour: 14, minute: 0, minutes: 22,
      name: "1:1 with Sara",
      location: "Café downstairs",
      overview: "Sara wants to grow into research leadership; she'll lead the February study and mentor a junior designer.",
      summary: """
      ## Key Discussion Points
      - Sara wants to grow toward research leadership this year.
      - Her workload is high because of two parallel projects.
      - She'd like more time with customers.

      ## Decisions Made
      - Sara leads the February research study end to end.
      - One of her projects moves to Anna next month.

      ## Next Steps
      - Sara drafts a growth plan for the next 1:1.
      - Introduce Sara to the customer advisory group.
      """,
      transcript: """
      How are things going, honestly?

      Good, but busy. Running two projects in parallel means I never get deep into either.

      That's fair. Let's move one of them to Anna next month. What would you like to focus on?

      Research. I'd like to grow toward leading research, and spend more time with customers.

      Then lead the February study end to end. You'd plan it, run it and present the results.

      I'd love that. And maybe mentor someone junior?

      Good idea. Can you draft a short growth plan for our next one-on-one? I'll also introduce you to the customer advisory group.
      """
    ),
    Sample(
      daysAgo: 6, hour: 16, minute: 0, minutes: 39,
      name: "Marketing Sync",
      location: "Video call",
      overview: "Plan for the spring launch: one hero video, a refreshed website and a newsletter sequence.",
      summary: """
      ## Key Discussion Points
      - The spring launch needs one clear message instead of five features.
      - Video performed best in the last campaign.
      - The website still shows last year's screenshots.

      ## Decisions Made
      - One hero video focused on the main use case.
      - Website and store screenshots are refreshed before launch.
      - A three-email newsletter sequence replaces the single announcement.

      ## Next Steps
      - Paolo writes the video script by next Monday.
      - Chiara prepares the newsletter drafts.
      """,
      transcript: """
      For the spring launch, I think we're trying to say too much. Five features in one announcement is too many.

      Agreed. What did best last time?

      Video, by far. Twice the engagement of anything else.

      Then let's do one hero video about the main use case, and keep the rest for later posts.

      We also need to refresh the website, it still shows last year's screenshots. And the store page.

      Good point. For email, a sequence of three works better than one big announcement.

      Paolo, can you write the script by Monday? Chiara will prepare the newsletter drafts.
      """
    ),
    Sample(
      daysAgo: 8, hour: 10, minute: 0, minutes: 53,
      name: "Engineering Planning",
      location: "Room Volta",
      overview: "Sprint planning for the migration, with offline sync split into two smaller milestones.",
      summary: """
      ## Key Discussion Points
      - The database migration is on track but needs a rollback plan.
      - Offline sync is too large for a single sprint.
      - Test coverage on the sync layer is low.

      ## Decisions Made
      - Offline sync is split into read-only first, then editing.
      - No release goes out without the rollback runbook.

      ## Next Steps
      - Davide writes the rollback runbook.
      - Add sync tests before the editing milestone.
      """,
      transcript: """
      Let's go through the sprint. The migration is on track, but we don't have a rollback plan yet.

      I can write the runbook. Nothing should ship without it.

      Agreed. Offline sync is the big one. Honestly it's too large for one sprint.

      What if we split it? Read-only offline first, then editing in the second milestone.

      That's much safer. Editing is where the conflicts happen.

      Then we need better tests on the sync layer before we start editing. Coverage there is low.

      Okay. Davide takes the runbook, and we add sync tests before the editing milestone.
      """
    ),
    Sample(
      daysAgo: 11, hour: 17, minute: 0, minutes: 25,
      name: "Interview – Product Designer",
      location: "Video call",
      overview: "Strong portfolio and clear process; the team recommends moving the candidate to the final round.",
      summary: """
      ## Key Discussion Points
      - Strong portfolio with two shipped mobile products.
      - Clear explanation of research and iteration process.
      - Less experience with design systems at scale.

      ## Decisions Made
      - Move the candidate to the final round.

      ## Next Steps
      - Schedule the design exercise for next week.
      - Collect written feedback from all interviewers by Friday.
      """,
      transcript: """
      Thanks for walking us through your portfolio. Can you tell us how you decided what to cut in the second project?

      We tested three versions with users and the simplest one won by a lot, so we removed the advanced settings entirely.

      How did you work with engineering during that change?

      We paired every week. I'd bring rough sketches and we'd decide together what was realistic.

      Great. Have you worked with a design system across several products?

      Only on one product. I'd love to do more of that.

      Thank you, that's all from us. We'll be in touch soon about next steps.
      """
    ),
    Sample(
      daysAgo: 15, hour: 9, minute: 0, minutes: 44,
      name: "Budget Planning 2027",
      location: "Finance office",
      overview: "First pass at next year's budget, with tooling costs cut and the events budget doubled.",
      summary: """
      ## Key Discussion Points
      - Tooling costs grew 30% with overlapping subscriptions.
      - Events brought the highest-quality leads last year.
      - Hiring plan depends on the second-half revenue forecast.

      ## Decisions Made
      - Remove overlapping tools and consolidate to one suite.
      - Double the events budget for next year.

      ## Next Steps
      - Each team lists the tools it actually uses by the end of the month.
      - Revisit the hiring plan after the Q2 forecast.
      """,
      transcript: """
      First pass at next year's budget. The surprise is tooling, it grew thirty percent.

      A lot of that is overlap. Three teams pay for different tools that do the same thing.

      Let's consolidate. Every team lists the tools it actually uses by the end of the month.

      On the other side, events brought the best leads last year. I'd double that budget.

      I agree. And hiring?

      It depends on the second half. Let's revisit after the Q2 forecast.
      """
    ),
    Sample(
      daysAgo: 19, hour: 11, minute: 0, minutes: 31,
      name: "Customer Feedback Session",
      location: "Video call",
      overview: "Five customers shared how they use the app; search and exports were the most requested improvements.",
      summary: """
      ## Key Discussion Points
      - Customers mostly use the app for client calls and internal meetings.
      - Search across past meetings is the most requested improvement.
      - Exports to PDF and Word are used weekly by managers.

      ## Decisions Made
      - Improve search across transcripts and summaries.
      - Keep exports in the free plan.

      ## Next Steps
      - Share the session notes with the product team.
      - Follow up with two customers for a deeper interview.
      """,
      transcript: """
      Thanks everyone for joining. We'd love to hear how you actually use the app day to day.

      Mostly for client calls. I record, and afterwards I only read the summary and the next steps.

      Same here, but for internal meetings. What I miss is search. I know we discussed something two weeks ago and I can't find it.

      For me exports matter most. My manager wants a PDF every week.

      That's really helpful. Would two of you be open to a longer interview next week?
      """
    ),
  ]
}
#endif
