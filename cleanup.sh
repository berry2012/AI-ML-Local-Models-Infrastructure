#!/bin/bash

# Cleanup script for AI/ML Models Infrastructure
set -e

# Configuration
STACK_NAME="ai-ml-models-infrastructure"
REGION="us-east-1"  # Update this to match your deployment region

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}AI/ML Models Infrastructure Cleanup Script${NC}"
echo "=============================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check if stack exists
echo -e "${YELLOW}Checking if stack exists...${NC}"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")

if [ "$STACK_STATUS" = "STACK_NOT_FOUND" ]; then
    echo -e "${YELLOW}Stack $STACK_NAME not found. Nothing to clean up.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found stack: $STACK_NAME (Status: $STACK_STATUS)${NC}"

# Confirm deletion
echo -e "${RED}WARNING: This will delete the entire infrastructure including:${NC}"
echo "- EC2 instance and all data on it"
echo "- FSx Lustre file system and ALL MODELS stored on it"
echo "- Security groups"
echo "- IAM roles and policies"
echo ""
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

# Delete stack
echo -e "${YELLOW}Deleting CloudFormation stack...${NC}"
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Stack deletion initiated successfully${NC}"
    echo -e "${YELLOW}Waiting for stack deletion to complete...${NC}"
    
    aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Stack deleted successfully!${NC}"
        echo "All resources have been cleaned up."
    else
        echo -e "${RED}Stack deletion failed or timed out${NC}"
        echo "Please check the AWS Console for more details."
        exit 1
    fi
else
    echo -e "${RED}Failed to initiate stack deletion${NC}"
    exit 1
fi
