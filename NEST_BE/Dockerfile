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
ENTRYPOINT ["java", "-jar", "app.jar"]
