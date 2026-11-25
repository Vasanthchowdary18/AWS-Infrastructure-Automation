# Jenkins controller with all CLI tools the pipeline needs
FROM jenkins/jenkins:lts-jdk21

USER root
ARG TARGETARCH=amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-pip curl unzip ca-certificates gnupg lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (talks to host Docker via mounted socket)
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip

# kubectl
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# Trivy
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# SonarScanner CLI
ARG SONAR_SCANNER_VERSION=7.2.0.5079
RUN curl -fsSL "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" -o /tmp/ss.zip \
    && unzip -q /tmp/ss.zip -d /opt && mv /opt/sonar-scanner-* /opt/sonar-scanner \
    && ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner && rm /tmp/ss.zip

# Allow jenkins user to use the host docker socket
RUN groupadd -f docker && usermod -aG docker jenkins

USER jenkins
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
