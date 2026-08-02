---
name: offline-first-repo
description: Use this skill whenever generating a new data model, repository, or service that interacts with remote APIs. It enforces the queue-based, offline-first architecture by ensuring data is written to local storage first.
---

# Skill Info
This skill governs the creation of data layer components. You must never bypass the local database to make direct API calls. 

**Execution Steps:**
1. **Define the Local Schema:** Create the SQLite/Drift table definition for the new entity.
2. **Generate the Queue Wrapper:** If this is a `POST`, `PUT`, or `DELETE` action, wrap the payload in a `SyncQueueItem` with a pending status. 
3. **Repository Implementation:** Write the repository methods to only read from and write to the local SQLite tables. 
4. **Sync Trigger:** Append a silent background sync call to the repository method to attempt an immediate flush to the API Gateway, but return the local database success immediately to the UI.

**Resource References:**
* Reference `./templates/base_repository.dart` for the abstract class structure.
* Reference `./templates/queue_item_model.dart` for the required sync status enum.