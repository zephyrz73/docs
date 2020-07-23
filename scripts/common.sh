#!/bin/bash

# Return a friendly name for the current IAM user, e.g. "mattdr".
# Calling this function from an assumed-role account will return
# the temporary user ID assigned by AWS STS.
aws_user_id() {
    # e.g. "arn:aws:iam::153052954103:user/mattdr@pulumi.com"
    aws_user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)

    # e.g. "mattdr@pulumi.com". Also works for roles.
    last_part=${aws_user_arn##*/}

    # e.g. "mattdr"
    echo "${last_part%%@*}"
}

# On script startup, store the initial AWS user ID we saw. This way we have a record of
# who initiated the current script, even if we later assumed another role. (Which would
# then change the result of calling `aws_user_id` a second time.)
if [ -z "${INITIAL_AWS_USER_ID:-}" ]; then
    export INITIAL_AWS_USER_ID="$(aws_user_id)"
fi

# pulumi_stack_name returns the appropriate stack name for the current environment.
pulumi_stack_name() {
    echo "${PULUMI_ORG_NAME_OVERRIDE:-pulumi}/${PULUMI_STACK_NAME_OVERRIDE:-${INITIAL_AWS_USER_ID}}"
}

# run_pulumi_login logs into Pulumi using the Pulumi Service backend.
run_pulumi_login() {
    pulumi login
    pulumi whoami -v
}

# run_pulumi_stack_select chooses the appropriate Pulumi stack, based on the current environment.
run_pulumi_stack_select() {
    pulumi -C infrastructure stack select $(pulumi_stack_name)
}

# run_pulumi_config simply wraps pulumi config.
run_pulumi_config() {
    pulumi -C infrastructure config "$@"
}

# run_pulumi runs the specified pulumi command (e.g., preview or up), based on the current environment.
run_pulumi() {
    if [ "${pulumi_stack_name}" == "production" ]; then
        assume-role $(run_pulumi_config get roleArn) pulumi -C infrastructure "$@"
    else
        pulumi -C infrastructure "$@"
    fi
}

# Posts a message to Slack. Requires a valid access token is available in $SLACK_ACCESS_TOKEN.
# Usage: post_to_slack <channel> <message>
post_to_slack() {
    local channel=$1
    local message=$2

    local escaped=$(echo ${message} | sed 's/"/\"/g' | sed "s/'/\'/g" )
    local json="{\"channel\": \"#${channel}\", \"text\": \"${escaped}\", \"as_user\": true}"

    curl \
        -X POST \
        -H "Content-type: application/json" \
        -H "Authorization: Bearer ${SLACK_ACCESS_TOKEN}" \
        -d  "${json}" \
        https://slack.com/api/chat.postMessage > /dev/null
}

# Posts a comment to a GitHub PR. Requires a GitHub token is available in $GITHUB_TOKEN.
# Usage: post_github_pr_comment "Hi!" "https://api.github.com/repos/<org>/<repo>/issues/<pr-number>/comments"
post_github_pr_comment() {
    local pr_comment=$1
    local pr_comment_api_url=$2
    local pr_comment_body=$(printf '{ "body": "%s" }' "$comment")

    curl \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -d "$pr_comment_body" \
        $pr_comment_api_url > /dev/null
}

git_sha() {
    git rev-parse HEAD
}

git_sha_short() {
    git rev-parse --short HEAD
}

# pr_number_or_git_sha returns wither the PR number of the current GitHub Actions run or the Git SHA of the current branch, a name that can be used for build-specific purposes, like bucket naming and asset naming.
pr_number_or_git_sha() {
    echo ">$GITHUB_EVENT_NAME<"
    echo ">$GITHUB_EVENT_PATH<"
    echo ">$(cat "$GITHUB_EVENT_PATH" | jq -r ".number")<"
    echo ">$GITHUB_SHA<"
    echo ">$git_sha_short<"
    if [[ "$GITHUB_EVENT_NAME" == "pull_request" && ! -z "$GITHUB_EVENT_PATH" ]]; then
        echo $(cat "$GITHUB_EVENT_PATH" | jq -r ".number")
    else
        echo "${GITHUB_SHA:=$git_sha_short}"
    fi
}

# Retry the given command some number of times, with a delay of some number of seconds between calls.
# Usage: retry some_command <retry-count> <delay-in-seconds>
retry() {
    local n=1
    local max=$2
    local delay=$3
    while true; do
    "$@" && break || {
        if [[ $n -lt $max ]]; then
            ((n++))
            echo "Command failed. Attempt $n/$max:"
            sleep $delay;
        else
            echo "The command has failed after $n attempts." >&2
            return 1
        fi
    }
    done
}
