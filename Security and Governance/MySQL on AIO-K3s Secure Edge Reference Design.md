# MySQL on AIO/K3s – Secure Edge Reference Design

## 1. Purpose and scope

This reference design describes a **production-oriented MySQL deployment pattern** for an **Azure IoT Operations (AIO)** cluster running on **K3s** at a factory edge location. It assumes the cluster is **Azure Arc-enabled**, that **AIO is deployed with secure settings for production**, and that the plant requires a design that can tolerate intermittent WAN connectivity while still supporting centralized governance, identity separation, and predictable maintenance. AIO production guidance requires **custom locations** and **workload identity** on the Arc-enabled cluster and recommends configuring **your own certificate authority issuer** for production scenarios. citeturn1search15turn1search52turn2search88

This design focuses on **namespace layout**, **Azure identity and Key Vault flow**, **certificate and secret rotation**, **network policy zones**, **backup/restore operations**, and **Azure governance mappings** for a MySQL-backed edge workload. Azure Arc makes the cluster an Azure Resource Manager resource so it can be governed by tagging, Azure RBAC, Azure Policy, Arc extensions, and Defender for Containers across multiple factory sites. citeturn2search67turn2search72turn1search23

## 2. Design goals

- Keep MySQL available to the production line even when the site is **semi-disconnected**. Microsoft recommends the **Azure Key Vault Secret Store extension (SSE)** for clusters outside Azure cloud where connectivity to Key Vault may not be perfect because SSE synchronizes secrets for **offline access** in the Kubernetes secret store. citeturn2search97turn2search95
- Use **Azure Arc workload identity federation** whenever a pod needs Azure access, so credentials are not hard-coded into manifests or images. Arc workload identity uses OIDC federation between Kubernetes service accounts and Microsoft Entra identities. citeturn1search52turn1search55
- Harden the K3s substrate with **secret encryption**, **audit logging**, **Pod Security**, and CIS-aligned controls because the cluster itself becomes part of the MySQL trust boundary. K3s documents enabling `secrets-encryption`, `protect-kernel-defaults`, and audit controls as part of production hardening. citeturn1search1
- Use **Azure Policy**, **Azure RBAC**, **Kubernetes RBAC**, and **Defender for Containers** to enforce configuration baselines, minimize privileged access, and centralize security visibility for hybrid/edge clusters. Azure Policy extends Gatekeeper on Arc-enabled Kubernetes, and Defender for Containers on Arc provides posture management, vulnerability assessment, and runtime threat detection. citeturn1search18turn2search81turn2search83

## 3. Architecture overview

### 3.1 Preferred deployment pattern

**Preferred topology for a multi-node factory cluster**

- **Arc-enabled K3s cluster** with AIO production deployment, cluster connect, custom locations, workload identity, Azure Policy extension, Defender for Containers extension, and either the **AKV Secrets Provider** or the **AKV Secret Store extension** depending on connectivity requirements. AIO secure production deployment uses Key Vault, user-assigned managed identities, federated identity credentials, and secret sync as part of the reference pattern. citeturn1search15turn2search94turn2search97
- **MySQL HA topology** with at least **three database instances** and a **routing layer** if the plant has multi-node capacity and the business requires automatic failover. Google’s MySQL Kubernetes tutorial documents a typical InnoDB Cluster pattern with **three database pods** plus **MySQL Router** for resilient connection routing, which is a good conceptual reference for a Kubernetes-hosted MySQL HA layout even if your operator/tooling differs. citeturn1search36
- The MySQL workload is exposed **only through an internal ClusterIP service** and is protected by namespace-scoped **NetworkPolicies** plus MySQL’s **user@host** access model and **TLS-enforced transport**. MySQL’s privilege system evaluates both the user and the connecting host, and MySQL 8.4 supports `require_secure_transport=ON` to make encrypted connections mandatory. citeturn1search44turn1search32
- Secrets and certificates are sourced from **Azure Key Vault**. For connected sites, use the **AKV Secrets Provider** to mount secrets without persisting them by default; for semi-disconnected sites, use **SSE** so the cluster retains required secret material locally for database restart and recovery operations. Microsoft recommends not using both extensions side-by-side in the same cluster. citeturn2search94turn2search97

**Fallback topology for a single-node or low-resource plant**

- Run a **single MySQL instance** with explicit downtime assumptions, stricter change control, and more frequent local backups. Microsoft’s AIO guidance distinguishes single-node and multi-node deployment patterns for edge clusters, and the HA advantages of quorum-based MySQL topologies depend on having multiple schedulable nodes. citeturn1search11turn1search13turn1search36

### 3.2 High-level component model

```mermaid
flowchart LR
  A[Factory apps / AIO data flows] --> B[MySQL service\nClusterIP only]
  B --> C[Persistent Volumes]
  B --> D[Backup / binlog archive jobs]
  E[Azure Key Vault] --> F[AKV Secrets Provider or Secret Store Extension]
  F --> B
  G[Azure Arc] --> H[Azure Policy / Azure RBAC / Defender / Monitor]
  H --> I[K3s cluster + namespaces]
  I --> B
```

The MySQL service should be treated as a **dedicated line-service data plane** and not as a general shared database for unrelated workloads. Arc-enabled Kubernetes and custom locations let the platform team expose controlled Azure-facing deployment targets for approved namespaces while keeping the MySQL namespace tightly isolated. citeturn2search67turn2search89turn2search90



## 4. Prescriptive namespace layout

Use the following namespace model:

- **`azure-arc`** – Arc agents and core Arc integration components. Arc agents are installed in the `azure-arc` namespace when the cluster is connected to Azure Arc. citeturn2search72
- **`kube-system`** – K3s core services and selected cluster-scoped extensions. citeturn1search1turn2search98
- **`azure-iot-operations`** – AIO runtime namespace. citeturn1search15
- **`platform-security`** – optional namespace for platform-owned helper workloads, policy test pods, or observability sidecars that should remain separate from apps and databases. Azure Policy and Defender are cluster-scoped through extensions, but namespace separation still improves operational hygiene. citeturn1search18turn2search81
- **`db-mysql`** – MySQL instances, internal services, configuration objects, and PVCs. Keep it database-only. citeturn1search23turn1search18
- **`db-mysql-router`** – optional router/proxy tier if using a MySQL HA topology that benefits from a separate routing layer. MySQL HA reference patterns on Kubernetes commonly place routing functionality in its own deployment set for resilience and simpler cutover. citeturn1search36
- **`db-mysql-backup`** – backup/restore jobs, binlog archive jobs, validation jobs, and export tooling. Separating it from runtime pods helps keep service accounts, RoleBindings, and egress rules tighter. citeturn1search22turn1search23
- **`line-<plant-app>`** namespaces – application and integration namespaces that may connect to MySQL only through explicit NetworkPolicies and narrowly scoped MySQL roles. Custom locations map one-to-one to namespaces; use them where Azure deployment abstractions are needed, not by default for the DB namespace. citeturn2search88turn2search89

### 4.1 Namespace layout diagram (Mermaid)

```mermaid
flowchart TB
  subgraph AZ[Azure control plane]
    ARC[Azure Arc]
    POL[Azure Policy]
    DEF[Defender for Containers]
    KV[Azure Key Vault]
    MON[Azure Monitor / Log Analytics]
  end

  subgraph CL[K3s edge cluster]
    subgraph NS1[azure-arc namespace]
      A1[Arc agents]
      A2[Cluster connect / custom locations]
    end

    subgraph NS2[azure-iot-operations namespace]
      I1[AIO runtime]
      I2[Data flows / connectors]
    end

    subgraph NS3[platform-security namespace]
      P1[Policy test pods]
      P2[Observability helpers]
    end

    subgraph NS4[db-mysql namespace]
      MY1[MySQL primary]
      MY2[Replica / member 2]
      MY3[Replica / member 3]
      MYSVC[ClusterIP service]
    end

    subgraph NS5[db-mysql-router namespace]
      R1[MySQL Router / proxy tier]
    end

    subgraph NS6[db-mysql-backup namespace]
      B1[Backup jobs]
      B2[Binlog archive jobs]
      B3[Restore validation jobs]
    end

    subgraph NS7[line-app namespaces]
      L1[Factory apps]
      L2[AIO consumers]
    end
  end

  ARC --> A1
  ARC --> A2
  POL --> CL
  DEF --> CL
  MON --> CL
  KV --> NS4
  KV --> NS5
  KV --> NS6
  L1 --> R1
  L2 --> R1
  R1 --> MYSVC
  B1 --> MY1
  B2 --> MY1
```

### Namespace governance rules

1. Do **not** deploy MySQL in `default`, in `azure-iot-operations`, or in shared line namespaces. Namespace isolation is foundational for policy, RBAC, and network segmentation. citeturn1search18turn1search23
2. Enable **custom locations** only for namespaces that need Azure-side deployment targets; custom locations are dependent on **cluster connect** and create Azure-managed RoleBindings and ClusterRoleBindings as part of the abstraction. citeturn2search88turn2search89turn2search76
3. Apply stricter Pod Security and policy baselines to `db-mysql`, `db-mysql-router`, and `db-mysql-backup` than to application namespaces. K3s hardening guidance and Azure Policy for Kubernetes together provide the mechanism. citeturn1search1turn1search18

## 5. Identities and Key Vault flow

### 5.1 Identity model

Use **three separate identity planes**:

1. **Azure control plane identities** – Azure admins, platform engineers, and security personnel managed with **Azure RBAC** over the Arc-connected cluster resource and related Azure resources. Arc-enabled Kubernetes supports Azure RBAC for Kubernetes authorization scenarios where supported. citeturn2search69turn2search70
2. **Kubernetes identities** – namespace-scoped **service accounts** and RoleBindings limited to MySQL pods, routing pods, backup jobs, and extension resources. Arc secure operations guidance recommends Kubernetes RBAC for nonhuman access to the API server. citeturn1search22turn2search70
3. **Database identities** – MySQL accounts and roles mapped to application, migration, backup, router, replication, and break-glass admin functions. MySQL identifies accounts by **user plus host** and supports roles, privilege scoping, password management, and account locking. citeturn1search44turn1search47

### 5.2 Prescriptive Azure identity assignments

Use the following user-assigned managed identities (UAMIs):

- **`uami-aio-components`** – AIO components that need Azure access. AIO production guidance separates this from the identity used for secrets. citeturn1search15
- **`uami-aio-secrets`** – AIO secure settings secret sync path. Microsoft explicitly advises using a separate identity from AIO components. citeturn1search15
- **`uami-mysql-runtime`** – for MySQL-side components or helper pods that need Azure access (for example brokered backup access or secure secret retrieval workflows). Bind it through **Arc workload identity**. citeturn1search52turn1search55
- **`uami-mysql-backup`** – for backup, export, and restore jobs. Keep it separate from runtime so backup tooling does not inherit general DB pod permissions. citeturn1search52turn1search55

### 5.3 Key Vault consumption pattern

**Connected site pattern (preferred when WAN is reliable):**

- Install the **Azure Key Vault Secrets Provider extension** on the Arc-enabled cluster. It mounts **secrets, keys, and certificates** into pods, supports **auto rotation**, and by default does **not** persist secrets into the Kubernetes secret store. Microsoft recommends this online-only pattern for clusters that maintain reliable Key Vault connectivity and for scenarios where you want to avoid local secret copies. citeturn2search94turn2search96
- Use `SecretProviderClass` objects for MySQL server certificates, CA bundles, bootstrap admin credentials, router credentials, and backup target credentials if they should remain ephemeral and file-mounted. The provider supports file mounts and optional sync to Kubernetes secrets. citeturn2search94turn2search95

**Semi-disconnected site pattern (preferred when MySQL restart must survive WAN loss):**

- Install the **Azure Key Vault Secret Store extension (SSE)** on the Arc-enabled cluster. Microsoft recommends SSE for clusters outside Azure cloud with imperfect Key Vault connectivity because it synchronizes secrets for **offline access** into the Kubernetes secret store. Microsoft also emphasizes that these synchronized secrets are critical business assets and recommends encrypting the Kubernetes secret store. citeturn2search97turn1search1
- Use SSE for MySQL **TLS materials**, **bootstrap passwords**, **replication/router secrets**, and **backup credentials** that must exist locally even during a network outage. Configure the extension’s **rotation poll interval** and **jitter** according to the number of synchronized secrets and the expected rotation cadence. citeturn2search95turn2search99

### 5.4 Identity and Key Vault flow

```mermaid
sequenceDiagram
  autonumber
  participant APP as App Pod / AIO Pod
  participant SA as K8s Service Account
  participant OIDC as Arc OIDC Issuer
  participant ENTRA as Microsoft Entra ID
  participant UAMI as User-assigned Managed Identity
  participant AKV as Azure Key Vault
  participant EXT as AKV Provider or Secret Store Extension
  participant MYSQL as MySQL Pod / Router Pod

  APP->>SA: Use annotated service account
  SA->>OIDC: Request projected service account token
  OIDC->>ENTRA: Present federated trust metadata
  ENTRA->>UAMI: Validate federated credential
  UAMI-->>APP: Azure access token available to workload identity path
  EXT->>AKV: Read DB certs / passwords / CA chain
  AKV-->>EXT: Return current secret version
  EXT-->>MYSQL: Mount files or sync Kubernetes secrets
  APP->>MYSQL: Connect with TLS + approved MySQL role
```

Arc workload identity requires OIDC issuer and workload identity features on the Arc-enabled cluster, and AIO production secure settings also rely on federated identity credentials and Key Vault-backed secret flows. citeturn1search52turn1search55turn1search15

## 6. Certificate and rotation flow

### 6.1 Certificate authority model

Use a **plant-controlled or enterprise-controlled CA/issuer** for MySQL instead of relying on the Kubernetes cluster root CA. Kubernetes documentation advises using a separate custom CA for workload trust, and AIO production guidance recommends bringing your own issuer for production. citeturn1search31turn1search15

Recommended certificate sets:

- **MySQL server certificate** – presented by the MySQL service/instances to clients. MySQL 8.4 documents using `ssl_ca`, `ssl_cert`, and `ssl_key` for encrypted connections. citeturn1search32
- **Client CA bundle** – trusted by MySQL if privileged or administrative clients use certificate validation or mTLS-style controls. MySQL’s encrypted connection model is CA-based and can be made mandatory. citeturn1search32
- **Internal CA chain** – distributed to application pods, routers, and backup jobs so they can validate the MySQL server identity. Kubernetes recommends explicit workload CA distribution rather than assuming trust in the cluster root CA. citeturn1search31

### 6.2 MySQL TLS posture

Implement the following as baseline:

- Configure MySQL with **`ssl_ca`**, **`ssl_cert`**, and **`ssl_key`** and set **`require_secure_transport=ON`** so clients must use encrypted connections. MySQL 8.4 explicitly documents this as the way to require secure transport. citeturn1search32
- Use **host-scoped accounts** and **roles** so that application identities are valid only from the expected Kubernetes source patterns. MySQL’s privilege system evaluates **user plus host**, which aligns well with cluster-internal segmentation. citeturn1search44turn1search48
- For break-glass admin or privileged automation, prefer certificate-based admin workflows where practical instead of broad password reuse. MySQL’s encrypted connection stack is based on CA, server cert, and key configuration, making a certificate-governed admin model feasible. citeturn1search32

### 6.3 Rotation pattern

**Recommended rotation sequence**

1. Publish a **new certificate version** or secret version in Azure Key Vault. The AKV provider supports auto rotation and the Secret Store extension exposes `rotationPollIntervalInSeconds` and related settings to govern refresh behavior. citeturn2search94turn2search95
2. Let the provider/extension **refresh the mounted or synchronized material** into `db-mysql` and `db-mysql-router`. The online CSI provider supports auto rotation, but apps may still need reload/restart behavior depending on how they consume mounted files or synced secrets. citeturn2search43turn2search94
3. Perform a **controlled MySQL reload or rolling restart** during a maintenance window or using a quorum-aware operator/runbook. In an HA topology, rotate routers and replicas first, then the primary/cutover target. MySQL HA topologies on Kubernetes rely on multiple instances and routing state that must be updated coherently. citeturn1search36turn1search32
4. Validate **client trust**, **replication trust**, and **backup job trust** before retiring the previous cert version. This is essential in a factory environment where a failed transport change can stop the production line. citeturn1search32turn1search36

### 6.4 Rotation policy recommendations

- Rotate **server certificates** on a fixed schedule and after any incident that suggests key exposure. The technical mechanism should rely on Key Vault versioning plus controlled provider/extension refresh. citeturn2search94turn2search95
- Rotate **password-based MySQL accounts** using MySQL’s built-in password management features, including expiration, reuse restrictions, and failed-login controls, while sourcing the new material from Key Vault. MySQL 8.4 documents these password management features in detail. citeturn1search47turn1search44
- If using SSE, ensure **K3s secret encryption** is enabled because secret copies are stored locally in the Kubernetes secret store. K3s supports secrets encryption at rest, and Microsoft recommends encrypting the cluster secret store when using SSE. citeturn1search1turn2search97

## 7. Network policy zones

### 7.1 Prescriptive network zones

1. **Zone A – Arc / platform management**: `azure-arc`, Policy, Defender, cluster connect, and other Arc extensions. Arc works through secure outbound connectivity and does not require inbound firewall ports for cluster management. citeturn2search72turn2search76turn2search77
2. **Zone B – AIO runtime**: `azure-iot-operations` and approved application namespaces. These namespaces may call MySQL only through explicit NetworkPolicies and approved MySQL accounts. AIO runs as an Arc-managed production workload on the cluster. citeturn1search15turn2search67
3. **Zone C – MySQL data plane**: `db-mysql` namespace. Only allow inbound from approved application namespaces and `db-mysql-router`/`db-mysql-backup`; deny all other east-west traffic by default. Azure Policy for Kubernetes can help audit/enforce required policy patterns centrally. citeturn1search18turn1search23
4. **Zone D – Router / connection mediation**: `db-mysql-router` namespace if a router tier is used. Permit inbound from approved application namespaces and outbound only to MySQL pods. HA routing patterns such as MySQL Router are designed to centralize connection routing and failover decisions. citeturn1search36
5. **Zone E – Backup and restore**: `db-mysql-backup`. Permit egress only to MySQL, approved backup targets, Key Vault/Arc endpoints as needed, and monitoring endpoints. Arc/Defender/AKV extension documentation all define outbound requirements that should be included in egress design. citeturn2search83turn2search94
6. **Zone F – External edge/plant network**: OT networks and integration networks should not connect directly to MySQL. Any external integration should terminate in an application service namespace that then connects inward to MySQL using approved credentials and TLS. Arc governance guidance emphasizes clear security boundaries and controlled operations. citeturn1search22turn1search23

### 7.2 Mandatory network controls

- **Default deny** ingress and egress in `db-mysql`, `db-mysql-router`, and `db-mysql-backup`; then create explicit allowlists only for required flows. Azure Policy for Kubernetes can apply these kinds of safeguards at scale. citeturn1search18
- Expose MySQL as **ClusterIP only**. Do not publish it directly with NodePort or external ingress. MySQL’s host-based access model is valuable, but it should complement rather than replace tight cluster-internal network boundaries. citeturn1search44turn1search32
- Make **encrypted transport mandatory** everywhere with `require_secure_transport=ON` and certificate validation on clients wherever feasible. MySQL explicitly documents mandatory encrypted transport. citeturn1search32
- Validate required outbound access only for Arc, Defender, and the chosen AKV extension. Arc and Defender documentation both document outbound dependency requirements. citeturn2search72turn2search82turn2search83

## 8. MySQL workload design and hardening

### 8.1 Authentication and authorization

Use this MySQL baseline:

- Create separate accounts and roles for **application**, **migration**, **backup**, **router/replication**, and **break-glass admin** access. MySQL 8.4 supports roles and granular privilege assignments through account-management statements. citeturn1search44turn1search48
- Use **host-scoped account definitions** so each service account is valid only from the approved cluster source patterns. MySQL’s account model uses both the user name and connecting host to determine identity and permissions. citeturn1search44
- Enable password-management controls for human or privileged accounts: **password expiration**, **reuse restrictions**, **verification-required changes**, **failed-login tracking**, and **temporary account locking**. MySQL 8.4 documents all of these capabilities. citeturn1search47turn1search44
- Prefer certificate or identity-based access patterns for privileged automation where possible; keep long-lived passwords only where unavoidable and store them in Key Vault. Workload identity plus Key Vault-backed extensions reduce the need to embed secrets in pods. citeturn1search52turn2search94turn2search97

### 8.2 HA and durability

- **Preferred**: multi-instance HA topology with a routing tier if the plant requires automatic failover. Kubernetes MySQL HA reference patterns place multiple MySQL instances behind a routing layer to allow primary election and connection redirection. citeturn1search36
- **Minimum acceptable**: single instance with planned maintenance windows, documented outage acceptance, and strong local backup posture when the site lacks multi-node resources. AIO guidance distinguishes multi-node and single-node patterns for edge environments. citeturn1search11turn1search13
- Define RPO/RTO and whether the business can tolerate asynchronous lag or requires tighter failover semantics. The topology and backup/binlog strategy should follow that decision explicitly. MySQL Kubernetes HA patterns assume multiple instances precisely to improve resiliency and disaster tolerance. citeturn1search36

### 8.3 Logging and auditing

- Capture MySQL events for **authentication failures**, **privilege changes**, **DDL changes**, and backup/replication failures, and stream them to the cluster logging pipeline. If you have **MySQL Enterprise**, use **MySQL Enterprise Audit** for richer filtering and durable audit handling. Oracle documents audit log tables, functions, and filters for the Enterprise Audit feature. citeturn1search49turn1search44
- Correlate MySQL events with **Kubernetes audit logs**, **GitOps commits**, and **Arc/Defender alerts** for incident response. Arc secure operations guidance emphasizes monitoring control-plane changes, controlling who can deploy, and detecting emerging threats. citeturn1search22turn2search81

## 9. Backup and restore runbook

### 9.1 Backup principles

The backup strategy must cover **storage failure**, **logical corruption**, **operator error**, and **site loss**. In Kubernetes-hosted MySQL, combine **persistent-volume-level recovery options** with **engine-native backup/binlog approaches** appropriate to the chosen topology. Arc governance guidance emphasizes documented operational ownership and recovery planning for hybrid clusters. citeturn1search23turn1search36

### 9.2 Prescriptive backup design

- **Local fast restore tier**: maintain local encrypted backups or storage snapshots on site for fast recovery during plant incidents. Edge platforms should preserve local operational autonomy during WAN disruption. citeturn1search23turn1search15
- **Off-site or Azure archival tier**: replicate backup artifacts or binlog archives off site whenever connectivity is available. Use a dedicated backup identity and narrow egress. Workload identity and Key Vault-backed secret management make this easier without static pod credentials. citeturn1search52turn2search97
- **Secret availability**: if the backup job must start during a disconnected window, source its materials from **SSE** rather than the online-only provider. SSE is specifically recommended for semi-disconnected sites. citeturn2search97turn2search95

```mermaid
flowchart LR
  subgraph RUNTIME[db-mysql namespace]
    MY[MySQL primary]
    RP1[Replica 1]
    RP2[Replica 2]
    SVC[ClusterIP service]
  end

  subgraph RTR[db-mysql-router namespace]
    RT[Router / proxy tier]
  end

  subgraph BK[db-mysql-backup namespace]
    FULL[Full backup job]
    BIN[Binlog archive job]
    VAL[Restore validation job]
    CUT[Cutover decision]
  end

  subgraph LOCAL[Local edge backup tier]
    SNAP[Local snapshots / encrypted backup store]
  end

  subgraph REMOTE[Remote / Azure archival tier]
    OFF[Off-site or Azure backup archive]
  end

  MY --> FULL
  MY --> BIN
  FULL --> SNAP
  BIN --> SNAP
  FULL --> OFF
  BIN --> OFF
  SNAP --> VAL
  OFF --> VAL
  VAL --> CUT
  CUT --> RT
  RT --> SVC
  RP1 --> CUT
  RP2 --> CUT
```

### 9.3 Backup schedule (recommended baseline)

- **Daily full backup** or full logical/physical backup baseline appropriate to database size and site recovery needs. Stateful Kubernetes workloads need a repeatable base restore point before incremental/binlog recovery makes sense. citeturn1search36turn1search23
- **Frequent binlog archival** if the plant cannot accept large data-loss windows. MySQL HA and disaster-tolerance patterns depend on maintaining a consistent change history between restore points. citeturn1search36
- **Restore validation** at least monthly and after every significant version change, routing change, cert rotation change, or backup tooling update. Recovery trust depends on real restore tests, not just successful backup jobs. citeturn1search22turn1search23

### 9.4 Restore runbook

**Runbook – standard restore**

1. **Declare incident mode** and collect current evidence: cluster events, MySQL logs, Arc alerts, Defender alerts, and backup job history. Defender for Containers on Arc provides centralized security signals and K3s supports audit logging for control-plane changes. citeturn2search81turn1search1
2. **Quiesce or isolate writers** by scaling down applications that write to MySQL and tightening NetworkPolicies if corruption or compromise is suspected. Azure Policy and Kubernetes RBAC/NetworkPolicies form part of the operational control baseline. citeturn1search18turn1search22
3. **Choose recovery source**: latest good local snapshot/backup, latest complete off-site backup, or the correct binlog boundary for point recovery. MySQL HA/disaster-tolerance designs on Kubernetes assume explicit recovery target choices. citeturn1search36
4. **Restore into a new recovery target** in `db-mysql` or a temporary `db-mysql-restore` namespace rather than overwriting the original immediately. Namespace isolation simplifies validation and rollback. citeturn1search18turn1search23
5. **Validate integrity**: schema checks, application smoke tests, TLS trust, router connectivity, and replication membership if HA is enabled. MySQL HA patterns depend on routers and topology metadata being correct after recovery. citeturn1search36turn1search32
6. **Cut over** application traffic to the restored MySQL endpoint or router tier, then re-enable normal ingress flows. ClusterIP-only service exposure and a dedicated router namespace simplify controlled cutover. citeturn1search36turn1search44
7. **Review the incident** and capture achieved RPO/RTO, failed controls, extension states, and whether secret/certificate rotation played any role. Arc, Policy, and Defender centralize part of the evidence trail in Azure. citeturn2search67turn2search81turn1search18

## 10. Azure governance mappings (Policy / RBAC / Arc / Defender)

| Governance area                       | Prescriptive mapping                                                                                                                                                                                                                                                                                                                                                                                                                                   | Why it matters                                                                                                                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Azure Arc**                         | Connect the K3s cluster to Azure Arc and use Arc extensions for Policy, Defender, Key Vault integration, and AIO lifecycle. Arc agents create secure outbound connectivity and let the cluster be managed as an Azure resource. citeturn2search67turn2search72                                                                                                                                                                                     | Provides centralized governance, tagging, inventory, and extension lifecycle across multiple plant clusters. citeturn1search23turn2search67                                  |
| **Azure RBAC / Entra**                | Use Azure RBAC for human/admin access to Arc resources and, where supported, Azure RBAC for Kubernetes authorization on Arc-enabled clusters. Arc documents Azure RBAC on Arc-enabled Kubernetes and how it integrates with Entra-backed authorization. citeturn2search69turn2search70                                                                                                                                                             | Centralizes authorization and reduces per-plant drift in admin access models. citeturn1search22turn2search70                                                                 |
| **Kubernetes RBAC**                   | Continue to use namespace-scoped Kubernetes RBAC for nonhuman access and for scenarios not covered by Azure RBAC support. Arc secure operations guidance explicitly recommends Kubernetes RBAC for workloads and service accounts. citeturn1search22turn2search69                                                                                                                                                                                  | Enforces least privilege for MySQL pods, routers, and backup jobs inside the cluster. citeturn1search22turn1search23                                                         |
| **Azure Policy for Kubernetes**       | Install the Azure Policy extension and assign policies that audit/deny missing NetworkPolicies, privileged pods, weak security contexts, unapproved images, and noncompliant namespaces. Azure Policy extends Gatekeeper and reports compliance centrally. citeturn1search18turn2search96                                                                                                                                                          | Supplies policy-as-code guardrails and compliance evidence across all factory clusters. citeturn1search23turn1search18                                                       |
| **Microsoft Defender for Containers** | Enable Defender for Containers on Arc-enabled Kubernetes and deploy the Defender sensor extension if your organization permits the current Arc deployment model. Defender for Containers on Arc provides runtime threat detection, security posture management, and vulnerability assessment, but Microsoft’s current deployment overview still labels Arc-enabled Kubernetes support as **Preview**. citeturn2search81turn2search83turn2search84 | Adds centralized threat detection and posture visibility for edge MySQL environments and helps correlate security findings with DB incidents. citeturn2search81turn2search86 |
| **Custom locations**                  | Use custom locations only for namespaces that need Azure-managed deployment targets; do not expose `db-mysql` or `db-mysql-router` as custom locations by default. Custom locations map one-to-one to namespaces and depend on cluster connect. citeturn2search88turn2search89                                                                                                                                                                     | Preserves clean tenancy and avoids unnecessary Azure-side abstractions over sensitive database namespaces. citeturn2search89turn2search90                                    |
| **Key Vault integration**             | Use the AKV Secrets Provider for connected sites and SSE for semi-disconnected sites, and do not run both side-by-side. If using SSE, enable K3s secret encryption. citeturn2search94turn2search97turn1search1                                                                                                                                                                                                                                    | Supports secure secret and certificate rotation while respecting plant connectivity realities. citeturn2search95turn2search99                                                |
| **AIO production settings**           | Keep the MySQL design aligned with AIO secure production deployment: separate identities for components and secrets, Key Vault integration, and workload identity federation. citeturn1search15turn1search52                                                                                                                                                                                                                                       | Ensures the data layer follows the same security/governance model as the rest of the edge platform. citeturn1search15                                                         |

## 11. Implementation checklist

### Phase 1 – Platform readiness

- Arc-enable the K3s cluster and verify connected state. citeturn2search75turn2search67
- Enable **cluster connect**, **custom locations**, and **workload identity** on the Arc-enabled cluster. Custom locations require cluster connect, and workload identity requires OIDC issuer support. citeturn2search88turn1search52
- Harden K3s with `secrets-encryption`, `protect-kernel-defaults`, audit logging, and Pod Security settings. citeturn1search1
- Install the **Azure Policy** extension and, if approved, **Defender for Containers**. citeturn1search18turn2search83

### Phase 2 – Secret and certificate plumbing

- Create Key Vault objects for MySQL server cert, CA chain, bootstrap/admin credentials, router or replication credentials, and backup/export credentials. citeturn2search94turn2search97
- Choose either **AKV Provider** or **SSE** based on site connectivity and startup requirements. citeturn2search94turn2search97
- Configure workload identity for `uami-mysql-runtime` and `uami-mysql-backup`. citeturn1search52turn1search55

### Phase 3 – MySQL deployment

- Create `db-mysql`, `db-mysql-router` (if used), and `db-mysql-backup` namespaces with dedicated RBAC and NetworkPolicies. citeturn1search18turn1search23
- Configure MySQL with `ssl_ca`, `ssl_cert`, `ssl_key`, `require_secure_transport=ON`, host-scoped accounts, and roles. citeturn1search32turn1search44turn1search48
- If HA is required, deploy and validate a multi-instance topology with routing and failover behavior. citeturn1search36

### Phase 4 – Operations and recovery

- Implement a local backup tier plus off-site/binlog archival as required. citeturn1search36turn1search23
- Validate restore procedures and certificate rotation in a maintenance window. citeturn2search94turn2search95
- Run quarterly reviews of Azure RBAC, Kubernetes RBAC, and MySQL roles/accounts. Azure and Arc centralize part of that review, while MySQL still requires DB-level access review. citeturn2search69turn1search44turn1search47

## 12. References

- Microsoft Learn – Deploy Azure IoT Operations to a production cluster: https://learn.microsoft.com/en-us/azure/iot-operations/deploy-iot-ops/howto-deploy-iot-operations citeturn1search15
- Microsoft Learn – Prepare your Azure Arc-enabled Kubernetes cluster for Azure IoT Operations: https://learn.microsoft.com/en-us/azure/iot-operations/deploy-iot-ops/howto-prepare-cluster citeturn1search11
- Microsoft Learn – Deploy and configure workload identity federation in Azure Arc-enabled Kubernetes: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/workload-identity citeturn1search52
- Microsoft Learn – Workload identity federation in Azure Arc-enabled Kubernetes: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-workload-identity citeturn1search55
- Microsoft Learn – Governance, security, and compliance baseline for Azure Arc-enabled Kubernetes: https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/hybrid/arc-enabled-kubernetes/eslz-arc-kubernetes-governance-disciplines citeturn1search23
- Microsoft Learn – Understand Azure Policy for Kubernetes clusters: https://learn.microsoft.com/en-us/azure/governance/policy/concepts/policy-for-kubernetes citeturn1search18
- Microsoft Learn – Use Azure RBAC on Azure Arc-enabled Kubernetes clusters: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/azure-rbac citeturn2search69
- Microsoft Learn – Identity and access overview for Azure Arc-enabled Kubernetes: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/identity-access-overview citeturn2search70
- Microsoft Learn – Create and manage custom locations on Azure Arc-enabled Kubernetes: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/custom-locations citeturn2search88
- Microsoft Learn – Use the Azure Key Vault Secrets Provider extension on Arc-enabled Kubernetes: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-akv-secrets-provider citeturn2search94
- Microsoft Learn – Use the Azure Key Vault Secret Store extension for offline access: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/secret-store-extension citeturn2search97
- Microsoft Learn – Azure Key Vault Secret Store extension configuration reference: https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/secret-store-extension-reference citeturn2search95
- Microsoft Learn – Defender for Containers on Arc-enabled Kubernetes overview: https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-arc-overview citeturn2search81
- Microsoft Learn – Deploy Defender for Containers on Arc-enabled Kubernetes programmatically: https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-arc-enable-programmatically citeturn2search83
- K3s documentation – CIS Hardening Guide: https://docs.k3s.io/security/hardening-guide citeturn1search1
- MySQL 8.4 Reference – Configuring MySQL to Use Encrypted Connections: https://dev.mysql.com/doc/refman/8.4/en/using-encrypted-connections.html citeturn1search32
- MySQL 8.4 Reference – Access Control and Account Management: https://dev.mysql.com/doc/refman/8.4/en/access-control.html citeturn1search44
- MySQL 8.4 Reference – Password Management: https://dev.mysql.com/doc/refman/8.4/en/password-management.html citeturn1search47
- MySQL 8.4 Reference – Account Management Statements: https://dev.mysql.com/doc/refman/8.4/en/account-management-statements.html citeturn1search48
- MySQL 8.4 Reference – Audit Log Reference: https://dev.mysql.com/doc/refman/8.4/en/audit-log-reference.html citeturn1search49
- Google Cloud tutorial – Deploy a stateful MySQL cluster on GKE (HA topology reference): https://docs.cloud.google.com/kubernetes-engine/docs/tutorials/stateful-workloads/mysql citeturn1search36
