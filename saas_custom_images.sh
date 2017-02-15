#!/bin/sh
# Copyright (c) 2016 Codenvy, S.A.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
set -e

HUB_USER=$1
if [ -z $HUB_USER ]; then echo "please pass your docker hub username as an arg"; exit 2; fi

is_logged=$(docker info | grep -c Username) || true
if [ $is_logged -ne 1 ]; then
    docker login
fi

sh dockerfiles/agents/build.sh --skip-update
sh dockerfiles/saas/build.sh
sh dockerfiles/init/build.sh

# retag
docker tag codenvy/init-saas:nightly $HUB_USER/init-saas:nightly
docker tag codenvy/codenvy-saas:nightly $HUB_USER/codenvy-saas:nightly
docker tag codenvy/agents-saas:nightly $HUB_USER/agents-saas:nightly
# push
docker push $HUB_USER/init-saas:nightly
docker push $HUB_USER/codenvy-saas:nightly
docker push $HUB_USER/agents-saas:nightly
