#!/bin/bash

# AI/ML Local Model Download Script
# This script downloads and sets up AI/ML models on FSx Lustre storage
# Usage: ./local-model-download.sh [FSX_DNS_NAME]
# export HF_TOKEN=your_huggingface_token_here # set your env


set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FSX_MOUNT_POINT="/fsx"
MODELS_DIR="$FSX_MOUNT_POINT/models"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. Consider running as ec2-user for better security."
    fi
}

# Function to install required packages
install_packages() {
    print_status "Installing required packages..."
    
    # Update system
    sudo yum update -y
    
    # Install required packages
    sudo yum install -y python3-pip git 
    sudo dnf install -y lustre-client
    
    # Install Python packages
    pip3 install --upgrade pip
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
    pip3 install transformers accelerate huggingface_hub gpt4all
    
    # Install Hugging Face CLI system-wide
    sudo pip3 install --upgrade huggingface_hub[cli]
    
    print_success "Package installation completed"
}

# Function to mount FSx Lustre
mount_fsx() {
    local fsx_dns="$1"
    local fsx_mount_name="$2"
    
    if [ -z "$fsx_dns" ]; then
        print_error "FSx DNS name not provided"
        echo "Usage: $0 <FSX_DNS_NAME>"
        echo "Example: $0 fs-1234567890abcdef0.fsx.us-east-1.amazonaws.com q7okhbev"
        exit 1
    fi
    
    print_status "Setting up FSx Lustre mount..."
    
    # Create mount point
    sudo mkdir -p $FSX_MOUNT_POINT
    
    # Check if already mounted
    if mountpoint -q $FSX_MOUNT_POINT; then
        print_success "FSx is already mounted at $FSX_MOUNT_POINT"
        return 0
    fi
    
    # Try to mount FSx with retries
    print_status "Attempting to mount FSx Lustre: $fsx_dns"
    local max_retries=10
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        print_status "Mount attempt $((retry_count + 1))/$max_retries..."
        
        if sudo mount -t lustre $fsx_dns@tcp:/$fsx_mount_name $FSX_MOUNT_POINT; then
            sudo chown -R ec2-user:ec2-user /fsx
            print_success "FSx mounted successfully!"
            break
        else
            print_warning "Mount failed, waiting 30 seconds before retry..."
            sleep 30
            retry_count=$((retry_count + 1))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        print_error "Failed to mount FSx after $max_retries attempts"
        exit 1
    fi
    
    # Verify mount
    if ! mountpoint -q $FSX_MOUNT_POINT; then
        print_error "FSx is not properly mounted"
        exit 1
    fi
    
    print_success "FSx mount verified successfully"
    df -h $FSX_MOUNT_POINT
    
    # Add to fstab for persistent mounting (optional)
if ! grep -q "$fsx_dns@tcp:/fsx" /etc/fstab; then
    print_status "Adding FSx to /etc/fstab for persistent mounting..."
    echo "$fsx_dns@tcp:/fsx $FSX_MOUNT_POINT lustre defaults,_netdev 0 0" | sudo tee -a /etc/fstab
fi
}

# Function to create model directories
create_directories() {
    print_status "Creating model directories..."
    
    # Create directories for models
    sudo mkdir -p $MODELS_DIR/{gpt4all,gpt-oss-20b,deepseek-r1,mistral-7b}
    
    # Set permissions
    sudo chmod -R 755 $MODELS_DIR
    sudo chown -R $USER:$USER $MODELS_DIR
    
    # Verify directories were created
    print_status "Model directory structure:"
    ls -la $MODELS_DIR/
    
    print_success "Model directories created successfully"
}

# Function to download GPT4All model
download_gpt4all() {
    print_status "Downloading GPT4All Llama3 model..."
    
    if [ ! -d "$MODELS_DIR/gpt4all" ]; then
        print_error "GPT4All directory not found: $MODELS_DIR/gpt4all"
        return 1
    fi
    
    cd $MODELS_DIR/gpt4all
    
    # Create Python script for GPT4All download
    cat > /tmp/download_gpt4all.py << 'PYTHON_EOF'
from gpt4all import GPT4All
import os

print("Downloading GPT4All Llama3 model...")
model = GPT4All("Meta-Llama-3-8B-Instruct.Q4_0.gguf", model_path="/fsx/models/gpt4all/")
print("GPT4All model downloaded successfully!")

# Test the model
print("Testing the model...")
with model.chat_session():
    response = model.generate("Hello, how are you?", max_tokens=50)
    print(f"Test response: {response}")
PYTHON_EOF
    
    python3 /tmp/download_gpt4all.py
    rm -f /tmp/download_gpt4all.py
    
    print_success "GPT4All model download completed"
    du -sh $MODELS_DIR/gpt4all/
}

# Function to download GPT-OSS-20B model
download_gpt_oss() {
    print_status "Downloading GPT-OSS-20B model..."
    
    if [ ! -d "$MODELS_DIR/gpt-oss-20b" ]; then
        print_error "GPT-OSS-20B directory not found: $MODELS_DIR/gpt-oss-20b"
        return 1
    fi
    
    # Create Hugging Face cache directory with proper permissions
    mkdir -p $HOME/.cache/huggingface
    chmod 755 $HOME/.cache/huggingface
    
    cd $MODELS_DIR/gpt-oss-20b
    hf download openai/gpt-oss-20b --include "original/*" --local-dir ./
    
    print_success "GPT-OSS-20B model download completed"
    du -sh $MODELS_DIR/gpt-oss-20b/
}

# Function to download DeepSeek R1 model
download_deepseek() {
    print_status "Downloading DeepSeek R1-Distill-Llama-8B model..."
    
    if [ ! -d "$MODELS_DIR/deepseek-r1" ]; then
        print_error "DeepSeek R1 directory not found: $MODELS_DIR/deepseek-r1"
        return 1
    fi
    
    cd $MODELS_DIR/deepseek-r1
    hf download deepseek-ai/DeepSeek-R1-Distill-Llama-8B --local-dir ./
    
    print_success "DeepSeek R1 model download completed"
    du -sh $MODELS_DIR/deepseek-r1/
}

# Function to download Mistral model
download_mistral() {
    print_status "Downloading Mistral-7B-Instruct-v0.2 model..."
    
    if [ ! -d "$MODELS_DIR/mistral-7b" ]; then
        print_error "Mistral-7B directory not found: $MODELS_DIR/mistral-7b"
        return 1
    fi
    
    # Check if HF token is set
    if [ -z "$HF_TOKEN" ]; then
        print_error "HF_TOKEN environment variable not set. Please set it with your Hugging Face token."
        return 1
    fi
    
    cd $MODELS_DIR/mistral-7b
    hf download mistralai/Mistral-7B-Instruct-v0.2 --token $HF_TOKEN --local-dir ./
    
    print_success "Mistral-7B model download completed"
    du -sh $MODELS_DIR/mistral-7b/
}

# Function to create usage examples
create_examples() {
    print_status "Creating usage examples..."
    
    # Create usage examples script
    cat > ~/model_examples.py << 'EOF'
#!/usr/bin/env python3
"""
Example usage scripts for the downloaded AI/ML models
"""

def test_gpt4all():
    """Test GPT4All model"""
    from gpt4all import GPT4All
    
    model_path = "/fsx/models/gpt4all/Meta-Llama-3-8B-Instruct.Q4_0.gguf"
    model = GPT4All(model_path, allow_download=False)
    
    with model.chat_session():
        response = model.generate("How can I run LLMs efficiently on my laptop?", max_tokens=1024)
        print("GPT4All Response:", response)

def test_gpt_oss():
    """Test GPT-OSS model"""
    print("To use GPT-OSS-20B:")
    print("cd /fsx/models/gpt-oss-20b")
    print("python -m gpt_oss.chat model/")

def test_transformers_models():
    """Test Hugging Face transformers models"""
    from transformers import AutoTokenizer, AutoModelForCausalLM
    
    # Example for Mistral
    print("Loading Mistral model...")
    tokenizer = AutoTokenizer.from_pretrained("/fsx/models/mistral-7b")
    model = AutoModelForCausalLM.from_pretrained("/fsx/models/mistral-7b")
    
    inputs = tokenizer("Hello, how are you?", return_tensors="pt")
    outputs = model.generate(**inputs, max_length=50)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    print("Mistral Response:", response)

def test_deepseek():
    """Test DeepSeek model"""
    from transformers import AutoTokenizer, AutoModelForCausalLM
    
    print("Loading DeepSeek R1 model...")
    tokenizer = AutoTokenizer.from_pretrained("/fsx/models/deepseek-r1")
    model = AutoModelForCausalLM.from_pretrained("/fsx/models/deepseek-r1")
    
    inputs = tokenizer("Explain quantum computing in simple terms:", return_tensors="pt")
    outputs = model.generate(**inputs, max_length=100)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    print("DeepSeek Response:", response)

if __name__ == "__main__":
    print("AI/ML Model Testing Examples")
    print("============================")
    print("Available functions:")
    print("- test_gpt4all()")
    print("- test_gpt_oss()")
    print("- test_transformers_models()")
    print("- test_deepseek()")
    print()
    print("Example usage:")
    print("python3 model_examples.py")
    print(">>> test_gpt4all()")
EOF
    
    chmod +x ~/model_examples.py
    
    # Create README
    cat > ~/README_models.md << 'EOF'
# AI/ML Models Setup

This instance has been configured with FSx Lustre storage for AI/ML models.

## Storage Layout
- FSx Lustre mounted at: `/mnt/fsx`
- Models directory: `/mnt/fsx/models/`

## Available Models
1. **GPT4All Llama3**: `/mnt/fsx/models/gpt4all/`
2. **GPT-OSS-20B**: `/mnt/fsx/models/gpt-oss-20b/`
3. **DeepSeek R1-Distill-Llama-8B**: `/mnt/fsx/models/deepseek-r1/`
4. **Mistral-7B-Instruct-v0.2**: `/mnt/fsx/models/mistral-7b/`

## Usage Examples

### GPT4All
```python
from gpt4all import GPT4All
model = GPT4All("/mnt/fsx/models/gpt4all/Meta-Llama-3-8B-Instruct.Q4_0.gguf")
with model.chat_session():
    print(model.generate("Your question here", max_tokens=1024))
```

### GPT-OSS-20B
```bash
cd /mnt/fsx/models/gpt-oss-20b
python -m gpt_oss.chat model/
```

### Transformers Models (Mistral, DeepSeek)
```python
from transformers import AutoTokenizer, AutoModelForCausalLM

tokenizer = AutoTokenizer.from_pretrained("/mnt/fsx/models/mistral-7b")
model = AutoModelForCausalLM.from_pretrained("/mnt/fsx/models/mistral-7b")
```

## Testing
Run the example script: `python3 model_examples.py`

## Notes
- All models are stored persistently on FSx Lustre
- FSx provides high-performance shared storage
- Models are accessible across instance restarts
EOF
    
    print_success "Usage examples created in ~/model_examples.py and ~/README_models.md"
}

# Function to show final summary
show_summary() {
    print_success "Model download completed successfully!"
    echo
    echo -e "${BLUE}=== SUMMARY ===${NC}"
    echo "Models downloaded to: $MODELS_DIR"
    echo
    echo "Model sizes:"
    du -sh $MODELS_DIR/* 2>/dev/null || echo "No models found"
    echo
    echo "Total storage used:"
    du -sh $MODELS_DIR 2>/dev/null || echo "Directory not found"
    echo
    echo "FSx mount status:"
    df -h $FSX_MOUNT_POINT 2>/dev/null || echo "Not mounted"
    echo
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Read the documentation: cat ~/README_models.md"
    echo "2. Test the models: python3 ~/model_examples.py"
    echo "3. Start using your AI/ML models!"
}

# Main execution
main() {
    echo -e "${GREEN}AI/ML Local Model Download Script${NC}"
    echo "=================================="
    echo
    
    # Check if FSx DNS name is provided
    if [ $# -eq 0 ]; then
        print_error "FSx DNS name is required"
        echo "Usage: $0 <FSX_DNS_NAME>"
        echo "Example: $0 fs-1234567890abcdef0.fsx.us-east-1.amazonaws.com"
        echo
        echo "You can find your FSx DNS name in the AWS Console or CloudFormation outputs"
        exit 1
    fi
    
    local fsx_dns="$1"
    local fsx_mount_name="$2"
    
    # Check if running as root
    check_root
    
    # Install packages
    install_packages
    
    # Mount FSx
    mount_fsx "$fsx_dns"
    
    # Create directories
    create_directories
    
    # Download models
    print_status "Starting model downloads..."
    download_gpt4all
    download_gpt_oss
    download_deepseek
    download_mistral
    
   
    # Show summary
    show_summary

    # Create examples
    create_examples    
}

# Run main function with all arguments
main "$@"

