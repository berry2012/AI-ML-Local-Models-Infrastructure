# AI/ML Local Models Infrastructure

This project creates AWS infrastructure for running local AI/ML models using FSx Lustre for high-performance storage and EC2 for compute.

## Architecture

- **VPC**: Configurable VPC selection via parameter
- **Subnet**: Configurable subnet selection via parameter  
- **FSx Lustre**: 2.4 TiB PERSISTENT_1 deployment for model storage
- **EC2 Instance**: Configurable instance type for model inference
- **Security Groups**: Properly configured for FSx and EC2 communication
- **SSM Document**: Manages model download process
- **Lambda Function**: Python 3.13 function that triggers SSM document execution
- **Custom Resource**: CloudFormation custom resource to orchestrate model downloads

## Model Download Process

Instead of using EC2 UserData, this infrastructure uses a more robust approach:

1. **SSM Document** (`ModelDownloadDocument`): Contains all the commands to download models
2. **Lambda Function** (`ModelDownloadLambda`): Python 3.13 function that executes the SSM document
3. **Custom Resource** (`ModelDownloadTrigger`): Triggers the Lambda function during stack creation
4. **Monitoring**: Full CloudWatch logging for troubleshooting

## Models Included

The infrastructure automatically downloads and stores these models:

1. **GPT4All Llama3** (`Meta-Llama-3-8B-Instruct.Q4_0.gguf`)
   - Size: ~4.66GB
   - Location: `/mnt/fsx/models/gpt4all/`
   - Usage: Python GPT4All library

2. **GPT-OSS-20B** (OpenAI GPT-OSS-20B)
   - Source: Hugging Face `openai/gpt-oss-20b`
   - Location: `/mnt/fsx/models/gpt-oss-20b/`
   - Usage: gpt-oss Python package

3. **DeepSeek R1-Distill-Llama-8B**
   - Source: Hugging Face `deepseek-ai/DeepSeek-R1-Distill-Llama-8B`
   - Location: `/mnt/fsx/models/deepseek-r1/`
   - Usage: Transformers library

4. **Mistral-7B-Instruct-v0.2**
   - Source: Hugging Face `mistralai/Mistral-7B-Instruct-v0.2`
   - Location: `/mnt/fsx/models/mistral-7b/`
   - Usage: Transformers library

## Files

- `local-models-infrastructure.yaml` - CloudFormation template
- `deploy.sh` - Deployment script
- `cleanup.sh` - Cleanup script
- `README.md` - This documentation

## Prerequisites

1. AWS CLI installed and configured
2. An existing EC2 Key Pair in your AWS account
3. Appropriate AWS permissions for:
   - CloudFormation
   - EC2
   - FSx
   - IAM
   - VPC (read access to existing resources)
   - Lambda
   - SSM

## Deployment

### Step 1: Deploy Infrastructure

```bash
./deploy.sh
```

The script will:
1. Validate the CloudFormation template
2. Prompt for VPC selection from available VPCs
3. Prompt for Subnet selection from available subnets in the chosen VPC
4. Prompt for EC2 Key Pair name
5. Prompt for instance type selection
6. Deploy the stack
7. Wait for completion
8. Display connection information

### Step 2: Connect to Instance

```bash
ssh -i your-key.pem ec2-user@<PUBLIC_IP>
```

### Step 3: Monitor Model Downloads

Monitor the model download process through CloudWatch Logs:

1. **Lambda Logs**: Check the Lambda function logs for execution status
2. **SSM Command History**: View SSM command execution in the AWS Console
3. **Instance Logs**: SSH to the instance and check `/var/log/amazon/ssm/`

```bash
# Check SSM agent logs on the instance
sudo tail -f /var/log/amazon/ssm/amazon-ssm-agent.log

# Check command execution logs
sudo tail -f /var/log/amazon/ssm/audits/audit-*.log
```

## Usage Examples

### GPT4All

```python
from gpt4all import GPT4All

model = GPT4All("/mnt/fsx/models/gpt4all/Meta-Llama-3-8B-Instruct.Q4_0.gguf")
with model.chat_session():
    response = model.generate("How can I run LLMs efficiently on my laptop?", max_tokens=1024)
    print(response)
```

### GPT-OSS-20B

```bash
cd /mnt/fsx/models/gpt-oss-20b
python -m gpt_oss.chat model/
```

### Transformers Models (Mistral, DeepSeek)

```python
from transformers import AutoTokenizer, AutoModelForCausalLM

# Mistral example
tokenizer = AutoTokenizer.from_pretrained("/mnt/fsx/models/mistral-7b")
model = AutoModelForCausalLM.from_pretrained("/mnt/fsx/models/mistral-7b")

inputs = tokenizer("Hello, how are you?", return_tensors="pt")
outputs = model.generate(**inputs, max_length=100)
response = tokenizer.decode(outputs[0], skip_special_tokens=True)
print(response)
```

## Cost Considerations

### FSx Lustre Costs
- **Storage**: 2.4 TiB PERSISTENT_1 at ~$0.145/GB-month = ~$358/month
- **Throughput**: 50 MB/s/TiB included (120 MB/s total)

### EC2 Costs (varies by instance type)
- **m5.xlarge**: ~$0.192/hour (~$140/month if running 24/7)
- **m5.2xlarge**: ~$0.384/hour (~$280/month if running 24/7)

### Lambda Costs
- **Execution**: Minimal cost for one-time model download trigger
- **Duration**: ~15 minutes maximum execution time

### Total Estimated Monthly Cost
- **Minimum**: ~$498/month (FSx + m5.xlarge)
- **Recommended**: Stop EC2 when not in use to reduce costs significantly

## Management

### View Stack Status
```bash
aws cloudformation describe-stacks --stack-name ai-ml-models-infrastructure
```

### Re-run Model Downloads
If you need to re-download models, you can manually execute the SSM document:

```bash
aws ssm send-command \
    --instance-ids i-1234567890abcdef0 \
    --document-name "ai-ml-models-infrastructure-ModelDownload" \
    --parameters "fsxDnsName=fs-1234567890abcdef0.fsx.us-east-1.amazonaws.com"
```

### Update Stack
Modify the template and run:
```bash
aws cloudformation update-stack --stack-name ai-ml-models-infrastructure --template-body file://local-models-infrastructure.yaml --capabilities CAPABILITY_IAM
```

### Cleanup
**WARNING**: This will delete ALL data including downloaded models!

```bash
./cleanup.sh
```

## Troubleshooting

### Model Download Issues
```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/ai-ml-models-infrastructure-ModelDownload"

# Check SSM command execution
aws ssm list-commands --instance-id i-1234567890abcdef0

# Get command details
aws ssm get-command-invocation --command-id "command-id" --instance-id i-1234567890abcdef0
```

### FSx Mount Issues
```bash
# Check if FSx is mounted
df -h | grep fsx

# Manually mount if needed
sudo mount -t lustre <FSX_DNS_NAME>@tcp:/fsx /mnt/fsx
```

### SSM Agent Issues
```bash
# Check SSM agent status
sudo systemctl status amazon-ssm-agent

# Restart SSM agent if needed
sudo systemctl restart amazon-ssm-agent
```

### Storage Space
```bash
# Check FSx usage
df -h /mnt/fsx

# Check model sizes
du -sh /mnt/fsx/models/*
```

## Security Notes

- Security groups are configured for minimal required access
- SSH access is open to 0.0.0.0/0 (consider restricting to your IP)
- FSx access is restricted to the EC2 security group
- IAM roles follow least privilege principle
- Lambda function has minimal required permissions
- SSM document execution is logged and auditable

## Advantages of SSM + Lambda Approach

1. **Better Error Handling**: Lambda provides detailed error reporting
2. **Retry Logic**: Can implement custom retry mechanisms
3. **Monitoring**: Full CloudWatch integration
4. **Scalability**: Can easily extend to multiple instances
5. **Security**: More granular permission control
6. **Debugging**: Better visibility into execution process
7. **Flexibility**: Easy to modify download logic without changing EC2 UserData

## Customization

### Different Models
Edit the SSM document's `downloadModels` step to add/remove models.

### Instance Types
Modify the `AllowedValues` in the `InstanceType` parameter for different options.

### Storage Size
Change the `StorageCapacity` parameter in the FSx resource (minimum 1.2 TiB, increments of 2.4 TiB).

### Lambda Timeout
Adjust the Lambda function timeout if model downloads take longer than expected.

## Support

For issues with:
- **AWS Resources**: Check CloudFormation events in AWS Console
- **Model Downloads**: Check Lambda and SSM logs in CloudWatch
- **Model Usage**: Refer to respective model documentation

Remember to stop or terminate resources when not in use to minimize costs!
