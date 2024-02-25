#1/usr/bin/env bats 
load 'parse_script.sh'

client_email=$(jq -r .client_auth_email env.json)
api_key=$(jq -r .api_key env.json)
base_url=$(jq -r .base_url env.json)
default_role_id="$(jq -r .light_agent_role_id env.json)"
group_ids="group_id.csv"
userids_csv_file="user_ids.csv"


@test "create group" { 
    skip 
    local input="test_department_32"
    local output=$(create_group "$input")
    echo "OUTPUT: $output"
    [ -n "$output" ]
    expected_group_id=$(sed 's/.$//' "$group_ids")
    local request_url="$base_url/v2/groups/$expected_group_id.json"
    local response=$(curl -s -u "$client_email:$api_key" -H "Content-Type: application/json" -X GET "$request_url" | jq '.')
    local actual_group_id=$(echo "$response" | jq -r '.group' | jq '.id')
    [ "$actual_group_id" = "$expected_group_id" ]

    echo -n > "group_id.csv"
}

@test "create group 422" {
    skip 
    local actual_output=$(create_group "")
    local expected_output="create_group(): Something went wrong with formatting. Exiting now"
    [[ $actual_output == *"$expected_output"* ]]
    echo -n > "group_id.csv"
}

@test "create group - make sure null string is not being output into file" {
    skip 
    local actual_output=$(create_group "")
    local expected_output="create_group(): Something went wrong with formatting or this group has already been created. Please check Admin Center for more info. Exiting now"
    [[ $actual_output == *"$expected_output"* ]]
    echo -n > "group_id.csv"
}


@test "create group 401 - changed credentials in env.json" {
    skip 
    local actual_output=$(create_group "")
    local expected_output="create_group(): Incorrect authentication. Usage: client-api-email: [youremail]/token. Contact your Zendesk administrator for API token."
    [[ $actual_output == *"$expected_output"* ]]
    echo -n > "group_id.csv"
}


@test "parsefile with missing fields" { 
    local missing_actual=$(./parse_script.sh test_missingfields.csv) 
    local expected_out="Error: expected format ^[[:alpha:]][[:space:][:alpha:]&.-]*$, for , skipping"
    [[ $actual_output == *"$expected_out"* ]]

}