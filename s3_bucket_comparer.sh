#!/bin/bash

echo "##########################################################################################"
echo "#  SCRIPT TO COMPARE S3 BUCKETS FROM DIFFERENT ACCOUNTS (VALIDATING BUCKET REPLICATION)  #"
echo "##########################################################################################"

# Function to check if AWS credentials are configured
check_aws_credentials() {
    local PROFILE_NAME=$1
    aws sts get-caller-identity --profile "$PROFILE_NAME" &>/dev/null
    if [ $? -ne 0 ]; then
        echo "AWS credentials for profile $PROFILE_NAME are not configured correctly."
        return 1
    else
        return 0
    fi
}

# Ask if credentials are already configured
echo "Do you already have AWS credentials configured for both accounts? (yes/no)"
read CREDENTIALS_CONFIGURED

if [ "$CREDENTIALS_CONFIGURED" == "no" ]; then
    for ACCOUNT in "source" "destination"; do
        echo "Is the $ACCOUNT account using federated access? (yes/no)"
        read FEDERATED
        
        echo "Enter the profile name for the $ACCOUNT account:"
        read PROFILE
        
        echo "Enter AWS Access Key ID:"
        read AWS_ACCESS_KEY_ID
        
        echo "Enter AWS Secret Access Key:"
        read AWS_SECRET_ACCESS_KEY
        
        if [ "$FEDERATED" == "yes" ]; then
            echo "Enter AWS Session Token:"
            read AWS_SESSION_TOKEN
            aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile "$PROFILE"
        fi
        
        echo "Enter AWS region:"
        read AWS_REGION
        
        aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$PROFILE"
        aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$PROFILE"
        aws configure set region "$AWS_REGION" --profile "$PROFILE"
        
        if [ "$ACCOUNT" == "source" ]; then
            SOURCE_PROFILE="$PROFILE"
        else
            DEST_PROFILE="$PROFILE"
        fi
    done
else
    echo "Enter the profile name for the source account:"
    read SOURCE_PROFILE
    while ! check_aws_credentials "$SOURCE_PROFILE"; do
        echo "Enter a valid profile name for the source account:"
        read SOURCE_PROFILE
    done

    echo "Enter the profile name for the destination account:"
    read DEST_PROFILE
    while ! check_aws_credentials "$DEST_PROFILE"; do
        echo "Enter a valid profile name for the destination account:"
        read DEST_PROFILE
    done
fi

# List buckets in each account
echo "Fetching bucket list from source account..."
aws s3 ls --profile "$SOURCE_PROFILE"
echo "Enter the source bucket name you want to compare:"
read SOURCE_BUCKET_NAME

echo "Fetching bucket list from destination account..."
aws s3 ls --profile "$DEST_PROFILE"
echo "Does the destination bucket have the same name? (yes/no)"
read SAME_NAME
if [ "$SAME_NAME" == "yes" ]; then
    DEST_BUCKET_NAME=$SOURCE_BUCKET_NAME
else
    echo "Enter the destination bucket name you want to compare:"
    read DEST_BUCKET_NAME
fi

# Fetch files for the specified source bucket
echo "Fetching files from source bucket: $SOURCE_BUCKET_NAME"
aws s3 ls "s3://$SOURCE_BUCKET_NAME" --recursive --profile "$SOURCE_PROFILE" | awk '{print $4, $3}' | sort > "source_$SOURCE_BUCKET_NAME.txt"

# Fetch files for the specified destination bucket
echo "Fetching files from destination bucket: $DEST_BUCKET_NAME"
aws s3 ls "s3://$DEST_BUCKET_NAME" --recursive --profile "$DEST_PROFILE" | awk '{print $4, $3}' | sort > "dest_$DEST_BUCKET_NAME.txt"

# Compare files for the specified buckets
echo "Comparing files between source bucket $SOURCE_BUCKET_NAME and destination bucket $DEST_BUCKET_NAME"
diff "source_$SOURCE_BUCKET_NAME.txt" "dest_$DEST_BUCKET_NAME.txt" > "diff_${SOURCE_BUCKET_NAME}_vs_${DEST_BUCKET_NAME}.txt"
if [ -s "diff_${SOURCE_BUCKET_NAME}_vs_${DEST_BUCKET_NAME}.txt" ]; then
    echo "Differences found in replication. Check diff_${SOURCE_BUCKET_NAME}_vs_${DEST_BUCKET_NAME}.txt for details."
    echo "Output format:"
    echo "  - Lines starting with '<' exist in the source bucket but are missing from the destination."
    echo "  - Lines starting with '>' exist in the destination bucket but are missing from the source."
    echo "  - The number next to the file name represents its size in bytes."
else
    echo "Replication is correct. All files match."
    rm -f "diff_${SOURCE_BUCKET_NAME}_vs_${DEST_BUCKET_NAME}.txt"
fi

# Clean temp files
rm -f "source_$SOURCE_BUCKET_NAME.txt" "dest_$DEST_BUCKET_NAME.txt"

# Ask if credentials should be removed
echo "Do you want to remove the temporary AWS credentials? (yes/no)"
read REMOVE_CREDENTIALS
if [ "$REMOVE_CREDENTIALS" == "yes" ]; then
    echo "Removing temporary AWS credentials..."
    aws configure set aws_access_key_id "" --profile "$SOURCE_PROFILE"
    aws configure set aws_secret_access_key "" --profile "$SOURCE_PROFILE"
    aws configure set aws_session_token "" --profile "$SOURCE_PROFILE"
    aws configure set aws_access_key_id "" --profile "$DEST_PROFILE"
    aws configure set aws_secret_access_key "" --profile "$DEST_PROFILE"
    aws configure set aws_session_token "" --profile "$DEST_PROFILE"
    echo "Credentials removed."
else
    echo "Credentials were not removed."
fi

echo "Cleanup completed. Script execution finished."
