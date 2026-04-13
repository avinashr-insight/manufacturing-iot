# PostgreSQL on AIO/K3s – Diagram Pack

Use this diagram pack as **Section 3.3 – Visual architecture diagrams** in the original PostgreSQL reference design.

## 3.3 Visual architecture diagrams

The following diagrams can be pasted directly into Markdown renderers that support **Mermaid**, and the pseudo-Visio versions can be used in Word or plain-text runbooks when Mermaid rendering is not available.

### Namespace layout diagram (Mermaid)

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

    subgraph NS4[db-postgres namespace]
      PG1[PostgreSQL primary]
      PG2[Synchronous standby]
      PG3[Optional read replica]
      PGSVC[ClusterIP service]
    end

    subgraph NS5[db-postgres-backup namespace]
      B1[Backup jobs]
      B2[WAL archive jobs]
      B3[Restore validation jobs]
    end

    subgraph NS6[line-app namespaces]
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
  I2 --> PGSVC
  L1 --> PGSVC
  L2 --> PGSVC
  B1 --> PG1
  B2 --> PG1
```

### Namespace layout diagram (pseudo-Visio)

```text
+----------------------------------------------------------------------------------+
|                               Azure Control Plane                                |
|  Azure Arc | Azure Policy | Defender for Containers | Key Vault | Azure Monitor |
+-------------------------------------------+--------------------------------------+
                                            |
                                            v
+----------------------------------------------------------------------------------+
|                                 K3s Edge Cluster                                 |
|                                                                                  |
|  +------------------+   +--------------------------+   +----------------------+   |
|  | azure-arc        |   | azure-iot-operations     |   | platform-security    |   |
|  | Arc agents       |   | AIO runtime / connectors |   | policy + observability|  |
|  +------------------+   +--------------------------+   +----------------------+   |
|                                                                                  |
|  +------------------------------------+   +-----------------------------------+   |
|  | db-postgres                        |   | db-postgres-backup                |   |
|  | PostgreSQL primary                 |<--| backup jobs / WAL archive / test  |   |
|  | sync standby / optional replica    |   +-----------------------------------+   |
|  | ClusterIP service                  |                                       |   |
|  +------------------^-----------------+                                       |   |
|                     |                                                         |   |
|      +--------------+------------------------------+                          |   |
|      | line-app namespaces / AIO consumers         |--------------------------+   |
|      | approved app namespaces only                |                              |
|      +---------------------------------------------+                              |
+----------------------------------------------------------------------------------+
```

### Identity and Key Vault flow (Mermaid)

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
  participant PG as PostgreSQL Pod

  APP->>SA: Use annotated service account
  SA->>OIDC: Request projected service account token
  OIDC->>ENTRA: Present federated trust metadata
  ENTRA->>UAMI: Validate federated credential
  UAMI-->>APP: Azure access token available to workload identity path
  EXT->>AKV: Read DB certs / passwords / CA chain
  AKV-->>EXT: Return current secret version
  EXT-->>PG: Mount files or sync Kubernetes secrets
  APP->>PG: Connect with TLS + approved DB role
```

### Identity and Key Vault flow (pseudo-Visio)

```text
[App Pod / AIO Pod]
        |
        | annotated service account
        v
[Kubernetes Service Account] --> [Arc OIDC Issuer] --> [Microsoft Entra ID]
                                                          |
                                                          v
                                           [User-assigned Managed Identity]
                                                          |
                                                          v
                                                   [Azure Key Vault]
                                                          |
                                                          v
                              [AKV Provider or Secret Store Extension on cluster]
                                                          |
                                                          v
                                            [PostgreSQL Pod: certs / creds mounted]
                                                          |
                                                          v
                                         [TLS connection using approved DB role]
```

### Backup and restore flow (Mermaid)

```mermaid
flowchart LR
  subgraph RUNTIME[db-postgres namespace]
    PG[PostgreSQL primary]
    STBY[Sync standby]
    SVC[ClusterIP service]
  end

  subgraph BK[db-postgres-backup namespace]
    BASE[Base backup job]
    WAL[WAL archive job]
    VAL[Restore validation job]
    CUT[Cutover decision]
  end

  subgraph LOCAL[Local edge backup tier]
    SNAP[Local snapshots / encrypted backup store]
  end

  subgraph REMOTE[Remote / Azure archival tier]
    OFF[Off-site or Azure backup archive]
  end

  PG --> BASE
  PG --> WAL
  BASE --> SNAP
  WAL --> SNAP
  BASE --> OFF
  WAL --> OFF
  SNAP --> VAL
  OFF --> VAL
  VAL --> CUT
  CUT --> SVC
  STBY --> CUT
```

### Backup and restore flow (pseudo-Visio)

```text
+------------------------+        +----------------------------------+
| db-postgres namespace  |        | db-postgres-backup namespace     |
| PostgreSQL primary     |------->| Base backup job                  |
| Sync standby           |------->| WAL archive job                  |
| ClusterIP service      |        | Restore validation job           |
+-----------+------------+        +----------------+-----------------+
            |                                      |
            v                                      v
+-------------------------------+      +-------------------------------+
| Local edge backup tier        |      | Remote / Azure archival tier  |
| encrypted snapshots / backups |      | off-site backups / WAL archive|
+---------------+---------------+      +---------------+---------------+
                \\                                 /
                 \\                               /
                  v                             v
                 +----------------------------------+
                 | Restore validation + cutover     |
                 | validate DB, then repoint service|
                 +----------------------------------+
```
