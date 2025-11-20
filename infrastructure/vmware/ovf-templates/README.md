# Health-InfraOps VMware OVF Templates

This directory contains OVF templates for deploying Health-InfraOps virtual machines.

## Available Templates

- `infokes-app-server.ovf` - Application server template
- `infokes-db-server.ovf` - Database server template  
- `infokes-lb-server.ovf` - Load balancer template
- `infokes-mon-server.ovf` - Monitoring server template

## Deployment

1. Import OVF template to vCenter
2. Configure network settings
3. Customize with Health-InfraOps specific configurations
4. Deploy from template

## Template Specifications

- **OS**: Ubuntu 22.04 LTS
- **Format**: OVF 2.0
- **Virtual Hardware**: VMware ESXi 7.0 compatible
- **Tools**: VMware Tools pre-installed