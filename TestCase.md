## EventProcessor – Demo Test Cases

> **Note:** These are **demo test cases only**, intended as a starting point for coverage.  
> They are **not** a full‑fledged or exhaustive test suite for all modules.

---

### 1. `HomeViewModel` – LLM call success
- **Preconditions**: Inject a mock `LLMInferenceProtocol` that returns tokens `["Hello", " ", "World"]`. Inject an in‑memory `LogDBService` or dummy DB.
- **Steps**:
  1. Create a `HomeViewModel` with the mocks.
  2. Create a `LogEntry` with value `42` and current timestamp.
  3. Call `await viewModel.callLLM(for: log)`.
- **Expected result**:
  - Result is `.success("Hello World")`.
  - Prompt passed to the mock contains `SystemConstants.defaultPrompt` and the string `"42"`.

### 2. `HomeViewModel` – LLM call failure surfaces error
- **Preconditions**: Inject a mock `LLMInferenceProtocol` that always throws from `generate`.
- **Steps**:
  1. Create a `HomeViewModel` with the failing mock.
  2. Call `await viewModel.callLLM(for: someLog)`.
- **Expected result**:
  - Result is `.failure` with a non‑nil error.

### 3. `HomeViewModel` – Retry logic succeeds before max retries
- **Preconditions**: Inject a “flaky” mock `LLMInferenceProtocol` that:
  - Fails on the first two calls to `generate`.
  - Succeeds on the third call and yields token `"OK"`.
- **Steps**:
  1. Create `HomeViewModel` with the flaky mock.
  2. Call `await viewModel.process(log)`.
- **Expected result**:
  - Returned string is `"OK"`.
  - The mock indicates `generate` was called exactly 3 times.

### 4. `HomeViewModel` – Retry logic exhausts and returns fallback
- **Preconditions**: Inject a mock `LLMInferenceProtocol` that *always* throws.
- **Steps**:
  1. Create `HomeViewModel` with the failing mock.
  2. Call `await viewModel.process(log)`.
- **Expected result**:
  - Returned string is `"LLM generation Failed after retries..."`.
  - `generate` was called up to the configured max retry count.

### 5. `HomeViewModel` – Timer pipeline publishes recent event
- **Preconditions**: Use a `HomeViewModel` with a dummy `LogDBService` and mock LLM.
- **Steps**:
  1. Subscribe to `viewModel.$resentEvent` using Combine.
  2. Call `viewModel.startService()`.
  3. Wait for up to a few seconds for an event emission.
- **Expected result**:
  - `resentEvent` eventually becomes non‑nil.
  - The emitted `LogEntry` has a value in the expected random range and a recent timestamp.

### 6. `HomeViewModel` – `processingLogs` flag reflects LLM work
- **Preconditions**: Inject a mock LLM that has a small artificial delay before emitting tokens.
- **Steps**:
  1. Start the service and feed a small batch of logs to `processBatch`.
  2. Observe `processingLogs` before, during, and after processing.
- **Expected result**:
  - `processingLogs` becomes `true` when processing starts.
  - It stays `true` throughout the LLM call and metadata update.
  - (Optional) A separate design could set it back to `false` when done.

---

### 7. `LogDBService` – Grouping by minute and flushing
- **Preconditions**: Inject a `RecordingLogDB` that implements `LogDBProtocol` and stores passed `LogMinEntry` objects.
- **Steps**:
  1. Create `LogDBService` with a long flush interval (so it doesn’t auto‑flush).
  2. Log two entries in the same minute and one in the next minute.
  3. Call `forceFlush()`.
- **Expected result**:
  - Exactly two `LogMinEntry` buckets are passed to the DB (one per minute).
  - The first bucket contains the two logs in the same minute.
  - The second bucket contains the single log from the next minute.

### 8. `LogDBService` – Meta string update applied on flush
- **Preconditions**: Same `RecordingLogDB` as above.
- **Steps**:
  1. Log a single `LogEntry`.
  2. Call `update(metaString:for:)` with a known `Date` for that entry.
  3. Call `forceFlush()`.
- **Expected result**:
  - One `LogMinEntry` is flushed.
  - Its `metaString` matches the provided value.

### 9. `LogDBService` – Force flush with no buffered logs
- **Preconditions**: Fresh `LogDBService` instance, no calls to `log` or `update`.
- **Steps**:
  1. Call `forceFlush()`.
- **Expected result**:
  - No `addEvents` or `update(metadataWith:)` calls are made to the underlying DB.

---

### 10. `LogSQLite` – Adding a single event creates minute and second row
- **Preconditions**: Use a temporary DB path for `LogSQLite` so tests do not touch real user data.
- **Steps**:
  1. Create a `LogSQLite` instance with a temp file path.
  2. Call `addEvent(data:timestamp:)` once.
  3. Query the DB tables directly or via `getEvents` for that time range.
- **Expected result**:
  - One row exists in the minutes table for the normalized start‑of‑minute.
  - One row exists in the seconds table pointing to that minute row, with the correct value and timestamp.

### 11. `LogSyncManager` – Sync uploads only when events exist
- **Preconditions**:
  - Mock `LogDBProtocol` that returns a configurable list of `LogMinEntry`.
  - Mock `LogUploaderProtocol` that records uploaded events.
- **Steps**:
  1. Configure DB mock to return an empty array, call `sync()`, and assert that uploader is **not** called.
  2. Configure DB mock to return a non‑empty array, call `sync()`, and assert that uploader is called with that array.
- **Expected result**:
  - When there are no events, `upload(events:)` is never called.
  - When there are events, `upload(events:)` is called once with the expected data, and the last sync timestamp is updated.

---

These scenarios are meant to guide further, more exhaustive test design across the app (UI, error handling, performance, and integration paths are **not** fully covered here).

