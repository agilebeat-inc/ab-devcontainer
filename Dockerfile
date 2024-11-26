# THIS I S A TEST
FROM tensorflow/tensorflow:latest-gpu

LABEL maintainer Marek Dwulit<Marek.Dwulit@agilebeat.com>”

WORKDIR /tmp 

RUN apt-get upgrade -y 
RUN apt update
RUN apt install --reinstall python3-apt
RUN apt-get -y install sudo vim mc git wget gcc g++ 
RUN cp /usr/lib/python3/dist-packages/apt_pkg.cpython-310-x86_64-linux-gnu.so /usr/lib/python3/dist-packages/apt_pkg.so
RUN apt-get -y install gnome-terminal --fix-missing
RUN apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common jq 
RUN wget https://github.com/mikefarah/yq/releases/download/v4.34.1/yq_linux_amd64 -O yq && \
    chmod +x yq  && \
    mv yq /usr/local/bin/yq
RUN rm -rf /etc/apt/sources.list.d/cuda.list
RUN rm -rf /etc/apt/sources.list.d/nvidia-ml.list
RUN apt-key del 7fa2af80 && \ 
    apt install wget &&  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb && \ 
    dpkg -i cuda-keyring_1.0-1_all.deb

RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt-get -y update
RUN apt-get -y install docker-ce-cli


# RUN pip install pyinquirer --upgrade
RUN pip install --upgrade numpy
RUN pip --no-cache-dir install awscli opencv-python Pillow tensorflowjs

# https://deb.nodesource.com/setup_12.x is a bash script that prepares for installing NodeJS
RUN curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt-get install -y nodejs

RUN npm install -g @vue/cli
RUN npm install -g npm@latest
RUN npm install -g yarn
RUN npm install -g serve
# RUN npm config set unsafe-perm=true npm 12.x

RUN pip install --upgrade pip
RUN pip install pylint numpy pandas geopandas matplotlib rope importlib_resources autopep8 geopy boto3
RUN pip install boto3 awscli
RUN pip install mysql-connector-python psycopg2-binary neo4j pymilvus
RUN pip install tensorflow torch torchvision torchaudio transformers
RUN /usr/bin/python3 -m pip install --upgrade pip

ARG HOST_USERNAME=vscode
ARG HOST_GROUPNAME=vscode
ARG HOST_UID=1000
ARG HOST_GID=$HOST_UID
ARG HOST_HOME=/home/vscode

# Create the user
RUN groupadd --gid $HOST_GID $HOST_GROUPNAME \
    && useradd --uid $HOST_UID --gid $HOST_GID -m $HOST_USERNAME -d $HOST_HOME \
    # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
    && apt-get update \
    && apt-get install -y sudo \
    && echo $HOST_USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$HOST_USERNAME \
    && chmod 0440 /etc/sudoers.d/$HOST_USERNAME

RUN apt --fix-broken install
#RUN apt-get -y install iproute2 bind9-dnsutils --fix-missing

RUN apt-get install wget curl unzip software-properties-common gnupg2 -y
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
RUN apt-add-repository "deb [arch=$(dpkg --print-architecture)] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
RUN apt-get update -y
RUN apt-get install terraform -y

# ********************************************************
# * Install go                                           *
# ********************************************************

# Configure Go
ENV GOROOT /usr/local/go
ENV PATH /usr/local/go/bin:$PATH

RUN rm -rf /usr/local/go && \
    curl --silent --location "https://go.dev/dl/go1.21.4.linux-amd64.tar.gz" | tar xz -C /usr/local && \
    sed -i '19iexport PATH=$PATH:/usr/local/go/bin' /etc/bash.bashrc && \
    sed '19i# Add deafult path for go' /etc/bash.bashrc && \
    GOPATH=/usr/local/go /usr/local/go/bin/go install -v golang.org/x/tools/gopls@latest && \
    GOPATH=/usr/local/go /usr/local/go/bin/go install -v github.com/go-delve/delve/cmd/dlv@latest && \
    GOPATH=/usr/local/go /usr/local/go/bin/go install -v sigs.k8s.io/kind@v0.24.0 && \
    GOPATH=/usr/local/go /usr/local/go/bin/go install -v github.com/derailed/k9s@latest

# ********************************************************
# * Install go                                           *
# ********************************************************
# download kubebuilder and install locally.
RUN curl -L -o kubebuilder "https://go.kubebuilder.io/dl/latest/$(/usr/local/go/bin/go env GOOS)/$(/usr/local/go/bin/go env GOARCH)" && \
    chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

# ********************************************************
# * Install eksctl and kubectl                           *
# ********************************************************
RUN curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && \
    sudo mv /tmp/eksctl /usr/local/bin && \
    curl -Lo "/tmp/kubectl" "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    curl -Lo "/tmp/kubectl.sha256" "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check && mv /tmp/kubectl /usr/local/bin && chmod 755 /usr/local/bin/kubectl

RUN curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null && \
    sudo apt-get install apt-transport-https --yes && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list && \
    sudo apt-get update && \
    sudo apt-get install helm

# ********************************************************
# * Install operator-sdk                                 *
# ********************************************************
RUN curl --create-dirs -O --output-dir /tmp/helmify -LO https://github.com/arttor/helmify/releases/download/v0.4.11/helmify_Linux_x86_64.tar.gz && \
    curl --create-dirs -O --output-dir /tmp/helmify -LO https://github.com/arttor/helmify/releases/download/v0.4.11/checksums.txt && \
    cd /tmp/helmify && \
    tar -xzvf helmify_Linux_x86_64.tar.gz && \
    chmod +x /tmp/helmify/helmify && \
    mv /tmp/helmify/helmify /usr/local/bin/helmify

# ********************************************************
# * Install helmify                                      *
# ********************************************************
RUN export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac) && \
    export OS=$(uname | awk '{print tolower($0)}')&& \
    export OPERATOR_SDK_VERSION=v0.4.11 && \
    export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/$OPERATOR_SDK_VERSION && \
    curl --create-dirs -O --output-dir /tmp/operator-sdk -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH} && \
    curl --create-dirs -O --output-dir /tmp/operator-sdk -LO ${OPERATOR_SDK_DL_URL}/checksums.txt && \
    curl --create-dirs -O --output-dir /tmp/operator-sdk -LO ${OPERATOR_SDK_DL_URL}/checksums.txt.asc && \
    gpg --keyserver keyserver.ubuntu.com --recv-keys 052996E2A20B5C7E && \
    chmod +x /tmp/operator-sdk/operator-sdk_${OS}_${ARCH} && \
    mv /tmp/operator-sdk/operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk

# ********************************************************
# * Add network troubleshooting on the container         *
# ********************************************************

RUN apt-get -y install iproute2 bind9-dnsutils postgresql-client telnet net-tools inetutils-* nmap --fix-missing

# ********************************************************
# * Install helm                                         *
# ********************************************************
RUN curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null && \
    sudo apt-get install apt-transport-https --yes && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list && \
    sudo apt-get update && \
    sudo apt-get install helm


# ********************************************************
# * Install yq                                           *
# ********************************************************
RUN curl --create-dirs -O --output-dir /tmp/yq_linux_amd64 -LO https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod a+x /tmp/yq_linux_amd64/yq_linux_amd64 && \
    mv /tmp/yq_linux_amd64/yq_linux_amd64 /usr/local/bin/yq


# ********************************************************
# * Install hashicorp packer                             *
# ********************************************************

RUN wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list && \
    sudo apt update && sudo apt install packer && \
    packer plugins install github.com/hashicorp/amazon
# ********************************************************
# * Anything else you want to do like clean up goes here *
# ********************************************************




# [Optional] Set the default user. Omit if you want to keep the default as root.
USER $HOST_USERNAME

RUN packer plugins install github.com/hashicorp/amazon