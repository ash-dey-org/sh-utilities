#!/bin/bash

if [ $# -ne 2 ]; then
    clear
    echo "Usage : $0 tf_project_name, tf_variable_set_name "
    echo
    echo "Assumption: environment variable TF_API_TOKEN and TF_CLOUD_ORGANIZATION is avilable"
    echo "This script requires 2 arguments"
    echo "Assigns an exisitng variable set to a Terraform project in Terraform Cloud"
    echo
    echo "1. Terrafrom cloud project name (e.g. prj-xxxx-infra prj-store-infra)"
    echo "2. Name of variable set (e.g. Azure-Tenant-ID-OIDC)"
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
PROJECT_NAME=$1
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
function get_project_id_by_name() {
    PROJECT_NAME=$1

    response=$(curl -s --request GET \
      "${API_URL}/organizations/${TF_CLOUD_ORGANIZATION}/projects?q=${PROJECT_NAME}" \
      "${HEADERS[@]}")

    # echo $response
    PROJECT_ID=$(echo "$response" | jq -r ".data[] | select(.attributes.name==\"$PROJECT_NAME\") | .id")

    if [ -z "$PROJECT_ID" ]; then
        echo "Project not found: $PROJECT_NAME"
        exit 1
    fi
    echo "Found Project ID: $PROJECT_ID"
}


function get_var_set_id_by_name() {
    VAR_SET_NAME=$1
    # Get the list of variable sets for the organization
    RESPONSE=$(curl -s --request GET \
      "${API_URL}/organizations/${TF_CLOUD_ORGANIZATION}/varsets?q=${VAR_SET_NAME}" \
      "${HEADERS[@]}")

    # echo $RESPONSE
    # Check if the response is not empty
    if [ -z "$RESPONSE" ]; then
      echo "Failed to retrieve variable sets. Check your API token and organization name."
      exit 1
    fi

    VARIABLE_SET_ID=$(echo "$RESPONSE" | jq -r ".data[] | select(.attributes.name==\"$VAR_SET_NAME\") | .id")

    # Check if the variable set ID was found
    if [ -z "$VARIABLE_SET_ID" ]; then
      echo "Variable set '$VAR_SET_NAME' not found."
    else
      echo "Variable set ID for '$VAR_SET_NAME' is: $VARIABLE_SET_ID"
    fi
}


# Assign the variable set to a project
function assign_variable_set_to_project() {
    curl --request POST \
      "${API_URL}/varsets/${VARIABLE_SET_ID}/relationships/projects" \
      "${HEADERS[@]}" \
      --data '{
        "data": [
          {
            "type": "projects",
            "id": "'"$PROJECT_ID"'"
          }
        ]
      }'
    echo "Variable Set $VARIABLE_SET_NAME assigned to Project: $PROJECT_NAME"
}

# Main script

get_project_id_by_name "$PROJECT_NAME"
get_var_set_id_by_name "$VARIABLE_SET_NAME"
assign_variable_set_to_project

