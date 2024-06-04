# How to install and use the standalone version


1. Go into your GCP console and launch Cloud shell, make sure that the default project is set to the project you want to deploy into
    `` gcloud config set project PROJECT_ID ``
2. Issue the following statement to download the terraform script
3. `` wget https://raw.githubusercontent.com/c-damien/gcp-public-demos/main/data-beans/terraform-script/standalone/main.tf ``

1. Let's initialise Terraform
   ``terraform init``
2. And upgrade
   ``terraform init --upgrade``
6. Finally, launch the script:
 ``terraform apply``

After a few minutes all should be provisionned and ready to be used,

Use the following instructions to complete the root cause analysis:
(link)[https://docs.google.com/document/d/179Ba2yIqaM9_VIdalgbU6T0O_QhniFT-zOChH6zaK6I/edit?usp=sharing&resourcekey=0-pJGruYc7FusQ-WHJBNy46Q]
