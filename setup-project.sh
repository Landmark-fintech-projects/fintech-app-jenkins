#!/bin/bash
#
# === CONFIGURATION ===
AWS_ACCOUNT_ID="805703880776"
AWS_REGION="us-east-1"
ECR_REPO_NAME="fintech-app"
EKS_NAMESPACE="fintech"
DOMAIN_NAME="shollztech.com"
APP_PORT=8080

# === GO TO PROJECT ROOT ===
cd "$(dirname "$0")/.." || exit

# === ENSURE DIRECTORIES EXIST ===
echo "📁 Creating folders..."
mkdir -p .github/workflows
mkdir -p k8s
mkdir -p scripts

echo "🚀 Generating Dockerfile..."
cat <<EOF > Dockerfile
FROM eclipse-temurin:17-jdk-alpine
WORKDIR /app
COPY target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF

echo "🧪 Creating GitHub Actions CI/CD workflow..."
cat <<EOF > .github/workflows/ci-cd.yml
name: CI-CD Pipeline

on:
  push:
    branches: [ main ]

env:
  AWS_REGION: $AWS_REGION
  ECR_REGISTRY: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
  ECR_REPO: $ECR_REPO_NAME

jobs:
  build:
    name: Build & Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Source
        uses: actions/checkout@v3

      - name: Set up JDK
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Build with Maven
        run: mvn clean package -DskipTests

      - name: SonarQube Scan
        uses: sonarsource/sonarqube-scan-action@master
        env:
          SONAR_TOKEN: \${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: \${{ secrets.SONAR_HOST_URL }}

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build and Push Docker image
        run: |
          IMAGE_TAG=\${{ github.sha }}
          docker build -t \$ECR_REGISTRY/\$ECR_REPO:\$IMAGE_TAG .
          docker push \$ECR_REGISTRY/\$ECR_REPO:\$IMAGE_TAG

  deploy:
    name: Deploy to EKS
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Configure kubectl
        uses: aws-actions/eks-setup-kubectl@v1
        with:
          cluster-name: dominion-cluster
          region: $AWS_REGION

      - name: Apply Kubernetes Resources
        run: |
          kubectl apply -n $EKS_NAMESPACE -f k8s/
EOF

echo "🌐 Creating Kubernetes manifests..."

# Web Deployment
cat <<EOF > k8s/web-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: $EKS_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: $EKS_NAMESPACE
spec:
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF

# App Deployment
cat <<EOF > k8s/app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: $EKS_NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: fintech-app
          image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:latest
          ports:
            - containerPort: $APP_PORT
---
apiVersion: v1
kind: Service
metadata:
  name: app
  namespace: $EKS_NAMESPACE
spec:
  selector:
    app: app
  ports:
    - port: $APP_PORT
      targetPort: $APP_PORT
  type: ClusterIP
EOF

# DB Deployment
cat <<EOF > k8s/db-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: $EKS_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
        - name: mysql
          image: mysql:8
          env:
            - name: MYSQL_ROOT_PASSWORD
              value: rootpass
            - name: MYSQL_DATABASE
              value: fintech
          ports:
            - containerPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: $EKS_NAMESPACE
spec:
  selector:
    app: db
  ports:
    - port: 3306
      targetPort: 3306
  type: ClusterIP
EOF

# ALB Ingress
cat <<EOF > k8s/alb-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alb-ingress
  namespace: $EKS_NAMESPACE
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    external-dns.alpha.kubernetes.io/hostname: $DOMAIN_NAME
spec:
  ingressClassName: alb
  rules:
    - host: $DOMAIN_NAME
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port:
                  number: $APP_PORT
EOF

echo "✅ All project files successfully generated!"
echo ""
echo "🔑 Next Steps:"
echo "1. Commit and push everything to your GitHub repo"
echo "2. Add GitHub secrets: SONAR_TOKEN, SONAR_HOST_URL, AWS credentials"
echo "3. Ensure EKS and ALB Ingress Controller are ready"
echo "4. Deploy your app using 'kubectl apply -f k8s/' 🚀"
