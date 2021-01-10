#!/usr/bin/env bash
# fail if any commands fails
set -e
# debug log
if [ "${show_debug_logs}" == "yes" ]; then
  set -x
fi

# it checks whether a string contains another one or not
function containsWait()
{
    if [[ $1 == *$2* ]]; then
      return 0
    else
      return 1
    fi 
}

function getToken()
{
  printf "\n\nObtaining a Token\n"
  
  curl --silent -X POST \
    https://connect-api.cloud.huawei.com/api/oauth2/v1/token \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{
      "grant_type": "client_credentials",
      "client_id": "'$1'",
      "client_secret": "'$2'"
  }' > token.json

  printf "\nObtaining a Token - DONE\n"
} 

function getFileUploadUrl()
{
  printf "\nObtaining the File Upload URL\n"

  curl --silent -X GET \
  'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url?appId='$1'&suffix='$2 \
  -H 'Authorization: Bearer '$3'' \
  -H 'client_id: '$4'' > uploadurl.json

  printf "\nObtaining the File Upload URL - DONE\n"
}

function uploadFile()
{
  printf "\nUploading a File\n"

  curl --silent -X POST \
    $1 \
    -H 'Accept: application/json' \
    -F authCode=$2 \
    -F fileCount=1 \
    -F parseType=1 \
    -F file=@$3 > uploadfile.json
  
  printf "\nUploading a File - DONE\n"  
}

function updateAppFileInfo()
{
  printf "\nUpdating App File Information - With the previoulsy uploaded file: ${1}"

  curl --silent -X PUT \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-file-info?appId='$2'' \
    -H 'Authorization: Bearer '$3'' \
    -H 'Content-Type: application/json' \
    -H 'client_id: '$4'' \
    -H 'releaseType: '$5'' \
    -d '{
    "fileType":"5",
    "files":[
      {
        "fileName":"'$1'",
        "fileDestUrl":"'$6'",
        "size":"'$7'"
      }]
  }' > result.json

  printf "\nUpdating App File Information - With the previoulsy uploaded file - DONE"
}

function submitForReview()
{
  printf "\nSubmit for Review\n" 

  curl --location --request POST \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='$1'' \
    -H 'Authorization: Bearer '$2'' \
    -H 'client_id: '$3''> resultDraftSubmission.json

  printf "\nSubmit for Review - DONE\n" 
}

function submitCompletely()
{
  curl --location --request POST \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='$1'' \
    -H 'Authorization: Bearer '$2'' \
    -H 'client_id: '$3''> resultSubmission.json 
}

function showResponseOrSubmitCompletelyAgain()
{
  if  $1 -eq 204144660  &&  containsWait $2 "It may take 2-5 minutes"  ;then
    printf "\nBuild is currently processing, waiting for 2 minutes before submitting again...\n" 
    sleep 120
    submitCompletely  $3 $4 $5
    CODE=`jq -r '.ret.code' resultSubmission.json`
    MESSAGE=`jq -r '.ret.msg' resultSubmission.json`

    printf "\nFinal SubmitRetCode - ${CODE}\n" 
    printf "\nFinal SubmitRetMessage - ${MESSAGE}\n" 

  elif [ $1 -eq 0 ] ;then 
    printf "\nSuccessfully submitted app for review\n" 
  else 
    printf "\nFailed to Submit App Completely.\n" 
    printf $2
  fi
}

# Setup env vars
LANG="${lang}"
FILENAME_TO_UPLOAD="${huawei_filename}"
FILE_EXT="${file_path##*.}"

# 1. Get Token
getToken  "${huawei_client_id}" "${huawei_client_secret}"
ACCESS_TOKEN=`jq -r '.access_token' token.json`

# 2. Get File Upload Url
getFileUploadUrl "${huawei_app_id}" "${FILE_EXT}" "${ACCESS_TOKEN}" "${huawei_client_id}"
UPLOAD_URL=`jq -r '.uploadUrl' uploadurl.json`
UPLOAD_AUTH_CODE=`jq -r '.authCode' uploadurl.json` 

# 3. Upload .apk/.aab File
uploadFile "${UPLOAD_URL}" "${UPLOAD_AUTH_CODE}" "${file_path}"
FILE_DEST_URL=`jq -r '.result.UploadFileRsp.fileInfoList[0].fileDestUlr' uploadfile.json`
FILE_SIZE=`jq -r '.result.UploadFileRsp.fileInfoList[0].size' uploadfile.json`

# 4. Update App File Information
updateAppFileInfo "${FILENAME_TO_UPLOAD}" "$huawei_app_id" "${ACCESS_TOKEN}" "${huawei_client_id}" "${releaseType}" "$FILE_DEST_URL" "$FILE_SIZE"
FILE_UPLOAD_CODE=`jq -r '.ret.code' result.json`
FILE_UPLOAD_MSG=`jq -r '.ret.msg' result.json`

# 5. Submit App for Review (Draft)
submitForReview "$huawei_app_id" "${ACCESS_TOKEN}" "${huawei_client_id}"
RET_CODE=`jq -r '.ret.code' resultDraftSubmission.json`
RET_MESSAGE=`jq -r '.ret.msg' resultDraftSubmission.json`

# 6. Submit App Completely
submitCompletely "$huawei_app_id" "${ACCESS_TOKEN}" "${huawei_client_id}"
SUBMIT_RET_CODE=`jq -r '.ret.code' resultSubmission.json`
SUBMIT_RET_MESSAGE=`jq -r '.ret.msg' resultSubmission.json`

# 7. Wait 2 mins to try again or show Response Message
showResponseOrSubmitCompletelyAgain "${SUBMIT_RET_CODE}" "${SUBMIT_RET_MESSAGE}" "$huawei_app_id" "${ACCESS_TOKEN}" "${huawei_client_id}" 

exit 0
