# Health-InfraOps Hyper-V Templates

VM templates and configuration files for Hyper-V deployment.

## Contents

- `infokes-gen2-template.vhdx` - Generation 2 VM template
- `cluster-config.xml` - Failover cluster configuration
- `switch-templates.ps1` - Virtual switch templates

## Deployment

Use the provided PowerShell scripts for automated deployment:
- `New-VMCluster.ps1` - Create Hyper-V cluster
- `Configure-VMSwitch.ps1` - Configure virtual switches