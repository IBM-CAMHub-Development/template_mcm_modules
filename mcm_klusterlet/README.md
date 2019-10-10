# MCM Klusterlet within public Kubernetes Service platform
Copyright IBM Corp. 2019, 2019
This code is released under the Apache 2.0 License.

## Overview
This terraform template imports an existing kubernetes cluster into a v3.2.1 MCM hub-cluster.
Supported kubernetes cluster environments include:
* IBM Cloud Private (ICP)
* IBM Cloud Private with Openshift (OCP)
* IBM Cloud Kubernetes Service (IKS)
* Microsoft Azure Kubernetes Service (AKS)
* Google Cloud Kubernetes Engine (GKE)
* Amazon EC2 Kubernetes Service (EKS)

## Prerequisites
* Tiller should not be installed within the kubernetes cluster

## Automation summary
The terraform template performs the following activities to import the specified kubernetes cluster into the MCM hub-cluster:
* Authenticates with the ICP server hosting the MCM hub-cluster
* Uses the given kubernetes cluster details to configure the import process
* Runs the import commands supported by the MCM hub-cluster

## Template input parameters

| Parameter Name                  | Parameter Description | Required | Allowed Values |
| :---                            | :--- | :--- | :--- |
| cluster_type                    | Indicates the type of environment supporting the target kubernetes cluster | true | icp, ocp, iks, aks, gke, eks |
| icp\_url                        | URL, including port, for the ICP server hosting the MCM hub-cluster | true | |
| icp\_admin\_user                | User name for connecting to the ICP server | true | |
| icp\_admin\_password            | Password for connecting to the ICP server | true | |
| cluster_name                    | Name of the target cluster to be imported into the MCM hub cluster | true | |
| cluster_namespace               | Namespace in the hub cluster into which the target cluster will be imported; Defaults to cluster name | | |

If accessing the target cluster via a username and authentication token:
| Parameter Name                  | Parameter Description | Required | Allowed Values |
| :---                            | :--- | :--- | :--- |
| cluster_endpoint                | URL for the target kubernetes cluster endpoint | | |
| cluster_user                    | Username for accessing the target kubernetes cluster | | |
| cluster_token                   | Token for authenticating with the target kubernetes cluster | | |

If accessing the target cluster using a KUBECONFIG file:
| Parameter Name                  | Parameter Description | Required | Allowed Values |
| :---                            | :--- | :--- | :--- |
| cluster_config                  | kubectl configuration text, Base64 encoded | IKS, AKS, GKE, EKS | |
| cluster\_certificate\_authority | Certificate for authenticating with cluster, Base64 encoded | IKS | |
| cluster_location                | Location (region / zone) where cluster is deployed in public cloud | EKS | |
| access\_key\_id                 | Key ID for gaining access to the cloud and Kubernetes Service | EKS | |
| secret\_access\_key             | Key secret for gaining access to the cloud and Kubernetes Service | EKS | |
| service\_account\_credentials   | JSON-formatted key for admin service account associated with cluster, Base64 encoded | GKE | |