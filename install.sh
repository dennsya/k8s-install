#!/bin/bash
# Author: Jrohy
# Github: https://github.com/Jrohy/k8s-install

# cancel centos alias
[[ -f /etc/redhat-release ]] && unalias -a

#######color code########
RED="31m"      
GREEN="32m"  
YELLOW="33m" 
BLUE="36m"
FUCHSIA="35m"

GOOGLE_URLS=(
    packages.cloud.google.com
    k8s.gcr.io
    gcr.io
)

MIRROR_SOURCE="registry.cn-hangzhou.aliyuncs.com/google_containers"

CAN_GOOGLE=1

IS_MASTER=0

NETWORK=""

K8S_VERSION=""

colorEcho(){
    COLOR=$1
    echo -e "\033[${COLOR}${@:2}\033[0m"
}

ipIsConnect(){
    ping -c2 -i0.3 -W1 $1 &>/dev/null
    if [ $? -eq 0 ];then
        return 0
    else
        return 1
    fi
}

runCommand(){
    echo ""
    local COMMAND=$1
    echo -e "\033[32m$COMMAND\033[0m"
    echo $COMMAND|bash
}

setHostname(){
    local HOSTNAME=$1
    if [[ $HOSTNAME =~ '_' ]];then
        colorEcho $YELLOW "hostname can't contain '_' character, auto change to '-'.."
        HOSTNAME=`echo $HOSTNAME|sed 's/_/-/g'`
    fi
    echo "set hostname: `colorEcho $BLUE $HOSTNAME`"
    echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
    runCommand "hostnamectl --static set-hostname $HOSTNAME"
}

#######get params#########
while [[ $# > 0 ]];do
    KEY="$1"
    case $KEY in
        --hostname)
        setHostname $2
        shift
        ;;
        -v|--version)
        K8S_VERSION=`echo "$2"|sed 's/v//g'`
        echo "prepare install k8s version: $(colorEcho $GREEN $K8S_VERSION)"
        shift
        ;;
        --flannel)
        echo "use flannel network, and set this node as master"
        NETWORK="flannel"
        IS_MASTER=1
        ;;
        --calico)
        echo "use calico network, and set this node as master"
        NETWORK="calico"
        IS_MASTER=1
        ;;
        -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "   --flannel                    use flannel network, and set this node as master"
        echo "   --calico                     use calico network, and set this node as master"
        echo "   --hostname [HOSTNAME]        set hostname"
        echo "   -v, --version [VERSION]:     install special version k8s"
        echo "   -h, --help:                  find help"
        echo ""
        exit 0
        shift # past argument
        ;; 
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done
#############################

checkSys() {
    #检查是否为Root
    [ $(id -u) != "0" ] && { colorEcho ${RED} "Error: You must be root to run this script"; exit 1; }

    #检查CPU核数
    [[ `cat /proc/cpuinfo |grep "processor"|wc -l` == 1 && $IS_MASTER == 1 ]] && { colorEcho ${RED} "master node cpu number should be >= 2!"; exit 1;}

    #检查系统信息
    if [[ -e /etc/redhat-release ]];then
        if [[ $(cat /etc/redhat-release | grep Fedora) ]];then
            OS='Fedora'
            PACKAGE_MANAGER='dnf'
        else
            OS='CentOS'
            PACKAGE_MANAGER='yum'
        fi
    elif [[ $(cat /etc/issue | grep Debian) ]];then
        OS='Debian'
        PACKAGE_MANAGER='apt-get'
    elif [[ $(cat /etc/issue | grep Ubuntu) ]];then
        OS='Ubuntu'
        PACKAGE_MANAGER='apt-get'
    else
        colorEcho ${RED} "Not support OS, Please reinstall OS and retry!"
        exit 1
    fi

    [[ `cat /etc/hostname` =~ '_' ]] && setHostname `cat /etc/hostname`

    echo "Checking machine network(access google)..."
    for ((i=0;i<${#GOOGLE_URLS[*]};i++))
    do
        ipIsConnect ${GOOGLE_URLS[$i]}
        if [[ ! $? -eq 0 ]]; then
            colorEcho ${YELLOW} "server can't access google source, switch to chinese source(aliyun).."
            CAN_GOOGLE=0
            break	
        fi
    done
}

#安装依赖
installDependent(){
    if [[ ${OS} == 'CentOS' || ${OS} == 'Fedora' ]];then
        ${PACKAGE_MANAGER} install bash-completion -y
    else
        ${PACKAGE_MANAGER} update
        ${PACKAGE_MANAGER} install bash-completion apt-transport-https -y
    fi
}

setupDocker(){
    ## 修改cgroupdriver
    if [[ ! -e /etc/docker/daemon.json || -z `cat /etc/docker/daemon.json|grep systemd` ]];then
        ## see https://kubernetes.io/docs/setup/production-environment/container-runtimes/
        mkdir -p /etc/docker
        if [[ ${OS} == 'CentOS' || ${OS} == 'Fedora' ]];then
            if [[ $CAN_GOOGLE == 1 ]];then
                cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF
            else
                cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://registry.docker-cn.com"
    ]
}
EOF
            fi
        else
            if [[ $CAN_GOOGLE == 1 ]];then
                cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF
            else
                cat > /etc/docker/daemon.json <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2",
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://registry.docker-cn.com"
    ]
}
EOF
            fi
        fi
        systemctl restart docker
        if [ $? -ne 0 ];then
            rm -f /etc/docker/daemon.json
            if [[ $CAN_GOOGLE == 0 ]];then
                cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://registry.docker-cn.com"
    ]
}
EOF
            fi
            systemctl restart docker
        fi
    fi
}

setupContainerd() {
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd
}

prepareWork() {
    ## Centos设置
    if [[ ${OS} == 'CentOS' || ${OS} == 'Fedora' ]];then
        if [[ `systemctl list-units --type=service|grep firewalld` ]];then
            systemctl disable firewalld.service
            systemctl stop firewalld.service
        fi
        cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
        sysctl --system
    fi
    ## 禁用SELinux
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    ## 关闭swap
    swapoff -a
    sed -i 's/.*swap.*/#&/' /etc/fstab

    ## 安装最新版docker
    if [[ ! $(type docker 2>/dev/null) ]];then
        colorEcho ${YELLOW} "docker no install, auto install latest docker..."
        source <(curl -sL https://docker-install.netlify.app/install.sh) -s
    fi

    setupDocker

    setupContainerd
}

installK8sBase() {
    if [[ $CAN_GOOGLE == 1 ]];then
        if [[ $OS == 'Fedora' || $OS == 'CentOS' ]];then
            cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
        else
            curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
            echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
            ${PACKAGE_MANAGER} update
        fi
    else
        if [[ $OS == 'Fedora' || $OS == 'CentOS' ]];then
            cat>>/etc/yum.repos.d/kubrenetes.repo<<EOF
[kubernetes]
name=Kubernetes Repo
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
EOF
        else
            echo "deb https://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
            curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
            ${PACKAGE_MANAGER} update
        fi
    fi

    if [[ -z $K8S_VERSION ]];then
        ${PACKAGE_MANAGER} install -y kubelet kubeadm kubectl
    else
        if [[ $PACKAGE_MANAGER == "apt-get" ]];then
            INSTALL_VERSION=`apt-cache madison kubectl|grep $K8S_VERSION|cut -d \| -f 2|sed 's/ //g'`
            ${PACKAGE_MANAGER} install -y kubelet=$INSTALL_VERSION kubeadm=$INSTALL_VERSION kubectl=$INSTALL_VERSION
        else
            ${PACKAGE_MANAGER} install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION
        fi
    fi
    systemctl enable kubelet && systemctl start kubelet

    #命令行补全
    [[ -z $(grep kubectl ~/.bashrc) ]] && echo "source <(kubectl completion bash)" >> ~/.bashrc
    [[ -z $(grep kubeadm ~/.bashrc) ]] && echo "source <(kubeadm completion bash)" >> ~/.bashrc
    source ~/.bashrc
    K8S_VERSION=$(kubectl version --output=yaml|grep gitVersion|awk 'NR==1{print $2}')
    K8S_MINOR_VERSION=`kubectl version --output=yaml|grep minor|head -n 1|tr -cd '[0-9]'`
    echo "k8s version: $(colorEcho $GREEN $K8S_VERSION)"
}

downloadImages() {
    colorEcho $YELLOW "auto download $K8S_VERSION all k8s.gcr.io images..."
    PAUSE_VERSION=`cat /etc/containerd/config.toml|grep k8s.gcr.io/pause|grep -Po '\d\.\d'`
    K8S_IMAGES=(`kubeadm config images list 2>/dev/null|grep 'k8s.gcr.io'|xargs -r` "k8s.gcr.io/pause:$PAUSE_VERSION")
    for IMAGE in ${K8S_IMAGES[@]}
    do
        if [ $K8S_MINOR_VERSION -ge 24 ];then
            if [[ `ctr -n k8s.io i ls -q|grep -w $IMAGE` ]];then
                echo " already download image: $(colorEcho $GREEN $IMAGE)"
                continue
            fi
        else
            if [[ `docker images $IMAGE|awk 'NR!=1'` ]];then
                echo " already download image: $(colorEcho $GREEN $IMAGE)"
                continue
            fi
        fi
        if [[ $CAN_GOOGLE == 0 ]];then
            CORE_NAME=${IMAGE#*/}
            if [[ $CORE_NAME =~ "coredns" ]];then
                MIRROR_NAME="$MIRROR_SOURCE/coredns:`echo $CORE_NAME|egrep -o "[0-9.]+"`"
            else
                MIRROR_NAME="$MIRROR_SOURCE/$CORE_NAME"
            fi
            if [ $K8S_MINOR_VERSION -ge 24 ];then
                ctr -n k8s.io i pull $MIRROR_NAME
                ctr -n k8s.io i tag $MIRROR_NAME $IMAGE
                ctr -n k8s.io i del $MIRROR_NAME
            else
                docker pull $MIRROR_NAME
                docker tag $MIRROR_NAME $IMAGE
                docker rmi $MIRROR_NAME
            fi
        else
            [ $K8S_MINOR_VERSION -ge 24 ] && ctr -n k8s.io i pull $IMAGE || docker pull $IMAGE
        fi

        if [ $? -eq 0 ];then
            echo "Downloaded image: $(colorEcho $BLUE $IMAGE)"
        else
            echo "Failed download image: $(colorEcho $RED $IMAGE)"
        fi
        echo ""
    done
}

runK8s(){
    if [[ $IS_MASTER == 1 ]];then
        if [[ $NETWORK == "flannel" ]];then
            runCommand "kubeadm init --pod-network-cidr=10.244.0.0/16 --kubernetes-version=`echo $K8S_VERSION|sed "s/v//g"`"
            runCommand "mkdir -p $HOME/.kube"
            runCommand "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
            runCommand "chown $(id -u):$(id -g) $HOME/.kube/config"
            runCommand "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
        elif [[ $NETWORK == "calico" ]];then
            runCommand "kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=`echo $K8S_VERSION|sed "s/v//g"`"
            runCommand "mkdir -p $HOME/.kube"
            runCommand "cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
            runCommand "chown $(id -u):$(id -g) $HOME/.kube/config"
            runCommand "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
        fi
    else
        echo "this node is slave, please manual run 'kubeadm join' command. if forget join command, please run `colorEcho $GREEN "kubeadm token create --print-join-command"` in master node"
    fi
    if [[ `command -v crictl` ]];then
        crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
        [[ -z $(grep crictl ~/.bashrc) ]] && echo "source <(crictl completion bash)" >> ~/.bashrc
    fi
    colorEcho $YELLOW "kubectl and kubeadm command completion must reopen ssh to affect!"
}

main() {
    checkSys
    prepareWork
    installDependent
    installK8sBase
    downloadImages
    runK8s
}

main