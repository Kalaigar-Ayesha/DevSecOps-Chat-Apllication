pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_REPO = 'chat-app'
        NODE_VERSION = '20'
        KUBECONFIG = credentials('kubeconfig')
        SLACK_WEBHOOK = credentials('slack-webhook')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
        timestamps()
        ansiColor('xterm')
    }
    
    triggers {
        pollSCM('H/5 * * * *')
        githubPush()
    }
    
    stages {
        stage('Preparation') {
            steps {
                script {
                    env.BUILD_TAG_SHORT = env.BUILD_TAG.replaceAll(/[^a-zA-Z0-9-]/, '-').toLowerCase()
                    env.IMAGE_TAG = env.BUILD_NUMBER
                    env.GIT_COMMIT_SHORT = env.GIT_COMMIT.take(8)
                }
                echo "Building ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
                echo "Git Commit: ${env.GIT_COMMIT_SHORT}"
                echo "Branch: ${env.GIT_BRANCH}"
            }
        }
        
        stage('Code Quality') {
            parallel {
                stage('Backend Quality') {
                    steps {
                        dir('backend') {
                            sh 'npm ci --silent'
                            sh 'npm audit --audit-level moderate'
                            sh 'npm run lint || true'
                            sh 'npm run test:coverage'
                        }
                    }
                    post {
                        always {
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'backend/coverage',
                                reportFiles: 'lcov-report/index.html',
                                reportName: 'Backend Coverage Report'
                            ])
                        }
                    }
                }
                
                stage('Frontend Quality') {
                    steps {
                        dir('frontend') {
                            sh 'npm ci --silent'
                            sh 'npm audit --audit-level moderate'
                            sh 'npm run lint || true'
                            sh 'npm run test:coverage'
                        }
                    }
                    post {
                        always {
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'frontend/coverage',
                                reportFiles: 'index.html',
                                reportName: 'Frontend Coverage Report'
                            ])
                        }
                    }
                }
            }
        }
        
        stage('Build & Security Scan') {
            steps {
                parallel {
                    stage('Backend Build') {
                        steps {
                            dir('backend') {
                                sh 'npm ci --production --silent'
                                script {
                                    def backendImage = docker.build("${DOCKER_REGISTRY}/${DOCKER_REPO}-backend:${IMAGE_TAG}", "./backend")
                                    docker.withRegistry("https://${DOCKER_REGISTRY}", 'dockerhub-credentials') {
                                        backendImage.push()
                                        if (env.GIT_BRANCH == 'main') {
                                            backendImage.push('latest')
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    stage('Frontend Build') {
                        steps {
                            dir('frontend') {
                                sh 'npm ci --silent'
                                sh 'npm run build'
                                script {
                                    def frontendImage = docker.build("${DOCKER_REGISTRY}/${DOCKER_REPO}-frontend:${IMAGE_TAG}", "./frontend")
                                    docker.withRegistry("https://${DOCKER_REGISTRY}", 'dockerhub-credentials') {
                                        frontendImage.push()
                                        if (env.GIT_BRANCH == 'main') {
                                            frontendImage.push('latest')
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            post {
                success {
                    archiveArtifacts artifacts: 'frontend/dist/**', fingerprint: true
                }
            }
        }
        
        stage('Deploy') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                script {
                    def namespace = env.GIT_BRANCH == 'main' ? 'production' : 'staging'
                    
                    // Update Kubernetes manifests
                    sh "sed -i 's|image: .*backend:.*|image: ${DOCKER_REGISTRY}/${DOCKER_REPO}-backend:${IMAGE_TAG}|' kubernetes/backend-deployment.yaml"
                    sh "sed -i 's|image: .*frontend:.*|image: ${DOCKER_REGISTRY}/${DOCKER_REPO}-frontend:${IMAGE_TAG}|' kubernetes/frontend-deployment.yaml"
                    
                    // Apply to Kubernetes
                    sh "kubectl apply -f kubernetes/ -n ${namespace}"
                    sh "kubectl rollout status deployment/backend -n ${namespace} --timeout=300s"
                    sh "kubectl rollout status deployment/frontend -n ${namespace} --timeout=300s"
                    
                    echo "Deployed to ${namespace} namespace"
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                script {
                    def namespace = env.GIT_BRANCH == 'main' ? 'production' : 'staging'
                    def serviceUrl = sh(script: "kubectl get svc frontend -n ${namespace} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()
                    
                    if (!serviceUrl) {
                        serviceUrl = sh(script: "kubectl get svc frontend -n ${namespace} -o jsonpath='{.spec.clusterIP}'", returnStdout: true).trim()
                    }
                    
                    dir('tests/api') {
                        sh "npm install -g newman"
                        sh "newman run postman-collection.json --environment '{\"baseUrl\": \"http://${serviceUrl}\"}' --reporters cli,junit --reporter-junit-export integration-results.xml"
                    }
                }
            }
            post {
                always {
                    publishJUnit 'tests/api/integration-results.xml'
                }
            }
        }
        
        stage('Performance Tests') {
            when {
                branch 'main'
            }
            steps {
                script {
                    def namespace = 'production'
                    def serviceUrl = sh(script: "kubectl get svc frontend -n ${namespace} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()
                    
                    if (!serviceUrl) {
                        serviceUrl = sh(script: "kubectl get svc frontend -n ${namespace} -o jsonpath='{.spec.clusterIP}'", returnStdout: true).trim()
                    }
                    
                    dir('tests/performance') {
                        writeFile file: 'load-test.yml', text: """
config:
  target: 'http://${serviceUrl}'
  phases:
    - duration: 60
      arrivalRate: 10
      name: "Warm up"
    - duration: 120
      arrivalRate: 50
      name: "Load test"
    - duration: 60
      arrivalRate: 100
      name: "Stress test"
scenarios:
  - name: "Health check"
    weight: 50
    flow:
      - get:
          url: "/health"
  - name: "API endpoints"
    weight: 50
    flow:
      - get:
          url: "/api/messages"
"""
                        sh 'npm install -g artillery'
                        sh 'artillery run load-test.yml --output artillery-results.json'
                        sh 'artillery report artillery-results.json --output artillery-report.html'
                    }
                }
            }
            post {
                always {
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'tests/performance',
                        reportFiles: 'artillery-report.html',
                        reportName: 'Performance Test Report'
                    ])
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        
        success {
            script {
                if (env.SLACK_WEBHOOK) {
                    slackSend(
                        channel: '#deployments',
                        color: 'good',
                        message: """✅ *Pipeline Success*
📦 *Job*: ${env.JOB_NAME}
🔢 *Build*: ${env.BUILD_NUMBER}
🌿 *Branch*: ${env.GIT_BRANCH}
📝 *Commit*: ${env.GIT_COMMIT_SHORT}
🚀 *Deployed to*: ${env.GIT_BRANCH == 'main' ? 'Production' : 'Staging'}
"""
                    )
                }
            }
        }
        
        failure {
            script {
                if (env.SLACK_WEBHOOK) {
                    slackSend(
                        channel: '#deployments',
                        color: 'danger',
                        message: """❌ *Pipeline Failed*
📦 *Job*: ${env.JOB_NAME}
🔢 *Build*: ${env.BUILD_NUMBER}
🌿 *Branch*: ${env.GIT_BRANCH}
📝 *Commit*: ${env.GIT_COMMIT_SHORT}
🔗 *Build URL*: ${env.BUILD_URL}
"""
                    )
                }
            }
        }
        
        unstable {
            script {
                if (env.SLACK_WEBHOOK) {
                    slackSend(
                        channel: '#deployments',
                        color: 'warning',
                        message: """⚠️ *Pipeline Unstable*
📦 *Job*: ${env.JOB_NAME}
🔢 *Build*: ${env.BUILD_NUMBER}
🌿 *Branch*: ${env.GIT_BRANCH}
📝 *Commit*: ${env.GIT_COMMIT_SHORT}
"""
                    )
                }
            }
        }
    }
}
