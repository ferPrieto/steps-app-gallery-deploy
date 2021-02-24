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
      "client_id": "'${huawei_client_id}'",
      "client_secret": "'${huawei_client_secret}'"
  }' > token.json

  printf "\nObtaining a Token - DONE\n"
} 

function getFileUploadUrl()
{
  ACCESS_TOKEN=`jq -r '.access_token' token.json`
  FILE_EXT="${file_path##*.}"
  RELEASE_TYPE=$( getReleaseTypeValue ) 

  printf "\nObtaining the File Upload URL\n"

  curl --silent -X GET \
  'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url?appId='"${huawei_app_id}"'&suffix='"${FILE_EXT}"'&releaseType='"${RELEASE_TYPE}" \
  -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
  -H 'client_id: '"${huawei_client_id}"'' > uploadurl.json

  printf "\nObtaining the File Upload URL - DONE\n"
}

function getReleaseTypeValue()
{
  if [ "${release_type}" == "By Phase" ]; then
     releaseTypeValue=3
  else 
     releaseTypeValue=1
  fi

  echo $releaseTypeValue
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
    -F file="@${file_path}" > uploadfile.json
  
  printf "\nUploading a File - DONE\n"  
}

function updateAppFileInfo()
{
  ACCESS_TOKEN=`jq -r '.access_token' token.json`
  FILE_DEST_URL=`jq -r '.result.UploadFileRsp.fileInfoList[0].fileDestUlr' uploadfile.json`
  FILE_SIZE=`jq -r '.result.UploadFileRsp.fileInfoList[0].size' uploadfile.json`

  printf "\nUpdating App File Information - With the previoulsy uploaded file: ${huawei_filename}"

  curl --silent -X PUT \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-file-info?appId='"$huawei_app_id"'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'Content-Type: application/json' \
    -H 'client_id: '"${huawei_client_id}"'' \
    -H 'releaseType: '"${releaseType}"'' \
    -d '{
    "fileType":"5",
    "files":[
      {
        "fileName":"'${huawei_filename}'",
        "fileDestUrl":"'"${FILE_DEST_URL}"'",
        "size":"'"${FILE_SIZE}"'"
      }]
  }' > result.json

  printf "\nUpdating App File Information - With the previoulsy uploaded file - DONE"
}

function submitApp()
{  
  ACCESS_TOKEN=`jq -r '.access_token' token.json`

  if [ "${release_type}" == "By Phase" ] ;then
      submitAppPhaseMode
  else  
      submitAppDirectly
  fi 
}

function submitAppPhaseMode()
{  
  ACCESS_TOKEN=`jq -r '.access_token' token.json`
  RELEASE_TYPE=$( getReleaseTypeValue ) 
  JSON_STRING="{\"phasedReleaseStartTime\":\"$phase_release_start_time+0000\",\"phasedReleaseEndTime\":\"$phase_release_end_time+0000\",\"phasedReleaseDescription\":\"$phase_release_description\",\"phasedReleasePercent\":\"$phase_release_percentage\"}"

  curl --silent -X  POST \
  'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='"$huawei_app_id"'&releaseType='"${RELEASE_TYPE}" \
  -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
  -H 'Content-Type: application/json' \
  -H 'client_id: '"${huawei_client_id}"'' \
  -d  "${JSON_STRING}" > resultSubmission.json
} 

function submitAppDirectly()
{  
  ACCESS_TOKEN=`jq -r '.access_token' token.json`

  curl --silent -X  POST \
  'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='"$huawei_app_id"'' \
  -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
  -H 'client_id: '"${huawei_client_id}"''> resultSubmission.json
}

function showResponseOrSubmitCompletelyAgain()
{
  ACCESS_TOKEN=`jq -r '.access_token' token.json`
  RET_CODE=`jq -r '.ret.code' resultSubmission.json`
  RET_MESSAGE=`jq -r '.ret.msg' resultSubmission.json` 

  if [[ "${RET_CODE}" == 204144660 ]] && [[ "${RET_MESSAGE}" =~ "It may take 2-5 minutes" ]]  ;then
    getSubmissionStatus  
    SUBMISSION_STATUS=`jq -r '.aabCompileStatus' resultSubmissionStatus.json`
    printf "Submission Status ${SUBMISSION_STATUS}"
    i=0
    while (( "${SUBMISSION_STATUS}" == 1 && i < 16 ));
    do 
        sleep 20
        getSubmissionStatus  
        SUBMISSION_STATUS=`jq -r '.aabCompileStatus' resultSubmissionStatus.json`
        printf "\nBuild is currently processing, waiting 20 seconds before trying to submit again...\n" 
        ((i+=1))
    done

    if [ "${SUBMISSION_STATUS}" == 2 ]; then
        submitApp 
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
   'https://connect-api.cloud.huawei.com/api/publish/v2/aab/complile/status?appId='"${huawei_app_id}"'&pkgVersion='"${PKG_VERSION}"'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '"${huawei_client_id}"''> resultSubmissionStatus.json
}    

getToken  

getFileUploadUrl 

uploadFile 

updateAppFileInfo 

printf "\nSubmitting app...\n" 
submitApp 

if [ "${submit_for_review}" == "true" ]; then
  printf "\nApp submitted as a Draft - Pending to be Submitted for Review\n" 
  showResponseOrSubmitCompletelyAgain 
else 
  printf "\nApp successfully submitted as a Draft\n" 
fi

exit 0
