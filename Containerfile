# SPDX-License-Identifier: Apache-2.0
#
# Builds the image that builds the fpsot.org website. It holds JDK 25, Maven and a Maven
# repository with the Quarkus and Roq builds the site needs, until their fixes for large
# sites are released upstream:
#   - Quarkus: quarkusio/quarkus#58090 (Qute template data), on the 3.40 branch;
#   - Roq: quarkiverse/quarkus-roq#1312 and #1340 (large sites), on 2.2.0.
# The site selects them with:
#   -Dquarkus.platform.group-id=io.quarkus -Dquarkus.platform.version=3.40.999-SNAPSHOT
#   -Droq.version=2.2.1-sitenetsoft-SNAPSHOT
# The image sets these in FPSOT_SITE_MAVEN_ARGS.

FROM docker.io/library/maven:3.9-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
ARG QUARKUS_REPO=https://github.com/SiteNetSoft/quarkus.git
ARG QUARKUS_REF=37e430ca9a142134f7b2dc83c51474694212391d
ARG ROQ_REPO=https://github.com/SiteNetSoft/quarkus-roq.git
ARG ROQ_REF=c37fd663e2a1fb07ec842a6cad2f962f2842d261
ENV MAVEN_OPTS="-Xmx4g -XX:ReservedCodeCacheSize=512m"
# First the modules that Quarkus's own build uses as plugins (-am does not follow
# plugin dependencies), then the Quarkus modules that the site and the Roq build use,
# with what they need (-am).
RUN git init -q /src/quarkus && cd /src/quarkus \
 && git fetch -q --depth 1 "$QUARKUS_REPO" "$QUARKUS_REF" && git checkout -q FETCH_HEAD \
 && mvn -B -q install -Dquickly -Dskip.gradle.build=true \
      -pl independent-projects/ide-config,independent-projects/enforcer-rules,independent-projects/extension-maven-plugin,independent-projects/resteasy-reactive/build-support -am \
 && mvn -B -q install -Dquickly -Dskip.gradle.build=true -T 4 \
      -pl bom/application,core/builder,core/class-change-agent,core/deployment,core/devmode-spi,core/launcher,core/runtime,devtools/config-doc-maven-plugin,devtools/maven,extensions/arc/deployment,extensions/arc/runtime,extensions/arc/runtime-dev,extensions/arc/test-supplement,extensions/arc/test-supplement-decorator,extensions/assistant/deployment,extensions/assistant/runtime-dev,extensions/cache/deployment-spi,extensions/credentials/deployment,extensions/credentials/runtime,extensions/devui/deployment-spi,extensions/devui/runtime-spi,extensions/hibernate-validator/spi,extensions/jackson/deployment,extensions/jackson/runtime,extensions/jackson/spi,extensions/jsonp/runtime,extensions/kubernetes/spi,extensions/mutiny/deployment,extensions/mutiny/runtime,extensions/netty/deployment,extensions/netty/runtime,extensions/panache/panache-common/deployment,extensions/panache/panache-common/runtime,extensions/qute/deployment,extensions/qute/runtime,extensions/resteasy-reactive/rest-common/runtime,extensions/resteasy-reactive/rest-common/spi-deployment,extensions/resteasy-reactive/rest-qute/runtime,extensions/resteasy-reactive/rest/runtime,extensions/security/runtime,extensions/security/runtime-spi,extensions/security/spi,extensions/smallrye-context-propagation/deployment,extensions/smallrye-context-propagation/runtime,extensions/smallrye-context-propagation/spi,extensions/tls-registry/deployment,extensions/tls-registry/deployment-spi,extensions/tls-registry/runtime,extensions/tls-registry/spi,extensions/vertx-http/deployment,extensions/vertx-http/deployment-spi,extensions/vertx-http/runtime,extensions/vertx/deployment,extensions/vertx/deployment-spi,extensions/vertx/latebound-mdc-provider,extensions/vertx/runtime,extensions/virtual-threads/deployment,extensions/virtual-threads/runtime,independent-projects/arc/processor,independent-projects/arc/runtime,independent-projects/bootstrap/app-model,independent-projects/bootstrap/classloader-commons,independent-projects/bootstrap/core,independent-projects/bootstrap/gradle-resolver,independent-projects/bootstrap/json,independent-projects/bootstrap/maven-resolver,independent-projects/bootstrap/maven4-resolver,independent-projects/bootstrap/runner,independent-projects/bootstrap/value-registry,independent-projects/qute/core,independent-projects/qute/generator,independent-projects/resteasy-reactive/common/runtime,independent-projects/resteasy-reactive/common/types,independent-projects/resteasy-reactive/server/runtime,independent-projects/resteasy-reactive/server/vertx,independent-projects/vertx-utils,test-framework/common,test-framework/junit,test-framework/junit-common,test-framework/junit-config,test-framework/junit-internal \
      -am \
 && cd / && rm -rf /src/quarkus
RUN git init -q /src/roq && cd /src/roq \
 && git fetch -q --depth 1 "$ROQ_REPO" "$ROQ_REF" && git checkout -q FETCH_HEAD \
 && mvn -B -q install -DskipTests -Dmaven.javadoc.skip=true -Dquarkus.version=3.40.999-SNAPSHOT \
      -pl roq/deployment,roq-plugin/asciidoc-jruby/deployment -am \
 && cd / && rm -rf /src/roq

FROM docker.io/library/maven:3.9-eclipse-temurin-25@sha256:93b8a14ea2f412782e4e842651273b4d903e35cc496284f178fbbe2d67d00976
LABEL org.opencontainers.image.source=https://github.com/fpsot-org/fpsot-website-builder \
      org.opencontainers.image.description="Builds the fpsot.org website" \
      org.opencontainers.image.licenses=Apache-2.0
COPY --from=build /root/.m2/repository /root/.m2/repository
ENV FPSOT_SITE_MAVEN_ARGS="-Dquarkus.platform.group-id=io.quarkus -Dquarkus.platform.version=3.40.999-SNAPSHOT -Droq.version=2.2.1-sitenetsoft-SNAPSHOT"
# Building a small site once checks that the image holds everything and fetches the rest.
COPY warmup /warmup
RUN cd /warmup && QUARKUS_ROQ_GENERATOR_BATCH=true mvn -B -q $FPSOT_SITE_MAVEN_ARGS package quarkus:run \
 && test -f target/roq/page/index.html && grep -q 'Warm-up page' target/roq/page/index.html \
 && cd / && rm -rf /warmup
