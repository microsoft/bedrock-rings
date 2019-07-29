# Source build.sh
. build.sh --source-only

# Initialization
verify_access_token
init
helm init
get_os

# Fabrikate
get_fab_version
download_fab

# Clone HLD repo
git_connect

# Extract the subcomponent from the Build ID (e.g. 'hello-rings-featurec-1234', in the format 'servicename-branch-buildid')
SUBCOMPONENT=$(echo "$(Build.BuildId)" | sed 's/\-[^-]*$//')
echo "SUBCOMPONENT = $SUBCOMPONENT" # e.g. 'hello-rings-featurec'

cd $SERVICE

# Setting the metadata for the ring.yaml
buildid=$(echo ${YAML_PATH_VALUE##*-})
echo "buildid=$buildid"
BUILD_URL=$(System.TaskDefinitionsURI)
echo "BUILD_URL=$BUILD_URL"
BUILD_PROJECT=$(System.TeamProject)
echo "BUILD_PROJECT=$BUILD_PROJECT"
echo "curl $BUILD_URL$BUILD_PROJECT/_apis/build/builds/$buildid\?api-version\=5.0"
commitId=$(curl -s $BUILD_URL$BUILD_PROJECT/_apis/build/builds/$buildid\?api-version\=5.0 | jq -r ".sourceVersion")
echo "commitId=$commitId"
buildTime=$(curl -s $BUILD_URL$BUILD_PROJECT/_apis/build/builds/$buildid\?api-version\=5.0 | jq -r ".finishTime")
echo "buildTime=$buildTime"
author=$(curl -s $BUILD_URL$BUILD_PROJECT/_apis/build/builds/$buildid\?api-version\=5.0 | jq -r ".requestedFor.displayName")
echo "author=$author"
branch=$(curl -s $BUILD_URL$BUILD_PROJECT/_apis/build/builds/$buildid\?api-version\=5.0 | jq -r ".sourceBranch")
branch=$(echo ${branch##*/})
echo "branch=$branch"

# Use Fabrikate to set image tag, and ring metadata
echo "FAB SET"
if [[ ! -z $FAB_ENV_NAME ]]
then
    echo "fab set --environment $FAB_ENV_NAME --subcomponent $SUBCOMPONENT $YAML_PATH=$YAML_PATH_VALUE $YAML_PATH_2=$YAML_PATH_VALUE_2"
    fab set --environment $FAB_ENV_NAME --subcomponent $SUBCOMPONENT $YAML_PATH=$YAML_PATH_VALUE $YAML_PATH_2=$YAML_PATH_VALUE_2
    echo "fab set --subcomponent $SUBCOMPONENT branchName=$branch buildId=$buildid commitId=$commitId"
    fab set --environment $FAB_ENV_NAME --subcomponent $SUBCOMPONENT branchName=$branch buildId=$buildid commitId=$commitId buildDate="$buildTime"

else
    echo "fab set --subcomponent $SUBCOMPONENT $YAML_PATH=$YAML_PATH_VALUE $YAML_PATH_2=$YAML_PATH_VALUE_2"
    fab set --subcomponent $SUBCOMPONENT $YAML_PATH=$YAML_PATH_VALUE $YAML_PATH_2=$YAML_PATH_VALUE_2
    echo "fab set --subcomponent $SUBCOMPONENT branchName=$branch buildId=$buildid commitId=$commitId"
    fab set --subcomponent $SUBCOMPONENT branchName=$branch buildId=$buildid commitId=$commitId buildDate="$buildTime"
fi

# Execute fab add to add this branch to the service HLD
echo "fab add $SUBCOMPONENT --source $SRC_REPO --branch $branch --method git --path ring --type component"
fab add $SUBCOMPONENT --source $SRC_REPO --branch $branch --method git --path ring --type component

# Execute a series of git commands to add, commit, and push new content to the Cluster HLD repo.
echo "GIT STATUS"
git status

echo "GIT ADD"
git add -A

echo "GIT CHECKOUT"
PR_BRANCH_NAME=pr_$SUBCOMPONENT_$YAML_PATH_VALUE
git checkout -b $PR_BRANCH_NAME

# Set git identity
git config user.email "admin@azuredevops.com"
git config user.name "Automated Account"

echo "GIT COMMIT"
git commit -m "Updating image tag for service $branch"

echo "GIT PUSH"
git_push

# If using GitHub repos...
echo "CREATE PULL REQUEST"
export GITHUB_TOKEN=$ACCESS_TOKEN_SECRET
hub pull-request -m "Updating service $branch"

# If using AzDo repos (comment above, and uncomment below)
# You will need to specify variables $ORG_NAME and $PROJECT_NAME
#export AZURE_DEVOPS_EXT_PAT=$ACCESS_TOKEN_SECRET
#az devops configure --defaults organization=$ORG_NAME project=$PROJECT_NAME
#echo "Making pull request from $pr_branch_name against master"
#az repos pr create --org $ORG_NAME  -p $PROJECT_NAME -r $REPO -s "$pr_branch_name" -t "master" --title "Updating service $branch_name" -d "Automated pull request for branch $branch_name"
