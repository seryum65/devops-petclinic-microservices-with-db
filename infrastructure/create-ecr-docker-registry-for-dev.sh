PATH="$PATH:/usr/local/bin"
APP_REPO_NAME="seryum-repo/petclinic-app-dev"
AWS_REGION="eu-north-1"

aws ecr describe-repositories --region ${AWS_REGION} --repository-name ${APP_REPO_NAME} || \
aws ecr create-repository \
--repository-name ${APP_REPO_NAME} \
--image-scanning-configuration scanOnPush=false \
--image-tag-mutability MUTABLE \
--region ${AWS_REGION}