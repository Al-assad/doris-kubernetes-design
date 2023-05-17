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

# Base on https://github.com/apache/doris/blob/master/docker/runtime/fe/Dockerfile

# choose a base image
FROM openjdk:8u342-jdk

# set environment variables
ENV JAVA_HOME="/usr/local/openjdk-8/" \
	PATH="/opt/apache-doris/fe/bin:${PATH}"

# download the software to the mirror and replace it as needed
ADD ./resource/apache-doris-fe-x.x.x-bin.tar.gz /opt/

# choose platform-specific binary package
RUN if [[ "$TARGETPLATFORM" == "linux/amd64" ]]; then \
      ADD ./resource/apache-doris-fe-*-bin-x86_64.tar.gz /opt/ \
    elif [[ "$TARGETPLATFORM" == "linux/arm64*" ]]; then \
      ADD ./resource/apache-doris-fe-*-bin-arm.tar.gz /opt/ \
    else \
      echo "Unsupported platform: $TARGETPLATFORM"; exit 1; \
    fi

# deploy software
RUN apt-get update && \
	apt-get install -y default-mysql-client && \
	apt-get clean && \
	mkdir /opt/apache-doris && \
	cd /opt && \
	mv apache-doris-fe-* /opt/apache-doris/fe

ADD ../entrypoint_helper.sh /opt/apache-doris/fe/bin
ADD fe_entrypoint.sh /opt/apache-doris/fe/bin
RUN chmod 755 /opt/apache-doris/fe/bin/entrypoint_helper.sh
RUN chmod 755 /opt/apache-doris/fe/bin/fe_entrypoint.sh

ENTRYPOINT ["/opt/apache-doris/fe/bin/fe_entrypoint.sh"]