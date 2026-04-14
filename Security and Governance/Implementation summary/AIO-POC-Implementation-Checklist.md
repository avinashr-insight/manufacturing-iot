# AIO POC Implementation Checklist

## Purpose
This document consolidates the security and governance controls from the uploaded AIO/K3s reference designs into a prescriptive implementation checklist for an engineering team deploying a proof of concept (POC).

## Scope assumptions
- Azure IoT Operations runs on an Arc-enabled K3s cluster.
- The POC uses Azure as the governance plane and Kubernetes/Arc as the edge workload plane.
- The POC may include Event Hubs and/or Event Grid, ADLS Gen2, optional Databricks, and one optional edge database pattern (PostgreSQL).
- The POC is designed to support a connected or semi-disconnected site model.

## Minimum viable secure POC baseline
- Arc-enabled K3s with OIDC issuer, workload identity, cluster connect, and custom locations.
- GitOps and Azure Policy for baseline governance.
- Key Vault with private access, RBAC, soft delete, purge protection, and a single approved secret delivery pattern.
- Azure Monitor, Log Analytics, and alerting before go-live.
- Defender for Containers enabled.
- NetworkPolicy default deny with only approved east-west flows.
- Event Hubs/Event Grid, ADLS, and optional analytics/database components deployed only after the platform baseline is complete.

## Ordered implementation checklist

### Phase 0 – Architecture decisions and scope lock

### Phase 0
- [ ] **AZ-001 – Define POC site, environment, and criticality boundary**  
  - Service / Component: Program / Platform  
  - Primary owner: Platform  
  - Source documents: AIO Governance; ADLS
- [ ] **AZ-002 – Decide connected vs semi-disconnected operating model**  
  - Service / Component: Connectivity / Resilience  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Key Vault; PostgreSQL
- [ ] **AZ-003 – Select primary cloud eventing pattern (Event Hubs and/or Event Grid)**  
  - Service / Component: Integration / Messaging  
  - Primary owner: App  
  - Source documents: Event Hubs; Event Grid
- [ ] **AZ-004 – Select retained storage pattern (ADLS) and analytics scope (Databricks optional)**  
  - Service / Component: Storage / Analytics  
  - Primary owner: App  
  - Source documents: ADLS; Databricks

### Phase 1
- [ ] **GOV-001 – Create dedicated subscription and/or resource group aligned to site boundary**  
  - Service / Component: Azure Landing Zone  
  - Primary owner: Platform  
  - Source documents: AIO Governance; ADLS; Azure Monitor; Event Hubs
- [ ] **GOV-002 – Use one AIO instance per resource group**  
  - Service / Component: AIO / Azure  
  - Primary owner: Platform  
  - Source documents: AIO Governance
- [ ] **GOV-003 – Apply required tags: site, environment, owner, criticality, cost center, connectivity model, data classification, patch ring**  
  - Service / Component: Azure Resource Manager  
  - Primary owner: Platform  
  - Source documents: AIO Governance; ADLS; Azure Monitor; Event Hubs; Event Grid
- [ ] **GOV-004 – Document ownership across platform, OT, security, app/integration, data/analytics, PKI, and operations**  
  - Service / Component: Operating Model  
  - Primary owner: Platform  
  - Source documents: Event Grid; Event Hubs; Key Vault; Databricks; Azure Monitor
- [ ] **IAM-001 – Use group-based Azure RBAC instead of direct user assignments**  
  - Service / Component: Entra ID / Azure RBAC  
  - Primary owner: Security  
  - Source documents: AIO Governance; Key Vault; Azure Monitor
- [ ] **IAM-002 – Separate human access roles for platform admin, security operator, observability reader, OT operator, and app deployer**  
  - Service / Component: Entra ID / Azure RBAC  
  - Primary owner: Security  
  - Source documents: AIO Governance; Azure Monitor; Event Hubs; Event Grid
- [ ] **IAM-003 – Protect privileged access with MFA, Conditional Access, and PIM where available**  
  - Service / Component: Entra ID  
  - Primary owner: Security  
  - Source documents: AIO Governance; Key Vault; Azure Monitor

### Phase 2
- [ ] **K3S-001 – Build Arc-enabled K3s cluster on hardened supported host baseline**  
  - Service / Component: K3s / Arc  
  - Primary owner: Platform  
  - Source documents: AIO Governance; ADLS; Event Hubs
- [ ] **K3S-002 – Enable K3s secrets encryption at rest**  
  - Service / Component: K3s  
  - Primary owner: Platform  
  - Source documents: Key Vault; PostgreSQL
- [ ] **K3S-003 – Enable protect-kernel-defaults / CIS-aligned host controls**  
  - Service / Component: K3s / Host OS  
  - Primary owner: Platform  
  - Source documents: Key Vault; PostgreSQL; AIO Governance
- [ ] **K3S-004 – Enable API server audit logging and controlled SSH break-glass**  
  - Service / Component: K3s / Host OS  
  - Primary owner: Platform  
  - Source documents: Key Vault; AIO Governance; PostgreSQL
- [ ] **ARC-001 – Arc-enable the K3s cluster**  
  - Service / Component: Azure Arc  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Azure Monitor; Event Hubs; ADLS
- [ ] **ARC-002 – Enable OIDC issuer, workload identity, cluster connect, and custom locations**  
  - Service / Component: Azure Arc  
  - Primary owner: Platform  
  - Source documents: AIO Governance; PostgreSQL
- [ ] **ARC-003 – Create baseline namespaces for arc, aio, platform-security, line-apps, and optional database namespaces**  
  - Service / Component: Kubernetes  
  - Primary owner: Platform  
  - Source documents: AIO Governance; PostgreSQL
- [ ] **ARC-004 – Use custom locations only for namespaces that require Azure-side deployment targets**  
  - Service / Component: Azure Arc / Kubernetes  
  - Primary owner: Platform  
  - Source documents: AIO Governance; PostgreSQL

### Phase 3
- [ ] **PKI-001 – Adopt enterprise or plant-controlled CA / issuer for production-style AIO and DB trust**  
  - Service / Component: PKI / Certificates  
  - Primary owner: Security  
  - Source documents: Certificate Management; AIO Governance; PostgreSQL
- [ ] **PKI-002 – Define certificate sets for AIO, workload TLS, client CA bundles, admin/backup certs as needed**  
  - Service / Component: PKI / Certificates  
  - Primary owner: Security  
  - Source documents: Certificate Management; PostgreSQL
- [ ] **IAM-004 – Create dedicated user-assigned managed identities per trust boundary**  
  - Service / Component: Entra ID / Managed Identity  
  - Primary owner: Security  
  - Source documents: AIO Governance; Key Vault; PostgreSQL
- [ ] **IAM-005 – Bind managed identities to dedicated Kubernetes service accounts; never use default service accounts**  
  - Service / Component: Entra ID / Kubernetes  
  - Primary owner: Security  
  - Source documents: AIO Governance; Key Vault; Event Grid; Event Hubs; PostgreSQL

### Phase 4
- [ ] **KV-001 – Create dedicated Key Vault boundary for POC / non-prod and separate from prod**  
  - Service / Component: Azure Key Vault  
  - Primary owner: Security  
  - Source documents: Key Vault
- [ ] **KV-002 – Enable Azure RBAC permission model on Key Vault**  
  - Service / Component: Azure Key Vault  
  - Primary owner: Security  
  - Source documents: Key Vault
- [ ] **KV-003 – Enable soft delete, purge protection, diagnostics, and expiration governance**  
  - Service / Component: Azure Key Vault  
  - Primary owner: Security  
  - Source documents: Key Vault
- [ ] **KV-004 – Choose one secret delivery pattern: CSI provider for connected sites or Secret Store Extension for semi-disconnected sites**  
  - Service / Component: Azure Key Vault / Arc  
  - Primary owner: Platform  
  - Source documents: Key Vault; PostgreSQL; AIO Governance
- [ ] **KV-005 – Do not run the CSI provider and Secret Store Extension side-by-side in the same cluster**  
  - Service / Component: Azure Key Vault / Arc  
  - Primary owner: Platform  
  - Source documents: Key Vault; PostgreSQL; AIO Governance
- [ ] **KV-006 – Publish Key Vault through Private Endpoint and private DNS; disable public network access by default**  
  - Service / Component: Azure Key Vault / Networking  
  - Primary owner: Security  
  - Source documents: Key Vault

### Phase 5
- [ ] **GIT-001 – Enable Flux v2 GitOps and make Git the source of truth for baseline config**  
  - Service / Component: Azure Arc / Flux  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Event Grid; Event Hubs
- [ ] **GIT-002 – Create repo structure for platform, aio, site overlays, and optional db/eventing/storage/monitoring layers**  
  - Service / Component: Source Control / GitOps  
  - Primary owner: Platform  
  - Source documents: AIO Governance
- [ ] **POL-001 – Install Azure Policy for Kubernetes and start baseline controls in Audit mode**  
  - Service / Component: Azure Policy  
  - Primary owner: Security  
  - Source documents: AIO Governance; PostgreSQL
- [ ] **POL-002 – Define policy initiatives for cluster baseline, workload hardening, extension deployment, monitoring/Defender, labels/tags, network policies, and secret/cert standards**  
  - Service / Component: Azure Policy  
  - Primary owner: Security  
  - Source documents: AIO Governance; Key Vault; Azure Monitor
- [ ] **DEF-001 – Enable Defender for Containers on the Arc-connected cluster**  
  - Service / Component: Defender for Cloud  
  - Primary owner: Security  
  - Source documents: AIO Governance; Event Hubs; Event Grid; ADLS

### Phase 6
- [ ] **NET-001 – Implement default-deny Kubernetes NetworkPolicy in workload namespaces**  
  - Service / Component: Kubernetes Networking  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Event Grid; PostgreSQL
- [ ] **NET-002 – Allow only explicit east-west flows between AIO, approved apps, observability, and optional DB namespaces**  
  - Service / Component: Kubernetes Networking  
  - Primary owner: Platform  
  - Source documents: AIO Governance; PostgreSQL; Event Grid
- [ ] **NET-003 – Keep database services ClusterIP only; do not expose via NodePort / public ingress**  
  - Service / Component: Kubernetes Networking  
  - Primary owner: Platform  
  - Source documents: PostgreSQL
- [ ] **NET-004 – Define site egress model (Arc gateway, explicit proxy, allowlist, private WAN) and approve Azure dependencies**  
  - Service / Component: Factory Network / Firewall  
  - Primary owner: OT  
  - Source documents: AIO Governance; Azure Monitor; Event Hubs; Event Grid; ADLS

### Phase 7
- [ ] **MON-001 – Pre-create and govern Azure Monitor workspace, Log Analytics workspace, Managed Grafana, and alert resources**  
  - Service / Component: Azure Monitor  
  - Primary owner: Platform  
  - Source documents: Azure Monitor
- [ ] **MON-002 – Enable Azure Monitor metrics and container insights for Arc-enabled K3s**  
  - Service / Component: Azure Monitor / Arc  
  - Primary owner: Platform  
  - Source documents: Azure Monitor; AIO Governance
- [ ] **MON-003 – Define alerts for node health, restarts, AIO broker/connector failures, cert expiry, secret sync failures, private connectivity failures, and telemetry pipeline failures**  
  - Service / Component: Azure Monitor  
  - Primary owner: Platform  
  - Source documents: Azure Monitor; Event Grid; Event Hubs; Key Vault; AIO Governance
- [ ] **MON-004 – Use AMPLS + private connectivity for Azure Monitor where required**  
  - Service / Component: Azure Monitor / Networking  
  - Primary owner: Platform  
  - Source documents: Azure Monitor

### Phase 8
- [ ] **AIO-001 – Deploy AIO with secure settings on the Arc-enabled K3s cluster**  
  - Service / Component: Azure IoT Operations  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Event Hubs
- [ ] **AIO-002 – Use separate managed identities for AIO component access and secret synchronization**  
  - Service / Component: Azure IoT Operations / Entra ID  
  - Primary owner: Security  
  - Source documents: AIO Governance; PostgreSQL
- [ ] **AIO-003 – Validate line-critical paths remain local-first and do not depend on cloud round trips**  
  - Service / Component: Azure IoT Operations  
  - Primary owner: OT  
  - Source documents: AIO Governance; Event Hubs; Event Grid; ADLS

### Phase 9
- [ ] **MSG-001 – For Event Hubs path, deploy Standard or Premium namespace, not Basic**  
  - Service / Component: Azure Event Hubs  
  - Primary owner: App  
  - Source documents: Event Hubs
- [ ] **MSG-002 – Use Entra ID / managed identity for publishers and consumers; reserve SAS for exceptions only**  
  - Service / Component: Azure Event Hubs  
  - Primary owner: Security  
  - Source documents: Event Hubs
- [ ] **MSG-003 – Configure Event Hubs private endpoints or IP firewall rules and diagnostics**  
  - Service / Component: Azure Event Hubs  
  - Primary owner: Security  
  - Source documents: Event Hubs
- [ ] **MSG-004 – Define Event Hubs partitioning, throughput sizing, capture/archive, and DR approach if needed**  
  - Service / Component: Azure Event Hubs  
  - Primary owner: App  
  - Source documents: Event Hubs
- [ ] **MSG-005 – For Event Grid path, use cloud Event Grid as enterprise fan-out tier; keep line-critical events local**  
  - Service / Component: Azure Event Grid  
  - Primary owner: App  
  - Source documents: Event Grid
- [ ] **MSG-006 – Define topic taxonomy, filters, and managed-identity-based downstream delivery where supported**  
  - Service / Component: Azure Event Grid  
  - Primary owner: App  
  - Source documents: Event Grid

### Phase 10
- [ ] **STO-001 – Create ADLS Gen2 account with HNS enabled and managed-identity-first access**  
  - Service / Component: ADLS Gen2  
  - Primary owner: App  
  - Source documents: ADLS
- [ ] **STO-002 – Create raw, curated, and audit/evidence storage zones with RBAC + ACL path segmentation**  
  - Service / Component: ADLS Gen2  
  - Primary owner: App  
  - Source documents: ADLS
- [ ] **STO-003 – Create both Blob and DFS private endpoints with private DNS**  
  - Service / Component: ADLS Gen2 / Networking  
  - Primary owner: Platform  
  - Source documents: ADLS
- [ ] **STO-004 – Enable container soft delete, blob soft delete, lifecycle policies, and immutability where required**  
  - Service / Component: ADLS Gen2  
  - Primary owner: Security  
  - Source documents: ADLS

### Phase 11
- [ ] **ANA-001 – If analytics is in scope, deploy Databricks Premium with Unity Catalog enabled from day one**  
  - Service / Component: Azure Databricks  
  - Primary owner: App  
  - Source documents: Databricks
- [ ] **ANA-002 – Use Access Connector / managed identity for storage credentials and service credentials**  
  - Service / Component: Azure Databricks / Entra ID  
  - Primary owner: Security  
  - Source documents: Databricks
- [ ] **ANA-003 – Apply compute policies, private connectivity, and audit log delivery before broad workspace use**  
  - Service / Component: Azure Databricks  
  - Primary owner: Security  
  - Source documents: Databricks

### Phase 12
- [ ] **DB-001 – PostgreSQL path: deploy dedicated db-postgres and db-postgres-backup namespaces with ClusterIP-only exposure**  
  - Service / Component: PostgreSQL  
  - Primary owner: App  
  - Source documents: PostgreSQL
- [ ] **DB-002 – PostgreSQL path: require TLS, hostssl-style access controls, SCRAM-SHA-256, role separation, and backup/WAL validation**  
  - Service / Component: PostgreSQL  
  - Primary owner: App  
  - Source documents: PostgreSQL

### Phase 13
- [ ] **RES-001 – Test cluster rebuild from code + Arc registration + extension deployment**  
  - Service / Component: Arc / GitOps  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Azure Monitor
- [ ] **RES-002 – Test Key Vault object recovery and certificate rotation with dependent workload restart/reload**  
  - Service / Component: Key Vault / PKI  
  - Primary owner: Security  
  - Source documents: Key Vault; Certificate Management; PostgreSQL
- [ ] **RES-003 – Test ADLS delete recovery and database restore/cutover runbooks**  
  - Service / Component: ADLS / Database  
  - Primary owner: App  
  - Source documents: ADLS; PostgreSQL
- [ ] **RES-004 – Simulate WAN outage and validate local-first behavior, buffering/replay, restart behavior, and alerting**  
  - Service / Component: AIO / Messaging / Storage  
  - Primary owner: OT  
  - Source documents: Key Vault; Event Hubs; Event Grid; ADLS; Azure Monitor

### Phase 14
- [ ] **OPS-001 – Publish runbooks for cluster onboarding, AIO deployment, secret sync failures, certificate rotation, eventing changes, storage recovery, monitoring failures, and DB restore/failover**  
  - Service / Component: Operational Runbooks  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Key Vault; Azure Monitor; Event Hubs; Event Grid; ADLS; PostgreSQL
- [ ] **OPS-002 – Define periodic access reviews and exception management for SAS, public access, broad Kubernetes privileges, and preview features**  
  - Service / Component: Governance / Operations  
  - Primary owner: Security  
  - Source documents: Key Vault; Azure Monitor; Event Hubs; Event Grid; Databricks
- [ ] **OPS-003 – Use ring-based change control for cluster, AIO, policy, monitoring, messaging, and database changes**  
  - Service / Component: Change Management  
  - Primary owner: Platform  
  - Source documents: AIO Governance; Azure Monitor; Event Hubs; Event Grid

## Source documents used
- **AIO Governance:** `AIO Goverance and Security.md`
- **Key Vault:** `Azure Key Vault Security and Governance.md`
- **Certificate Management:** `Certificate Management Architecture.md`
- **Azure Monitor:** `Azure Monitor and Log Analytics Security and Governance.md`
- **ADLS:** `ADLS Security and Governance.md`
- **Event Hubs:** `Event Hub Security and Governance.md`
- **Event Grid:** `Event Grid Security and Governance.md`
- **Databricks:** `Azure Databricks Security and Governance.md`
- **PostgreSQL:** `PostgreSQL on AIO-K3s Secure Edge Reference Design.md`
