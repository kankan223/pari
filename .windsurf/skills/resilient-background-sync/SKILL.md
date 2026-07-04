---
name: resilient-background-sync
description: Use this skill for implementing background task runners, WebSockets, or polling mechanisms that sync the local SQLite queue with the remote API Gateway under highly fluctuating network conditions.
---

# Skill Info
This skill governs how the local queue flushes data to the server. You must assume the network state is highly volatile, similar to mobile data dropping in and out during extended rail transit. The sync engine must be built for aggressive retries and failure tolerance.

**Execution Steps:**
1. **State Check:** Always verify the active network connection state before attempting to process the `SyncQueueItem` list.
2. **Chunking & Timeouts:** Batch queue items into small chunks. Set aggressive, short timeout limits on HTTP requests to prevent hanging threads if a connection drops mid-transit.
3. **Idempotency Enforcement:** Generate and attach a unique `Idempotency-Key` header to every mutation request so the API Gateway can safely ignore duplicate retries if a response drops.
4. **Silent Failure:** If a sync fails, increment the retry counter on the local queue item, update the sync timestamp, and fail silently in the background without throwing unhandled exceptions to the UI.

**Resource References:**
* Reference `./utils/network_info_provider.dart` for the connection state listener.
* Reference `./templates/sync_worker.dart` for the background isolate configuration.