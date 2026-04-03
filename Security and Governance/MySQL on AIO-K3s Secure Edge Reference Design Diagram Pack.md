# MySQL on AIO/K3s – Diagram Pack

Use this diagram pack as **Section 3.3 – Visual architecture diagrams** in the original MySQL reference design.

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
|  +------------------------------------+   +-------------------------------+      |
|  | db-mysql                           |   | db-mysql-router               |      |
|  | MySQL primary / replicas           |<--| Router / proxy tier           |<-----+-- line-app
|  | ClusterIP service                  |   +-------------------------------+      |  namespaces
|  +------------------^-----------------+                                       |  |
|                     |                                                         |  |
|  +------------------------------------+                                       |  |
|  | db-mysql-backup                    |---------------------------------------+  |
|  | backup / binlog archive / restore  |                                          |
|  +------------------------------------+                                          |
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
                               [MySQL Pod / Router Pod: certs / creds mounted]
                                                          |
                                                          v
                                         [TLS connection using approved MySQL role]
```

### Backup and restore flow (Mermaid)

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

### Backup and restore flow (pseudo-Visio)

```text
+-----------------------+      +---------------------------+      +---------------------------+
| db-mysql namespace    |      | db-mysql-router namespace |      | db-mysql-backup namespace |
| MySQL primary         |----->| Router / proxy tier       |<-----| Cutover after validation  |
| Replica 1 / Replica 2 |      +---------------------------+      | Full backup / binlog /    |
| ClusterIP service     |                                            | restore validation jobs |
+-----------+-----------+                                            +-------------+-----------+
            |                                                                      |
            v                                                                      v
+-------------------------------+                                   +-------------------------------+
| Local edge backup tier        |                                   | Remote / Azure archival tier  |
| encrypted snapshots / backups |                                   | off-site backups / binlogs    |
+---------------+---------------+                                   +---------------+---------------+
                \\                                                                 /
                 \\                                                               /
                  v                                                             v
                          +-------------------------------------------+
                          | Restore validation + router/service cutover|
                          +-------------------------------------------+
```
