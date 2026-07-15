# Stage 1: Build the application
FROM gradle:8.12-jdk21 AS build
COPY --chown=gradle:gradle . /home/gradle/src
WORKDIR /home/gradle/src
RUN ./gradlew buildFatJar --no-daemon || ./gradlew installDist --no-daemon

# Stage 2: Create runtime image with FFmpeg
FROM eclipse-temurin:21-jre-noble

# Install FFmpeg
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 8080

WORKDIR /app

# Copy build artifacts from the builder stage
# (Adjust source path depending on your Ktor build plugin output, e.g., fat JAR or installDist)
COPY --from=build /home/gradle/src/build/libs/*-all.jar /app/server.jar

CMD ["java", "-jar", "/app/server.jar", "-config=application.docker.yaml"]