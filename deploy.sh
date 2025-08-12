#!/bin/bash

# Deployment script for AI/ML Models Infrastructure
set -e

# Configuration
STACK_NAME="ai-ml-models-infrastructure"
TEMPLATE_FILE="local-models-infrastructure.yaml"
REGION="us-east-1"  # Update this to your preferred region

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}AI/ML Models Infrastructure Deployment Script${NC}"
echo "=============================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: Template file $TEMPLATE_FILE not found${NC}"
    exit 1
fi

# Get available VPCs
echo -e "${YELLOW}Available VPCs:${NC}"
aws ec2 describe-vpcs --region $REGION --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock,State]' --output table

# Prompt for VPC selection
read -p "Enter the VPC ID to use: " VPC_ID

if [ -z "$VPC_ID" ]; then
    echo -e "${RED}Error: VPC ID is required${NC}"
    exit 1
fi

# Validate VPC exists
VPC_EXISTS=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --region $REGION --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
if [ "$VPC_EXISTS" = "None" ]; then
    echo -e "${RED}Error: VPC $VPC_ID not found${NC}"
    exit 1
fi

echo -e "${GREEN}Selected VPC: $VPC_ID${NC}"

# Get available subnets in the selected VPC
echo -e "${YELLOW}Available Subnets in VPC $VPC_ID:${NC}"
aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0],CidrBlock,AvailabilityZone,State]' --output table

# Prompt for Subnet selection
read -p "Enter the Subnet ID to use: " SUBNET_ID

if [ -z "$SUBNET_ID" ]; then
    echo -e "${RED}Error: Subnet ID is required${NC}"
    exit 1
fi

# Validate subnet exists and is in the selected VPC
SUBNET_VPC=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --query 'Subnets[0].VpcId' --output text 2>/dev/null || echo "None")
if [ "$SUBNET_VPC" = "None" ]; then
    echo -e "${RED}Error: Subnet $SUBNET_ID not found${NC}"
    exit 1
elif [ "$SUBNET_VPC" != "$VPC_ID" ]; then
    echo -e "${RED}Error: Subnet $SUBNET_ID is not in VPC $VPC_ID${NC}"
    exit 1
fi

echo -e "${GREEN}Selected Subnet: $SUBNET_ID${NC}"

# Get available key pairs
echo -e "${YELLOW}Available EC2 Key Pairs:${NC}"
aws ec2 describe-key-pairs --region $REGION --query 'KeyPairs[].KeyName' --output table

# Prompt for key pair name
read -p "Enter the name of your EC2 Key Pair: " KEY_PAIR_NAME

if [ -z "$KEY_PAIR_NAME" ]; then
    echo -e "${RED}Error: Key pair name is required${NC}"
    exit 1
fi

# Prompt for instance type
echo -e "${YELLOW}Available instance types:${NC}"
echo "1. m5.large (2 vCPU, 8 GB RAM) - Basic"
echo "2. m5.xlarge (4 vCPU, 16 GB RAM) - Recommended"
echo "3. m5.2xlarge (8 vCPU, 32 GB RAM) - High performance"
echo "4. c5.xlarge (4 vCPU, 8 GB RAM) - Compute optimized"
echo "5. c5.2xlarge (8 vCPU, 16 GB RAM) - Compute optimized"

read -p "Select instance type (1-5, default: 2): " INSTANCE_CHOICE
INSTANCE_CHOICE=${INSTANCE_CHOICE:-2}

case $INSTANCE_CHOICE in
    1) INSTANCE_TYPE="m5.large" ;;
    2) INSTANCE_TYPE="m5.xlarge" ;;
    3) INSTANCE_TYPE="m5.2xlarge" ;;
    4) INSTANCE_TYPE="c5.xlarge" ;;
    5) INSTANCE_TYPE="c5.2xlarge" ;;
    *) INSTANCE_TYPE="m5.xlarge" ;;
esac

echo -e "${GREEN}Selected instance type: $INSTANCE_TYPE${NC}"

# Validate template
echo -e "${YELLOW}Validating CloudFormation template...${NC}"
aws cloudformation validate-template --template-body file://$TEMPLATE_FILE --region $REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Template validation successful${NC}"
else
    echo -e "${RED}Template validation failed${NC}"
    exit 1
fi

# Deploy stack
echo -e "${YELLOW}Deploying CloudFormation stack...${NC}"
aws cloudformation create-stack \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --parameters ParameterKey=VpcId,ParameterValue=$VPC_ID \
                 ParameterKey=SubnetId,ParameterValue=$SUBNET_ID \
                 ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR_NAME \
                 ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE \
    --capabilities CAPABILITY_IAM \
    --region $REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Stack creation initiated successfully${NC}"
    echo -e "${YELLOW}Waiting for stack creation to complete...${NC}"
    
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Stack created successfully!${NC}"
        
        # Get outputs
        echo -e "${YELLOW}Stack Outputs:${NC}"
        aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs' --output table
        
        # Get SSH command
        PUBLIC_IP=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`EC2PublicIP`].OutputValue' --output text)
        
        echo ""
        echo -e "${GREEN}Deployment Complete!${NC}"
        echo "===================="
        echo -e "SSH Command: ${YELLOW}ssh -i $KEY_PAIR_NAME.pem ec2-user@$PUBLIC_IP${NC}"
        echo ""
        echo "Next steps:"
        echo "1. SSH into the instance"
        echo "2. Check model download progress: sudo journalctl -u model-download.service -f"
        echo "3. Models will be available at: /mnt/fsx/models/"
        echo "4. Read the README.md file for usage examples"
        
    else
        echo -e "${RED}Stack creation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}Failed to initiate stack creation${NC}"
    exit 1
fi
