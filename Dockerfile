FROM golang:1.26-trixie

LABEL org.opencontainers.image.authors="Marek.Dwulit@agilebeat.com,Scott.Marchese@agilebeat.com"

WORKDIR /tmp 

# adding
# - locales-all since psql complains otherwise
# - lsb-release so that terraform install command can identify the OS version
# - networking utilties
RUN apt-get update && \
  apt-get install -y \
  curl gcc g++ git jq lsb-release less locales-all python3 sudo unzip vim wget \
  apt-transport-https ca-certificates gnupg gnupg-agent \
  bind9-dnsutils iproute2 iputils-ping lsof netcat-openbsd nmap traceroute \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# installing Docker CLI
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker-ce-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# install node (is this needed when we have containers?)
COPY --from=node:25 /usr/local/bin/ /usr/local/bin/
COPY --from=node:25 /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

ARG HOST_USERNAME=vscode
ARG HOST_GROUPNAME=vscode
ARG HOST_UID=1000
ARG HOST_GID=$HOST_UID
ARG HOST_HOME=/home/vscode

# Create the user
RUN groupadd --gid $HOST_GID $HOST_GROUPNAME \
    && useradd --uid $HOST_UID --gid $HOST_GID -m $HOST_USERNAME -d $HOST_HOME \
    && echo $HOST_USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$HOST_USERNAME \
    && chmod 0440 /etc/sudoers.d/$HOST_USERNAME

# ********************************************************
# install terraform - see https://developer.hashicorp.com/terraform/install#linux
# ********************************************************
# this obscure and error-prone command depends on lsb_release having been installed, which happens in the initial apt-get install above
# RUN wget -O - https://apt.releases.hashicorp.com/gpg | \
#     sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
#     echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" \
#     | sudo tee /etc/apt/sources.list.d/hashicorp.list && \
#     apt-get update && \
#     apt-get install -y terraform

# ********************************************************
# * Install go utils                                     *
# ********************************************************
# https://go.dev/ref/mod#go-install
RUN go install -v golang.org/x/tools/gopls@latest && \
    go install -v sigs.k8s.io/kind@v0.31.0 && \
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
COPY --from=alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

# ********************************************************
# * Install kubectl                                      *
# ********************************************************
COPY --from=rancher/kubectl:v1.35.1 /bin/kubectl /usr/local/bin/kubectl

# ********************************************************
# * Install eksctl                                       *
# ********************************************************
ARG EKSCTL_VERSION=0.223.0
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
COPY --from=mikefarah/yq:4.52.2 /usr/bin/yq /usr/local/bin/yq

# ********************************************************
# * Install mc - minio client                            *
# ********************************************************
RUN curl --create-dirs -O --output-dir /tmp/mc_client -LO https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod a+x /tmp/mc_client/mc && \
    mv /tmp/mc_client/mc /usr/local/bin/mc && \
    rm -rf /tmp/mc_client

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

# ********************************************************
# * Install Python utilities via uv                      *
# ********************************************************
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /uvx /usr/local/bin/

# Set up the uv project in /opt/python-utils
ARG PYTHON_UTILS_PATH=/opt/python-utils
RUN mkdir -p ${PYTHON_UTILS_PATH}
COPY pyproject.toml ${PYTHON_UTILS_PATH}/

# Install dependencies using uv sync
WORKDIR ${PYTHON_UTILS_PATH}
RUN uv sync --no-cache && \
    rm -rf ${PYTHON_UTILS_PATH}/.uv/cache && \
    find ${PYTHON_UTILS_PATH} -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true && \
    chown -R $HOST_USERNAME:$HOST_GROUPNAME ${PYTHON_UTILS_PATH}

# Add the uv-managed venv to PATH, as well as ~/.local/bin:
ENV PATH="${PYTHON_UTILS_PATH}/.venv/bin:${HOST_HOME}/.local/bin:${PATH}"

# Reset workdir
WORKDIR /tmp

USER $HOST_USERNAME
