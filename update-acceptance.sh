#!/bin/sh

set -e

init() {
for i in "${@}"
do
case $i in
       -du=*|--hub-username=*)
          HUB_USER="${i#*=}"
          shift
       ;;
       -ciu=*|--ci-username=*)
           CI_USER="${i#*=}"
           shift
       ;;
       -cip=*|--ci-password=*)
           CI_PASSWORD="${i#*=}"
           shift
       ;;
       -a=*|--acceptance=*)
           ACCEPTANCE="${i#*=}"
           shift
       ;;
       *)
            echo "You've passed unknown option"
            echo "possible options are:"
            echo "--hub-username=<YOUR_DOCKER_HUB_USERNAME>"
            echo "--ci-username=<YOUR_CI_USERNAME>"
            echo "--ci-password=<YOUR_CI_PASSWORD>"
            echo "--acceptance=<ACCEPTANCE_ID>"
            echo "example: ./update-acceptance.sh --hub-username=riuvshin --ci-username=riuvshin --ci-password=password --acceptance=a1"
            exit 2
            ;;
        esac
    done

    if [ -d dockerfiles ]; then
        CLI_IMAGE_NAME=$(cat dockerfiles/cli/build.sh | grep IMAGE_NAME)
    else
        echo "script should be executed inside of a project"
        exit 1
    fi

    if [ -z ${HUB_USER} ]; then echo "please pass an arg with your docker hub username --hub-username=<YOUR_DOCKER_HUB_USERNAME>"; exit 2; fi
    if [ -z ${CI_USER} ]; then echo "please pass an arg with your ci username --ci-username=<YOUR_CI_USERNAME>"; exit 2; fi
    if [ -z ${CI_PASSWORD} ]; then echo "please pass an arg with your ci password --ci-password=<YOUR_CI_PASSWORD>"; exit 2; fi
    if [ -z ${ACCEPTANCE} ]; then echo "please pass an arg with acceptance id --acceptance=<ACCEPTANCE_ID>"; exit 2; fi

    if [[ $CLI_IMAGE_NAME == *"saas"* ]]; then
        CODENVY_DIR="saas"
        SAAS_POSTFIX="-saas"
        PRODUCT="saas"
    else
        CODENVY_DIR="codenvy"
        PRODUCT="onprem"
    fi
    INIT_IMAGE="${HUB_USER}/init${SAAS_POSTFIX}:nightly"
    AGENTS_IMAGE="${HUB_USER}/agents${SAAS_POSTFIX}:nightly"
    CODENVY_IMAGE="${HUB_USER}/codenvy${SAAS_POSTFIX}:nightly"
}

dockerhub_login() {
    local is_logged=$(cat ~/.docker/config.json | grep -c index.docker.io) || true
    if [ $is_logged -ne 1 ]; then
        echo "\033[0;31mPlease login to hub.docker.com\033[0m"
        docker login
    fi
}

build_and_push_images() {
    docker pull codenvy/init:nightly
    sh dockerfiles/agents/build.sh --skip-update
    sh dockerfiles/${CODENVY_DIR}/build.sh
    sh dockerfiles/init/build.sh
    # retag
    docker tag codenvy/init${SAAS_POSTFIX}:nightly ${INIT_IMAGE}
    docker tag codenvy/codenvy${SAAS_POSTFIX}:nightly ${CODENVY_IMAGE}
    docker tag codenvy/agents${SAAS_POSTFIX}:nightly ${AGENTS_IMAGE}
    # push
    docker push ${INIT_IMAGE}
    docker push ${CODENVY_IMAGE}
    docker push ${AGENTS_IMAGE}
    echo ""
    echo "============"
    echo "your images:"
    echo ${INIT_IMAGE}
    echo ${CODENVY_IMAGE}
    echo ${AGENTS_IMAGE}
}

trigger_ci_job() {
    curl -X POST https://ci.codenvycorp.com/view/update/job/update-${ACCEPTANCE}/build?delay=0sec \
      --user ${CI_USER}:${CI_PASSWORD} \
      --data-urlencode json="{\"parameter\": [{\"name\":\"INIT_IMAGE_LOCATION\", \"value\":\"${INIT_IMAGE}\"}, {\"name\":\"AGENTS_IMAGE_LOCATION\", \"value\":\"${AGENTS_IMAGE}\"}, {\"name\":\"CODENVY_IMAGE_LOCATION\", \"value\":\"${CODENVY_IMAGE}\"}, {\"name\":\"PRODUCT\", \"value\":\"${PRODUCT}\"}]}"
}


init $@
dockerhub_login
build_and_push_images
trigger_ci_job
#TODO print update logs from ci