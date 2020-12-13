#!/usr/bin/env bash
# fail if any commands fails
set -e
# debug log
if [ "${show_debug_logs}" == "yes" ]; then
  set -x
fi

#Setup env vars
LANG="${lang}"
FILENAME_TO_UPLOAD="${huawei_filename}"
FILE_EXT="${file_path##*.}"

printf "File path is: ${file_path}\n"
printf "Lang is: ${LANG}\n"
printf "File extension is ${FILE_EXT}\n"

printf "\n\nObtaining a Token\n"
curl --silent -X POST \
  https://connect-api.cloud.huawei.com/api/oauth2/v1/token \
  -H 'Content-Type: application/json' \
  -H 'cache-control: no-cache' \
  -d '{
    "grant_type": "client_credentials",
    "client_id": "'"${huawei_client_id}"'",
    "client_secret": "'"${huawei_client_secret}"'"
}' > token.json

ACCESS_TOKEN=`jq -r '.access_token' token.json`
printf "Obtaining a Token - Done\n"

printf "huawei_app_id - ${APP_ID}\n"
printf "ACCESS_TOKEN - ${ACCESS_TOKEN}\n" 

printf "\nObtaining the File Upload URL\n"
curl --silent -X GET \
  'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url?appId='"${huawei_app_id}"'&suffix='"${FILE_EXT}" \
  -H 'Authorization: Bearer '"${ACCESS_TOKEN}"'' \
  -H 'client_id: '"${huawei_client_id}"'' > uploadurl.json

UPLOAD_URL=`jq -r '.uploadUrl' uploadurl.json`
UPLOAD_AUTH_CODE=`jq -r '.authCode' uploadurl.json` 

printf "Obtaining the File Upload URL - Done\n"

printf "\nUploading a File\n"
curl --silent -X POST \
  "${UPLOAD_URL}" \
  -H 'Accept: application/json' \
  -F authCode="${UPLOAD_AUTH_CODE}" \
  -F fileCount=1 \
  -F parseType=1 \
  -F file=@"${file_path}" > uploadfile.json

FILE_DEST_URL=`jq -r '.result.UploadFileRsp.fileInfoList[0].fileDestUlr' uploadfile.json`
FILE_SIZE=`jq -r '.result.UploadFileRsp.fileInfoList[0].size' uploadfile.json`

printf "Uploading a File - Done\n"  

printf "\nUpdating App File Information - add previoulsy uploaded file\nFileName: ${FILENAME_TO_UPLOAD}"
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
			"fileName":"'"$FILENAME_TO_UPLOAD"'",
			"fileDestUrl":"'"$FILE_DEST_URL"'",
		  "size":"'"$FILE_SIZE"'"
		}]
}' > result.json

FILE_UPLOAD_CODE=`jq -r '.ret.code' result.json`
FILE_UPLOAD_MSG=`jq -r '.ret.msg' result.json`

printf "\nUpdating App File Information - Done\n"
printf "Message:${FILE_UPLOAD_MSG}\n"
printf "Code: ${FILE_UPLOAD_CODE}\n"

exit "${FILE_UPLOAD_CODE}"
