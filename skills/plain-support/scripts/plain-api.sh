#!/bin/bash
# Plain API CLI - Interact with Plain customer support platform
# Requires: PLAIN_API_KEY environment variable, curl, jq

set -euo pipefail

API_URL="${PLAIN_API_URL:-https://core-api.uk.plain.com/graphql/v1}"

# Check required dependencies
check_deps() {
    command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
    [ -n "${PLAIN_API_KEY:-}" ] || { echo "Error: PLAIN_API_KEY environment variable is required" >&2; exit 1; }
}

# Execute GraphQL query
gql() {
    local query="$1"
    local empty_json='{}'
    local variables="${2:-$empty_json}"

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

# ============================================================================
# CUSTOMERS (READ ONLY)
# ============================================================================

customer_get() {
    local id="$1"
    gql 'query($id: ID!) { customer(customerId: $id) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

customer_get_by_email() {
    local email="$1"
    gql 'query($email: String!) { customerByEmail(email: $email) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"email\": \"$email\"}"
}

customer_get_by_external_id() {
    local external_id="$1"
    gql 'query($externalId: ID!) { customerByExternalId(externalId: $externalId) { id fullName shortName email { email isVerified } externalId status company { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"externalId\": \"$external_id\"}"
}

customer_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { customers(first: \$first) { edges { node { id fullName email { email } externalId status company { id name } } } pageInfo { hasNextPage endCursor } totalCount } }" \
        "{\"first\": $first}"
}

customer_search() {
    local query="$1"
    shift || true
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($term: String!, $first: Int!) { searchCustomers(searchQuery: {or: [{fullName: {caseInsensitiveContains: $term}}, {email: {caseInsensitiveContains: $term}}]}, first: $first) { edges { node { id fullName email { email } externalId status company { id name } } } } }' \
        "{\"term\": \"$query\", \"first\": $first}"
}

# ============================================================================
# THREADS (READ + WRITE)
# ============================================================================

thread_note() {
    local thread_id=""
    local text=""
    local markdown=""
    local text_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --text) text="$2"; shift 2 ;;
            --markdown) markdown="$2"; shift 2 ;;
            --text-file) text_file="$2"; shift 2 ;;
            '') shift ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    # Read text from file if specified
    if [[ -n "$text_file" ]]; then
        if [[ ! -f "$text_file" ]]; then
            echo "Error: Text file not found: $text_file" >&2
            exit 1
        fi
        text=$(cat "$text_file")
    fi

    if [[ -z "$thread_id" ]] || [[ -z "$text" ]]; then
        echo "Error: thread_id and --text (or --text-file) are required" >&2
        echo "Usage: plain-api.sh thread note <thread_id> --text \"Note text\"" >&2
        exit 1
    fi

    # First, get the thread to find the customer ID
    local thread_result
    thread_result=$(gql 'query($id: ID!) { thread(threadId: $id) { id customer { id } } }' "{\"id\": \"$thread_id\"}")

    local customer_id
    customer_id=$(echo "$thread_result" | jq -r '.data.thread.customer.id // empty')

    if [[ -z "$customer_id" ]]; then
        echo "Error: Could not find thread or customer for thread $thread_id" >&2
        echo "$thread_result" | jq . >&2
        exit 1
    fi

    # Build input JSON using jq for proper escaping
    local input
    input=$(jq -n \
        --arg customerId "$customer_id" \
        --arg threadId "$thread_id" \
        --arg text "$text" \
        '{customerId: $customerId, threadId: $threadId, text: $text}')

    # Add optional markdown field
    if [[ -n "$markdown" ]]; then
        input=$(echo "$input" | jq --arg md "$markdown" '. + {markdown: $md}')
    fi

    local query='mutation CreateNote($input: CreateNoteInput!) { createNote(input: $input) { note { id text } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

thread_get() {
    local id="$1"
    gql 'query($id: ID!) { thread(threadId: $id) { id title description previewText status priority externalId channel customer { id fullName email { email } } assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } labels { id labelType { id name } } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

thread_list() {
    local first=10
    local status_filter=""
    local priority_filter=""
    local customer_filter=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            --status)
                if [[ "$2" != "all" ]]; then
                    status_filter="$2"
                fi
                shift 2 ;;
            --priority) priority_filter="$2"; shift 2 ;;
            --customer) customer_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local filter_parts=()
    if [[ -n "$status_filter" ]]; then
        filter_parts+=("\"statuses\": [\"$status_filter\"]")
    fi
    if [[ -n "$priority_filter" ]]; then
        filter_parts+=("\"priorities\": [$priority_filter]")
    fi
    if [[ -n "$customer_filter" ]]; then
        filter_parts+=("\"customerIds\": [\"$customer_filter\"]")
    fi

    local filter="{}"
    if [[ ${#filter_parts[@]} -gt 0 ]]; then
        filter="{$(IFS=,; echo "${filter_parts[*]}")}"
    fi

    gql "query(\$first: Int!, \$filters: ThreadsFilter) { threads(first: \$first, filters: \$filters) { edges { node { id title status priority customer { id fullName } assignedTo { ... on User { id fullName } ... on MachineUser { id fullName } } createdAt { iso8601 } } } pageInfo { hasNextPage endCursor } totalCount } }" \
        "{\"first\": $first, \"filters\": $filter}"
}

thread_search() {
    local query="$1"
    shift || true
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($term: String!, $first: Int!) { searchThreads(searchQuery: {term: $term}, first: $first) { edges { node { thread { id title status priority customer { id fullName } assignedTo { ... on User { id fullName } } createdAt { iso8601 } } } } } }' \
        "{\"term\": \"$query\", \"first\": $first}"
}

thread_timeline() {
    local thread_id=""
    local first=20
    local after=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            --after) after="$2"; shift 2 ;;
            *) thread_id="$1"; shift ;;
        esac
    done

    if [[ -z "$thread_id" ]]; then
        echo "Error: thread_id is required" >&2
        exit 1
    fi

    local after_param=""
    if [[ -n "$after" ]]; then
        after_param=", \"after\": \"$after\""
    fi

    # Build comprehensive timeline query with all 24 entry types
    local query='query($threadId: ID!, $first: Int!, $after: String) {
      thread(threadId: $threadId) {
        timelineEntries(first: $first, after: $after) {
          edges {
            cursor
            node {
              id
              customerId
              threadId
              timestamp { iso8601 }
              actor {
                __typename
                ... on UserActor { userId }
                ... on SystemActor { systemId }
                ... on MachineUserActor { machineUserId machineUser { id fullName } }
                ... on CustomerActor { customerId customer { id fullName email { email } } }
                ... on DeletedCustomerActor { customerId }
              }
              entry {
                __typename
                ... on NoteEntry {
                  noteId
                  text
                  markdown
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on ChatEntry {
                  chatId
                  chatText: text
                  customerReadAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on EmailEntry {
                  emailId
                  subject
                  textContent
                  hasMoreTextContent
                  markdownContent
                  hasMoreMarkdownContent
                  from { name email }
                  to { name email }
                  additionalRecipients { name email }
                  hiddenRecipients { name email }
                  authenticity
                  isStartOfThread
                  sentAt { iso8601 }
                  receivedAt { iso8601 }
                  sendStatus
                  category
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on CustomEntry {
                  externalId
                  title
                  type
                  components {
                    __typename
                    ... on ComponentText { text textColor textSize }
                    ... on ComponentPlainText { plainText plainTextColor plainTextSize }
                    ... on ComponentLinkButton { linkButtonLabel linkButtonUrl }
                    ... on ComponentBadge { badgeLabel badgeColor }
                    ... on ComponentDivider { dividerSpacingSize }
                    ... on ComponentSpacer { spacerSize }
                    ... on ComponentCopyButton { copyButtonValue copyButtonTooltipLabel }
                  }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on ThreadAssignmentTransitionedEntry {
                  previousAssignee {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                  nextAssignee {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                }
                ... on ThreadAdditionalAssigneesTransitionedEntry {
                  previousAssignees {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                  nextAssignees {
                    __typename
                    ... on User { id fullName }
                    ... on MachineUser { id fullName }
                    ... on System { id }
                  }
                }
                ... on ThreadStatusTransitionedEntry {
                  nextStatus
                  nextStatusDetail {
                    __typename
                    ... on ThreadStatusDetailCreated { createdAt { iso8601 } }
                    ... on ThreadStatusDetailSnoozed { snoozedAt { iso8601 } snoozedUntil { iso8601 } }
                    ... on ThreadStatusDetailUnsnoozed { snoozedAt { iso8601 } }
                    ... on ThreadStatusDetailNewReply { newReplyAt { iso8601 } }
                    ... on ThreadStatusDetailReplied { repliedAt { iso8601 } }
                    ... on ThreadStatusDetailWaitingForCustomer { statusChangedAt { iso8601 } }
                    ... on ThreadStatusDetailWaitingForDuration { statusChangedAt { iso8601 } waitingUntil { iso8601 } }
                    ... on ThreadStatusDetailInProgress { statusChangedAt { iso8601 } }
                    ... on ThreadStatusDetailThreadDiscussionResolved { threadDiscussionId statusChangedAt { iso8601 } }
                    ... on ThreadStatusDetailThreadLinkUpdated { updatedAt { iso8601 } threadLinkLinearIssueId: linearIssueId }
                    ... on ThreadStatusDetailLinearUpdated { updatedAt { iso8601 } deprecatedLinearIssueId: linearIssueId }
                  }
                }
                ... on ThreadPriorityChangedEntry {
                  previousPriority
                  nextPriority
                }
                ... on ThreadLabelsChangedEntry {
                  previousLabels { id labelType { id name } }
                  nextLabels { id labelType { id name } }
                }
                ... on ThreadEventEntry {
                  timelineEventId
                  title
                  customerId
                  externalId
                  components {
                    __typename
                    ... on ComponentText { text textColor textSize }
                    ... on ComponentPlainText { plainText plainTextColor plainTextSize }
                    ... on ComponentLinkButton { linkButtonLabel linkButtonUrl }
                    ... on ComponentBadge { badgeLabel badgeColor }
                    ... on ComponentDivider { dividerSpacingSize }
                    ... on ComponentSpacer { spacerSize }
                    ... on ComponentCopyButton { copyButtonValue copyButtonTooltipLabel }
                  }
                }
                ... on CustomerEventEntry {
                  timelineEventId
                  title
                  customerId
                  externalId
                  components {
                    __typename
                    ... on ComponentText { text textColor textSize }
                    ... on ComponentPlainText { plainText plainTextColor plainTextSize }
                    ... on ComponentLinkButton { linkButtonLabel linkButtonUrl }
                    ... on ComponentBadge { badgeLabel badgeColor }
                    ... on ComponentDivider { dividerSpacingSize }
                    ... on ComponentSpacer { spacerSize }
                    ... on ComponentCopyButton { copyButtonValue copyButtonTooltipLabel }
                  }
                }
                ... on SlackMessageEntry {
                  slackMessageLink
                  slackWebMessageLink
                  text
                  lastEditedOnSlackAt { iso8601 }
                  deletedOnSlackAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                  reactions { name imageUrl }
                }
                ... on SlackReplyEntry {
                  slackMessageLink
                  slackWebMessageLink
                  text
                  lastEditedOnSlackAt { iso8601 }
                  deletedOnSlackAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                  reactions { name imageUrl }
                }
                ... on ServiceLevelAgreementStatusTransitionedEntry {
                  previousSlaStatus: previousStatus
                  nextSlaStatus: nextStatus
                  serviceLevelAgreement {
                    __typename
                    id
                    useBusinessHoursOnly
                    threadPriorityFilter
                    ... on FirstResponseTimeServiceLevelAgreement { firstResponseTimeMinutes }
                    ... on NextResponseTimeServiceLevelAgreement { nextResponseTimeMinutes }
                  }
                }
                ... on ThreadDiscussionEntry {
                  threadDiscussionId
                  discussionType
                  slackChannelName
                  slackMessageLink
                  emailRecipients
                  customerId
                }
                ... on ThreadDiscussionResolvedEntry {
                  threadDiscussionId
                  discussionType
                  slackChannelName
                  slackMessageLink
                  emailRecipients
                  customerId
                  resolvedAt { iso8601 }
                }
                ... on MSTeamsMessageEntry {
                  msTeamsMessageId
                  msTeamsMessageLink
                  text
                  markdownContent
                  customerId
                  lastEditedOnMsTeamsAt { iso8601 }
                  deletedOnMsTeamsAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on DiscordMessageEntry {
                  discordMessageId
                  discordMessageLink
                  markdownContent
                  customerId
                  lastEditedOnDiscordAt { iso8601 }
                  deletedOnDiscordAt { iso8601 }
                  attachments { id fileName fileExtension fileSize { kiloBytes } }
                }
                ... on LinearIssueThreadLinkStateTransitionedEntry {
                  linearIssueId
                  previousLinearStateId
                  nextLinearStateId
                }
                ... on ThreadLinkCreatedEntry {
                  threadLink {
                    id
                    title
                    url
                    description
                    status
                    createdAt { iso8601 }
                    ... on LinearIssueThreadLink { linearIssueId linearIssueIdentifier }
                    ... on JiraIssueThreadLink { jiraIssueId jiraIssueKey }
                    ... on PlainThreadThreadLink { plainThreadId }
                    ... on PlainTaskThreadLink { plainTaskId }
                    ... on GenericThreadLink { sourceType sourceId }
                  }
                }
                ... on ThreadLinkUpdatedEntry {
                  threadLink {
                    id
                    title
                    url
                    description
                    status
                    ... on LinearIssueThreadLink { linearIssueId linearIssueIdentifier }
                    ... on JiraIssueThreadLink { jiraIssueId jiraIssueKey }
                    ... on PlainThreadThreadLink { plainThreadId }
                    ... on PlainTaskThreadLink { plainTaskId }
                    ... on GenericThreadLink { sourceType sourceId }
                  }
                  previousThreadLink {
                    id
                    title
                    url
                    status
                  }
                }
                ... on ThreadLinkDeletedEntry {
                  threadLink {
                    id
                    title
                    url
                    status
                    ... on LinearIssueThreadLink { linearIssueId linearIssueIdentifier }
                    ... on JiraIssueThreadLink { jiraIssueId jiraIssueKey }
                    ... on PlainThreadThreadLink { plainThreadId }
                    ... on PlainTaskThreadLink { plainTaskId }
                    ... on GenericThreadLink { sourceType sourceId }
                  }
                }
                ... on HelpCenterAiConversationMessageEntry {
                  messageId
                  helpCenterId
                  messageMarkdown: markdown
                }
                ... on CustomerSurveyRequestedEntry {
                  customerId
                  customerSurveyId
                  surveyResponseId
                  surveyResponsePublicId
                }
              }
            }
          }
          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    }'

    gql "$query" "{\"threadId\": \"$thread_id\", \"first\": $first$after_param}"
}

# ============================================================================
# COMPANIES (READ ONLY)
# ============================================================================

company_get() {
    local id="$1"
    gql 'query($id: ID!) { company(companyId: $id) { id name domainName createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

company_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { companies(first: \$first) { edges { node { id name domainName } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

# ============================================================================
# TENANTS (READ ONLY)
# ============================================================================

tenant_get() {
    local id="$1"
    gql 'query($id: ID!) { tenant(tenantId: $id) { id name externalId createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

tenant_list() {
    local first=10
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { tenants(first: \$first) { edges { node { id name externalId } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

# ============================================================================
# LABELS (READ ONLY)
# ============================================================================

label_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { labelTypes(first: \$first) { edges { node { id name isArchived } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

# ============================================================================
# HELP CENTER (READ ONLY)
# ============================================================================

helpcenter_list() {
    gql '{ helpCenters(first: 50) { edges { node { id publicName internalName description type } } } }' '{}'
}

helpcenter_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenter(id: $id) { id publicName internalName description type articleGroups(first: 50) { edges { node { id name slug } } } articles(first: 50) { edges { node { id title slug status } } } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_articles() {
    local help_center_id="$1"
    shift || true
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql 'query($id: ID!, $first: Int!) { helpCenter(id: $id) { articles(first: $first) { edges { node { id title slug status description contentHtml articleGroup { id name } } } pageInfo { hasNextPage endCursor } } } }' \
        "{\"id\": \"$help_center_id\", \"first\": $first}"
}

helpcenter_article_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenterArticle(id: $id) { id title description contentHtml slug status articleGroup { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_article_get_by_slug() {
    local help_center_id="$1"
    local slug="$2"
    gql 'query($helpCenterId: ID!, $slug: String!) { helpCenterArticleBySlug(helpCenterId: $helpCenterId, slug: $slug) { id title description contentHtml slug status articleGroup { id name } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"helpCenterId\": \"$help_center_id\", \"slug\": \"$slug\"}"
}

helpcenter_article_upsert() {
    local help_center_id=""
    local article_id=""
    local title=""
    local description=""
    local content=""
    local content_file=""
    local group_id=""
    local status="DRAFT"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --id) article_id="$2"; shift 2 ;;
            --title) title="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --content) content="$2"; shift 2 ;;
            --content-file) content_file="$2"; shift 2 ;;
            --group) group_id="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            '') shift ;;  # Skip empty arguments
            *) help_center_id="$1"; shift ;;
        esac
    done

    # Read content from file if specified
    if [[ -n "$content_file" ]]; then
        if [[ ! -f "$content_file" ]]; then
            echo "Error: Content file not found: $content_file" >&2
            exit 1
        fi
        content=$(cat "$content_file")
    fi

    if [[ -z "$help_center_id" ]] || [[ -z "$title" ]] || [[ -z "$description" ]] || [[ -z "$content" ]]; then
        echo "Error: help_center_id, --title, --description, and --content (or --content-file) are required" >&2
        exit 1
    fi

    # Validate status
    if [[ "$status" != "DRAFT" ]] && [[ "$status" != "PUBLISHED" ]]; then
        echo "Error: --status must be DRAFT or PUBLISHED" >&2
        exit 1
    fi

    # Get workspace ID for constructing the link
    local workspace_result
    workspace_result=$(gql '{ myWorkspace { id } }' '{}')
    local workspace_id
    workspace_id=$(echo "$workspace_result" | jq -r '.data.myWorkspace.id')

    # Build input JSON using jq for proper escaping
    local input
    input=$(jq -n \
        --arg helpCenterId "$help_center_id" \
        --arg title "$title" \
        --arg description "$description" \
        --arg contentHtml "$content" \
        --arg status "$status" \
        '{helpCenterId: $helpCenterId, title: $title, description: $description, contentHtml: $contentHtml, status: $status}')

    # Add optional fields
    if [[ -n "$article_id" ]]; then
        input=$(echo "$input" | jq --arg id "$article_id" '. + {helpCenterArticleId: $id}')
    fi
    if [[ -n "$group_id" ]]; then
        input=$(echo "$input" | jq --arg id "$group_id" '. + {helpCenterArticleGroupId: $id}')
    fi

    local query='mutation($input: UpsertHelpCenterArticleInput!) { upsertHelpCenterArticle(input: $input) { helpCenterArticle { id title slug status } error { message code fields { field message type } } } }'
    local variables
    variables=$(jq -n --argjson input "$input" '{input: $input}')

    local result
    result=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')")

    # Extract article ID and construct link
    local new_article_id
    new_article_id=$(echo "$result" | jq -r '.data.upsertHelpCenterArticle.helpCenterArticle.id // empty')

    if [[ -n "$new_article_id" ]]; then
        local link="https://app.plain.com/workspace/${workspace_id}/help-center/${help_center_id}/articles/${new_article_id}/"
        echo "$result" | jq --arg link "$link" '.link = $link'
    else
        echo "$result"
    fi
}

helpcenter_group_get() {
    local id="$1"
    gql 'query($id: ID!) { helpCenterArticleGroup(id: $id) { id name slug parentArticleGroup { id name } articles(first: 50) { edges { node { id title slug status } } } childArticleGroups(first: 50) { edges { node { id name slug } } } } }' \
        "{\"id\": \"$id\"}"
}

helpcenter_group_create() {
    local help_center_id=""
    local name=""
    local parent_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            --parent) parent_id="$2"; shift 2 ;;
            *) help_center_id="$1"; shift ;;
        esac
    done

    if [[ -z "$help_center_id" ]] || [[ -z "$name" ]]; then
        echo "Error: help_center_id and --name are required" >&2
        exit 1
    fi

    local input="{\"helpCenterId\": \"$help_center_id\", \"name\": \"$name\""
    [[ -n "$parent_id" ]] && input="$input, \"parentHelpCenterArticleGroupId\": \"$parent_id\""
    input="$input}"

    gql 'mutation($input: CreateHelpCenterArticleGroupInput!) { createHelpCenterArticleGroup(input: $input) { helpCenterArticleGroup { id name slug } error { message code } } }' \
        "{\"input\": $input}"
}

helpcenter_group_update() {
    local group_id=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name) name="$2"; shift 2 ;;
            *) group_id="$1"; shift ;;
        esac
    done

    if [[ -z "$group_id" ]] || [[ -z "$name" ]]; then
        echo "Error: group_id and --name are required" >&2
        exit 1
    fi

    gql 'mutation($input: UpdateHelpCenterArticleGroupInput!) { updateHelpCenterArticleGroup(input: $input) { helpCenterArticleGroup { id name slug } error { message code } } }' \
        "{\"input\": {\"helpCenterArticleGroupId\": \"$group_id\", \"name\": \"$name\"}}"
}

helpcenter_group_delete() {
    local id="$1"
    gql 'mutation($input: DeleteHelpCenterArticleGroupInput!) { deleteHelpCenterArticleGroup(input: $input) { error { message code } } }' \
        "{\"input\": {\"helpCenterArticleGroupId\": \"$id\"}}"
}

# ============================================================================
# TIERS & SLAs (READ ONLY)
# ============================================================================

tier_list() {
    local first=20
    while [[ $# -gt 0 ]]; do
        case $1 in
            --first) first="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    gql "query(\$first: Int!) { tiers(first: \$first) { edges { node { id name externalId color isDefault defaultThreadPriority serviceLevelAgreements { ... on FirstResponseTimeServiceLevelAgreement { id firstResponseTimeMinutes useBusinessHoursOnly } ... on NextResponseTimeServiceLevelAgreement { id nextResponseTimeMinutes useBusinessHoursOnly } } } } pageInfo { hasNextPage endCursor } } }" \
        "{\"first\": $first}"
}

tier_get() {
    local id="$1"
    gql 'query($id: ID!) { tier(tierId: $id) { id name externalId color isDefault defaultThreadPriority serviceLevelAgreements { ... on FirstResponseTimeServiceLevelAgreement { id firstResponseTimeMinutes useBusinessHoursOnly threadPriorityFilter } ... on NextResponseTimeServiceLevelAgreement { id nextResponseTimeMinutes useBusinessHoursOnly threadPriorityFilter } } memberships(first: 50) { edges { node { ... on TenantTierMembership { id tenantId } ... on CompanyTierMembership { id companyId } } } totalCount } createdAt { iso8601 } updatedAt { iso8601 } } }' \
        "{\"id\": \"$id\"}"
}

# ============================================================================
# WORKSPACE (READ ONLY)
# ============================================================================

workspace_get() {
    gql '{ myWorkspace { id name publicName } }' '{}'
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat << 'EOF'
Plain API CLI - Interact with Plain customer support platform

USAGE: plain-api.sh <resource> <action> [options]

RESOURCES:
  customer      Read customers
  thread        Read threads, timeline, and add notes
  company       Read companies
  tenant        Read tenants
  label         Read labels
  helpcenter    Read + create draft articles and groups
  tier          Read tiers and SLAs
  workspace     Get workspace info

EXAMPLES:
  plain-api.sh customer list --first 10
  plain-api.sh customer get c_123
  plain-api.sh customer search "john"

  plain-api.sh thread list --status TODO --first 20
  plain-api.sh thread get th_123
  plain-api.sh thread timeline th_123 --first 50
  plain-api.sh thread note th_123 --text "Internal note content"

  plain-api.sh helpcenter list
  plain-api.sh helpcenter articles hc_123 --first 10
  plain-api.sh helpcenter article upsert hc_123 --title "Title" --content "<p>HTML</p>"

  plain-api.sh tier list
  plain-api.sh workspace

ENVIRONMENT:
  PLAIN_API_KEY   Required. Your Plain API key.
  PLAIN_API_URL   Optional. API endpoint (default: https://core-api.uk.plain.com/graphql/v1)
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local resource="$1"

    # Allow help without API key
    if [[ "$resource" == "help" ]] || [[ "$resource" == "--help" ]] || [[ "$resource" == "-h" ]]; then
        usage
        exit 0
    fi

    check_deps
    shift

    case "$resource" in
        customer)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) customer_get "$@" ;;
                get-by-email) customer_get_by_email "$@" ;;
                get-by-external-id) customer_get_by_external_id "$@" ;;
                list) customer_list "$@" ;;
                search) customer_search "$@" ;;
                *) echo "Unknown customer action: $action" >&2; exit 1 ;;
            esac
            ;;
        thread)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) thread_get "$@" ;;
                list) thread_list "$@" ;;
                search) thread_search "$@" ;;
                timeline) thread_timeline "$@" ;;
                note) thread_note "$@" ;;
                *) echo "Unknown thread action: $action" >&2; exit 1 ;;
            esac
            ;;
        company)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) company_get "$@" ;;
                list) company_list "$@" ;;
                *) echo "Unknown company action: $action" >&2; exit 1 ;;
            esac
            ;;
        tenant)
            local action="${1:-list}"
            shift || true
            case "$action" in
                get) tenant_get "$@" ;;
                list) tenant_list "$@" ;;
                *) echo "Unknown tenant action: $action" >&2; exit 1 ;;
            esac
            ;;
        label)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) label_list "$@" ;;
                *) echo "Unknown label action: $action" >&2; exit 1 ;;
            esac
            ;;
        helpcenter)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) helpcenter_list ;;
                get) helpcenter_get "$@" ;;
                articles) helpcenter_articles "$@" ;;
                article)
                    local sub_action="${1:-get}"
                    shift || true
                    case "$sub_action" in
                        get) helpcenter_article_get "$@" ;;
                        get-by-slug) helpcenter_article_get_by_slug "$@" ;;
                        upsert) helpcenter_article_upsert "$@" ;;
                        *) echo "Unknown article action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                group)
                    local sub_action="${1:-get}"
                    shift || true
                    case "$sub_action" in
                        get) helpcenter_group_get "$@" ;;
                        create) helpcenter_group_create "$@" ;;
                        update) helpcenter_group_update "$@" ;;
                        delete) helpcenter_group_delete "$@" ;;
                        *) echo "Unknown group action: $sub_action" >&2; exit 1 ;;
                    esac
                    ;;
                *) echo "Unknown helpcenter action: $action" >&2; exit 1 ;;
            esac
            ;;
        tier)
            local action="${1:-list}"
            shift || true
            case "$action" in
                list) tier_list "$@" ;;
                get) tier_get "$@" ;;
                *) echo "Unknown tier action: $action" >&2; exit 1 ;;
            esac
            ;;
        workspace)
            workspace_get
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown resource: $resource" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
