#login to gcloud
gcloud info
gcloud components update
gcloud init
gcloud auth list
gcloud config list
gcloud auth application-default login

#get Kube credentials
gcloud container clusters get-credentials $(terraform output -raw kubernetes_cluster_name) --region $(terraform output -raw region)