# Build only the monolith module (and its "common" dependency) - the reactor also lists a bunch
# of standalone microservices left over from an earlier design that were never built out; -pl -am
# skips building/testing those entirely so this stays fast and doesn't fail on unrelated modules.
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY . .
RUN mvn -q -pl monolith -am -DskipTests package

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY --from=build /app/monolith/target/*.jar app.jar
EXPOSE 8081

# Without explicit limits the JVM's container-aware defaults overshoot Render's 512Mi plan and the
# container gets OOM-killed ("Out of memory (used over 512Mi)") right after startup. The container
# is charged for the JVM's WHOLE footprint, not just heap, so every region is capped below.
# Measured with Native Memory Tracking under concurrent load: ~400Mi total committed, leaving
# roughly 100Mi of headroom for RSS overhead the JVM doesn't account for (glibc arenas, the binary
# itself).
#
# Sizes are deliberate, not guesses:
#   Xmx224m               heap; the app is comfortable here and it's the single biggest region.
#   MaxMetaspaceSize=192m NOT smaller - Spring/Hibernate generate enough proxies and JIT metadata
#                         at runtime that 96m dies with "OutOfMemoryError: Metaspace" under load.
#                         It's a cap, not a reservation, so unused headroom costs nothing.
#   ReservedCodeCacheSize/MaxDirectMemorySize   caps on JIT output and NIO buffers, both of which
#                         otherwise size themselves off the host, not the container.
#   UseSerialGC           far less fixed overhead than G1 at this size (Temurin's own guidance for
#                         sub-2GB containers), and this workload doesn't need parallel collection.
#   ExitOnOutOfMemoryError  die immediately instead of limping along in GC thrash, so Render's
#                         restart is a clean one rather than a half-responsive instance.
# MALLOC_ARENA_MAX caps glibc's per-thread arenas, which otherwise scale with CPU count and can add
# well over 100Mi of RSS that never shows up in JVM-level metrics.
ENV MALLOC_ARENA_MAX=2
ENTRYPOINT ["java", \
    "-Xmx224m", \
    "-Xss512k", \
    "-XX:MaxMetaspaceSize=192m", \
    "-XX:ReservedCodeCacheSize=64m", \
    "-XX:MaxDirectMemorySize=48m", \
    "-XX:+UseSerialGC", \
    "-XX:+ExitOnOutOfMemoryError", \
    "-jar", "app.jar"]
