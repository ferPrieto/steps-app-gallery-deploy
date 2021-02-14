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
    getSubmissionStatus  $1 $2
    SUBMISSION_STATUS=`jq -r '.aabCompileStatus' resultSubmissionStatus.json`
    printf "Submission Status ${SUBMISSION_STATUS}"
    i=0
    while [[ "${SUBMISSION_STATUS}" == "1" ]] && [[ i < 8 ]]
      do
          printf "${i}"
          sleep 60
          SUBMISSION_STATUS = getSubmissionStatus $1 $2
          printf "\nBuild is currently processing, waiting another minute before submitting again...\n" 
          ((i++))
      done

    if [ "${SUBMISSION_STATUS}" == "2" ]; then

        submitApp  $1 $2 
        CODE=`jq -r '.ret.code' resultSubmission.json`
        MESSAGE=`jq -r '.ret.msg' resultSubmission.json`

        printf "\nFinal SubmitRetCode - ${CODE}\n" 
        printf "\nFinal SubmitRetMessage - ${MESSAGE}\n" 
    else 
          printf "\nFailed to Submit App Completely.\n" 
    fi 

  elif [[ "${RET_CODE}" == 0 ]] ;then 
    printf "\App Successfully Submitted For Review\n" 
  else 
    printf "\nFailed to Submit App Completely.\n" 
    printf "${RET_MESSAGE}"
  fi
}

function getSubmissionStatus()
{
   ACCESS_TOKEN=`jq -r '.access_token' token.json`
   PKG_VERSION=`jq -r '.pkgVersion[0]' result.json`

   curl --silent -X  GET \
   'https://connect-api.cloud.huawei.com/api/publish/v2/aab/complile/status?appId='$1'&pkgVersion='"${PKG_VERSION}"'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '$2''> resultSubmissionStatus.json
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

if [ "${submit_for_review}" == true ]; then
  showResponseOrSubmitCompletelyAgain "${huawei_app_id}" "${huawei_client_id}"
fi

exit 0
