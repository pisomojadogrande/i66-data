#!/bin/bash

set -eo pipefail

usage() {
    echo "Usage: $0 -f <code_file> -b <bucket_name>" >&2
    exit 1
}

while getopts ":f:b:" o; do
    case "${o}" in
        f)
            CODE_FILE=${OPTARG}
            ;;
        b)
            BUCKET_NAME=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${CODE_FILE}" ] || [ ! -f "${CODE_FILE}" ] || [ -z "${BUCKET_NAME}" ]; then
    usage
fi

CODE_DIR=$(dirname "${CODE_FILE}")
CODE_FILE_NAME=$(basename "${CODE_FILE}")
SUFFIX=$(date +%Y-%m-%d-%H-%M-%S)
ZIPFILE_NAME=${CODE_FILE_NAME}-${SUFFIX}.zip
ZIPFILE_PATH=/tmp/${ZIPFILE_NAME}
S3_PATH=function/
S3_KEY=${S3_PATH}${ZIPFILE_NAME}
pushd $CODE_DIR
zip ${ZIPFILE_PATH} ${CODE_FILE_NAME}
popd
aws s3 cp ${ZIPFILE_PATH} s3://${BUCKET_NAME}/${S3_KEY}
rm $ZIPFILE_PATH
echo $S3_KEY

