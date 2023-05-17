# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Base on https://github.com/apache/doris/blob/master/docker/runtime/be/Dockerfile

# choose a base image
FROM --platform=$BUILDPLATFORM openjdk:8u342-jdk

# set environment variables
ENV JAVA_HOME="/usr/local/openjdk-8/" \
	PATH="/opt/apache-doris/be/bin:${PATH}"

# choose platform-specific binary package
RUN if [[ "$TARGETPLATFORM" == "linux/amd64" ]]; then \
      ADD ./resource/apache-doris-be-*-bin-x86_64.tar.gz /opt/ \
    elif [[ "$TARGETPLATFORM" == "linux/arm64*" ]]; then \
      ADD ./resource/apache-doris-be-*-bin-arm.tar.gz /opt/ \
    else \
      echo "Unsupported platform: $TARGETPLATFORM"; exit 1; \
    fi

# deploy software
RUN apt-get update && \
	apt-get install -y default-mysql-client && \
	apt-get clean && \
	mkdir /opt/apache-doris && \
	cd /opt && \
	mv apache-doris-be-* /opt/apache-doris/be

ADD ../entrypoint_helper.sh /opt/apache-doris/be/bin
ADD cn_entrypoint.sh /opt/apache-doris/be/bin
RUN chmod 755 /opt/apache-doris/be/bin/entrypoint_helper.sh
RUN chmod 755 /opt/apache-doris/be/bin/cn_entrypoint.sh

ENTRYPOINT ["bash","entry_point.sh"]