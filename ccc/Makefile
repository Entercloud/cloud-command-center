# Name of the virtual environment
VENV = .venv

# Python interpreter path
PYTHON = $(VENV)/bin/python3.11

# AWS CLI command
AWS = $(VENV)/bin/aws

# Azure CLI command
AZ = $(VENV)/bin/az

# Create the virtual environment and install dependencies
$(VENV):
	python3.11 -m venv $(VENV)
	$(PYTHON) -m pip install awscli azure-cli

# Command to connect to AWS
aws:
	$(AWS) configure

# Command to connect to Azure
az:
	$(AZ) login

# Default command
all: $(VENV) aws az

# Remove the virtual environment
clean:
	rm -rf $(VENV)
