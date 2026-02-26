# PR #6 Review Fixes - 2026-02-26

## Issues to Address

### Issue 1 (Red): MockReminder.isAllDay doesn't strip time from dueDateComponents

- `EKReminderWrapper.isAllDay` setter strips hour/minute/second when set to true
- `MockReminder.isAllDay` is a plain Bool — no side effect on dueDateComponents
- Fix: Add computed property with getter/setter mirroring EKReminderWrapper behavior
- Also improve the test to use non-midnight time

### Issue 2 (Yellow): weekPosition only read from first daysOfTheWeek entry

- `rule.daysOfTheWeek?.first?.weekNumber` — loses data from other entries
- This is a known limitation of our simplified model (single weekPosition)
- Fix: Add a comment documenting this limitation

### Issue 3 (Yellow): endDate + endCount both provided silently discards endCount

- In parseRecurrenceInput, validate and throw if both provided
- Simple guard check

### Issue 4 (Yellow): dueDateIncludesTime without dueDate silently no-ops

- In create: if dueDateIncludesTime specified but no dueDate input, throw error
- In update: if dueDateIncludesTime specified but no existing dueDateComponents, throw error

### Issue 5 (Yellow): Date range filter re-parses ISO 8601 strings

- Move date range filtering before convertToOutput
- Filter on raw Reminder objects using Date comparisons
- Need helper to get the relevant Date from a Reminder

### Issue 6 (Blue): daysOfMonth schema says 1-31 but EventKit supports negative

- Expand schema minimum from 1 to -31
- Update description to mention negative values

### Issue 7 (Blue): weekPosition range not validated

- Validate in parseRecurrenceInput: must be in [-4...-1, 1...5] or 0
- Throw clear error for out-of-range values

## Progress

- [ ] Issue 1: MockReminder.isAllDay
- [ ] Issue 2: weekPosition comment
- [ ] Issue 3: endDate + endCount validation
- [ ] Issue 4: dueDateIncludesTime validation
- [ ] Issue 5: Date range filter refactor
- [ ] Issue 6: daysOfMonth schema
- [ ] Issue 7: weekPosition validation
- [ ] Update test for issue 1 (non-midnight time)
- [ ] Run tests + build
- [ ] Commit + push
