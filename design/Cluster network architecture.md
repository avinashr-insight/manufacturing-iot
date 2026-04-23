# Cluster Network Topology – Hybrid OT / IT with ExpressRoute
This diagram presents the hybrid cluster topology for Azure AIO, showing how on‑premises K3s clusters in OT and IT environments are connected to Azure through private express route connectivity and managed centrally using Azure Arc. OT clusters remain isolated within their own network zones, while approved data flows are routed through the iDMZ to access analytics,and management services in Azure.
The network design ensures all cluster connectivity follows controlled, auditable paths, preserving the safety and reliability of OT systems while enabling enterprise‑wide visibility and lifecycle management. 

![Cluster Network Topology](../images/Cluster%20Network%20Topology.png)


# Data Flow – On‑Premises / Data Center to Azure
This diagram illustrates how on‑premises OT and IT environments securely connect to Azure to support Azure AIO and Arc‑enabled K3s clusters. Private connectivity provides predictable, reliable access to Azure services without reliance on the public internet. All traffic enters Azure through centralized control points, ensuring consistent inspection, monitoring, and access control.
This approach allows operational teams to adopt cloud‑based capabilities while maintaining strong separation between OT and IT environments. 

![Data Flow – On‑Premises / Data Center to Azure](../images/Data%20Flow%20DC%20to%20Azure.png)


# Data Flow – iDMZ to IT Spoke
This diagram summarizes how the iDMZ and IT networks are connected to support Azure Arc–enabled K3s clusters as part of an Azure AIO implementation. The iDMZ acts as a controlled integration zone where edge and analytics workloads can operate without direct access to core IT systems. Centralized IT services—such as identity, security monitoring, and configuration management—are accessed through tightly governed network paths, ensuring consistent governance across distributed clusters.
The design enables centralized visibility and policy enforcement for Arc‑managed Kubernetes environments while reducing risk to enterprise systems. Network segmentation ensures workloads in the iDMZ can be managed and monitored from IT without expanding trust boundaries, supporting scalable operations and regulatory expectations for secure OT‑adjacent deployments.

![Data Flow – iDMZ to IT Spoke](../images/Data%20Flow%20iDMZ%20to%20IT%20Spoke.png)