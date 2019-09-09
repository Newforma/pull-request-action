#!/bin/bash

# Suggested by Github actions to be strict
set -e
set -o pipefail

################################################################################
# Global Variables (we can't use GITHUB_ prefix)
################################################################################

API_VERSION=v3
BASE=https://api.github.com
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
HEADER="Accept: application/vnd.github.${API_VERSION}+json"
HEADER="${HEADER}; application/vnd.github.antiope-preview+json; application/vnd.github.shadow-cat-preview+json"

# URLs
REPO_URL="${BASE}/repos/${GITHUB_REPOSITORY}"
PULLS_URL=$REPO_URL/pulls

################################################################################
# Helper Functions
################################################################################


check_credentials() {

    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo "You must include the GITHUB_TOKEN as an environment variable."
        exit 1
    fi

}

check_events_json() {

    if [[ ! -f "${GITHUB_EVENT_PATH}" ]]; then
        echo "Cannot find Github events file at ${GITHUB_EVENT_PATH}";
        exit 1;
    fi
    echo "Found ${GITHUB_EVENT_PATH}";

}

create_pull_request() {

    # JSON strings
    SOURCE="$(echo -n "${1}" | jq --raw-output --raw-input --slurp ".")"  # from this branch
    TARGET="$(echo -n "${2}" | jq --raw-output --raw-input --slurp ".")"  # pull request TO this target
    BODY="Auto code reconciliation from \"${SOURCE}\" to \"${TARGET}\""    # this is the content of the message
    TITLE="Auto code reconciliation"   # pull request title

    SOURCE=$(echo ${SOURCE} | sed -e "s/\"//g")
    TARGET=$(echo ${TARGET} | sed -e "s/\"//g")

    # Check if the branch already has a pull request open

    DATA="{\"base\":${TARGET}, \"head\":${SOURCE}, \"body\":${BODY}}"
    CURL_GET_REQUEST="curl -sSL -H \"${AUTH_HEADER}\" -H \"${HEADER}\" -X GET --data \"${DATA}\" ${PULLS_URL}"
    CURL_POST_REQUEST="curl -sSL -H \"${AUTH_HEADER}\" -H \"${HEADER}\" -X POST --data \"${DATA}\" ${PULLS_URL}"

    echo "Getting Existing PRs:"
    echo "$CURL_GET_REQUEST"
    RESPONSE=$(curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X GET --data "${DATA}" ${PULLS_URL})

    PR=$(echo "${RESPONSE}" | jq --raw-output '.[] | .head.ref')
    echo "Response ref: ${PR}"

    # Option 1: The pull request is already open
    if [[ "${PR}" == "${SOURCE}" ]]; then
        echo "Pull request from ${SOURCE} to ${TARGET} is already open!"

    # Option 2: Open a new pull request
    else
        # Post the pull request
        echo "Creating Pull Request:"
        echo "$CURL_POST_REQUEST"
        DATA="{\"title\":${TITLE}, \"body\":${BODY}, \"base\":${TARGET}, \"head\":${SOURCE}"
        RESPONSE=$(curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X POST --data "${DATA}" ${PULLS_URL})
        echo "PR Creation Response: ${RESPONSE}"
    fi

    LABELS="{\"labels\":[\"autorebase\"]"
    PR_NUMBER=$(echo "${RESPONSE}" | jq --raw-output '.[] | .number')
    LABELS_URL="${REPO_URL}/issues/${PR_NUMBER}/labels"

    curl -sSL -H "${AUTH_HEADER}" -H "${HEADER}" -X POST --data "${LABELS}" ${LABELS_URL}
}


main () {

    # path to file that contains the POST response of the event
    # Example: https://github.com/actions/bin/tree/master/debug
    # Value: /github/workflow/event.json
    check_events_json;

    # User specified branch to PR to, and check
    if [ -z "${BRANCH_PREFIX}" ]; then
        echo "No branch prefix is set, all branches will be used."
        BRANCH_PREFIX=""
        echo "Branch prefix is $BRANCH_PREFIX"
    fi

    if [ -z "${PULL_REQUEST_BRANCH}" ]; then
        PULL_REQUEST_BRANCH=master
    fi
    echo "Pull requests will go to ${PULL_REQUEST_BRANCH}"

    # Get the name of the action that was triggered
    BRANCH=$(jq --raw-output .ref "${GITHUB_EVENT_PATH}");
    BRANCH=$(echo "${BRANCH/refs\/heads\//}")
    echo "Found branch $BRANCH"

    # If it's to the target branch, ignore it
    if [[ "${BRANCH}" == "${PULL_REQUEST_BRANCH}" ]]; then
        echo "Target and current branch are identical (${BRANCH}), skipping."
    else

        # If the prefix for the branch matches
        if  [[ $BRANCH == ${BRANCH_PREFIX}* ]]; then

            # Ensure we have a GitHub token
            check_credentials

            create_pull_request "${BRANCH}" "${PULL_REQUEST_BRANCH}"

        fi

    fi
}

echo "==========================================================================
START: Running Pull Request on Branch Update Action!";
main;
echo "==========================================================================
END: Finished";
