# AIO Governance and Security

## Executive Summary

This document defines a **prescriptive reference architecture** for applying governance and security to **Azure IoT Operations (AIO)** deployed on **Azure Arc-enabled Kubernetes** and running on **K3s edge clusters**. Microsoft requires an **Azure Arc-enabled Kubernetes cluster** as the management plane for AIO, supports **K3s for multi-node Ubuntu deployments**, and uses **cluster-connect**, **custom locations**, **OIDC issuer**, and **workload identity** as foundational capabilities in the AIO deployment model. [R1][R2][R3]

The target operating model is a **Microsoft-first hybrid governance pattern** where Azure governs the **control plane**, Kubernetes and Arc extensions govern the **workload plane**, and the edge platform team retains accountability for **host OS, hardware, physical security, and local network controls**. This architecture assumes semi-connected or intermittently connected edge sites and explicitly accounts for offline-capable secrets handling, segmented networks, and controlled lifecycle management. [R4][R5][R6]

---

## 1. Scope and Design Goals

### In Scope
- Azure IoT Operations deployed to **Arc-enabled K3s** edge clusters. [R1][R2]
- Governance of Azure resources, Arc resources, Kubernetes configuration, extensions, and workload security controls. [R4][R7]
- Production-oriented controls for **identity, secrets, certificates, policy, monitoring, supply chain validation, network segmentation, and recovery**. [R5][R8][R9]

### Out of Scope
- Detailed OT asset hardening and plant-floor network engineering beyond the control points exposed through Azure, Arc, and Kubernetes. Microsoft’s IoT security model treats **asset security**, **connection security**, **edge security**, and **cloud security** as distinct domains; Azure governance complements but does not replace local OT/edge controls. [R10]

### Design Goals
1. **Use Azure as the authoritative governance plane** for connected edge Kubernetes clusters. [R4][R7]
2. **Enforce least privilege** across Azure, Arc, Kubernetes, and AIO personas. [R11][R12]
3. **Standardize secure configuration** at scale using Azure Policy and GitOps. [R13][R14]
4. **Protect secrets, certificates, and identities** in a way that tolerates edge connectivity constraints. [R5][R9][R15]
5. **Provide operational evidence** through logs, metrics, and security telemetry suitable for SOC and audit workflows. [R16][R17]
6. **Support layered or segmented networks** common in industrial environments. [R6][R18]

---

## 2. Prescriptive Reference Architecture

```text
+--------------------------------------------------------------------------------------+
|                                Azure Governance Plane                                |
|--------------------------------------------------------------------------------------|
| Management Groups / Subscriptions / Resource Groups / Tags / RBAC / Policy / Monitor |
| Defender for Cloud / Defender for Containers / Key Vault / Managed Identity / Sentinel|
+--------------------------------------------------------------------------------------+
                   |                                   |                        
                   | Azure Resource Manager            | Policy / Telemetry      
                   v                                   v                        
+--------------------------------------------------------------------------------------+
|                           Azure Arc Control Plane for K3s                             |
|--------------------------------------------------------------------------------------|
| Arc-enabled Kubernetes | Cluster-Connect | Custom Locations | Extensions | GitOps     |
| OIDC Issuer | Workload Identity | Azure RBAC | Azure Policy for Kubernetes            |
+--------------------------------------------------------------------------------------+
                   |                                   |                        
                   | Arc agents / extensions           | Desired state           
                   v                                   v                        
+--------------------------------------------------------------------------------------+
|                          Edge Site: K3s Cluster (Ubuntu)                              |
|--------------------------------------------------------------------------------------|
| Namespaces: azure-iot-operations, cert-manager, security, observability, apps         |
| AIO services | MQTT broker | Data flows | Connector for OPC UA | Schema registry      |
| Flux controllers | Azure Policy extension | Azure Monitor | Defender sensors           |
| Secret Store extension OR Key Vault Secrets Provider | cert-manager | trust-manager    |
+--------------------------------------------------------------------------------------+
                   |                                   |                        
                   | OT / IT integrations              | Logs / Metrics / Alerts 
                   v                                   v                        
+--------------------------------------------------------------------------------------+
|                     Local / Plant / Factory Dependencies                              |
|--------------------------------------------------------------------------------------|
| OT assets / OPC UA servers / local apps / firewalls / proxies / DNS / PKI / storage   |
+--------------------------------------------------------------------------------------+
```

This architecture deliberately splits control into **three layers**:
- **Azure governance layer** for inventory, RBAC, policy assignment, monitoring, and security posture. [R4][R7][R16]
- **Arc / Kubernetes governance layer** for cluster attach, extension lifecycle, GitOps, policy enforcement, and namespace scoping through custom locations. [R2][R11][R13][R14]
- **Edge execution layer** for AIO services and adjacent workloads on K3s. [R1][R3]

---

## 3. Core Architecture Decisions

### 3.1 Use one AIO instance per resource group and one site-aligned resource group per edge deployment
Microsoft states that **only one Azure IoT Operations instance is supported per resource group**. The prescriptive pattern is therefore:
- **One resource group per site or edge deployment boundary**.
- **One AIO instance per resource group**.
- Consistent tags for site, business unit, environment, plant zone, criticality, and owner. [R1]

This boundary simplifies role assignment, policy scoping, monitoring ownership, and remediation workflows. [R4][R11]

### 3.2 Standardize on Arc-connected K3s with required AIO features enabled
For K3s-based edge deployments, Arc onboarding should enable:
- **OIDC issuer**
- **Workload identity**
- **Cluster-connect**
- **Custom locations** [R1][R2][R19]

For K3s, Microsoft also documents adding the Arc-generated issuer URL to the K3s API server configuration so service account token issuance aligns with workload identity federation requirements. [R1][R19]

### 3.3 Treat custom locations as the namespace tenancy and delegation boundary
Custom locations have a **1:1 mapping to a Kubernetes namespace** and can be combined with **Azure RBAC** to give application or platform teams permission to deploy into specific namespaces without granting broad cluster-admin rights. Use custom locations to represent environment or tenancy boundaries such as:
- `site1-aio-prod`
- `site1-observability`
- `site1-apps-shared` [R11][R20]

---

## 4. Identity and Access Architecture

### 4.1 Human access
Use **Microsoft Entra ID** with **Azure RBAC** for Arc-enabled Kubernetes access wherever possible. Microsoft states Azure RBAC for Arc-enabled Kubernetes supports centralized authorization and can be combined with Conditional Access and just-in-time patterns. [R12][R21]

**Prescriptive roles**
- Platform engineering: scoped to the resource group and Arc cluster resources. [R11][R12]
- Security operations: read/compliance/monitoring roles plus Defender/Sentinel access as needed. [R16][R17]
- Application/AIO operators: **AIO built-in roles** plus explicitly assigned dependency roles. Microsoft notes that AIO built-in roles do **not** automatically grant all permissions required for Arc, Key Vault, monitoring, managed identities, Kubernetes extensions, and related dependencies. [R22]

### 4.2 Nonhuman access
Use **workload identity federation** for workloads that need to access Azure resources. Microsoft recommends workload identity to avoid distributing static secrets for Entra-backed authorization, and AIO secure settings require OIDC/workload identity for secret synchronization and managed identity-based cloud connections. [R8][R23]

**Prescriptive pattern**
- Use a **dedicated user-assigned managed identity** for the **Secret Store** path. [R8]
- Use a **separate user-assigned managed identity** for **AIO cloud connections** such as data flow endpoints or other Azure-connected components. Microsoft explicitly recommends separate identities for these two purposes. [R8]
- Avoid using the default Kubernetes service account for application workloads; define one service account per workload/component. [R24]

### 4.3 Conditional Access and MFA
Protect the **Azure control plane** with MFA and Conditional Access, including requirements for compliant devices or approved locations where appropriate. Microsoft’s Arc operational security guidance explicitly recommends these Azure access control best practices. [R25]

---

## 5. Governance Controls

### 5.1 Azure Policy for Kubernetes
Install **Azure Policy for Kubernetes** on all Arc-enabled K3s clusters. Microsoft states the Azure Policy extension is supported for Arc-enabled Kubernetes and that **K3s is a validated distribution in conformance testing** for the extension. [R13][R26]

**Prescriptive rollout pattern**
1. Start with **Audit** effects for all new clusters. [R13]
2. Promote selected controls to **Deny** only after validating impact on AIO system namespaces and required extensions. [R13][R24]
3. Use Policy initiatives to separate:
   - Cluster baseline controls
   - Workload hardening controls
   - Extension deployment controls
   - Monitoring and Defender onboarding controls [R13][R16]

### 5.2 GitOps as the authoritative configuration system
Use **Flux v2 GitOps** for Arc-enabled Kubernetes so the Git repository is the source of truth for cluster configuration and application deployment. Microsoft documents Flux v2 as the supported GitOps model for Arc-enabled Kubernetes. [R14]

**Prescriptive repository model**
- `platform/` for namespaces, RBAC, policies, network policies, and baseline services. [R14][R24]
- `aio/` for approved AIO-related manifests and overlays. [R1][R14]
- `site-overlays/` for site-specific values, endpoints, or connector configuration. [R14][R18]

Do **not** allow manual drift for baseline components except by emergency break-glass procedure. [R14][R25]

### 5.3 Tagging, inventory, and scope
All Arc-connected clusters should be tagged with minimum metadata:
- `Site`
- `Environment`
- `Criticality`
- `Owner`
- `ConnectivityModel`
- `DataResidency`
- `PatchRing` [R4][R7]

This supports inventory, policy scoping, remediation, and reporting from Azure Resource Manager. [R4]

---

## 6. Security Control Architecture

### 6.1 Platform hardening
For connected non-Microsoft clusters such as K3s, Microsoft recommends keeping the **cluster version**, **node OS**, **Arc agents**, and **extensions** current and evaluating secure platform defaults such as **hardware root-of-trust**, **Secure Boot**, and **drive encryption**. Microsoft also suggests evaluating **Microsoft Defender for Endpoint** for node protection. [R27][R28]

**Prescriptive controls**
- Harden Ubuntu hosts according to enterprise Linux baseline.
- Restrict direct SSH/node access; administer through the Kubernetes API server and controlled break-glass procedures. Microsoft recommends avoiding direct node access where possible. [R28]
- Protect communication between control-plane components with TLS and validate the K3s distribution/vendor hardening posture for etcd and API server communication. [R27]

### 6.2 Workload hardening
Apply Kubernetes **Pod Security Standards**, aiming for **Restricted** wherever feasible and **Baseline** only where AIO or supporting extensions require more privilege. Microsoft recommends non-root execution, avoiding host mounts unless required, and setting namespace quotas and pod resource requests/limits. [R24]

Use additional Linux hardening where available:
- **seccomp** default profile
- **AppArmor** or **SELinux**
- Least-privilege Linux capabilities [R24]

### 6.3 Threat protection
Enable **Microsoft Defender for Containers** on Arc-enabled Kubernetes for runtime threat detection, vulnerability assessment, software supply chain capabilities, and posture management. [R29]

For broader edge and OT visibility, pair with **Microsoft Defender for IoT**, which Microsoft’s IoT security guidance positions alongside Defender for Containers as a frontline control for edge-based IoT solutions. [R10]

### 6.4 Supply chain validation
Azure IoT Operations publishes image-signing guidance and supports verification of Microsoft-signed Docker and Helm images using **Notation** and Microsoft’s signing certificate. [R30]

**Prescriptive controls**
- Validate AIO image signatures before introducing new versions into production rings. [R30]
- Require SBOM retention and vulnerability scanning for customer-built images and sidecar workloads. Microsoft’s Arc workload guidance recommends a secure container lifecycle, SBOM generation, continuous vulnerability scanning, non-root images, multi-stage builds, and signing. [R24]

### 6.5 Secrets management
Microsoft recommends using **Azure Key Vault** as the managed vault and using the **Azure Key Vault Secret Store extension for Kubernetes (SSE)** to synchronize secrets for offline-capable use on Arc-enabled clusters. [R5][R15]

**Prescriptive pattern**
- Use **SSE** for semi-connected or intermittently connected edge sites. [R5]
- Use the **online Azure Key Vault Secrets Provider** only where reliable connectivity exists and you want to avoid persistent local secret copies. Microsoft explicitly states not to run both the online provider and offline SSE side-by-side in the same cluster. [R5][R31]
- Encrypt the Kubernetes secret store on the cluster and tightly scope RBAC around synchronization resources. Microsoft explicitly recommends encrypting the Kubernetes secret store for extra protection. [R5][R9]

### 6.6 Certificate management
All AIO component communications use **TLS**, and Microsoft recommends using **your own CA issuer and enterprise PKI** for production deployments rather than the default quickstart self-signed root CA. AIO uses **cert-manager** to manage certificates and **trust-manager** to distribute trust bundles. [R32]

**Prescriptive pattern**
- Use enterprise PKI-issued intermediate/issuer for production AIO namespaces. [R32]
- Store certificate material and external trust roots in **Key Vault** where feasible and synchronize to the cluster using approved secret management paths. [R5][R32]
- Restrict which namespaces and service accounts can read certificate secrets. [R9][R24]

### 6.7 Managed identity and IMDS protection
AIO secure settings require workload identity and managed identity-based patterns for cloud connections and secret synchronization. Microsoft also recommends blocking pod access to **Azure Instance Metadata Service (IMDS)** in the AKS secure-settings scenario to prevent metadata abuse when workload identity is the intended pattern. [R8]

**Prescriptive interpretation for edge**
- Prefer workload identity over instance metadata or static credentials for any Azure access path. [R8][R23]
- Block or tightly control metadata-style credential paths where relevant to the platform implementation. [R8]

---

## 7. Network Security Architecture

### 7.1 In-cluster segmentation
Use **Kubernetes NetworkPolicy** to control ingress and egress between pods, namespaces, and IP ranges. Microsoft recommends NetworkPolicy and suggests evaluating enforcement engines such as **Calico** or **Cilium**. [R33]

**Prescriptive policy model**
- Default deny ingress and egress at namespace level for application namespaces. [R33]
- Explicit allow between AIO components only where required. [R24][R33]
- Explicit allow from applications to approved AIO services and cloud egress endpoints only where needed. [R33]

### 7.2 Site and edge network boundaries
Microsoft’s AIO networking guidance documents:
- **Azure Arc gateway** for reducing firewall endpoint sprawl. [R6][R34]
- **Azure Firewall Explicit Proxy** for controlled and auditable outbound inspection. [R6]
- **Layered networking** guidance for industrial networks with URL/IP allowlists and connection auditing. [R6][R18]

**Prescriptive pattern**
- For standard enterprise sites, prefer **Arc gateway** if it aligns with your proxy model and current limitations. [R34]
- For tightly controlled egress environments, use **explicit proxy** and connection auditing. [R6]
- For Purdue-style segmented plants, implement inter-level allowlists and log all level-crossing connections. [R18]

### 7.3 Private connectivity
Microsoft’s Arc network security guidance recommends considering **Azure Private Link (preview)** for Arc-enabled clusters and dependent services such as Key Vault. [R33]

**Prescriptive use case**
Use Private Link when policy requires private connectivity to Azure services over ExpressRoute or VPN and when the dependency services support the required private endpoint model. [R33][R35]

---

## 8. Observability, Detection, and Response

### 8.1 Monitoring baseline
Azure Monitor supports Arc-enabled Kubernetes with **Prometheus metrics**, **Managed Grafana**, **container logging**, and **control-plane log** collection workflows for supported scenarios. Microsoft lists **SUSE Rancher K3s** among supported Arc-enabled clusters for monitoring onboarding. [R16]

**Prescriptive baseline**
- Send platform and workload logs to **Log Analytics**. [R16]
- Send metrics to **Azure Monitor workspace** and visualize in **Managed Grafana**. [R16]
- Define alert rules for node health, pod restarts, extension health, certificate expiry, secret sync health, and policy compliance drift. [R16][R22]

### 8.2 Security telemetry and SIEM integration
Microsoft’s Arc workload guidance recommends flowing telemetry into centralized monitoring and notes that once logs are in Log Analytics, you can enable **Microsoft Sentinel** for threat detection, investigation, response, and hunting. [R17]

For constrained/segmented edge sites, the **Azure Monitor pipeline at edge (preview)** can provide local caching, delayed cloud sync, and support for **OTLP** and **syslog** sources. [R17]

---

## 9. Lifecycle and Change Management

### 9.1 Controlled upgrades
There is an important design nuance for AIO:
- Microsoft’s general Arc security guidance recommends keeping Arc agents and extensions updated and configuring automatic upgrades where appropriate. [R27]
- Microsoft’s current AIO cluster preparation guidance uses `--disable-auto-upgrade` when connecting the cluster to avoid unplanned updates to Azure Arc and AIO system dependencies, and instead instructs operators to **manually upgrade agents as needed**. [R1]

**Prescriptive decision**
Use a **controlled ring-based upgrade process** for AIO-connected K3s clusters:
- **Ring 0**: lab / validation cluster
- **Ring 1**: pilot site
- **Ring 2**: production noncritical sites
- **Ring 3**: production critical sites [R1][R27]

Define a maximum allowed lag for security updates so “manual” does not become “unpatched.” [R27]

### 9.2 Change control
All baseline changes to cluster configuration, policies, network policies, extension settings, and monitoring should be applied through **GitOps** or approved IaC deployment paths. Manual portal or kubectl drift should be logged and remediated. [R14][R25]

---

## 10. Recovery and Resilience

Microsoft’s Arc data security guidance recommends planning for recovery of the cluster itself and aiming for configuration and data to be sourced from and synchronized back to the cloud so cluster rebuild resembles initial activation rather than manual reconstruction. [R9]

**Prescriptive recovery design**
- Store baseline manifests and cluster policy in Git. [R14][R9]
- Store secrets and cert sources in Key Vault / enterprise PKI, not as the only copy on-cluster. [R5][R32]
- Document the rebuild sequence: host prep -> K3s -> Arc connect -> OIDC/workload identity -> custom locations -> extensions -> Flux -> AIO deployment -> secret sync -> certificate issuance -> monitoring validation. [R1][R8]

---

## 11. Implementation Blueprint

### Phase 1 – Foundation
1. Build and harden Ubuntu/K3s hosts to enterprise baseline. [R27][R28]
2. Arc-connect the cluster with **OIDC issuer**, **workload identity**, **cluster-connect**, and **custom locations** enabled. [R1][R2][R19]
3. Create site-aligned resource group and apply mandatory tags. [R1][R4]
4. Establish Azure RBAC model for platform, security, and AIO operators. [R11][R22]

### Phase 2 – Governance Baseline
1. Install **Azure Policy for Kubernetes** and assign baseline audit policies. [R13][R26]
2. Install **Flux v2** and onboard cluster baseline repositories. [R14]
3. Define custom locations per namespace boundary. [R11][R20]
4. Enable Azure Monitor, Log Analytics, and alerting baseline. [R16]

### Phase 3 – Security Baseline
1. Enable **AIO secure settings**. [R8]
2. Configure **Secret Store extension** with dedicated managed identity for secret synchronization. [R8][R5]
3. Configure **separate user-assigned managed identity** for AIO cloud connections. [R8]
4. Configure **BYO issuer / enterprise PKI** for production certificates. [R32]
5. Enable **Defender for Containers** and integrate with security operations. [R29]
6. Apply namespace default deny **NetworkPolicies** and explicit allow rules. [R33]
7. Validate AIO image signing in the release pipeline. [R30]

### Phase 4 – Production Hardening
1. Promote selected Azure Policy controls from Audit to Deny. [R13]
2. Integrate Log Analytics with **Microsoft Sentinel** if required by the SOC model. [R17]
3. Implement patch/upgrade ring process for K3s, Arc agents, and extensions. [R1][R27]
4. Exercise site recovery and cluster rebuild runbooks. [R9]

---

## 12. Opinionated Baseline Checklist

### Required
- Arc-enabled K3s with OIDC issuer and workload identity enabled. [R1][R19]
- Cluster-connect and custom locations enabled. [R1][R11]
- Azure RBAC for human access to Arc-connected cluster resources. [R12][R21]
- AIO built-in role assignments plus explicitly assigned dependency roles. [R22]
- Azure Policy for Kubernetes installed. [R13][R26]
- Flux v2 GitOps installed. [R14]
- Secret Store extension **or** Key Vault Secrets Provider selected intentionally; not both. [R5][R31]
- Enterprise PKI / BYO issuer for production AIO. [R32]
- Azure Monitor baseline with alerts. [R16]
- Defender for Containers enabled. [R29]
- NetworkPolicy default deny model for non-system namespaces. [R33]

### Strongly Recommended
- Defender for IoT for OT/IoT visibility. [R10]
- Microsoft Sentinel integration. [R17]
- Arc gateway or explicit proxy for controlled egress. [R6][R34]
- Private Link where private Azure access is mandated. [R33][R35]
- Image signature verification in release process. [R30]
- Node hardening controls such as Secure Boot, disk encryption, and Defender for Endpoint where platform supports them. [R27][R28]

---

## 13. References

- **[R1]** Prepare your Kubernetes cluster – Azure IoT Operations  
  https://learn.microsoft.com/en-us/azure/iot-operations/deploy-iot-ops/howto-prepare-cluster
- **[R2]** Deploy Azure IoT Operations to a production cluster  
  https://learn.microsoft.com/en-us/azure/iot-operations/deploy-iot-ops/howto-deploy-iot-operations
- **[R3]** What is Azure IoT Operations?  
  https://learn.microsoft.com/en-us/azure/iot-operations/overview-iot-operations
- **[R4]** What is Azure Arc-enabled Kubernetes?  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/overview
- **[R5]** Use the Azure Key Vault Secret Store extension to sync secrets for offline access in Arc-enabled Kubernetes clusters  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/secret-store-extension
- **[R6]** Azure IoT Operations networking  
  https://learn.microsoft.com/en-us/azure/iot-operations/manage-layered-network/overview-layered-network
- **[R7]** Azure Arc overview  
  https://learn.microsoft.com/en-us/azure/azure-arc/overview
- **[R8]** Enable secure settings in Azure IoT Operations  
  https://learn.microsoft.com/en-us/azure/iot-operations/deploy-iot-ops/howto-enable-secure-settings
- **[R9]** Secure your data in Azure Arc-enabled Kubernetes  
  https://docs.azure.cn/en-us/azure-arc/kubernetes/conceptual-secure-your-data
- **[R10]** Secure your IoT solutions  
  https://learn.microsoft.com/en-us/azure/iot/iot-overview-security
- **[R11]** Create and manage custom locations on Azure Arc-enabled Kubernetes  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/custom-locations
- **[R12]** Use Azure RBAC on Azure Arc-enabled Kubernetes clusters  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/azure-rbac
- **[R13]** Understand Azure Policy for Kubernetes clusters  
  https://docs.azure.cn/en-us/governance/policy/concepts/policy-for-kubernetes
- **[R14]** Tutorial: Deploy applications by using GitOps with Flux v2  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2
- **[R15]** Manage secrets for your Azure IoT Operations deployment  
  https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/iot-operations/secure-iot-ops/howto-manage-secrets.md
- **[R16]** Enable monitoring for Arc-enabled Kubernetes clusters  
  https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable-arc
- **[R17]** Secure your workloads in Azure Arc-enabled Kubernetes  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-workloads
- **[R18]** How does Azure IoT Operations work in layered network?  
  https://learn.microsoft.com/en-us/azure/iot-operations/manage-layered-network/concept-iot-operations-in-layered-network
- **[R19]** Enable secure settings in Azure IoT Operations (K3s OIDC/workload identity details)  
  https://learn.microsoft.com/en-us/azure/iot-operations/deploy-iot-ops/howto-enable-secure-settings
- **[R20]** Overview of custom locations with Azure Arc  
  https://learn.microsoft.com/en-us/azure/azure-arc/platform/conceptual-custom-locations
- **[R21]** Azure Arc-enabled Kubernetes identity and access overview  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/identity-access-overview
- **[R22]** Built-in RBAC roles for IoT Operations  
  https://learn.microsoft.com/en-us/azure/iot-operations/secure-iot-ops/built-in-rbac
- **[R23]** Secure your workloads in Azure Arc-enabled Kubernetes (workload identity guidance)  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-workloads
- **[R24]** Secure your workloads in Azure Arc-enabled Kubernetes (pod security, seccomp, AppArmor, SBOM, signing)  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-workloads
- **[R25]** Secure your operations in Azure Arc-enabled Kubernetes  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-operations
- **[R26]** Available extensions for Azure Arc-enabled Kubernetes clusters  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/extensions-release
- **[R27]** Secure your platform in Azure Arc-enabled Kubernetes  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-platform
- **[R28]** Secure your platform in Azure Arc-enabled Kubernetes (node access / hardware protections)  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-platform
- **[R29]** Defender for Containers on Arc-enabled Kubernetes – overview  
  https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-arc-overview
- **[R30]** Validate image signing – Azure IoT Operations  
  https://learn.microsoft.com/en-us/azure/iot-operations/secure-iot-ops/howto-validate-images
- **[R31]** Use Azure Key Vault Secrets Provider extension to fetch secrets into Arc-enabled Kubernetes clusters  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-akv-secrets-provider
- **[R32]** Manage certificates for your Azure IoT Operations deployment  
  https://learn.microsoft.com/en-us/azure/iot-operations/secure-iot-ops/howto-manage-certificates
- **[R33]** Secure your network in Azure Arc-enabled Kubernetes  
  https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-secure-your-network
- **[R34]** Simplify network configuration requirements with Azure Arc gateway  
  https://learn.microsoft.com/en-us/azure/azure-arc/servers/arc-gateway
- **[R35]** Use Azure Private Link to securely connect servers to Azure Arc  
  https://learn.microsoft.com/en-us/azure/azure-arc/servers/private-link-security
