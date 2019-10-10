#!/bin/bash
##------------------------------------------------------------------------------
## Licensed Materials - Property of IBM
## 5737-E67
## (C) Copyright IBM Corporation 2019 All Rights Reserved.
## US Government Users Restricted Rights - Use, duplication or
## disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
##------------------------------------------------------------------------------
## This script is used to manage operations pertaining to the relationship
## between a MCM hub-cluster and clusters within a managed kubernetes service:
##   - Import a kubernetes cluster into the MCM hub-cluster
##   - Remove a kubernetes cluster from the MCM hub-cluster
##
## Supported Kubernetes Services include:
##   - Microsoft Azure Kubernetes Service (AKS)
##   - Amazon Elastic Kubernetes Service (EKS)
##   - Google Kubernetes Engine (GKE)
##   - IBM Cloud Kubernetes Service (IKS)
##
## Details pertaining to the actions to be taken and target cluster to be
## managed should be provided via the following command-line parameters or <environment variable>:
## Require:
##   -ac|--action <ACTION>                          Action to be taken; Valid values include (import, remove)
##   -ct|--clustertype <CLUSTER_TYPE>               Type of cluser to be targeted; Valid values include (aks, eks, gke, iks)
##   -wd|--workdir <WORK_DIR>                       Directory where temporary work files will be created during the action
##   -is|--icpserverurl <ICP_URL>                   URL (including port) of the ICP server hosting the MCM hub-cluster
##   -iu|--icpuser <ICP_ADMIN_USER>                 Name of the ICP administration user
##   -ip|--icppassword <ICP_ADMIN_PASSWORD>         Password used to authenticate with the ICP server
##   -cn|--clustername <CLUSTER_NAME>               Name of the target cluster
## Optional:
##   -cs|--clusternamespace <CLUSTER_NAMESPACE>     Namespace on the hub cluster into which the target cluster will be imported
##   -kc|--kubeconfig <CLUSTER_CONFIG_FILE>         Path to file of the target cluster's KUBECONFIG file
##   -ce|--clusterendpoint <CLUSTER_ENDPOINT>       URL for accessing the target cluster
##   -cu|--clusteruser <CLUSTER_USER>               Username for accessing the target cluster
##   -ck|--clustertoken <CLUSTER_TOKEN>             Authorization token for accessing the target cluster
##   -ca|--ikscacert <CLUSTER_CA_CERTIFICATE_FILE>  Path to file of the target cluster's CA certificate (Base64 encoded); Applicable for IKS
##   -ek|--ekskeyid <ACCESS_KEY_ID>                 Access Key ID; Used to authenticate with EKS
##   -es|--ekssecret <SECRET_ACCESS_KEY>            Secret Access key; Used to authenticate with EKS
##   -cr|--clusterregion <CLUSTER_REGION>           Name of the region containing the target cluster; Used to authenticate with EKS
##   -gc|--gkecreds <SERVICE_ACCOUNT_CREDENTIALS>   Credentials (Base64 encoded) for the service account; Used to authenticate with GKE cluster
##   -ir|--imageregistry <IMAGE_REGISTRY>           Name of the registry containing the MCM image(s)
##   -ix|--imagesuffix <IMAGE_SUFFIX>               Suffix (e.g. platform type) to be appended to image name
##   -iv|--imageversion <IMAGE_VERSION>             Version (tag) of the MCM image to be pulled
##   -du|--dockeruser <DOCKER_USER>                 User name for authenticating with the image registry
##   -dp|--dockerpassword <DOCKER_PASSWORD>         Password for authenticating with the image registry
##------------------------------------------------------------------------------

set -e
trap cleanup KILL ERR QUIT TERM INT EXIT

## Perform cleanup tasks prior to exit
function cleanup() {
    if [ "${ACTION}" == "import"  -a  "${IMPORT_STATUS}" != "imported" ]; then
        echo "Unable to import the managed cluster; Exiting..."
    fi
    if [ ! ${USING_TOKEN}  -a  "${CLUSTER_TYPE}" == "gke" ]; then
        echo "Performing cleanup tasks for the Google Cloud (GKE) cluster..."
        gcloudLogout
    fi
}

## Download and install the cloudctl utility used to import/remove the managed cluster
function installCloudctlLocally() {
    if [ ! -x ${WORK_DIR}/bin/cloudctl ]; then
        echo "Installing cloudctl into ${WORK_DIR}..."
        wget --quiet --no-check-certificate ${ICP_URL}/api/cli/cloudctl-linux-amd64 -P ${WORK_DIR}/bin
        mv ${WORK_DIR}/bin/cloudctl-linux-amd64 ${WORK_DIR}/bin/cloudctl
        chmod +x ${WORK_DIR}/bin/cloudctl
    else
        echo "cloudctl has already been installed; No action taken"
    fi
}

## Download and install the kubectl utility used to import/remove the managed cluster
function installKubectlLocally() {
    ## This script should be running with a unique HOME directory; Initialize '.kube' directory
    rm -rf   ${HOME}/.kube
    mkdir -p ${HOME}/.kube

    ## Install kubectl, if necessary
    if [ ! -x ${WORK_DIR}/bin/kubectl ]; then
        kversion=$(wget -qO- https://storage.googleapis.com/kubernetes-release/release/stable.txt)

        echo "Installing kubectl (version ${kversion}) into ${WORK_DIR}..."
        wget --quiet https://storage.googleapis.com/kubernetes-release/release/${kversion}/bin/linux/amd64/kubectl -P ${WORK_DIR}/bin
        chmod +x ${WORK_DIR}/bin/kubectl
    else
        echo "kubectl has already been installed; No action taken"
    fi
}

## Download and install AWS tool used to authenticate with the EKS cluster
function installAwsLocally() {
    if [ ! -x ${WORK_DIR}/bin/aws-iam-authenticator ]; then
        echo "Installing AWS IAM Authenticator into ${WORK_DIR}..."
        wget --quiet https://amazon-eks.s3-us-west-2.amazonaws.com/1.13.7/2019-06-11/bin/linux/amd64/aws-iam-authenticator -P ${WORK_DIR}/bin
        chmod +x ${WORK_DIR}/bin/aws-iam-authenticator
        export AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}
        export AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}
        export AWS_DEFAULT_REGION=${CLUSTER_REGION}
        aws-iam-authenticator version
        echo "AWS IAM Authenticator has been successfully installed"
    else
        aws-iam-authenticator version
        echo "AWS IAM Authenticator has already been installed; No action taken"
    fi
}

## Download and install Google Cloud tool used to authenticate with the GKE cluster
function installGcloudLocally() {
    if [ ! -x ${WORK_DIR}/bin/gcloud ]; then
        echo "Installing Google Cloud CLI into ${WORK_DIR}..."
        mkdir -p ${WORK_DIR}/.gke
        rm -rf ${WORK_DIR}/google-cloud-sdk*
        wget --quiet https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-254.0.0-linux-x86_64.tar.gz -P ${WORK_DIR}
        tar -zxvf ${WORK_DIR}/google-cloud-sdk-254.0.0-linux-x86_64.tar.gz --directory ${WORK_DIR}

        gcloud version
        echo "Google Cloud CLI has been successfully installed"
    else
        gcloud version
        echo "Google Cloud CLI has already been installed; No action taken"
    fi
}

## Verify that required details pertaining to the MCM hub-cluster have been provided
function verifyMcmControllerInformation() {
    if [ -z "$(echo "${ICP_URL}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}ICP API URL is not available${WARN_OFF}"
        exit 1
    fi
    if [ -z "$(echo "${ICP_ADMIN_USER}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}ICP admin username is not available${WARN_OFF}"
        exit 1
    fi
    if [ -z "$(echo "${ICP_ADMIN_PASSWORD}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}ICP admin password is not available${WARN_OFF}"
        exit 1
    fi
    installCloudctlLocally
}

## Verify the information needed to access the target cluster
function verifyTargetClusterInformation() {
    installKubectlLocally

    if [ -s "${CLUSTER_CONFIG_FILE}" ]; then
        ## KUBECONFIG file provided; Verify cloud-specific details
        if [ "${CLUSTER_TYPE}" == "iks" ]; then
            verifyIksInformation
        elif [ "${CLUSTER_TYPE}" == "aks" ]; then
            verifyAksInformation
        elif [ "${CLUSTER_TYPE}" == "eks" ]; then
            verifyEksInformation
            installAwsLocally
        elif [ "${CLUSTER_TYPE}" == "gke" ]; then
            export PATH=${WORK_DIR}/google-cloud-sdk/bin:${PATH}
            installGcloudLocally
            verifyGkeInformation
            gcloudLogin
        else 
            echo "Unsupported kubernetes service - ${CLUSTER_TYPE}; Exiting."
            exit 1
        fi
        USING_TOKEN=1
    else
        ## KUBECONFIG file was not provided; Verify manual kubectl config details
        if [ -z "$(echo "${CLUSTER_TOKEN}" | tr -d '[:space:]')" ]; then
            echo "${WARN_ON}Authorization token has not been specified; Exiting...${WARN_OFF}"
            exit 1
        fi
        if [ -z "$(echo "${CLUSTER_ENDPOINT}" | tr -d '[:space:]')" ]; then
            echo "${WARN_ON}Cluster server URL has not been specified; Exiting...${WARN_OFF}"
            exit 1
        fi
        if [ -z "$(echo "${CLUSTER_USER}" | tr -d '[:space:]')" ]; then
            echo "${WARN_ON}Cluster user has not been specified; Exiting...${WARN_OFF}"
            exit 1
        fi

        ## Configure kubectl
        ${WORK_DIR}/bin/kubectl config set-cluster     ${CLUSTER_NAME} --insecure-skip-tls-verify=true --server=${CLUSTER_ENDPOINT}
        ${WORK_DIR}/bin/kubectl config set-credentials ${CLUSTER_USER} --token=${CLUSTER_TOKEN}
        ${WORK_DIR}/bin/kubectl config set-context     ${CLUSTER_NAME} --user=${CLUSTER_USER} --namespace=kube-system --cluster=${CLUSTER_NAME}
        ${WORK_DIR}/bin/kubectl config use-context     ${CLUSTER_NAME}

        ## Generate KUBECONFIG file to be used when accessing the target cluster
        ${WORK_DIR}/bin/kubectl config view --minify=true --flatten=true > ${KUBECONFIG_FILE}
    fi
    verifyTargetClusterAccess
}

## Verify the target cluster can be accessed
function verifyTargetClusterAccess() {
    set +e
    echo "Verifying access to target cluster..."
    export KUBECONFIG=${KUBECONFIG_FILE}
    ${WORK_DIR}/bin/kubectl get nodes
    if [ $? -ne 0 ]; then
        echo "${WARN_ON}Unable to access the target cluster; Exiting...${WARN_OFF}"
        exit 1
    fi
    unset KUBECONFIG
    set -e
}

## Verify that required details pertaining to the IKS cluster have been provided
function verifyIksInformation() {
    # Verify cluster-specific information is provided via environment variables
    KUBECONFIG_TEXT=$(cat ${CLUSTER_CONFIG_FILE})
    if [ -z "$(echo "${KUBECONFIG_TEXT}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}IKS cluster identification details are not available${WARN_OFF}"
        exit 1
    else
        echo "Creating kubeconfig file..."
        echo "${KUBECONFIG_TEXT}" > ${KUBECONFIG_FILE}
    fi
    CA_CERTIFICATE=$(cat ${CLUSTER_CA_CERTIFICATE_FILE})
    if [ -z "$(echo "${CA_CERTIFICATE}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}IKS cluster certificate authority is not available${WARN_OFF}"
        exit 1
    else
        echo "Embedding CA certificate into IKS kubeconfig file..."
        sed -i -e "s|certificate-authority:.*|certificate-authority-data: ${CA_CERTIFICATE}|" ${KUBECONFIG_FILE}
    fi
}

## Verify that required details pertaining to the AKS cluster have been provided
function verifyAksInformation() {
    # Verify cluster-specific information is provided via environment variables
    KUBECONFIG_TEXT=$(cat ${CLUSTER_CONFIG_FILE})
    if [ -z "$(echo "${KUBECONFIG_TEXT}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}AKS cluster identification details are not available${WARN_OFF}"
        exit 1
    else
        echo "Creating kubeconfig file..."
        echo "${KUBECONFIG_TEXT}" > ${KUBECONFIG_FILE}
    fi
}

## Verify that required details pertaining to the EKS cluster have been provided
function verifyEksInformation() {
    # Verify cluster-specific information is provided via environment variables
    KUBECONFIG_TEXT=$(cat ${CLUSTER_CONFIG_FILE})
    if [ -z "$(echo "${KUBECONFIG_TEXT}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}EKS cluster identification details are not available${WARN_OFF}"
        exit 1
    else
        echo "Creating kubeconfig file..."
        echo "${KUBECONFIG_TEXT}" > ${KUBECONFIG_FILE}
    fi
    if [ -z "$(echo "${ACCESS_KEY_ID}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}EKS access key ID is not available${WARN_OFF}"
        exit 1
    fi
    if [ -z "$(echo "${SECRET_ACCESS_KEY}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}EKS secret access key is not available${WARN_OFF}"
        exit 1
    fi
    if [ -z "$(echo "${CLUSTER_REGION}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}EKS region name is not available${WARN_OFF}"
        exit 1
    fi
}

## Verify that required details pertaining to the GKE cluster have been provided
function verifyGkeInformation() {
    # Verify cluster-specific information is provided via environment variables
    KUBECONFIG_TEXT=$(cat ${CLUSTER_CONFIG_FILE})
    if [ -z "$(echo "${KUBECONFIG_TEXT}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}GKE cluster identification details are not available${WARN_OFF}"
        exit 1
    else
        echo "Creating kubeconfig file..."
        echo "${KUBECONFIG_TEXT}" > ${KUBECONFIG_FILE}
    fi
    if [ -z "$(echo "${SERVICE_ACCOUNT_CREDENTIALS}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}GKE service account credentials are not available${WARN_OFF}"
        exit 1
    fi
}

## Authenticate with Google Cloud in order to perform operations against the GKE cluster
function gcloudLogin() {
    # Authenticate using the GKE service account credentials.  This will allow
    # the cloudctl command(s) to obtain and use a valid token for the kubernetes operations.
    export CLOUDSDK_CONFIG=${WORK_DIR}/.gke
    echo "Authenticating with GKE..."
    acctCredentialsFile=${WORK_DIR}/gkeCredentials.json
    echo "${SERVICE_ACCOUNT_CREDENTIALS}" | base64 -d > ${acctCredentialsFile}
    gcloud auth activate-service-account --key-file ${acctCredentialsFile}
}

## Logout from Google Cloud after performing operations against the GKE cluster
function gcloudLogout() {
    # Revoke authorization for GKE access
    export CLOUDSDK_CONFIG=${WORK_DIR}/.gke
    echo "Revoking GKE access..."
    acctCredentialsFile=${WORK_DIR}/gkeCredentials.json
    echo "${SERVICE_ACCOUNT_CREDENTIALS}" | base64 -d > ${acctCredentialsFile}
    acctEmail=$(cat ${acctCredentialsFile} | grep client_email | cut -f4 -d'"')
    if [ -z "$(echo "${acctEmail}" | tr -d '[:space:]')" ]; then
        echo "Revoking gcloud access for all"
        gcloud auth revoke --all
    else
        echo "Revoking gcloud access for ${acctEmail}"
        gcloud auth revoke ${acctEmail}
    fi
}

## Authenticate with MCM hub-cluster in order to perform import/remove operations
function hubClusterLogin() {
    echo "Logging into the MCM hub cluster..."
    mkdir -p ${WORK_DIR}/.helm
    export CLOUDCTL_HOME=${WORK_DIR}/.helm
    cloudctl login -a ${ICP_URL} --skip-ssl-validation -u ${ICP_ADMIN_USER} -p ${ICP_ADMIN_PASSWORD} -n default
}

## Logout from the MCM hub-cluster
function hubClusterLogout() {
    echo "Logging out of MCM hub cluster..."
    export CLOUDCTL_HOME=${WORK_DIR}/.helm
    cloudctl logout
}

## Prepare for the target cluster to be imported into the hub cluster:
##   - Create configuration file
##   - Create cluster resource
##   - Generate import file to be applied to target cluster
function prepareClusterImport() {
    ## Connect to hub cluster
    hubClusterLogin

    echo "Generating configuration file template..."
    nameSpace=${CLUSTER_NAME}
    if [ ! -z "$(echo "${CLUSTER_NAMESPACE}" | tr -d '[:space:]')" ]; then
        nameSpace="${CLUSTER_NAMESPACE}"
    fi
    cloudctl mc cluster template ${CLUSTER_NAME} -n ${nameSpace} > ${CONFIG_FILE}

    ## If image registry is provided, modify config template to include registry details
    imageRegistry="$(echo ${IMAGE_REGISTRY} | tr -d '[:space:]')"
    if [ ! -z "${imageRegistry}" ]; then
        sed -i -e "s/# *private_registry_enabled:.*/private_registry_enabled: true/" \
               -e "s|# *imageRegistry:.*|imageRegistry: ${imageRegistry}|" ${CONFIG_FILE}
        if [ ! -z "$(echo "${IMAGE_SUFFIX}" | tr -d '[:space:]')" ]; then
            sed -i -e "s/# *imageNamePostfix:.*/imageNamePostfix: ${IMAGE_SUFFIX}/" ${CONFIG_FILE}
        fi
        if [ ! -z "$(echo "${DOCKER_USER}" | tr -d '[:space:]')" ]; then
            sed -i -e "s/# *docker_username:.*/docker_username: ${DOCKER_USER}/" ${CONFIG_FILE}
        fi
        if [ ! -z "$(echo "${DOCKER_PASSWORD}" | tr -d '[:space:]')" ]; then
            sed -i -e "s/# *docker_password:.*/docker_password: ${DOCKER_PASSWORD}/" ${CONFIG_FILE}
        fi
        if [ ! -z "$(echo "${IMAGE_VERSION}" | tr -d '[:space:]')" ]; then
            sed -i -e "s/version:.*/version: ${IMAGE_VERSION}/" ${CONFIG_FILE}
        fi
    fi
    IMPORT_STATUS="configured"

    echo "Creating the resource for cluster ${CLUSTER_NAME}..."
    cloudctl mc cluster create -f ${CONFIG_FILE}
    IMPORT_STATUS="created"

    echo "Generating import file for target cluster ${CLUSTER_NAME}..."
    cloudctl mc cluster import ${CLUSTER_NAME} -n ${nameSpace} > ${IMPORT_FILE}
    IMPORT_STATUS="prepared"

    ## Disconnect from hub cluster
    hubClusterLogout
}

## Initiate the import of the target cluster
function initiateClusterImport() {
    echo "Applying import file to target cluster ${CLUSTER_NAME}..."
    export KUBECONFIG=${KUBECONFIG_FILE}
    ${WORK_DIR}/bin/kubectl apply -f ${IMPORT_FILE}
    IMPORT_STATUS="applied"
    unset KUBECONFIG
}

## Monitor the import status of the target cluster
function monitorClusterImport() {
    echo "Monitoring the import status of target cluster ${CLUSTER_NAME}..."
    nameSpace=${CLUSTER_NAME}
    if [ ! -z "$(echo "${CLUSTER_NAMESPACE}" | tr -d '[:space:]')" ]; then
        nameSpace="${CLUSTER_NAMESPACE}"
    fi

    ## Connect to hub cluster
    hubClusterLogin

    ## Check status, waiting for success/failure status
    iterationCount=1
    iterationInterval=15
    maxMinutes=20
    iterationMax=$((maxMinutes * 60 / iterationInterval))
    initialStatus="Pending"
    clusterStatus=`kubectl get clusters -n ${nameSpace} | tail -1 | awk {'print $(NF-1)'}`
    while [ "${clusterStatus}" == "${initialStatus}"  -a  ${iterationCount} -lt ${iterationMax} ]; do
        echo "Checking cluster status; Iteration ${iterationCount}..."
        clusterStatus=`kubectl get clusters -n ${nameSpace} | tail -1 | awk {'print $(NF-1)'}`
        echo "Current cluster status is: ${clusterStatus}"
        if [ "${clusterStatus}" != "${initialStatus}" ]; then
            ## Status changed; Prepare to exit loop
            iterationCount=${iterationMax}
        else
            echo "Status has not changed; Waiting for next check..."
            iterationCount=$((iterationCount + 1))
            sleep ${iterationInterval}
        fi
    done
    if [ "${clusterStatus}" != "Ready" ]; then
        echo "${WARN_ON}Cluster is not ready within the allotted time; Exiting...${WARN_OFF}"
        echo "${WARN_ON}State of target cluster shown below:${WARN_OFF}"
        export KUBECONFIG=${KUBECONFIG_FILE}
        ${WORK_DIR}/bin/kubectl get pods -n multicluster-endpoint
        unset KUBECONFIG
        exit 1
    else
        echo "Import of cluster ${CLUSTER_NAME} is successful"
        IMPORT_STATUS="imported"
    fi

    ## Disconnect from hub cluster
    hubClusterLogout
}

## Remove the target cluster from the hub cluster.
function initiateClusterRemoval() {
    ## Connect to hub cluster
    hubClusterLogin

    echo "Initiating removal of target cluster ${CLUSTER_NAME}..."
    nameSpace=${CLUSTER_NAME}
    if [ ! -z "$(echo "${CLUSTER_NAMESPACE}" | tr -d '[:space:]')" ]; then
        nameSpace="${CLUSTER_NAMESPACE}"
    fi
    cloudctl mc cluster delete ${CLUSTER_NAME} -n ${nameSpace}

    ## Disconnect from hub cluster
    hubClusterLogout
}

## Perform the requested cluster management operation
function performRequestedAction() {
    if [ "${ACTION}" == "import" ]; then
        prepareClusterImport
        initiateClusterImport
        monitorClusterImport
    elif [ "${ACTION}" == "remove" ]; then
        initiateClusterRemoval
    else 
        echo "Unsupported management action - ${ACTION}; Exiting."
        exit 1
    fi
}

## Perform the tasks required to complete the cluster management operation
function run() {
    ## Prepare work directory and install common utilities
    mkdir -p ${WORK_DIR}/bin
    export PATH=${WORK_DIR}/bin:${PATH}

    ## Check provided cluster information
    if [ -z "$(echo "${CLUSTER_NAME}" | tr -d '[:space:]')" ]; then
        echo "${WARN_ON}Target cluster name was not provided${WARN_OFF}"
        exit 1
    fi
    verifyMcmControllerInformation
    if [ "${ACTION}" == "import" ]; then
        verifyTargetClusterInformation
    fi

    ## Perform kubernetes service-specific tasks for the requested action
    performRequestedAction
}

##------------------------------------------------------------------------------------------------
##************************************************************************************************
##------------------------------------------------------------------------------------------------

## Gather information provided via the command line parameters
while test ${#} -gt 0; do
    [[ $1 =~ ^-ac|--action ]]           && { ACTION="${2}";                      shift 2; continue; };
    [[ $1 =~ ^-ct|--clustertype ]]      && { CLUSTER_TYPE="${2}";                shift 2; continue; };
    [[ $1 =~ ^-wd|--workdir ]]          && { WORK_DIR="${2}";                    shift 2; continue; };

    [[ $1 =~ ^-cn|--clustername ]]      && { CLUSTER_NAME="${2}";                shift 2; continue; };
    [[ $1 =~ ^-is|--icpserverurl ]]     && { ICP_URL="${2}";                     shift 2; continue; };
    [[ $1 =~ ^-iu|--icpuser ]]          && { ICP_ADMIN_USER="${2}";              shift 2; continue; };
    [[ $1 =~ ^-ip|--icppassword ]]      && { ICP_ADMIN_PASSWORD="${2}";          shift 2; continue; };
    [[ $1 =~ ^-cs|--clusternamespace ]] && { CLUSTER_NAMESPACE="${2}";           shift 2; continue; };

    [[ $1 =~ ^-ce|--clusterendpoint ]]  && { CLUSTER_ENDPOINT="${2}";            shift 2; continue; };
    [[ $1 =~ ^-cu|--clusteruser ]]      && { CLUSTER_USER="${2}";                shift 2; continue; };
    [[ $1 =~ ^-ck|--bearertoken ]]      && { CLUSTER_TOKEN="${2}";               shift 2; continue; };
    [[ $1 =~ ^-kc|--kubeconfig ]]       && { CLUSTER_CONFIG_FILE="${2}";         shift 2; continue; };

    [[ $1 =~ ^-ca|--ikscacert ]]        && { CLUSTER_CA_CERTIFICATE_FILE="${2}"; shift 2; continue; };  					  	
    [[ $1 =~ ^-cr|--clusterregion ]]    && { CLUSTER_REGION="${2}";              shift 2; continue; };
    [[ $1 =~ ^-gc|--gkecreds ]]         && { SERVICE_ACCOUNT_CREDENTIALS="${2}"; shift 2; continue; };  					  	
    [[ $1 =~ ^-ek|--ekskeyid ]]         && { ACCESS_KEY_ID="${2}";               shift 2; continue; };  					  	
    [[ $1 =~ ^-es|--ekssecret ]]        && { SECRET_ACCESS_KEY="${2}";           shift 2; continue; };  					  	

    [[ $1 =~ ^-ir|--imageregistry ]]    && { IMAGE_REGISTRY="${2}";              shift 2; continue; };
    [[ $1 =~ ^-ix|--imagesuffix ]]      && { IMAGE_SUFFIX="${2}";                shift 2; continue; };
    [[ $1 =~ ^-iv|--imageversion ]]     && { IMAGE_VERSION="${2}";               shift 2; continue; };
    [[ $1 =~ ^-du|--dockeruser ]]       && { DOCKER_USER="${2}";                 shift 2; continue; };
    [[ $1 =~ ^-dp|--dockerpassword ]]   && { DOCKER_PASSWORD="${2}";             shift 2; continue; };
    break;
done
ACTION="$(echo "${ACTION}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
if [ "${ACTION}" != "import"  -a  "${ACTION}" != "remove" ]; then
    echo "${WARN_ON}Management action (e.g. import, remove) has not been specified; Exiting...${WARN_OFF}"
    exit 1
fi
if [ -z "$(echo "${CLUSTER_TYPE}" | tr -d '[:space:]')" ]; then
    echo "${WARN_ON}Type of cluster to be managed has not been specified; Exiting...${WARN_OFF}"
    exit 1
fi
if [ -z "$(echo "${WORK_DIR}" | tr -d '[:space:]')" ]; then
    echo "${WARN_ON}Location of the work directory has not been specified; Exiting...${WARN_OFF}"
    exit 1
fi

## Prepare work directory
mkdir -p ${WORK_DIR}/bin
export PATH=${WORK_DIR}/bin:${PATH}

## Set default variable values
IMPORT_STATUS="unknown"
CONFIG_FILE=${WORK_DIR}/cluster-config.yaml
IMPORT_FILE=${WORK_DIR}/cluster-import.yaml
KUBECONFIG_FILE=${WORK_DIR}/kubeconfig.yaml
USING_TOKEN=0
WARN_ON='\033[0;31m'
WARN_OFF='\033[0m'

## Run the necessary action(s)
run
