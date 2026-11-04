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
# The Quarkus extensions the site uses, with what they need (-am).
RUN git init -q /src/quarkus && cd /src/quarkus \
 && git fetch -q --depth 1 "$QUARKUS_REPO" "$QUARKUS_REF" && git checkout -q FETCH_HEAD \
 && ./mvnw -B -q -Dquickly -Dskip.gradle.build=true -T 4 \
      -pl bom/application,devtools/maven,core/deployment,extensions/arc/deployment,extensions/qute/deployment,extensions/vertx-http/deployment,extensions/vertx/deployment,extensions/netty/deployment,extensions/mutiny/deployment,extensions/jackson/deployment,extensions/smallrye-context-propagation/deployment,extensions/virtual-threads/deployment,extensions/tls-registry/deployment,extensions/credentials/deployment \
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
