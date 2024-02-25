#!/bin/bash

# for testing purposes; deletes all the users
cleanup() { 
    # deletes users by using output in the csv file 
    userids_csv_file="user_ids.csv"
    user_ids=$(sed 's/.$//' "$userids_csv_file")
    echo "cleanup(): ids to delete: $ids"
    delete_users_url="$base_url/v2/users/destroy_many.json?ids=$ids"
    response=$(curl -s -w "%{http_code}" -u "$client_email:$api_key" -H "Content-Type: application/json" -X DELETE "$delete_url" | jq '.')
    echo "$response" | jq '.'


    groupids_csv_file="group_id.csv"
    group_ids=$(sed 's/.$//' "$groupids_csv_file")
    # delete groups 


}

# check our script to see if there were any duplicate users that were created 
check_duplicates() { 
    string_to_find=$1
    csv_file="user_names.csv"

if grep -q "$string_to_find" "$csv_file"; then
    return 0 
else
    return 1 
fi
}




# group creation API 
# assumption: this and create_user are already given validated data. 
create_group() { 
    department_name="$1"
    echo "create_group(): Begin creating group for $department_name"
    api_url="$base_url/v2/groups.json"
    local group_id 
    payload=$(printf '{"group": {"name": "%s"}}' "$department_name")
    echo $payload | jq '.'
    response=$(curl -s -w "%{http_code}" -u "$client_email:$api_key" -H "Content-Type: application/json" -X POST -d "$payload" "$api_url" | jq '.')
    if [[ $? -eq 0 ]]; then
        # Process JSON data with jq
        http_status_code=$(echo "$response" | tail -n 1) 
        if [[ "$http_status_code" = "401" ]]; then
            echo "create_group(): Incorrect authentication. Usage: client-api-email: [youremail]/token. Contact your Zendesk administrator for API token."
            exit 1 
        elif [[ "$http_status_code" = "422" ]]; then
            echo "create_group(): Something went wrong with formatting. Exiting now"
            exit 1 
        elif [[ "$http_status_code" = "500" ]]; then 
            echo "create_group(): Something went wrong. Contact Zendesk Support if this issue persists."
            exit 1 
        fi 

        echo "create_group() response: "
        echo "$response" | jq '.'
        group_id=$(echo "$response" | jq -r '.group' | jq '.id')
        echo "create_group(): HTTP status $http_status_code, returned group id $group_id" 
        ####### TESTING - comment out to run unit tests #### 
        departments["$department_name"]="$group_id"
        ####### TESTING - comment out to run unit tests #### 
        if [[ -n "$group_id" && "$group_id" != "null" ]]; then
            echo -n "$group_id," >> group_id.csv # use later for cleanup 
            return "$group_id"
        fi

    elif [[ $? -eq 1 ]]; then 
        echo "create_group(): Unexpected error in trying to create group for $department_name, please retry."
    elif [[ $? -eq 28 ]]; then 
        echo "create_group(): Timeout for creating $department_name group, try again later."
    fi 

}


# purpose: assign roles, construct user JSON, API request to create a user. 
create_user() {
    echo "create_user(): Begin create_user for ${curr_user[name]}"
    curr_user=$1
    request_url="$base_url/v2/users.json"
    title_regex="^(Manager|manager)" # manager title regex - if title contains 'manager', case-insensitive.  



    # strip string of spaces so we can use this as a key later. 
    local curr_name="${curr_user["name"]// /}"
    # check if we have already created a user for this corresponding email. 
    if grep -q "$curr_name" "user_names.csv"; then
        echo "create_user(): User $curr_name already exists with ID ${users["$curr_name"]}, returning"
        return 
    fi 
    echo "create_user(): User ${curr_user[name]} not already created yet, continuing."

    local group_id 
    user_file="user_ids.csv"
    curr_user["role"]="agent" # default role 

    # assign department id
    department_name="${curr_user["department"]}"
    if ! [[ ${departments["$department_name"]+exists} ]]; then
        echo "create_user(): No group ID exists for $department_name, creating group now"
        create_group $department_name # add timeout here if time permits 
    fi 
    group_id=$(printf "%d" ${departments["$department_name"]}) # grab corresponding group id for department 
    echo "create_user(): group ID $group_id for ${curr_user["name"]}in ${curr_user["department"]} department"

    # assign roles 
    echo "create_user(): Begin assigning roles for ${curr_user["name"]}"
    if [[ "${curr_user[department]}" =~ $it_regex ]] && [[ "${curr_user[title]}" =~ $title_regex ]]; then 
        curr_user["role"]="admin"
        "create_user(): added role 'admin' for ${curr_user["name"]}"
    fi  


    # format json 
    echo "create_user(): Begin constructing JSON request body for ${curr_user["name"]}"
    payload=$(printf '{"user": {"name": "%s", "role": "%s", "email": "%s", "skip_verify_email": "true", "default_group_id": \"%s\", "user_fields": { "title": "%s", "department": "%s" }' \
        "${curr_user["name"]}" \
        "${curr_user["role"]}" \
        "${curr_user["email"]}" \
        "$group_id" \
        "${curr_user["title"]}" \
        "${curr_user["department"]}") 

    if ! [[ "${curr_user[department]}" =~ $it_regex  ]]; then 
        payload+="$(printf ', "custom_role_id": "%s"}}' \ "$default_role_id")"
    else 
        payload+="}}"
    fi 

    echo "create_user(): Request Body for "${curr_user["name"]}":"
    echo $payload | jq '.'
    echo "create_user(): Trying request for "${curr_user["name"]}" now"
    response=$(curl -s -w "%{http_code}" -u "$client_email:$api_key" -H "Content-Type: application/json" -X POST -d "$payload" "$request_url" | jq '.')

    if [[ $? -eq 0 ]]; then
        # Process JSON data with jq
        http_status_code=$(echo "$response" | tail -n 1)
        
        if [[ "$http_status_code" = "401" ]]; then
            echo "create_user(): Incorrect authentication. Usage: client-api-email: [youremail]/token. Contact your Zendesk administrator for API token."
            exit 1 
        elif [[ "$http_status_code" = "422" ]]; then 
            echo "create_user(): The user "${curr_user["name"]}" could not be processed. Please refer to the response message above. Skipping"
            return 
        # elif [[ "$http_status_code" = "429" ]]; then 
        #     echo "create_user(): Maximum request limit reached on Zendesk API. Please try again later"
        #     exit 1
        elif [[ "$http_status_code" = "500" ]]; then 
            echo "create_user(): Something went wrong. Contact Zendesk Support if this issue persists."
            exit 1
        fi 
        echo "create_user(): Response for "${curr_user["name"]}":"
        echo "$response" | jq '.'
        user_id=$(echo "$response" | jq -r '.user.id')
        echo "create_user(): user ID $user_id returned, HTTP status Code: $http_status_code"
        # logs all the user ids onto csv file 
        if [[ -n "$user_id" && "$user_id" != "null" ]]; then
            echo -n "$user_id," >> user_ids.csv # use later for cleanup 
            echo -n "$curr_name," >> user_names.csv # use later for cleanup 

        fi
    else 
        echo "create_user(): Unexpected error trying to create user for ${curr_user["name"]}, please retry."
    fi 
}

# purpose: iterate through each row of our csv, validate data, assign roles, and construct the corresponding JSON object. 
parse_file() {
    echo "parse_script.sh: Begin parse_file()"
    field_regex=^[[:alpha:]][[:space:][:alpha:]\&\.\-]*$
    
    # parse csv file
    while IFS=, read -r first_name last_name title department; 
    do
        echo "parse_file(): Reading row for name: $first_name $last_name, Title: $title, Department: $department" 
        unset curr_user
        declare -A curr_user
        format_ok=1 
        curr_user["name"]="${first_name,,} ${last_name,,}"
        curr_user["title"]="${title,,}"
        curr_user["department"]="$department"
        # data validation - kinda sketch, will come up with a better regex if time permits. 
        for val in "${curr_user[@]}"; do 
            if ! [[ "$val" =~  $field_regex ]]; then # wce check all the fields and match them up against our regex to see if data is correctly formatted
                echo $val
                echo "parse_file(): Error: expected format $field_regex, for $val, skipping this row"
                format_ok=0 # if it doesn't match, then we skip this row - assumes that regex accounts for everything. 
                break 
            fi 
        done
        echo "parse_file(): all fields successfully validated for $first_name $last_name"
        if [[ $format_ok -eq 1 ]]; then
            curr_user["email"]="$first_name$last_name@thisoldbank-test.com"
            echo "parse_file(): Generated email ${curr_user["email"]} for $first_name $last_name, entering create_user now"
            create_user $curr_user 
        fi

    done < <(tail -n +2 $user_info) # skip column names - assuming that they're always in the same order! 
    echo "parse_file(): reading CSV file complete"
}



# check if correct number of args provided
if [[ $# != 1 ]]; then 
    echo "parse_script.sh: Error: Expected 1 argument"
    exit 1 
fi 
# grab csv file from arg 
user_info=$1
it_regex="^(IT|Information Technology)" # department regex - we check if dept field contains 'it' or 'Information Technology'
# check if file exists and is csv extension 
if [[ ! -f "$user_info" ]]; then 
    echo "parse_script.sh: Error: File $user_info does not exist or is not a regular file"
    exit 1 
fi 
 

# check file type 
# file_type=$(file -b --mime-type "$user_info")
# if [[ "$file_type" != "text/csv" ]]; then 
#     echo "parse_script.sh: Error: Expected *.csv, got $file_type"
#     exit 1 
# fi 


client_email=$(jq -r .client_auth_email env.json)
api_key=$(jq -r .api_key env.json)
base_url=$(jq -r .base_url env.json)
default_role_id="$(jq -r .light_agent_role_id env.json)"

declare -A departments # key = name, value = group id 

last_char=$(tail -c 1 "$user_info")
if [ "$last_char" == $'\n' ]; then
    echo "parse_script.sh: The file is missing a newline character and is badly formatting. adding a newline now"
    printf '\n' >> "$user_info"
fi 

# comment this block out for testing # 
parse_file 
# comment this block out for testing # 

######### testing stuff ########
# departments["finance"]="22692012395291"



######### testing stuff ########
# cleanup