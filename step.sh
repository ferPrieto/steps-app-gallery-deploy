#!/usr/bin/env bash
# fail if any commands fail
set -e
# debug log
if [ "${show_debug_logs}" == "yes" ]; then
  set -x
fi

function getToken() {
  printf "\n\nObtaining a Token...\n"

  response=$(curl --silent -X POST \
    https://connect-api.cloud.huawei.com/api/oauth2/v1/token \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{
      "grant_type": "client_credentials",
      "client_id": "'${huawei_client_id}'",
      "client_secret": "'${huawei_client_secret}'"
  }' || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to obtain a token. Check your network connection and credentials 😢\n"
    exit 1
  fi

  echo "$response" >token.json

  CODE=$(jq -r '.ret.code' token.json)
  if [ "${CODE}" != "null" ] && [ "${CODE}" != "0" ]; then
    printf "\n ❌ Failed to obtain a token 😢\n"
    echo "$response"
    exit 1
  fi

  printf "Obtaining a Token ✅\n"
}

function getFileUploadUrl() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)
  FILE_EXT="${file_path##*.}"
  RELEASE_TYPE=$(getReleaseTypeValue)

  printf "\nObtaining the File Upload URL...\n"

  response=$(curl --silent -X GET \
    'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url?appId='"${huawei_app_id}"'&suffix='"${FILE_EXT}"'&releaseType='"${RELEASE_TYPE}" \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '"${huawei_client_id}"'' || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to obtain the file upload URL. Check your network connection and parameters 😢\n"
    exit 1
  fi

  echo "$response" >uploadurl.json

  CODE=$(jq -r '.ret.code' uploadurl.json)
  if [ "${CODE}" != "null" ] && [ "${CODE}" != "0" ]; then
    printf "\n ❌ Failed to obtain the file upload URL. 😢\n"
    echo "$response"
    exit 1
  fi

  printf "Obtaining the File Upload URL ✅\n"
}

function getReleaseTypeValue() {
  if [ "${release_type}" == "By Phase" ]; then
    releaseTypeValue=3
  else
    releaseTypeValue=1
  fi

  echo $releaseTypeValue
}

function uploadFile() {
  UPLOAD_URL=$(jq -r '.uploadUrl' uploadurl.json)
  UPLOAD_AUTH_CODE=$(jq -r '.authCode' uploadurl.json)

  printf "\nUploading a File...\n"

  
  if [ ! -f "$filename" ]; then
      printf "\n ❌ File '$filename' does not exist 😢\n"
      exit 1
  fi

  response=$(curl --silent -X POST \
    "${UPLOAD_URL}" \
    -H 'Accept: application/json' \
    -F authCode="${UPLOAD_AUTH_CODE}" \
    -F fileCount=1 \
    -F parseType=1 \
    -F file="@${file_path}" || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to upload the file. Check your network connection and file path 😢\n"
    exit 1
  fi

  echo "$response" >uploadfile.json

  CODE=$(jq -r '.result.UploadFileRsp.ifSuccess' uploadfile.json)
  if [ "${CODE}" != "1" ]; then
    printf "\n ❌ Failed to upload the file.. 😢\n"
    echo "$response"
    exit 1
  fi

  printf "Uploading a File ✅\n"
}

function updateAppFileInfo() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)
  FILE_DEST_URL=$(jq -r '.result.UploadFileRsp.fileInfoList[0].fileDestUlr' uploadfile.json)
  FILE_SIZE=$(jq -r '.result.UploadFileRsp.fileInfoList[0].size' uploadfile.json)

  printf "\nUpdating App File Information - With the previously uploaded file: '${huawei_filename}'\n"

  response=$(curl --silent -X PUT \
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
  }' || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to update app file information. Check your network connection and parameters 😢\n"
    exit 1
  fi

  echo "$response" >result.json

  CODE=$(jq -r '.ret.code' result.json)
  if [ "${CODE}" != "0" ]; then
    printf "\n ❌ Failed to update app file information 😢\n"
    echo "$response"
    exit 1
  fi

  printf "Updating App File Information - With the previously uploaded file ✅\n"
}

function submitApp() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)

  if [ "${release_type}" == "By Phase" ]; then
    submitAppPhaseMode
  else
    submitAppDirectly
  fi
}

function submitAppPhaseMode() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)
  RELEASE_TYPE=$(getReleaseTypeValue)
  JSON_STRING="{\"phasedReleaseStartTime\":\"$phase_release_start_time+0000\",\"phasedReleaseEndTime\":\"$phase_release_end_time+0000\",\"phasedReleaseDescription\":\"$phase_release_description\",\"phasedReleasePercent\":\"$phase_release_percentage\"}"

  printf "\nSubmitting the app in phased release mode...\n"

  response=$(curl --silent -X POST \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='"$huawei_app_id"'&releaseType='"${RELEASE_TYPE}" \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'Content-Type: application/json' \
    -H 'client_id: '"${huawei_client_id}"'' \
    -d "${JSON_STRING}" || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to submit the app in phased release mode. Check your network connection and parameters 😢\n"
    exit 1
  fi

  echo "$response" >resultSubmission.json
}

function submitAppDirectly() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)

  printf "\nSubmitting the app directly...\n"

  response=$(curl --silent -X POST \
    'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit?appid='"$huawei_app_id"'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '"${huawei_client_id}"'' || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to submit the app directly. Check your network connection and parameters 😢\n"
    exit 1
  fi

  echo "$response" >resultSubmission.json
}

function getSubmissionStatus() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)
  PKG_VERSION=$(jq -r '.pkgVersion[0]' result.json)

  printf "\nGetting submission status...\n"

  response=$(curl --silent -X GET \
    'https://connect-api.cloud.huawei.com/api/publish/v2/aab/complile/status?appId='"${huawei_app_id}"'&pkgVersion='"${PKG_VERSION}"'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '"${huawei_client_id}"'' || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to get submission status. Check your network connection and parameters 😢\n"
    exit 1
  fi

  echo "$response" >resultSubmissionStatus.json
}

function showResponseOrSubmitCompletelyAgain() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)
  RET_CODE=$(jq -r '.ret.code' resultSubmission.json)
  RET_MESSAGE=$(jq -r '.ret.msg' resultSubmission.json)

  if [[ "${RET_CODE}" == 204144727 ]]; then
    getSubmissionStatus
    SUBMISSION_STATUS=$(jq -r '.aabCompileStatus' resultSubmissionStatus.json)
    printf "Submission Status ${SUBMISSION_STATUS}"
    i=0
    while (("${SUBMISSION_STATUS}" == 1 && i < 16)); do
      sleep 20
      getSubmissionStatus
      SUBMISSION_STATUS=$(jq -r '.aabCompileStatus' resultSubmissionStatus.json)
      printf "\nBuild is currently processing, waiting 20 seconds ⏱️ before trying to submit again...\n"
      ((i += 1))
    done

    if [ "${SUBMISSION_STATUS}" == 2 ]; then
      submitApp
      CODE=$(jq -r '.ret.code' resultSubmission.json)
      MESSAGE=$(jq -r '.ret.msg' resultSubmission.json)

      printf "\nFinal SubmitRetCode - ${CODE}\n"
      printf "\nFinal SubmitRetMessage - ${MESSAGE}\n"
    else
      printf "\n❌ FAILED to submit the App for Review 😢\n"
    fi

  elif [[ "${RET_CODE}" == 0 ]]; then
    printf "\n🤩 App SUCCESSFULLY SUBMITTED for Review 🎉🎊\n"
  else
    printf "\n ❌ FAILED to submit the App for Review 😢\n"
    printf "${RET_MESSAGE}"
  fi
}

function getSubmissionStatus() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)
  PKG_VERSION=$(jq -r '.pkgVersion[0]' result.json)

  printf "\nGetting submission status...\n"

  response=$(curl --silent -X GET \
    'https://connect-api.cloud.huawei.com/api/publish/v2/aab/complile/status?appId='"${huawei_app_id}"'&pkgVersion='"${PKG_VERSION}"'' \
    -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
    -H 'client_id: '"${huawei_client_id}"'' || true)

  if [[ -z "$response" ]]; then
    printf "\n ❌ Failed to get submission status. Check your network connection and parameters 😢\n"
    exit 1
  fi

  echo "$response" >resultSubmissionStatus.json
}

getToken

getFileUploadUrl

uploadFile

updateAppFileInfo

printf "\nSubmitting app as a Draft...⏳\n"

if [ "${submit_for_review}" == "true" ]; then
  submitApp
  showResponseOrSubmitCompletelyAgain
else
  printf "\n🤩 App successfully submitted as a Draft 🎉\n"
fi

exit 0
