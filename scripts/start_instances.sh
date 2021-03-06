#!/usr/bin/env bash

set -e
set -x

# get parent stack
PARENT_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "{{CloudFormationStack}}" --query 'Stacks[].ParentId' --output text)

# Lustre substack
LUSTRE_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK" --logical-resource-id "LustreStack"  --query StackResources[*].PhysicalResourceId --output text)

# MGTNode
MGTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $LUSTRE_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MGTNode`].PhysicalResourceId' --output text)
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MGTNode_ID

# MDTNode
MDTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $LUSTRE_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MDTNode`].PhysicalResourceId' --output text)

# StartMDTNode and MGTNode
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MGTNode_ID $MDTNode_ID

# Check status of MDTNode and MGTNode
STATUS='status'
until [ 2 == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $MGTNode_ID $MDTNode_ID --query InstanceStatuses[*].SystemStatus --output text)
done

# OSS Nodes
OSS_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $LUSTRE_STACK  --query 'StackResources[?LogicalResourceId == `OSSEC2Instances`].PhysicalResourceId' --output text)
if [ -f /tmp/oss_nodes ]; then
  rm /tmp/oss_nodes
fi
:
# this value has the oss VM ids separated by ":". Convert it into an array
IFS=':' read -r -a array <<< "$OSS_IDs"
for id in "${array[@]}"
do
  echo "$id" >> /tmp/oss_nodes
done

# Start oss nodes
o_ids=$(cat /tmp/oss_nodes)
o_ct=$(cat /tmp/oss_nodes | wc -w)
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $o_ids

# Check status of ossnodes
STATUS='status'
STATUS_CHECK_STOPPED='status'
until [ $o_ct == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $o_ids --query InstanceStatuses[*].SystemStatus --output text)
  STATUS_CHECK_STOPPED=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-ids $o_ids --query Reservations[*].Instances[*].State --output text)
  if [[ $(echo "$STATUS_CHECK_STOPPED" | grep -o "stopped" | wc -l) > 0 ]]; then aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $o_ids; fi
done

# SAS Grid substack
SAS_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK" --logical-resource-id "SASGridStack"  --query StackResources[*].PhysicalResourceId --output text)

# Metadata VM
MetadataNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMetadata`].PhysicalResourceId' --output text)
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MetadataNode_ID

# Midtier VM
MidtierNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMidTier`].PhysicalResourceId' --output text)
echo "$MidtierNode_ID" >> /tmp/sas_nodes
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MidtierNode_ID

# Check status of midtier and metadata nodes
STATUS='status'
until [ 2 == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $MetadataNode_ID $MidtierNode_ID --query InstanceStatuses[*].SystemStatus --output text)
done

# Grid VMs
Grid_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?LogicalResourceId == `SASGridEC2Instances`].PhysicalResourceId' --output text)

if [ -f /tmp/sas_nodes ]; then
  rm /tmp/sas_nodes
fi

# this value has the grid VM ids separated by ":". Convert it into an array
IFS=':' read -r -a array <<< "$Grid_IDs"
for id in "${array[@]}"
do
  echo "$id" >> /tmp/sas_nodes
done

# Start sas nodes
s_ids=$(cat /tmp/sas_nodes)
s_ct=$(cat /tmp/sas_nodes | wc -l)
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $s_ids

# Check status of sas nodes
STATUS='status'
STATUS_CHECK_STOPPED='status'
until [ $s_ct == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $s_ids --query InstanceStatuses[*].SystemStatus --output text)
  STATUS_CHECK_STOPPED=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-ids $s_ids --query Reservations[*].Instances[*].State --output text)
  if [[ $(echo "$STATUS_CHECK_STOPPED" | grep -o "stopped" | wc -l) > 0 ]]; then aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $s_ids; fi
done

ansible-playbook lsf_restart.yml -vv
ansible-playbook sas_servers_start.yml -vv

