# AIO POC RACI Matrix

This RACI matrix aligns the major implementation workstreams to four delivery groups:
- **Platform Team**
- **OT Team**
- **Security Team**
- **App Team**

Legend:
- **R** = Responsible
- **A** = Accountable
- **C** = Consulted
- **I** = Informed

| Workstream / Deliverable                                          | Platform Team   | OT Team   | Security Team   | App Team   |
|:------------------------------------------------------------------|:----------------|:----------|:----------------|:-----------|
| Define POC scope and site boundary                                | A               | C         | C               | C          |
| Approve landing zone, RG, tags, and ownership model               | A               | C         | C               | I          |
| Build and harden K3s / Arc cluster                                | R               | C         | C               | I          |
| Enable OIDC, workload identity, custom locations, cluster connect | R               | I         | A               | I          |
| Design Key Vault boundary and private connectivity                | R               | I         | A               | I          |
| Approve PKI / certificate issuer strategy                         | C               | I         | A               | I          |
| Implement secret delivery pattern (CSI or SSE)                    | R               | I         | A               | C          |
| Enable GitOps / Flux and baseline repos                           | A               | I         | C               | R          |
| Deploy Azure Policy and baseline initiatives                      | R               | I         | A               | I          |
| Enable Defender for Containers                                    | R               | I         | A               | I          |
| Define in-cluster network policies                                | R               | C         | A               | C          |
| Approve site firewall / egress rules                              | C               | A         | C               | I          |
| Pre-create Azure Monitor / Log Analytics / Grafana                | A               | I         | C               | I          |
| Define alert rules and runbooks                                   | R               | C         | A               | C          |
| Deploy AIO secure settings                                        | A               | C         | C               | R          |
| Design Event Hubs / Event Grid integration                        | C               | C         | C               | A          |
| Design ADLS layout, ACL model, and retention                      | C               | I         | C               | A          |
| Deploy Databricks and Unity Catalog (if in scope)                 | C               | I         | C               | A          |
| Deploy PostgreSQL or MySQL edge database                          | C               | I         | C               | A          |
| Test recovery / failover / disconnected operation                 | R               | A         | C               | C          |
| Publish operational handoff artifacts                             | A               | C         | C               | C          |
