# Family Account Backend API Spec

This document describes the backend API surface needed by the Family Account iOS app prototype.

The current app supports:

- Shared family ledger
- Private personal ledger
- Manual transaction input
- AI voice input
- AI receipt photo input
- Recurring weekly/monthly/custom transactions
- Fixed expense confirmation
- Tags and cross-month project tracking
- Budgets
- Reports
- Offline local changes with later sync

All API names are provisional and can be adjusted when the backend framework is chosen.

## Core Concepts

### Account Types

| Type | Meaning |
|---|---|
| `shared` | Visible to all family members. Used for family expenses. |
| `private` | Visible only to the owner. Must not be included in family-wide totals. |

Private ledger access must be enforced by the backend. The client must not be trusted to filter private data correctly.

### Current User Rule

For private transactions:

- A user can only read their own private transactions.
- A user can only create private transactions for themselves.
- A user can only update or delete their own private transactions.
- Other family members must never receive these records from list, summary, report, project, or sync APIs.

### Shared Ledger Rule

For shared transactions:

- All family members can read shared transactions.
- Each transaction stores who recorded it.
- Reports can aggregate shared spending by recorder/member.

## Auth / User / Family

### `POST /auth/login`

Logs in the user and returns an access token.

Request:

```json
{
  "provider": "apple",
  "identityToken": "..."
}
```

Response:

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "user": {
    "id": "user_ting",
    "displayName": "Ting",
    "initial": "婷",
    "color": "orange"
  }
}
```

### `GET /me`

Returns the current user.

### `GET /families/current`

Returns the current family workspace.

### `GET /families/current/members`

Returns family members.

Response:

```json
[
  {
    "id": "user_ting",
    "displayName": "Ting",
    "initial": "婷",
    "color": "orange"
  },
  {
    "id": "user_kai",
    "displayName": "Kai",
    "initial": "凱",
    "color": "green"
  }
]
```

### `POST /families/invitations`

Invites a new family member.

## Transactions

### Transaction Object

```json
{
  "id": "txn_123",
  "familyId": "fam_123",
  "ownerUserId": "user_ting",
  "recordedByUserId": "user_ting",
  "accountType": "shared",
  "title": "晚餐",
  "amount": 680,
  "currency": "TWD",
  "category": "food",
  "tags": ["#日常"],
  "occurredAt": "2026-07-16T12:30:00Z",
  "isAI": false,
  "source": "manual",
  "recurringRuleId": null,
  "createdAt": "2026-07-16T12:31:00Z",
  "updatedAt": "2026-07-16T12:31:00Z",
  "deletedAt": null,
  "clientMutationId": "local_uuid",
  "serverRevision": 42
}
```

### Categories

| API Value | UI Label |
|---|---|
| `food` | 食 |
| `clothing` | 衣 |
| `housing` | 住 |
| `transport` | 行 |
| `education` | 育 |
| `entertainment` | 樂 |
| `medical` | 醫 |
| `other` | 其他 |

### `GET /transactions`

Lists transactions visible to the current user.

Query params:

| Param | Purpose |
|---|---|
| `accountType` | `shared`, `private`, or omitted |
| `from` | Start date |
| `to` | End date |
| `category` | Filter by category |
| `recordedByUserId` | Filter shared transactions by recorder |
| `tag` | Filter by tag |
| `isAI` | Filter AI-created transactions |
| `cursor` | Pagination cursor |

Important behavior:

- If `accountType=private`, return only the current user's private transactions.
- If `accountType` is omitted, return shared transactions plus the current user's own private transactions.
- Never return another user's private transactions.

### `POST /transactions`

Creates a transaction.

Manual transactions can be created without AI.

Request:

```json
{
  "clientMutationId": "local_uuid",
  "accountType": "shared",
  "title": "晚餐",
  "amount": 680,
  "currency": "TWD",
  "category": "food",
  "tags": ["#日常"],
  "occurredAt": "2026-07-16T12:30:00Z",
  "source": "manual",
  "recurringRuleId": null
}
```

### `PATCH /transactions/{id}`

Updates a transaction.

Fields that should be editable:

- Title
- Amount
- Date
- Category
- Account type, if permission allows
- Tags
- Recurring rule link

### `DELETE /transactions/{id}`

Soft deletes a transaction.

Use `deletedAt` instead of hard delete when sync is enabled.

### `GET /transactions/summary`

Returns totals for the home account switcher.

Response:

```json
{
  "shared": {
    "total": 65440,
    "byRecorder": [
      {
        "userId": "user_ting",
        "amount": 14130
      },
      {
        "userId": "user_kai",
        "amount": 51310
      }
    ]
  },
  "private": {
    "total": 3000
  },
  "overview": {
    "total": 68440,
    "sharedAmount": 65440,
    "privateAmount": 3000
  }
}
```

Private total is only for the current user.

## AI Input

AI input requires API access. The app should not treat voice or photo input as fully offline.

### `POST /ai/parse-voice`

Parses voice input into a transaction draft.

Input options:

- Audio file upload
- Already-transcribed text

Request:

```json
{
  "transcript": "買了一杯飲料 30 塊",
  "familyId": "fam_123",
  "timezone": "Asia/Taipei"
}
```

Response:

```json
{
  "draftId": "draft_voice_123",
  "title": "飲料",
  "amount": 30,
  "currency": "TWD",
  "category": "food",
  "accountType": "shared",
  "tags": ["#AI", "#語音"],
  "confidence": 0.93,
  "rawText": "買了一杯飲料 30 塊"
}
```

### `POST /ai/parse-receipt`

Uploads a receipt photo and returns a transaction draft.

Response:

```json
{
  "draftId": "draft_receipt_123",
  "title": "全聯採買",
  "amount": 1268,
  "currency": "TWD",
  "category": "food",
  "accountType": "shared",
  "tags": ["#AI", "#收據"],
  "merchant": "全聯",
  "occurredAt": "2026-07-16T10:11:00Z",
  "confidence": 0.88
}
```

### `POST /ai/confirm-transaction`

Turns an AI draft into a real transaction.

Request:

```json
{
  "draftId": "draft_voice_123",
  "clientMutationId": "local_uuid",
  "overrides": {
    "category": "food",
    "accountType": "shared"
  }
}
```

### `POST /ai/feedback`

Stores user corrections after an AI transaction is edited.

Use this to improve future categorization.

## Recurring Transactions

Recurring rules should be separate from generated transactions.

### Recurring Rule Object

```json
{
  "id": "rule_123",
  "familyId": "fam_123",
  "ownerUserId": "user_ting",
  "accountType": "shared",
  "title": "保母費",
  "amount": 18000,
  "currency": "TWD",
  "category": "education",
  "tags": ["#保母費"],
  "frequency": "monthly",
  "detail": {
    "dayOfMonth": 5
  },
  "startsAt": "2026-01-01",
  "endsAt": null,
  "isActive": true,
  "createdAt": "2026-07-16T12:00:00Z",
  "updatedAt": "2026-07-16T12:00:00Z"
}
```

### Frequencies

| Value | Meaning |
|---|---|
| `none` | Not recurring |
| `weekly` | Every week |
| `monthly` | Fixed day of month |
| `custom` | Custom interval |

### `GET /recurring-rules`

Lists recurring rules visible to the current user.

Private recurring rules must only be visible to the owner.

### `POST /recurring-rules`

Creates a recurring rule.

Examples:

Weekly:

```json
{
  "frequency": "weekly",
  "detail": {
    "weekday": 2
  }
}
```

Monthly:

```json
{
  "frequency": "monthly",
  "detail": {
    "dayOfMonth": 5
  }
}
```

Custom:

```json
{
  "frequency": "custom",
  "detail": {
    "interval": 2,
    "unit": "week"
  }
}
```

### `PATCH /recurring-rules/{id}`

Updates a recurring rule.

Must support changing:

- Amount
- Category
- Tags
- Account type
- Frequency
- Weekly weekday
- Monthly day
- Custom interval

### `DELETE /recurring-rules/{id}`

Disables a recurring rule.

Prefer soft delete or `isActive=false`.

### `GET /recurring-rules/due`

Returns due recurring items that need confirmation.

Used by the home confirmation cards.

### `POST /recurring-rules/{id}/confirm`

Creates the transaction for the current due period.

### `POST /recurring-rules/{id}/skip`

Skips the current due period.

## Tags / Projects

Tags power cross-month projects.

### `GET /tags`

Lists tags visible to the current user.

### `POST /tags`

Creates a tag.

### `GET /projects`

Returns project-like tag summaries.

Response:

```json
[
  {
    "id": "project_123",
    "tag": "#2026日本旅遊",
    "title": "2026 日本旅遊",
    "budget": 120000,
    "spent": 46800,
    "transactionCount": 9,
    "status": "active",
    "isFixed": false
  }
]
```

### `GET /projects/{id}`

Returns project detail.

Should include:

- Budget
- Spent amount
- Transaction count
- Monthly bar chart data
- Status
- Related transactions

### `PATCH /projects/{id}`

Updates project metadata.

Editable fields:

- Title
- Budget
- Status: `active`, `closed`
- Fixed project flag

### `GET /projects/{id}/transactions`

Returns transactions under the project's tag.

Private transactions must only be included for the current user.

## Budgets

### Budget Object

```json
{
  "id": "budget_2026_07",
  "familyId": "fam_123",
  "month": "2026-07",
  "totalLimit": 50000,
  "currency": "TWD",
  "categoryLimits": {
    "food": 12000,
    "clothing": 5000,
    "housing": 32000,
    "transport": 4000,
    "education": 20000,
    "entertainment": 8000,
    "medical": 5000,
    "other": 6000
  }
}
```

### `GET /budgets/current`

Returns the current month's budget.

### `PUT /budgets/current`

Creates or updates the current month's budget.

### `GET /budgets/current/progress`

Returns spending progress.

Response:

```json
{
  "month": "2026-07",
  "totalLimit": 50000,
  "totalSpent": 49120,
  "dateProgressRatio": 0.62,
  "categories": [
    {
      "category": "food",
      "limit": 12000,
      "spent": 13240,
      "status": "over"
    }
  ]
}
```

### `GET /budgets/history`

Returns previous monthly budgets and spending.

## Reports

### `GET /reports/category-breakdown`

Returns category percentages for donut chart.

### `GET /reports/member-split`

Returns shared ledger split by recorder/member.

Should not include private ledger data.

### `GET /reports/monthly-trend`

Returns recent monthly spending trend.

Query params:

| Param | Purpose |
|---|---|
| `months` | Number of months, default 6 |
| `accountScope` | `shared`, `private`, or `overview` |

### `GET /reports/cashflow`

Optional future API for income/expense/cashflow reporting.

## Offline Sync

The app may keep local changes before pushing them.

Sync should be used for confirmed data changes, not for AI parsing itself.

Examples of syncable changes:

- Manual transaction created offline
- Transaction edited locally
- Transaction deleted locally
- AI transaction created after API parsing succeeds
- Recurring rule created or edited locally

Examples that require direct API access:

- Voice transcription
- AI voice parsing
- Receipt OCR
- AI receipt parsing

### `GET /sync/state`

Returns the current server revision/cursor.

Response:

```json
{
  "cursor": "rev_42",
  "serverRevision": 42
}
```

### `GET /sync/changes?since=cursor`

Pulls remote changes after a cursor.

Must include deletes, using tombstones or `deletedAt`.

### `POST /sync/push`

Pushes local mutations.

Request:

```json
{
  "baseCursor": "rev_42",
  "mutations": [
    {
      "clientMutationId": "local_001",
      "operation": "create",
      "resource": "transaction",
      "payload": {
        "title": "早餐",
        "amount": 95,
        "accountType": "shared",
        "category": "food"
      }
    },
    {
      "clientMutationId": "local_002",
      "operation": "update",
      "resource": "transaction",
      "resourceId": "txn_123",
      "payload": {
        "amount": 12000
      }
    }
  ]
}
```

Response:

```json
{
  "accepted": [
    {
      "clientMutationId": "local_001",
      "serverId": "txn_456",
      "serverRevision": 43
    }
  ],
  "conflicts": [],
  "cursor": "rev_43"
}
```

### `POST /sync/resolve-conflict`

Resolves a sync conflict.

Conflict policy can start simple:

- Last write wins for low-risk fields.
- Server rejects updates if `serverRevision` is stale.
- Client asks user when amount, account type, or delete conflicts.

## Permissions Summary

| Resource | Shared Visibility | Private Visibility |
|---|---|---|
| Transaction | Family members | Owner only |
| Recurring rule | Family members | Owner only |
| Project/tag summary | Family members, plus own private data where relevant | Owner only |
| Budget | Family members | Not applicable unless private budgets are added |
| Report | Shared data for family | Own private data only |
| Sync changes | Shared changes plus own private changes | Owner only |

## Recommended Backend Build Order

1. Auth and current user
2. Family and members
3. Transactions CRUD
4. Private ledger permission enforcement
5. Transaction summary
6. AI voice parse mock endpoint
7. AI receipt parse mock endpoint
8. Recurring rules CRUD
9. Due recurring confirmation and skip
10. Tags and project summaries
11. Budgets
12. Reports
13. Offline sync push/pull

## Initial Mock API Strategy

Before implementing the real backend, each endpoint can return deterministic mock data.

Suggested behavior:

- `POST /transactions` returns the input payload plus a generated server id.
- `PATCH /transactions/{id}` returns the updated object.
- `DELETE /transactions/{id}` returns `{ "deleted": true }`.
- `POST /ai/parse-voice` always returns a drink transaction for the current prototype phrase.
- `POST /ai/parse-receipt` always returns a grocery receipt transaction.
- `POST /sync/push` accepts all mutations and returns a new cursor.

