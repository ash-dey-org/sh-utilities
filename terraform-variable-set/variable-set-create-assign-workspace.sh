#!/bin/bash

if [ $# -ne 2 ]; then
    clear
    echo "Usage : $0 tf_workspace_name, tf_variable_set_name "
    echo
    echo "Assumption: environment variable TF_API_TOKEN and TF_CLOUD_ORGANIZATION is avilable"
    echo
    echo "This script requires 2 arguments"
    echo "Assigns a variable set to an existing Terraform workspace in Terraform Cloud"
    echo "workspaces are normally created by TFE provider using tarraform"
    echo "If the variable set does not exist, it will create the variable set and assign to workspace"
    echo
    echo "1. Terrafrom cloud workspace name (e.g. xxxx-infra-xxx | store-infra-dev)"
    echo "2. Name of variable set (e.g. IT-Non-Production-Subscription-ID | IT-Production-Subscription-ID | xxx-infra-xxx-ARM-client | store-infra-dev-ARM-client )"
    exit 0
fi

# Read the Terraform Cloud token from the environment variable
TF_API_TOKEN=${TF_API_TOKEN}
if [ -z "$TF_API_TOKEN" ]; then
  echo "Error: TERRAFORM_CLOUD_TOKEN environment variable is not set."
  exit 1
fi

# Read the Terraform organization from the environment variable
TF_CLOUD_ORGANIZATION=${TF_CLOUD_ORGANIZATION}
if [ -z "$TF_CLOUD_ORGANIZATION" ]; then
  echo "Error: TF_CLOUD_ORGANIZATION environment variable is not set."
  exit 1
fi

# TF_API_TOKEN="your-terraform-cloud-token"
# TF_CLOUD_ORGANIZATION="your-organization"
WORKSPACE_NAME=$1
VARIABLE_SET_NAME=$2
# URL-encode the variable set name
ENCODED_VAR_SET_NAME=$(echo "$VARIABLE_SET_NAME" | jq -sRr @uri)

# Terraform Cloud API Base URL
API_URL="https://app.terraform.io/api/v2"

# Set headers for authentication
HEADERS=(
    "-H" "Authorization: Bearer $TF_API_TOKEN"
    "-H" "Content-Type: application/vnd.api+json"
)

# Function to get Project ID by Project Name
function get_workspace_id_by_name() {
    WORKSPACE_NAME=$1

    response=$(curl -s --request GET \
      "${API_URL}/organizations/${TF_CLOUD_ORGANIZATION}/workspaces/${WORKSPACE_NAME}" \
      "${HEADERS[@]}")

    # echo $response
    # WORKSPACE_ID=$(echo "$response" | jq -r ".data[] | select(.attributes.name==\"$WORKSPACE_NAME\") | .id")
    WORKSPACE_ID=$(echo "$response" | jq -r ".data | select(.attributes.name == \"$WORKSPACE_NAME\") | .id")


    if [ -z "$WORKSPACE_ID" ]; then
        echo "Workspace not found: $WORKSPACE_NAME"
        exit 1
    fi
    echo "Found Workspace $WORKSPACE_NAME with ID: $WORKSPACE_ID"
}

# Add a variable to the variable set
function add_variable_to_set() {
    VARIABLE_KEY=$1
    VARIABLE_VALUE=$2
    VARIABLE_DESCRIPTION=$3
    SENSITIVE=$4
    CATEGORY=$5
    # VARIABLE_SET_ID=$5

    response=$(curl --request POST \
      "${API_URL}/varsets/${VARIABLE_SET_ID}/relationships/vars" \
      "${HEADERS[@]}" \
      --data '{
            "data": {
                "type": "vars",
                "attributes": {
                    "key": "'"$VARIABLE_KEY"'",
                    "value": "'"$VARIABLE_VALUE"'",
                    "description": "'"$VARIABLE_DESCRIPTION"'",
                    "sensitive": "'"$SENSITIVE"'",
                    "category": "'"$CATEGORY"'",
                    "hcl": false
                }
            }
        }'
    )

    # echo "response.... $response"
    # Check if the response is not empty
    if [ -z "$response" ]; then
      echo "Unable to add vriable $VARIABLE_KEY to variable set $VARIABLE_SET_ID"
      exit 1
    else
        echo "Variable '$VARIABLE_KEY' added to the variable set $VARIABLE_SET_ID."
    fi
}

# Function to prompt user to add multiple variables in a loop and add into a variable set
function add_variables_to_set_in_loop() {
    # VARIABLE_SET_ID=$1

    while true; do
        # Prompt for variable name and value
        read -p "Enter variable name (e.g. TFC_AZURE_RUN_CLIENT_ID): " variable_name
        read -p "Enter variable value (e.g. sp client id cxxxx): " variable_value
        read -p "Enter variable description (e.g. sp name, devops-dev-store-sp): " description
        read -p "Enter variable categorsy (e.g. env | terraform): " category

        # Ask if the variable is sensitive
        read -p "Is this a sensitive variable (y/n)? " sensitive_answer
        if [[ "$sensitive_answer" =~ ^[Yy]$ ]]; then
            sensitive=true
        else
            sensitive=false
        fi

        # Add the variable
        add_variable_to_set "$variable_name" "$variable_value" "$description" "$sensitive" "$category"

        # Ask the user if they want to add another variable
        read -p "Do you want to add another variable (y/n)? " continue_answer
        if [[ ! "$continue_answer" =~ ^[Yy]$ ]]; then
            break
        fi
    done
}

# Create the variable set
function create_variable_set() {
    VARIABLE_SET=$1

    response=$(curl --request POST \
      "${API_URL}/organizations/${TF_CLOUD_ORGANIZATION}/varsets" \
      "${HEADERS[@]}" \
      --data '{
        "data": {
            "type": "varsets",
            "attributes": {
                "name": "'"$VARIABLE_SET"'",
                "description": "Variable set created via script",
                "global": false,
                "priority": false
                }
            }
        }'
    )

    VARIABLE_SET_ID=$(echo "$response" | jq -r ".data.id")
    if [ -z "$VARIABLE_SET_ID" ]; then
        echo "Failed to create variable set"
        exit 1
    fi
    echo "Variable Set $VARIABLE_SET Created with ID: $VARIABLE_SET_ID"

    add_variables_to_set_in_loop
}

# Get the variable set id from varibale set name
function get_var_set_id_by_name() {
    VAR_SET_NAME=$1
    # Get the list of variable sets for the organization
    RESPONSE=$(curl -s --request GET \
      "${API_URL}/organizations/${TF_CLOUD_ORGANIZATION}/varsets?q=${VAR_SET_NAME}" \
      "${HEADERS[@]}")

    # echo "response $RESPONSE"
    # Check if the response is not empty
    if [ -z "$RESPONSE" ]; then
      echo "Failed to retrieve variable sets. Check your API token and organization name."
      exit 1
    fi

    VARIABLE_SET_ID=$(echo "$RESPONSE" | jq -r ".data[] | select(.attributes.name==\"$VAR_SET_NAME\") | .id")

    # Check if the variable set ID was found
    if [ -z "$VARIABLE_SET_ID" ]; then
      echo "Variable set $VAR_SET_NAME not found."
      echo "Creating variable set $VAR_SET_NAME"
      create_variable_set "$VAR_SET_NAME"

    else
      echo "Variable set ID for $VAR_SET_NAME is: $VARIABLE_SET_ID"
    fi
}

# Assign the variable set to a workspace
function assign_variable_set_to_workspace() {
    curl --request POST \
      "${API_URL}/varsets/${VARIABLE_SET_ID}/relationships/workspaces" \
      "${HEADERS[@]}" \
      --data '{
        "data": [
          {
            "type": "workspaces",
            "id": "'"$WORKSPACE_ID"'"
          }
        ]
      }'
    echo "Variable Set $VARIABLE_SET_NAME assigned to workspace: $WORKSPACE_NAME"
}

# Main script

get_workspace_id_by_name "$WORKSPACE_NAME"
get_var_set_id_by_name "$VARIABLE_SET_NAME"
assign_variable_set_to_workspace

