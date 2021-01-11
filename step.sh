#!/usr/bin/env bash
# fail if any commands fails
set -e
# debug log
if [ "${show_debug_logs}" == "yes" ]; then
  set -x
fi

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
  ACCESS_TOKEN=`jq -r '.access_token' token.json`

  printf "\nObtaining the File Upload URL\n"

  curl --silent -X GET \
  'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url?appId='$1'&suffix='$2 \
  -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
  -H 'client_id: '$3'' > uploadurl.json

  printf "\nObtaining the File Upload URL - DONE\n"
}

function uploadFile()
{
  UPLOAD_URL=`jq -r '.uploadUrl' uploadurl.json`
  UPLOAD_AUTH_CODE=`jq -r '.authCode' uploadurl.json` 

  printf "\nUploading a File\n"

  curl --silent -X POST \
    "${UPLOAD_URL}" \
    -H 'Accept: application/json' \
    -F authCode="${UPLOAD_AUTH_CODE}" \
    -F fileCount=1 \
    -F parseType=1 \
    -F file=@$1 > uploadfile.json
  
  printf "\nUploading a File - DONE\n"  
}

function updateAppFileInfo()
{
  ACCESS_TOKEN=`jq -r '.access_token' token.json`
  FILE_DEST_URL=`jq -r '.result.UploadFileRsp.fileInfoList[0].fileDestUlr' uploadfile.json`
  FILE_SIZE=`jq -r '.result.UploadFileRsp.fileInfoList[0].size' uploadfile.json`

  printf "\nUpdating App File Information - With the previoulsy uploaded file: ${1}"

  curl --silent -X PUT \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-file-info?appId='$2'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'Content-Type: application/json' \
    -H 'client_id: '$3'' \
    -H 'releaseType: '$4'' \
    -d '{
    "fileType":"5",
    "files":[
      {
        "fileName":"'$1'",
        "fileDestUrl":"'"${FILE_DEST_URL}"'",
        "size":"'"${FILE_SIZE}"'"
      }]
  }' > result.json

  printf "\nUpdating App File Information - With the previoulsy uploaded file - DONE"
}

function submitApp()
{  
  ACCESS_TOKEN=`jq -r '.access_token' token.json`

  curl --silent -X  POST \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='$1'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '$2''> resultSubmission.json
} 

function showResponseOrSubmitCompletelyAgain()
{
  ACCESS_TOKEN=`jq -r '.access_token' token.json`
  RET_CODE=`jq -r '.ret.code' resultSubmission.json`
  RET_MESSAGE=`jq -r '.ret.msg' resultSubmission.json` 

  if [[ "${RET_CODE}" == "204144660" ]] && [[ "${RET_MESSAGE}" =~ "It may take 2-5 minutes" ]]  ;then
    printf "\nBuild is currently processing, waiting for 2 minutes before submitting again...\n" 
    sleep 120
    submitApp  $1 $2

    CODE=`jq -r '.ret.code' resultSubmission.json`
    MESSAGE=`jq -r '.ret.msg' resultSubmission.json`
    printf "\nFinal SubmitRetCode - ${CODE}\n" 
    printf "\nFinal SubmitRetMessage - ${MESSAGE}\n" 

  elif [[ "${RET_CODE}" == 0 ]] ;then 
    printf "\App Successfully Submitted For Review\n" 
  else 
    printf "\nFailed to Submit App Completely.\n" 
    printf "${RET_MESSAGE}"
  fi
}

# Setup env vars
LANG="${lang}"
FILENAME_TO_UPLOAD="${huawei_filename}"
FILE_EXT="${file_path##*.}"

getToken  "${huawei_client_id}" "${huawei_client_secret}"

getFileUploadUrl "${huawei_app_id}" "${FILE_EXT}" "${huawei_client_id}"

uploadFile "${file_path}"

updateAppFileInfo "${FILENAME_TO_UPLOAD}" "$huawei_app_id" "${huawei_client_id}" "${releaseType}"

printf "\nSubmitting app...\n" 
submitApp "$huawei_app_id" "${huawei_client_id}"
printf "\nApp submitted as a Draft - Pending of being Submitted for Review\n" 

showResponseOrSubmitCompletelyAgain "$huawei_app_id" "${huawei_client_id}"

exit 0
