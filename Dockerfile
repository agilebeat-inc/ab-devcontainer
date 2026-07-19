FROM golang:1.26.5-trixie

LABEL org.opencontainers.image.authors="Marek.Dwulit@agilebeat.com,Scott.Marchese@agilebeat.com"

WORKDIR /tmp 

# adding
# - locales fiddling since psql complains otherwise (and it's good to have a locale properly set)
# - networking utilties
RUN apt-get update && \
  apt-get install -y \
  ca-certificates curl git jq less locales sudo unzip vim wget \
  bind9-dnsutils iproute2 iputils-ping lsof netcat-openbsd nmap traceroute \
  && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
  && locale-gen \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# installing Docker CLI
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker-ce-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG HOST_USERNAME=vscode
ARG HOST_GROUPNAME=vscode
ARG HOST_UID=1000
ARG HOST_GID=$HOST_UID
ARG HOST_HOME=/home/vscode

# Create the user; add them to sudoers and docker users groups
RUN groupadd --gid $HOST_GID $HOST_GROUPNAME \
    && useradd --uid $HOST_UID --gid $HOST_GID -m $HOST_USERNAME -d $HOST_HOME \
    && echo $HOST_USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$HOST_USERNAME \
    && chmod 0440 /etc/sudoers.d/$HOST_USERNAME \
    && groupadd -f docker && usermod -aG docker $HOST_USERNAME

# install node (is this needed when we have containers?)
COPY --from=node:26 /usr/local/bin/ /usr/local/bin/
COPY --from=node:26 /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

# ********************************************************
# install terraform - see https://developer.hashicorp.com/terraform/install#linux
# ********************************************************
COPY --from=hashicorp/terraform:1.15 /bin/terraform /usr/local/bin/terraform

# ********************************************************
# * Install go utils                                     *
# ********************************************************
# https://go.dev/ref/mod#go-install
RUN go install -v golang.org/x/tools/gopls@latest && \
    go install -v sigs.k8s.io/kind@v0.32.0 && \
    go install -v sigs.k8s.io/cloud-provider-kind@latest && \
    go clean -cache -modcache && \
    rm -rf /root/.cache/go-build

# ********************************************************
# * Install kubebuilder                                  *
# ********************************************************
# RUN curl -L -o kubebuilder "https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)" && \
#     chmod +x kubebuilder && \
#     mv kubebuilder /usr/local/bin/

# ********************************************************
# * Install helm                                         *
# ********************************************************
COPY --from=alpine/helm:4.2.3 /usr/bin/helm /usr/local/bin/helm        

# ********************************************************
# * Install kubectl                                      *
# ********************************************************
COPY --from=registry.k8s.io/kubectl:v1.36.2 /bin/kubectl /usr/local/bin/kubectl

# ********************************************************
# * Install eksctl                                       *
# ********************************************************
ARG EKSCTL_VERSION=0.229.0
RUN export ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/') && \
    curl -sL "https://github.com/eksctl-io/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_$(uname -s)_${ARCH}.tar.gz" | \
    tar xz -C /tmp && \
    chmod +x /tmp/eksctl && \
    mv /tmp/eksctl /usr/local/bin/eksctl

# ********************************************************
# * Install helmify                                      *
# ********************************************************
# ARG helmify_version=v0.4.18
# RUN curl --create-dirs -O --output-dir /tmp/helmify -LO "https://github.com/arttor/helmify/releases/download/${helmify_version}/helmify_Linux_x86_64.tar.gz" && \
#     curl --create-dirs -O --output-dir /tmp/helmify -LO "https://github.com/arttor/helmify/releases/download/${helmify_version}/checksums.txt" && \
#     cd /tmp/helmify && \
#     tar -xzvf helmify_Linux_x86_64.tar.gz && \
#     chmod +x /tmp/helmify/helmify && \
#     mv /tmp/helmify/helmify /usr/local/bin/helmify

# ********************************************************
# * Install operator-sdk                                 *
# * https://sdk.operatorframework.io/docs/installation/#install-from-github-release
# ********************************************************
# RUN export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac) && \
#     export OS=$(uname | awk '{print tolower($0)}') && \
#     export OPERATOR_SDK_VERSION=v1.41.1 && \
#     export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/$OPERATOR_SDK_VERSION && \
#     curl --create-dirs -O --output-dir /tmp/operator-sdk -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH} && \
#     curl --create-dirs -O --output-dir /tmp/operator-sdk -LO ${OPERATOR_SDK_DL_URL}/checksums.txt && \
#     curl --create-dirs -O --output-dir /tmp/operator-sdk -LO ${OPERATOR_SDK_DL_URL}/checksums.txt.asc && \
#     gpg --keyserver keyserver.ubuntu.com --recv-keys 052996E2A20B5C7E && \
#     chmod +x /tmp/operator-sdk/operator-sdk_${OS}_${ARCH} && \
#     mv /tmp/operator-sdk/operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk

# ********************************************************
# * Install yq                                           *
# ********************************************************
COPY --from=mikefarah/yq:4.53.3 /usr/bin/yq /usr/local/bin/yq

# ********************************************************
# * Install mc - minio client                            *
# ********************************************************
# TODO: get rid of minio/mc in favor of s3 and awscli
COPY --from=minio/mc:RELEASE.2025-08-13T08-35-41Z /usr/bin/mc /usr/local/bin/mc

# ********************************************************
# * Install AWS CLI v2                                   *
# ********************************************************
RUN export ARCH=$(uname -m) && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

# *********************************************************
# * Install krew                                          *
# https://krew.sigs.k8s.io/docs/user-guide/setup/install/ *
# *********************************************************
# RUN cd "$(mktemp -d)" && \
#     OS=$(uname | tr '[:upper:]' '[:lower:]') && \
#     ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/') && \
#     KREW="krew-${OS}_${ARCH}" && \
#     curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" && \
#     tar zxvf "${KREW}.tar.gz" && \
#     ./"${KREW}" install krew && \
#     echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /home/$HOST_USERNAME/.bashrc
# could also pre-install selected plugins:
# RUN kubectl krew install rabbitmq

# ***********************************
# * Install uv + python             *
# ***********************************
COPY --from=ghcr.io/astral-sh/uv:0.11.29 /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python
RUN uv python install 3.14 && \
    ln -s "$(uv python find 3.14)" /usr/local/bin/python3

# install claude cli
# doing this as container user since the binary is actually a symlink
# so copying from /root elsewhere still inherits permission issues
USER $HOST_USERNAME
RUN curl -fsSL https://claude.ai/install.sh | bash

# Reset workdir
WORKDIR /tmp
