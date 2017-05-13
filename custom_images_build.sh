#!/bin/sh

set -e

init() {
    if [ -d dockerfiles ]; then
        CLI_IMAGE_NAME=$(cat dockerfiles/cli/build.sh | grep IMAGE_NAME)
    else
        echo "script should be executed inside of a project"
        exit 1
    fi
    HUB_USER=$1
    if [ -z ${HUB_USER} ]; then echo "please pass your docker hub username as an arg"; exit 2; fi

    if [[ $CLI_IMAGE_NAME == *"saas"* ]]; then
        CODENVY_DIR="saas"
        SAAS_POSTFIX="-saas"
        PRODUCT="saas"
    else
        CODENVY_DIR="codenvy"
        PRODUCT="onprem"
    fi
    ACCEPTANCE="a1"
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
    curl -X POST https://ci.codenvycorp.com/view/update/job/update-${ACCEPTANCE}/buildWithParameters?token=build \
      --data-urlencode json="{\"parameter\": [{\"name\":\"INIT_IMAGE_LOCATION\", \"value\":\"${INIT_IMAGE}\"}, {\"name\":\"AGENTS_IMAGE_LOCATION\", \"value\":\"${AGENTS_IMAGE}\"}, {\"name\":\"CODENVY_IMAGE_LOCATION\", \"value\":\"${CODENVY_IMAGE}\"}, {\"name\":\"PRODUCT\", \"value\":\"${PRODUCT}\"}]}"
}


init $@
dockerhub_login
build_and_push_images
#TODO
#trigger_ci_job
