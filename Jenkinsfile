// CI/CD pipeline: GitHub webhook -> tests -> SonarQube -> Docker build -> Trivy -> ECR -> EKS
pipeline {
    agent any

    triggers {
        // Fired by the GitHub webhook (http://<jenkins>/github-webhook/)
        githubPush()
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        AWS_REGION     = 'ap-south-1'
        CLUSTER_NAME   = 'devops-eks'
        ECR_REPO_NAME  = 'devops-python-app'
        K8S_NAMESPACE  = 'devops-app'
        IMAGE_TAG      = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install -q -r requirements-dev.txt
                    pytest --junitxml=test-results.xml --cov=app --cov-report=xml
                '''
            }
            post {
                always { junit 'test-results.xml' }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh 'sonar-scanner -Dsonar.projectVersion=${IMAGE_TAG}'
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build --build-arg APP_VERSION=${IMAGE_TAG} -t ${ECR_REPO_NAME}:${IMAGE_TAG} .'
            }
        }

        stage('Trivy Security Scan') {
            steps {
                // Filesystem scan (deps + IaC misconfig) and image scan; fail on HIGH/CRITICAL
                sh '''
                    trivy fs --exit-code 1 --severity HIGH,CRITICAL --scanners vuln,secret --no-progress .
                    trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --no-progress \
                        --format table -o trivy-report.txt ${ECR_REPO_NAME}:${IMAGE_TAG}
                '''
            }
            post {
                always { archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true }
            }
        }

        stage('Push to ECR') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials',
                                                  usernameVariable: 'AWS_ACCESS_KEY_ID',
                                                  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                        REGISTRY=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${REGISTRY}
                        docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${REGISTRY}/${ECR_REPO_NAME}:latest
                        docker push ${REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${ECR_REPO_NAME}:latest
                        echo "${REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}" > image.txt
                    '''
                }
            }
        }

        stage('Deploy to EKS') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials',
                                                  usernameVariable: 'AWS_ACCESS_KEY_ID',
                                                  passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        IMAGE=$(cat image.txt)
                        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

                        kubectl apply -f k8s/namespace.yaml
                        kubectl apply -f k8s/service.yaml -f k8s/hpa.yaml -f k8s/pdb.yaml
                        sed "s#IMAGE_PLACEHOLDER#${IMAGE}#g" k8s/deployment.yaml | kubectl apply -f -
                        kubectl -n ${K8S_NAMESPACE} annotate deployment/devops-app \
                            kubernetes.io/change-cause="Jenkins build ${BUILD_NUMBER} image ${IMAGE}" --overwrite

                        # Automatic rollback if the rolling update does not become healthy
                        if ! kubectl -n ${K8S_NAMESPACE} rollout status deployment/devops-app --timeout=180s; then
                            echo "Rollout failed - rolling back to previous revision"
                            kubectl -n ${K8S_NAMESPACE} rollout undo deployment/devops-app
                            kubectl -n ${K8S_NAMESPACE} rollout status deployment/devops-app --timeout=180s
                            exit 1
                        fi

                        kubectl -n ${K8S_NAMESPACE} get svc devops-app \
                            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' > app-url.txt || true
                        echo "App URL: http://$(cat app-url.txt)"
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker rmi ${ECR_REPO_NAME}:${IMAGE_TAG} || true'
            cleanWs()
        }
        success { echo "Pipeline succeeded: ${IMAGE_TAG}" }
        failure { echo "Pipeline failed: ${IMAGE_TAG}" }
    }
}
