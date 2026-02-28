# -------- STAGE 1: Build the application --------
FROM maven:3.9.11-eclipse-temurin-17-alpine AS build

WORKDIR /build

# Copy Maven project files and download dependencies first
COPY pom.xml .
COPY src ./src

# Package application
RUN mvn clean package -DskipTests

# -------- STAGE 2: Create minimal runtime image --------
FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

# Copy only the final JAR from build stage
COPY --from=build /build/target/*.jar app.jar

# Default command
ENTRYPOINT ["java", "-jar", "app.jar"]
