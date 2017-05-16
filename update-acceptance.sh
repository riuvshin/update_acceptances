#!/bin/bash

set -e

init() {
    for i in "${@}"
    do
        case $i in
           -u=*|--hub-username=*)
               HUB_USER="${i#*=}"
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
                echo "--acceptance=<ACCEPTANCE_ID>"
                echo "example: ./update-acceptance.sh --hub-username=riuvshin  --acceptance=a1"
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
    if [ -z ${ACCEPTANCE} ]; then echo "please pass an arg with acceptance id --acceptance=<ACCEPTANCE_ID>"; exit 2; fi

    if [[ $CLI_IMAGE_NAME == *"saas"* ]]; then
        CODENVY_DIR="saas"
        SAAS_POSTFIX="-saas"
        PRODUCT="saas"
    else
        CODENVY_DIR="codenvy"
        PRODUCT="onprem"
    fi

    CUSTOM_INIT_IMAGE="${HUB_USER}/init${SAAS_POSTFIX}:nightly"
    CUSTOM_AGENTS_IMAGE="${HUB_USER}/agents${SAAS_POSTFIX}:nightly"
    CUSTOM_CODENVY_IMAGE="${HUB_USER}/codenvy${SAAS_POSTFIX}:nightly"
    SSH_KEY=~/.ssh/admin.key

    if [ ! -f ${SSH_KEY} ]; then
        echo "ssh key for acceptance server is not found, please contact system administrator :)"
        exit 3
    fi
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
    docker tag codenvy/init${SAAS_POSTFIX}:nightly ${CUSTOM_INIT_IMAGE}
    docker tag codenvy/codenvy${SAAS_POSTFIX}:nightly ${CUSTOM_CODENVY_IMAGE}
    docker tag codenvy/agents${SAAS_POSTFIX}:nightly ${CUSTOM_AGENTS_IMAGE}
    # push
    docker push ${CUSTOM_INIT_IMAGE}
    docker push ${CUSTOM_CODENVY_IMAGE}
    docker push ${CUSTOM_AGENTS_IMAGE}
}

trigger_ci_job() {
    curl -X POST https://ci.codenvycorp.com/view/update/job/update-${ACCEPTANCE}/build?delay=0sec \
      --user ${CI_USER}:${CI_PASSWORD} \
      --data-urlencode json="{\"parameter\": [{\"name\":\"INIT_IMAGE_LOCATION\", \"value\":\"${CUSTOM_INIT_IMAGE}\"}, {\"name\":\"AGENTS_IMAGE_LOCATION\", \"value\":\"${CUSTOM_AGENTS_IMAGE}\"}, {\"name\":\"CODENVY_IMAGE_LOCATION\", \"value\":\"${CUSTOM_CODENVY_IMAGE}\"}, {\"name\":\"PRODUCT\", \"value\":\"${PRODUCT}\"}]}"
}

update_acceptance() {
    if [ "${PRODUCT}" == "saas" ]; then
        IMAGE_INIT="init-saas"
        IMAGE_AGENTS="agents-saas"
        IMAGE_CODENVY="codenvy-saas"
        IMAGE_CLI="cli-saas"
        LAUNCH_SKRIPT="codenvy.sh"
    else
        IMAGE_INIT="init"
        IMAGE_AGENTS="agents"
        IMAGE_CODENVY="codenvy"
        IMAGE_CLI="cli"
        LAUNCH_SKRIPT="codenvy-onprem.sh"
    fi

    #INIT
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker pull ${CUSTOM_INIT_IMAGE}"
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker tag ${CUSTOM_INIT_IMAGE} codenvy/${IMAGE_INIT}:nightly"
    #AGENTS
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker pull ${CUSTOM_AGENTS_IMAGE}"
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker tag ${CUSTOM_AGENTS_IMAGE} codenvy/${IMAGE_AGENTS}:nightly"
    #CODENVY
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker pull ${CUSTOM_CODENVY_IMAGE}"
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker tag ${CUSTOM_CODENVY_IMAGE} codenvy/${IMAGE_CODENVY}:nightly"
    #CLI
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "docker pull codenvy/${IMAGE_CLI}:nightly"
    #STOP
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "bash /home/codenvy/stop.sh"
    #START
    ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} codenvy@${ACCEPTANCE}.codenvy-stg.com "bash /home/codenvy/${LAUNCH_SKRIPT} start --skip:nightly --skip:pull"
}

init $@
dockerhub_login
build_and_push_images
update_acceptance
