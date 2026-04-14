# AIO Edge Cluster — Network & Architecture Reference

> **Audience:** Platform engineers, network architects, and cloud infrastructure teams responsible for deploying, operating, or extending the Azure IoT Operations (AIO) edge cluster deployment in a manufacturing environment.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Cluster Topology — Diagram 1](#2-cluster-topology--diagram-1)
   - 2.1 [OT Source Zones](#21-ot-source-zones)
   - 2.2 [Edge Clusters (k3s)](#22-edge-clusters-k3s)
   - 2.3 [Data-Center (DC) VLAN Transit Zone](#23-data-center-dc-vlan-transit-zone)
   - 2.4 [Azure OT Hub](#24-azure-ot-hub)
   - 2.5 [Azure IT Hub](#25-azure-it-hub)
   - 2.6 [Shared Azure Services](#26-shared-azure-services)
   - 2.7 [Firewall Boundaries](#27-firewall-boundaries)
3. [Data Flow: DC to Azure — Diagram 2](#3-data-flow-dc-to-azure--diagram-2)
   - 3.1 [OT ExpressRoute Path (Step 1)](#31-ot-expressroute-path-step-1)
   - 3.2 [IT ExpressRoute Path (Step 2)](#32-it-expressroute-path-step-2)
   - 3.3 [Azure Ingestion Paths (Steps 3.A & 3.B)](#33-azure-ingestion-paths-steps-3a--3b)
4. [Data Flow: iDMZ to IT — Diagram 3](#4-data-flow-idmz-to-it--diagram-3)
   - 4.1 [Steps 1–4 (OT-side)](#41-steps-14-ot-side)
   - 4.2 [ADLS Gen2 & IT-Hub Paths (Steps 2–3)](#42-adls-gen2--it-hub-paths-steps-23)
   - 4.3 [Open Design Decisions](#43-open-design-decisions)
5. [Network Addressing & CIDR Allocation](#5-network-addressing--cidr-allocation)
6. [Authentication & Identity Domains](#6-authentication--identity-domains)
7. [Key Azure Services Reference](#7-key-azure-services-reference)
8. [Critical Constraints & Design Decisions](#8-critical-constraints--design-decisions)
9. [Legend](#9-legend)

---

## 1. Architecture Overview

This architecture describes a **dual-cluster, dual-hub Azure Arc + k3s edge deployment** for a manufacturing facility. The design separates operational technology (OT) and information technology (IT) domains at every layer — network, identity, and cloud connectivity — while enabling telemetry, analytics, and GitOps-driven workload management through Azure Arc.

### High-Level Design Principles

| Principle | Implementation |
|---|---|
| **OT/IT Air-Gap** | Separate ExpressRoute circuits, separate Azure hubs, no hub peering |
| **Edge Resilience** | k3s clusters are self-sufficient; PostgreSQL runs on local disk with replication |
| **Zero Internet Egress (OT)** | OT network is fully closed — no internet in or out |
| **Closed DC VLAN** | Building DC VLAN is internet-isolated; routing is transit-only |
| **GitOps / Arc-Managed** | Both clusters registered as separate Arc-enabled cluster objects |
| **mTLS End-to-End** | Cluster secrets and TLS certificates managed via Azure Key Vault (private endpoint) |

### Topology Zones at a Glance

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  OT Source Layer (Red)      │  Edge Clusters (Orange)  │  DC VLAN (Gold)            │
│  Atlas PLCs / BAS4 PLCs     │  Cluster 1 — Atlas Line  │  Building Core Switch      │
│  OPC-UA / REST / Ignition   │  Cluster 2 — BAS4 Line   │  AD DNS / NTP / Admin VDI │
│  Gateways                   │  k3s · Kube-VIP · PG     │  Palo Alto FW (BAS4 only) │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                          ┌─────────────┴────────────┐
                          │ OT ExpressRoute           │ IT ExpressRoute
                          ▼                           ▼
               ┌──────────────────┐       ┌──────────────────────┐
               │ Azure OT Hub     │       │ Azure IT Hub          │
               │ NAIOT.com Auth   │       │ NA.Denso.com Auth     │
               │ Key Vault (PE)   │       │ Databricks / ADLS     │
               │ Azure DevOps     │       │ Power BI              │
               └──────────────────┘       └──────────────────────┘
                          │                           │
                          └─────────────┬─────────────┘
                                        │
                          ┌─────────────▼────────────┐
                          │ Shared Azure Services      │
                          │ Event Hubs · Event Grid    │
                          │ Azure Monitor · ACR · Arc  │
                          └───────────────────────────┘
```

> **Critical constraint:** The OT hub and IT hub **cannot be peered**. Data crossing the OT→IT boundary must traverse an explicit path (iDMZ or double-hop via DC VLAN). This is a hard network policy enforced by the customer's security team.

---

## 2. Cluster Topology — Diagram 1

**Diagram name:** _AIO Edge Cluster — Network Topology_

This diagram captures the physical and logical network layout from the OT floor to Azure.

---

### 2.1 OT Source Zones

Two isolated OT zones originate data from the production floor.

#### Atlas / 103 PLC Zone

| Component | Detail |
|---|---|
| **PLCs** | Atlas/103 PLCs on the OT network (`192.168.x.x`) |
| **Gateway** | Single gateway node exposing OPC-UA, REST, and Ignition Streaming interfaces |
| **Protocol** | OPC-UA (primary), REST (secondary), Ignition Streaming |
| **Connectivity** | Gateway connects directly to Cluster 1 (line-side NIC) |

#### BAS4 PLC Zone

| Component | Detail |
|---|---|
| **PLCs** | BAS4 PLCs — isolated OT network; approximately 46 machines |
| **Gateway** | Single gateway node exposing OPC-UA, REST, and Ignition Streaming |
| **Protocol** | OPC-UA (primary), REST (secondary), Ignition Streaming |
| **Connectivity** | Gateway connects directly to Cluster 2 (line-side NIC) |
| **Special constraint** | BAS4 cluster **must remain on the OT network**; NIC 2 must carry DC VLAN traffic across the Palo Alto firewall |

---

### 2.2 Edge Clusters (k3s)

Both clusters run **k3s** (lightweight Kubernetes) and are deployed as **3-node control-plane + worker** configurations. Each node is dual-homed.

#### Cluster 1 — Atlas Line

| Property | Value |
|---|---|
| **Nodes** | 3 nodes (Node 1, Node 2, Node 3) |
| **NIC 1** | Line-side (OT network — Atlas Gateway) |
| **NIC 2** | DC VLAN |
| **VIP / Load Balancer** | Kube-VIP (L2 ARP mode) |
| **Exposed VIPs** | MQTT `:8883`, Kubernetes API `:443` |
| **Database** | PostgreSQL StatefulSet (`edge-db`) — local disk replication |
| **Constraint** | Cluster must stay on OT network; NIC 2 reaches DC VLAN for upstream connectivity |
| **CIDR (Line-side)** | `/27` (pending assignment — open design decision) |
| **CIDR (DC VLAN)** | `/27` (pending assignment — open design decision) |

#### Cluster 2 — BAS4 Line

| Property | Value |
|---|---|
| **Nodes** | 3 nodes (Node 1, Node 2, Node 3) |
| **NIC 1** | OT line-side (BAS4 Gateway) |
| **NIC 2** | DC VLAN |
| **VIP / Load Balancer** | Kube-VIP (L2 ARP mode) |
| **Exposed VIPs** | MQTT `:8883`, Kubernetes API `:443` |
| **Database** | PostgreSQL StatefulSet (`edge-db`) — local disk replication |
| **Constraint** | Cluster must stay on OT network; NIC 2 must cross Palo Alto firewall to reach DC VLAN |
| **CIDR (Line-side)** | `/27` (pending assignment — open design decision) |
| **CIDR (DC VLAN)** | `/27` (pending assignment — open design decision) |

> **Kube-VIP** provides L2 ARP-based virtual IP advertisement. This means the VIP is anchored to the local broadcast domain. No BGP or external load-balancer is required. The API server VIP and the MQTT broker VIP are both served from the same pool.

> **PostgreSQL** is deployed as a StatefulSet with local-disk-backed PersistentVolumes and cross-node replication within the cluster. No external database dependency exists — this is intentional for edge resiliency.

---

### 2.3 Data-Center (DC) VLAN Transit Zone

The DC VLAN is a **closed, internet-isolated** transit network. It provides cluster-to-cloud connectivity and on-premises shared services.

| Component | Role | Notes |
|---|---|---|
| **Building Core Switch** | Layer-3 routing between subnets | Routing transit only — no internet |
| **AD DNS (on-prem)** | DNS resolution for clusters | CoreDNS on each cluster forwards to this server |
| **NTP — Stratum 2 (on-prem)** | Time synchronization | Critical cluster dependency — k3s and cert rotation require accurate time |
| **Admin / Management** | kubectl / VDI access | Delivered via Secure Link / VDI; no direct internet path |
| **OT ExpressRoute** | OT hub connectivity | ~dedicated circuit; low latency; closed-network path |
| **IT ExpressRoute** | IT hub connectivity | ~30–40 ms; IT hub path only |
| **ADFS Integration Run-Time** | Federation / SSO | Open design decision: can on-prem ADFS reach the IT ExpressRoute? |

> **Double-hop concern:** BAS4 (Cluster 2) traffic must traverse two hops to reach Azure — (1) across the Palo Alto firewall from OT to DC VLAN, then (2) through the DC VLAN to ExpressRoute. This adds latency and a firewall inspection point that must be accounted for in QoS and firewall rule design.

---

### 2.4 Azure OT Hub

Governed by the **NAIOT.com** authentication domain. This is a closed Azure environment — no public internet access.

| Service | Purpose |
|---|---|
| **Azure Key Vault** (Private Endpoint) | Stores cluster secrets and mTLS certificates for both edge clusters |
| **Azure DevOps** (Self-hosted agent in OT hub) | GitOps pipeline execution; agent runs inside the OT hub to avoid public internet |
| **Azure Arc** (registration endpoint) | Both clusters register here as separate Arc-enabled Kubernetes objects |

> Key Vault is accessed exclusively via Private Endpoint — no public endpoint is enabled. The private DNS zone must be configured within the OT hub VNet.

---

### 2.5 Azure IT Hub

Governed by the **NA.Denso.com** authentication domain. Hosts the analytics and BI workloads.

| Service | Purpose |
|---|---|
| **Azure Databricks** | Delta Live Tables, analytics pipelines |
| **ADLS Gen2** | Co-located with Databricks; primary analytics data store |
| **Power BI** | Cloud dashboards; connects to Databricks |
| **Azure Key Vault** (IT Hub) | IT-scoped secrets, separate from OT Key Vault |
| **Azure Databricks Private Endpoint** | Isolates Databricks workspace from public network |

> **IT hub and OT hub cannot be peered.** Any data flow between the two hubs must traverse an explicit intermediary (e.g., Event Hubs, ADLS, or an approved iDMZ path). This is the most significant architectural constraint in the design.

---

### 2.6 Shared Azure Services

These services span both hubs and are accessible from both paths.

| Service | Purpose | Key Detail |
|---|---|---|
| **Azure Event Hubs** | Real-time telemetry ingestion; traceability events | Primary landing zone for edge telemetry |
| **Azure Event Grid** | Andon fast-path; sub-second SLA; LineStop events | Used for real-time alerting, not batch |
| **Azure Monitor** | Logs and metrics for both clusters | Reporting and alerting; cluster health dashboards |
| **Azure Container Registry (ACR)** | ALT container images | Private endpoint; used by Arc GitOps for image pulls |
| **Azure Arc** | Both clusters registered as separate objects | Provides GitOps, policy, and extension management |

---

### 2.7 Firewall Boundaries

| Firewall | Location | Scope |
|---|---|---|
| **Palo Alto (on-prem)** | Between BAS4 OT network and DC VLAN | Controls NIC 2 egress from Cluster 2; only cluster requiring FW traversal |
| **Azure Firewall / NVA (OT hub)** | OT hub VNet perimeter | Controls what the OT ExpressRoute path can reach in Azure |
| **Azure Firewall / NVA (IT hub)** | IT hub VNet perimeter | Controls IT ExpressRoute-sourced traffic entering the IT hub |

---

## 3. Data Flow: DC to Azure — Diagram 2

**Diagram name:** _AIO Edge — Data Flow DC to Azure_

This diagram illustrates the numbered data flow steps for telemetry and control data moving from on-premises edge clusters to Azure cloud services.

---

### 3.1 OT ExpressRoute Path (Step 1)

```
Edge Cluster (NIC 2) → DC VLAN Core Switch → OT ExpressRoute → Azure OT Hub
```

- **Step 1:** Edge cluster(s) emit telemetry via NIC 2 into the DC VLAN. The building core switch routes traffic to the OT ExpressRoute circuit. Data arrives in the Azure OT Hub VNet.
- Traffic at this stage includes: MQTT telemetry, Arc heartbeat/management, Key Vault secret retrieval, and container image pulls from ACR.
- The OT ExpressRoute is a dedicated, private circuit — no shared internet path.

---

### 3.2 IT ExpressRoute Path (Step 2)

```
DC VLAN Core Switch → IT ExpressRoute (~30–40 ms) → Azure IT Hub
```

- **Step 2:** Separately, IT-bound traffic (e.g., aggregated data destined for Databricks or ADLS) routes via the IT ExpressRoute circuit into the IT hub.
- Latency baseline: **30–40 ms** (on-prem to IT hub).
- IT hub authentication uses **NA.Denso.com** identity — separate from OT hub credentials.

---

### 3.3 Azure Ingestion Paths (Steps 3.A & 3.B)

| Step | Path | Status |
|---|---|---|
| **3.A** (Green) | OT Hub → Event Hubs → Azure Monitor / ACR / Arc | Confirmed architecture |
| **3.B** (Yellow) | IT Hub → Azure Databricks Private Endpoint → ADLS Gen2 | **Open design decision** — Databricks PE connectivity model under review |

**Step 3.A detail:**
- Event Hubs receives real-time telemetry from the edge clusters (via OT hub relay).
- Azure Monitor collects cluster logs and metrics from both clusters.
- ACR serves container images via private endpoint to Arc-managed GitOps pulls.

**Step 3.B detail:**
- Azure Databricks accesses ADLS Gen2 via a Private Endpoint.
- The exact network path (whether Databricks PE is in the IT hub VNet or a dedicated spoke) is an **open design decision**.
- Azure Private Link is used; the green dashed line in the diagram represents this PE-to-ADLS path.

---

## 4. Data Flow: iDMZ to IT — Diagram 3

**Diagram name:** _AIO Edge — Data Flow iDMZ to IT_

This diagram focuses on the data path from the on-premises DC VLAN zone (acting as an industrial DMZ / iDMZ) through to the IT hub and ultimately to ADLS Gen2 and Databricks. This is the analytics ingestion path.

---

### 4.1 Steps 1–4 (OT-side)

The left-hand legend panel in this diagram enumerates the confirmed and open steps:

| Step | Color | Description |
|---|---|---|
| **1** | Green (confirmed) | Edge cluster emits telemetry → Event Hubs (via OT ExpressRoute) |
| **2** | Green (confirmed) | Event Hubs triggers downstream processing (e.g., Azure Functions or Stream Analytics) |
| **3** | Green (confirmed) | Processed data written to ADLS Gen2 in IT hub via VNet integration or service endpoint |
| **4** | Green (confirmed) | Databricks Delta Live Tables reads from ADLS Gen2; runs analytics pipeline |

Step 4 corresponds to the **numbered bubble "4"** appearing near the Azure Databricks resource in the IT Hub zone.

---

### 4.2 ADLS Gen2 & IT-Hub Paths (Steps 2–3)

Two numbered open decision items appear in this diagram:

| Item | Color | Description |
|---|---|---|
| **Open Decision 1** | Yellow | Can on-prem ADFS Integration Run-Time reach the IT ExpressRoute? (ADFS zone shown in DC VLAN) |
| **Open Decision 2** | Yellow | Databricks Private Endpoint — network placement and DNS resolution model within the IT hub |

The **ADLS Gen2** resource is co-located with Databricks in the IT hub and is referenced as the terminal data store for both the analytics pipeline (Databricks Delta Live Tables) and the Power BI reporting layer.

---

### 4.3 Open Design Decisions

The following items appear explicitly as yellow (pending) elements across the three diagrams:

| # | Decision | Impact |
|---|---|---|
| **D-1** | Line-side CIDR allocation (`/27` each cluster) | Must not overlap with OT network or DC VLAN ranges |
| **D-2** | DC VLAN CIDR allocation (`/27` each cluster) | Must be routable to both ExpressRoute circuits |
| **D-3** | Can on-prem ADFS reach the IT ExpressRoute? | Determines SSO/federation capability for IT-hub-hosted tools |
| **D-4** | Databricks Private Endpoint placement | Affects DNS, routing, and PE subnet sizing in the IT hub |
| **D-5** | BAS4 Palo Alto firewall rule set | Must allow NIC 2 egress from Cluster 2 to DC VLAN without breaking OT isolation |

---

## 5. Network Addressing & CIDR Allocation

> **Note:** Specific CIDR values are partially defined. Items marked ⚠️ are open design decisions.

| Segment | Network | CIDR | Status |
|---|---|---|---|
| Atlas OT (line-side) | `192.168.x.x` | Existing OT range | Assigned |
| BAS4 OT (line-side) | OT network (isolated) | Existing OT range | Assigned (isolated) |
| Cluster 1 — Line-side NIC | Line-side VLAN | `/27` | ⚠️ Pending |
| Cluster 1 — DC VLAN NIC | DC VLAN | `/27` | ⚠️ Pending |
| Cluster 2 — Line-side NIC | Line-side VLAN | `/27` | ⚠️ Pending |
| Cluster 2 — DC VLAN NIC | DC VLAN | `/27` | ⚠️ Pending |
| DC VLAN (transit) | Building backbone | Existing | Closed / no internet |
| Azure OT Hub VNet | Azure (OT) | TBD | Private, NAIOT.com |
| Azure IT Hub VNet | Azure (IT) | TBD | Private, NA.Denso.com |

### Kube-VIP Address Pools

Each cluster requires at least **2 VIPs** from its line-side `/27` or a dedicated VIP pool:

| VIP | Port | Purpose |
|---|---|---|
| MQTT VIP | `:8883` | MQTT broker endpoint for OT gateway clients |
| API VIP | `:443` | Kubernetes API server (Arc, kubectl, GitOps) |

VIP advertisement uses **L2 ARP** — the VIP must be in the same broadcast domain as the nodes' NIC 1 (line-side). Ensure no static ARP conflicts exist with PLC gateways.

---

## 6. Authentication & Identity Domains

The architecture enforces strict domain separation between OT and IT.

| Domain | Scope | Used By |
|---|---|---|
| **NAIOT.com** | OT hub | Azure Arc, Azure DevOps (OT agent), Key Vault (OT), ACR |
| **NA.Denso.com** | IT hub | Databricks, ADLS Gen2, Power BI, Azure DevOps (IT agent) |
| **AD (on-prem)** | DC VLAN | CoreDNS forwarding, Admin/VDI access, ADFS Run-Time |

### Key Vault Strategy

| Key Vault Instance | Hub | Access Method | Secrets Stored |
|---|---|---|---|
| KV — OT Hub | OT hub | Private Endpoint only | Cluster mTLS certs, Arc enrollment tokens, ACR pull secrets |
| KV — IT Hub | IT hub | Private Endpoint only | Databricks tokens, ADLS access keys, IT-scoped secrets |

> **No cross-hub Key Vault access.** Each cluster retrieves secrets from the OT-hub Key Vault exclusively. IT hub secrets are only accessible from IT-hub-resident workloads.

### Azure DevOps Agent Placement

| Agent | Hub | Rationale |
|---|---|---|
| Self-hosted agent (OT) | OT hub VNet | Can reach Arc API, ACR, and Key Vault via private network without traversing internet |
| Self-hosted agent (IT) | IT hub VNet | Can reach Databricks, ADLS, and IT pipeline resources |

---

## 7. Key Azure Services Reference  

### Event Hubs

- **Purpose:** Primary telemetry ingestion from edge clusters
- **Data:** Real-time sensor telemetry, traceability events, Andon signals
- **Consumers:** Azure Stream Analytics, Databricks (via Event Hubs connector), Azure Monitor
- **Network:** Accessible from OT hub via private endpoint or service endpoint (confirm model)

### Event Grid

- **Purpose:** Fast-path event routing for Andon (line-stop) events
- **SLA:** Sub-second delivery guarantee
- **Topics:** `LineStop`, `QualityAlert` (inferred from diagram label)
- **Consumers:** Downstream alerting services, Power BI streaming datasets

### Azure Monitor

- **Scope:** Both clusters (Cluster 1 and Cluster 2)
- **Data collected:** Container logs, node metrics, Arc extension health, PostgreSQL metrics
- **Reporting:** Used for SLA reporting and operational alerting

### Azure Container Registry (ACR)

- **Purpose:** Stores all workload container images for Arc GitOps deployments
- **Access:** Private endpoint; clusters pull images via the OT ExpressRoute path
- **Images:** AIO workload images, operator images, custom manufacturing application containers

### Azure Arc

- **Registration:** Both Cluster 1 and Cluster 2 registered as **separate Arc-enabled Kubernetes** cluster objects
- **Extensions:** GitOps (Flux), Azure Monitor extension, Key Vault CSI driver (expected)
- **Policy:** Azure Policy applied at Arc cluster scope
- **GitOps:** Flux-based; pipeline managed by the self-hosted Azure DevOps agent in the OT hub

### Azure Databricks

- **Purpose:** Delta Live Tables for streaming + batch analytics
- **Storage:** ADLS Gen2 (co-located in IT hub)
- **Access:** Private Endpoint (placement TBD — open design decision D-4)
- **Auth:** NA.Denso.com identity

### ADLS Gen2

- **Purpose:** Primary analytics data lake
- **Location:** IT hub, co-located with Databricks
- **Ingest path:** Event Hubs → (processing) → ADLS Gen2
- **Consumers:** Databricks Delta Live Tables, Power BI

### Power BI

- **Purpose:** Cloud-based operational and analytics dashboards
- **Data source:** Azure Databricks (DirectQuery or import mode)
- **Auth:** NA.Denso.com

---

## 8. Critical Constraints & Design Decisions  

### Hard Constraints (Non-Negotiable)

| Constraint | Rationale |
|---|---|
| OT hub and IT hub **cannot be peered** | Customer network security policy; prevents OT data from leaking into the broader IT network without explicit crossing points |
| OT clusters **must remain on the OT network** | PLC gateway connectivity requires line-side adjacency; moving off the OT network breaks OPC-UA/Ignition streaming |
| DC VLAN is **closed — no internet in or out** | Compliance and OT security requirement |
| Azure Key Vault accessed **via Private Endpoint only** | No public endpoint exposure for secrets management |
| BAS4 (Cluster 2) **must traverse Palo Alto FW** to reach DC VLAN | BAS4 OT network is fully isolated; the only egress path is through the Palo Alto perimeter firewall |

### Architectural Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Double-hop latency (BAS4)** | Medium | OT → Palo Alto FW → DC VLAN → ExpressRoute adds 2–3 ms per hop; benchmark under load |
| **Kube-VIP L2 ARP scope** | Medium | VIP is broadcast-domain scoped; NIC 1 must be on a flat L2 segment with gateways |
| **CoreDNS dependency on AD DNS** | High | If AD DNS is unavailable, cluster DNS resolution fails; consider secondary forwarder or CoreDNS cache TTL extension |
| **NTP single point of failure** | Medium | Stratum 2 on-prem NTP; consider at least 2 NTP server targets in cluster config |
| **ADFS federation to IT hub (D-3)** | High | If ADFS cannot reach IT ExpressRoute, admin SSO for IT-hub tools requires a separate path (jump host or P2S VPN) |
| **Databricks PE DNS resolution** | Medium | Custom DNS zone delegation required; Databricks PE in IT hub must be resolvable from workloads in same VNet |
| **PostgreSQL local disk — no Azure Backup** | Medium | Local replication only; disk failure on majority of nodes is unrecoverable without Azure Backup or Velero |

---



---

## Appendix A — Component Inventory Summary

| Component | Type | Zone | Technology |
|---|---|---|---|
| Atlas/103 PLCs | OT Device | Atlas OT Zone | OPC-UA, proprietary |
| Atlas Gateway | Edge Gateway | Atlas OT Zone | OPC-UA, REST, Ignition |
| BAS4 PLCs (~46) | OT Device | BAS4 OT Zone | OPC-UA, proprietary |
| BAS4 Gateway | Edge Gateway | BAS4 OT Zone | OPC-UA, REST, Ignition |
| Cluster 1 (3 nodes) | Edge Compute | DC / OT | k3s, Kube-VIP, PostgreSQL |
| Cluster 2 (3 nodes) | Edge Compute | DC / OT | k3s, Kube-VIP, PostgreSQL |
| Palo Alto Firewall | Network Security | On-Prem | L3/L4 stateful inspection |
| Building Core Switch | Network | DC VLAN | L3 routing (transit only) |
| AD DNS | On-Prem Service | DC VLAN | Active Directory DNS |
| NTP (Stratum 2) | On-Prem Service | DC VLAN | NTP |
| OT ExpressRoute | WAN Circuit | DC VLAN → Azure OT | Azure ExpressRoute |
| IT ExpressRoute | WAN Circuit | DC VLAN → Azure IT | Azure ExpressRoute (~30–40 ms) |
| Azure Arc | Cloud Control Plane | Azure (OT Hub) | Azure Arc-enabled Kubernetes |
| Azure Key Vault (OT) | Secret Store | Azure OT Hub | Private Endpoint |
| Azure Key Vault (IT) | Secret Store | Azure IT Hub | Private Endpoint |
| Azure DevOps (OT agent) | CI/CD | Azure OT Hub | Self-hosted agent |
| Azure DevOps (IT agent) | CI/CD | Azure IT Hub | Self-hosted agent |
| Azure Event Hubs | Messaging | Shared | Apache Kafka-compatible |
| Azure Event Grid | Eventing | Shared | Push-based, sub-second |
| Azure Monitor | Observability | Shared | Logs + Metrics |
| Azure Container Registry | Registry | Shared | OCI-compliant, Private PE |
| Azure Databricks | Analytics | Azure IT Hub | Delta Live Tables |
| ADLS Gen2 | Data Lake | Azure IT Hub | Hierarchical namespace |
| Power BI | Reporting | Azure IT Hub | Cloud-native BI |

---

*Document generated from `Cluster-Network-Topology.drawio` (branch: `networking`) — avinashr-insight/manufacturing-iot*
*Last updated: 2026-04-14*
