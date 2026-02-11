# Plain API Entities Reference

This document describes the main entities in the Plain customer support platform API.

## Customer

A customer is a person who contacts support. Customers can be identified by ID, email, or external ID.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique customer identifier (e.g., `c_01ABC...`) |
| `fullName` | String | Customer's full name |
| `shortName` | String | Customer's short/display name |
| `email.email` | String | Customer's email address |
| `email.isVerified` | Boolean | Whether email is verified |
| `externalId` | String | Your system's identifier for this customer |
| `status` | Enum | `ACTIVE`, `INACTIVE`, `SPAM`, `DELETED`, `UNVERIFIED` |
| `company` | Company | Associated company (if any) |
| `createdAt` | DateTime | When customer was created |
| `updatedAt` | DateTime | When customer was last updated |

### Customer Identifiers

You can look up customers by:
- **ID**: `customer get c_01ABC...`
- **Email**: `customer get-by-email user@example.com`
- **External ID**: `customer get-by-external-id your-system-id`

---

## Thread

A thread represents a support conversation with a customer. Threads have a status, priority, and can be assigned to users.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique thread identifier (e.g., `th_01ABC...`) |
| `title` | String | Thread title/subject |
| `description` | String | Thread description |
| `previewText` | String | Preview of thread content |
| `status` | Enum | `TODO`, `SNOOZED`, `DONE` |
| `priority` | Int | 0 (urgent) to 3 (low) |
| `externalId` | String | Your system's identifier for this thread |
| `channel` | Enum | Source channel (see below) |
| `customer` | Customer | Associated customer |
| `assignedTo` | User/MachineUser | Assigned agent (if any) |
| `labels` | [Label] | Applied labels |
| `createdAt` | DateTime | When thread was created |
| `updatedAt` | DateTime | When thread was last updated |

### Thread Status

| Status | Description |
|--------|-------------|
| `TODO` | Active thread requiring attention |
| `SNOOZED` | Temporarily hidden until a specified time |
| `DONE` | Completed/resolved thread |

### Thread Priority

| Priority | Level | Description |
|----------|-------|-------------|
| 0 | Urgent | Requires immediate attention |
| 1 | High | Important, handle soon |
| 2 | Normal | Standard priority (default) |
| 3 | Low | Can wait |

### Thread Channel

The channel indicates how the thread was created:

| Channel | Description |
|---------|-------------|
| `EMAIL` | Created from email |
| `SLACK` | Created from Slack message |
| `CHAT` | Created from live chat |
| `API` | Created via API |
| `MS_TEAMS` | Created from Microsoft Teams |
| `DISCORD` | Created from Discord |
| `IMPORT` | Imported from another system |

---

## Timeline Entry

A timeline entry represents a single item in a thread's conversation history. Use `thread timeline <threadId>` to fetch entries.

### TimelineEntry Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique timeline entry identifier |
| `customerId` | ID | Associated customer ID |
| `threadId` | ID | Associated thread ID |
| `timestamp` | DateTime | When the entry occurred |
| `actor` | Actor | Who performed the action |
| `entry` | Entry | The entry content (see types below) |

### Entry Types (24 total)

The `entry` field contains one of the following types, identified by `__typename`:

#### Message Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `EmailEntry` | Email message | `subject`, `textContent`, `markdownContent`, `from`, `to`, `sentAt`, `attachments` |
| `ChatEntry` | Live chat message | `chatText`, `customerReadAt`, `attachments` |
| `SlackMessageEntry` | Slack message | `text`, `slackMessageLink`, `reactions`, `attachments` |
| `SlackReplyEntry` | Slack reply | `text`, `slackMessageLink`, `reactions`, `attachments` |
| `MSTeamsMessageEntry` | MS Teams message | `text`, `markdownContent`, `msTeamsMessageLink`, `attachments` |
| `DiscordMessageEntry` | Discord message | `markdownContent`, `discordMessageLink`, `attachments` |
| `NoteEntry` | Internal note | `text`, `markdown`, `attachments` |

#### Event Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `CustomEntry` | Custom timeline entry | `title`, `type`, `components`, `externalId` |
| `ThreadEventEntry` | Thread event (API-created) | `title`, `components`, `timelineEventId` |
| `CustomerEventEntry` | Customer event (API-created) | `title`, `components`, `timelineEventId` |

#### Status/Change Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `ThreadStatusTransitionedEntry` | Status change | `nextStatus`, `nextStatusDetail` |
| `ThreadPriorityChangedEntry` | Priority change | `previousPriority`, `nextPriority` |
| `ThreadAssignmentTransitionedEntry` | Assignment change | `previousAssignee`, `nextAssignee` |
| `ThreadAdditionalAssigneesTransitionedEntry` | Additional assignees change | `previousAssignees`, `nextAssignees` |
| `ThreadLabelsChangedEntry` | Labels change | `previousLabels`, `nextLabels` |
| `ServiceLevelAgreementStatusTransitionedEntry` | SLA status change | `previousSlaStatus`, `nextSlaStatus`, `serviceLevelAgreement` |

#### Thread Link Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `ThreadLinkCreatedEntry` | Link created | `threadLink` (with `title`, `url`, `status`) |
| `ThreadLinkUpdatedEntry` | Link updated | `threadLink`, `previousThreadLink` |
| `ThreadLinkDeletedEntry` | Link deleted | `threadLink` |
| `LinearIssueThreadLinkStateTransitionedEntry` | Linear issue state change | `linearIssueId`, `previousLinearStateId`, `nextLinearStateId` |

#### Discussion Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `ThreadDiscussionEntry` | Discussion started | `discussionType`, `slackChannelName`, `emailRecipients` |
| `ThreadDiscussionResolvedEntry` | Discussion resolved | `discussionType`, `resolvedAt` |

#### Specialized Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `HelpCenterAiConversationMessageEntry` | Help center AI message | `messageMarkdown`, `helpCenterId` |
| `CustomerSurveyRequestedEntry` | Survey requested | `customerSurveyId`, `surveyResponseId` |

### Actor Types

The `actor` field identifies who performed the action:

| Type | Description | Key Fields |
|------|-------------|------------|
| `UserActor` | Human user | `userId` |
| `MachineUserActor` | Machine/API user | `machineUserId`, `machineUser` |
| `CustomerActor` | Customer | `customerId`, `customer` |
| `SystemActor` | System | `systemId` |
| `DeletedCustomerActor` | Deleted customer | `customerId` |

### Example: Extracting Messages

```bash
# Get timeline
scripts/plain-api.sh thread timeline th_01ABC... --first 50 | jq '
  .data.thread.timelineEntries.edges[].node |
  select(.entry.__typename | test("Email|Chat|Slack|Teams|Discord|Note")) |
  {
    type: .entry.__typename,
    timestamp: .timestamp.iso8601,
    content: (.entry.textContent // .entry.text // .entry.chatText // .entry.markdownContent // .entry.markdown)
  }
'
```

---

## Company

A company represents an organization that customers belong to.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique company identifier (e.g., `co_01ABC...`) |
| `name` | String | Company name |
| `domainName` | String | Company domain (e.g., `example.com`) |
| `createdAt` | DateTime | When company was created |
| `updatedAt` | DateTime | When company was last updated |

---

## Tenant

A tenant represents a multi-tenant grouping for customers. Useful for B2B SaaS where customers belong to specific tenant organizations.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique tenant identifier (e.g., `ten_01ABC...`) |
| `name` | String | Tenant name |
| `externalId` | String | Your system's identifier for this tenant |
| `source` | Enum | `API`, `SALESFORCE`, `HUBSPOT` |
| `createdAt` | DateTime | When tenant was created |
| `updatedAt` | DateTime | When tenant was last updated |

---

## Label / LabelType

Labels are used to categorize and organize threads. LabelTypes define the available labels.

### LabelType Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique label type identifier (e.g., `lt_01ABC...`) |
| `name` | String | Label name |
| `isArchived` | Boolean | Whether the label is archived |

### Label Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique label identifier |
| `labelType` | LabelType | The label type definition |

---

## Help Center

Help centers contain knowledge base articles organized into groups.

### HelpCenter Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique help center identifier (e.g., `hc_01ABC...`) |
| `publicName` | String | Public-facing name |
| `internalName` | String | Internal name |
| `description` | String | Help center description |
| `type` | Enum | `SELF_SERVICE`, `PRIVATE`, `PORTAL` |
| `articles` | Connection | All articles in this help center |
| `articleGroups` | Connection | All article groups |

### HelpCenterArticle Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique article identifier (e.g., `hca_01ABC...`) |
| `title` | String | Article title |
| `description` | String | Article description/summary |
| `contentHtml` | String | Article content in HTML |
| `slug` | String | URL-friendly slug |
| `status` | Enum | `DRAFT`, `PUBLISHED` |
| `articleGroup` | Group | Parent group (if any) |
| `createdAt` | DateTime | When article was created |
| `updatedAt` | DateTime | When article was last updated |

### HelpCenterArticleGroup Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique group identifier (e.g., `hcag_01ABC...`) |
| `name` | String | Group name |
| `slug` | String | URL-friendly slug |
| `parentArticleGroup` | Group | Parent group for hierarchy |
| `articles` | Connection | Articles in this group |
| `childArticleGroups` | Connection | Child groups |

---

## Tier

Tiers define service levels for customers/tenants, including SLA configurations.

### Tier Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique tier identifier (e.g., `tier_01ABC...`) |
| `name` | String | Tier name |
| `externalId` | String | Your system's identifier for this tier |
| `color` | String | Hex color code (e.g., `#3B82F6`) |
| `isDefault` | Boolean | Whether this is the default tier |
| `defaultThreadPriority` | Int | Default priority for threads in this tier |
| `serviceLevelAgreements` | [SLA] | SLA configurations |
| `memberships` | Connection | Companies/tenants in this tier |

### ServiceLevelAgreement Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | ID | Unique SLA identifier |
| `firstResponseTimeMinutes` | Int | First response SLA (for FirstResponseTime SLA) |
| `nextResponseTimeMinutes` | Int | Next response SLA (for NextResponseTime SLA) |
| `useBusinessHoursOnly` | Boolean | Whether SLA tracks only during business hours |
| `threadPriorityFilter` | [Int] | Which thread priorities this SLA applies to |

---

## DateTime Format

All datetime fields return an object with:

```json
{
  "iso8601": "2024-01-15T10:30:00.000Z"
}
```

When providing datetime values (e.g., for snooze), use ISO 8601 format.
