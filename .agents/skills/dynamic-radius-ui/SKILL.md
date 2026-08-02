---
name: dynamic-radius-ui
description: Use this skill when building or modifying the feed logic for the Daily Ledger or Academy study groups to prevent empty screens in low-density areas.
---

# Skill Info
This skill governs the graceful degradation of hyperlocal scoping. An empty app feels like a broken app.

**Execution Steps:**
1. **Threshold Check:** Query the local database view for posts matching the user's exact pin code. 
2. **Radius Expansion:** If the result count is less than 5 within the last 7 days, trigger the secondary repository query targeting the broader district or Assembly constituency code.
3. **UI Badging:** For any item rendered from the expanded query, append the `NearbyBadgeWidget` to the list tile to clearly communicate that the content is outside their immediate hyperlocal zone.
4. **Seamless Blending:** Sort the combined results chronologically. Do not create separate UI sections for "Local" and "Nearby"; blend them into a single continuous feed.

**Resource References:**
* Reference `./widgets/nearby_badge_widget.dart` for the visual indicator.
* Reference `./queries/ledger_queries.drift` for the fallback district queries.