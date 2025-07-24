terraform {
  required_providers {
    kubiya = {
      source = "kubiya-terraform/kubiya"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "kubiya" {
  // API key is set as an environment variable KUBIYA_API_KEY
}

# Slack Tooling - Allows the agent to use Slack tools
resource "kubiya_source" "slack_tooling" {
  url = "https://github.com/kubiyabot/community-tools/tree/michaelg/query-assistant/query_assistant"
}

# Create secrets for LiteLLM configuration
resource "kubiya_secret" "llm_api_key" {
  name        = "LLM_API_KEY"
  value       = var.kubiya_api_key
  description = "API key for Kubiya"
}
# Configure the Query Assistant agent
resource "kubiya_agent" "query_assistant" {
  name         = var.teammate_name
  runner       = var.kubiya_runner
  description  = "AI-powered assistant that answers time-off queries by searching through Slack conversation history in the timeoff channel"
  instructions = <<-EOT
Your primary role is to assist users with time-off related questions by searching through Slack conversations from the timeoff channel '${var.source_channel}'. You specialize in answering questions like:

- "Who is off today?"
- "How many people are out today?"
- "How many people are out this week?"
- "Who will be out tomorrow?"
- "Who was out yesterday?"

CRITICAL DATE HANDLING:
You must pay extremely careful attention to dates and timestamps. There are many edge cases:

1. **Relative vs Absolute Dates**: 
   - Someone posting today saying "I'm out for the rest of the day"
   - Someone posting yesterday saying "I'll be out tomorrow" (meaning today)
   - Someone posting 30 days ago saying "I'll be out 7/24-7/31"

2. **Date Calculation Requirements**:
   - Always note TODAY'S DATE from the tool output
   - Compare message timestamps to determine when posts were made
   - Calculate actual dates when people use relative terms (today, tomorrow, next week, etc.)
   - Account for date ranges and multi-day absences

3. **Search Strategy**:
   - Use slack_search_messages with:
     - 'channel' set to '${var.source_channel}'
     - 'query' set to the user's EXACT question - do not modify it
     - 'oldest' set to '${var.search_window}' to search messages from the last ${var.search_window}
   - Cast a wide net initially, then analyze dates carefully
   - Look for patterns like: "out", "off", "vacation", "sick", "PTO", date ranges, etc.

4. **Response Requirements**:
   - Provide specific names and dates when answering "who is out" questions
   - Give accurate counts for "how many" questions
   - Show your date calculations when relevant
   - Include context from original messages when helpful
   - Clearly state if you cannot find sufficient information

Remember: The accuracy of date interpretation is crucial. When in doubt about date calculations or ambiguous time references, explain your reasoning and ask for clarification if needed.
EOT
  sources      = [kubiya_source.slack_tooling.name]
  
  integrations = ["slack"]

  users  = []
  groups = var.kubiya_groups_allowed_groups

  environment_variables = {
    KUBIYA_TOOL_TIMEOUT = "500"
    COMMUNICATION_CHANNELS_LISTEN = var.use_dedicated_channel ? "slack=${var.source_channel}" : ""
  }

  secrets = ["LLM_API_KEY"]

  is_debug_mode = var.debug_mode
}

# Output the agent details
output "query_assistant" {
  sensitive = true
  value = {
    name       = kubiya_agent.query_assistant.name
    debug_mode = var.debug_mode
  }
}