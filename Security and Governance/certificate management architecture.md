# Certificate Management Architecture

A **modern Microsoft-focused certificate architecture** for a hybrid company is usually **not** "one product does everything." The cleanest design is a **hybrid PKI model**:

- **AD CS remains the root of trust for legacy/on-prem AD-integrated workloads**
- **Microsoft Cloud PKI handles Intune-managed endpoint certificates**
- **Azure Key Vault becomes the cloud control plane for workload certificates and rotation automation**
- **Event Grid + Functions/Automation orchestrate renewal and redeployment at scale**

That is the architecture recommended for most enterprises that need to manage certificates **internally**, **on premises**, and **in Azure**, while also improving **rotation across many systems**.

---

## Recommended Target Architecture

### 1. Trust Plane: Keep a Private Enterprise PKI, but Modernize and Reduce Its Scope

Use a **two-tier private PKI** with an **offline root CA** and one or more **online issuing CAs** for the parts of the estate that still require traditional enterprise PKI. Microsoft's PKI guidance says to plan the CA hierarchy carefully and recommends using an HSM for CA keys, and Microsoft security guidance explicitly calls an **offline root CA** "non-negotiable" for a secure enterprise PKI.

For production, do **not** install the CA on a domain controller, and keep the root disconnected except for rare maintenance operations. Microsoft's hybrid certificate-trust guidance also notes that enterprises using certificate-based hybrid trust need enterprise PKI and that domain controllers require certificates for Kerberos-based trust.

#### What Should Stay on This Private PKI

- **Domain controller certificates**
- **NPS/RADIUS certificates**
- **Windows Hello for Business certificate trust dependencies**
- **Legacy server/workload certificates that still depend on AD-integrated templates or enterprise CA behavior**

#### Why This Is Still Needed

Microsoft Cloud PKI is excellent, but its documented issuance model is for **Intune-managed devices** through SCEP-based certificate profiles; it is not a full drop-in replacement for every on-prem server and AD-integrated workload.

---

### 2. Endpoint Plane: Use Microsoft Cloud PKI for Intune-Managed Devices

For **user and device certificates** on modern managed endpoints, use **Microsoft Cloud PKI for Intune**. Microsoft documents that Cloud PKI provides a **cloud-hosted PKI**, automates **issuance, renewal, and revocation**, supports **Windows, macOS, iOS/iPadOS, and Android**, and includes a **cloud SCEP registration authority** so you do not need on-prem NDES servers or the Intune certificate connector for this scenario.

A strong pattern is to use **Cloud PKI with BYOCA** when you want Intune-issued device certificates to chain back to your existing private trust hierarchy. Microsoft explicitly supports anchoring an Intune issuing CA to an external private CA through **BYOCA**, letting you keep the same root trust while modernizing issuance for managed devices.

#### Best Fit for Cloud PKI

- **Wi-Fi / 802.1X**
- **VPN certificates**
- **Device identity**
- **User/device auth certs for managed endpoints**
- **Reducing dependency on AD CS + NDES for endpoint issuance**

#### Why It Matters

This is the most "modern Microsoft" part of the design because Microsoft Cloud PKI was built specifically to simplify certificate lifecycle management for Intune-managed endpoints and remove a lot of the old PKI plumbing.

---

### 3. Workload Plane: Use Azure Key Vault as the Central Certificate Distribution and Automation Hub

For **server/application/workload certificates**, use **Azure Key Vault** as the central inventory, secure storage, and automation point. Microsoft documents that Key Vault supports **certificate lifecycle management**, **automatic renewal before expiry** for supported scenarios, **object versioning**, and **Event Grid notifications** for events like **certificate near expiry** and **new certificate version created**.

This is the key design decision that gives you **rotation at scale**:

1. The **CA** issues or renews the certificate
2. The certificate is stored/imported as a **new version in Key Vault**
3. **Event Grid** fires a near-expiry or new-version event
4. **Azure Functions / Logic Apps / Automation** update the systems that consume the cert
5. Consumers pick up the new version, or an automation script rebinds/restarts the service if needed

#### Important Nuance

Key Vault certificate autorotation is strongest when the certificate is **self-signed** in Key Vault or issued through a **partnered CA integration**. For **internal/private CA** certificates, the practical enterprise pattern is usually: **renew through your private CA, then import the renewed certificate as a new Key Vault version, and let Event Grid + automation handle downstream redeployment**. Microsoft's Key Vault documentation distinguishes certificate autorotation support from general event-driven automation and documents that Key Vault emits events for certificate lifecycle changes.

---

### 4. Rotation/Orchestration Plane: Event-Driven Automation, Not Manual Replacement

If the real goal is "rotate certificates across many systems," the most important architectural principle is:

> **Do not make each server an island. Make Key Vault the system of distribution truth, and make renewal event-driven.**

Microsoft recommends monitoring Key Vault rotation events, using versioning, and integrating automation for dependent systems. Azure Key Vault and Event Grid support **near-expiry**, **expired**, and **new-version-created** events for certificates, keys, and secrets, which is exactly what you want for enterprise-scale rotation workflows.

#### Practical Rotation Pattern

1. **Certificate is due for renewal**
2. Automation renews it from the issuing CA or generates a replacement
3. New certificate version is added to **Key Vault**
4. **Event Grid** triggers an automation workflow
5. Workflow updates:
   - IIS / Windows bindings
   - Linux web server cert paths
   - Reverse proxies / API gateways
   - Application secrets/config where needed
6. Workflow validates service health and only then retires the old cert version

#### Why This Works Better Than Old PKI Operations

Microsoft's Key Vault guidance specifically highlights the security and operational benefits of **regular rotation**, **reduced downtime**, **reduced manual effort**, and **scalable management across multiple assets and services**.

---

## Architecture Diagram

```text
                        ┌──────────────────────────────┐
                        │  Offline Root CA (Private)   │
                        │  HSM-backed / isolated       │
                        └──────────────┬───────────────┘
                                       │
                     ┌─────────────────┴─────────────────┐
                     │                                   │
      ┌──────────────▼──────────────┐     ┌──────────────▼──────────────┐
      │ Online Issuing CA(s)        │     │ Microsoft Cloud PKI         │
      │ AD CS / private CA          │     │ Intune device issuance      │
      │ Legacy + server templates   │     │ SCEP / renew / revoke       │
      └──────────────┬──────────────┘     └──────────────┬──────────────┘
                     │                                   │
                     │                                   │
        ┌────────────▼────────────┐        ┌────────────▼────────────┐
        │ Azure Key Vault         │        │ Intune-managed devices  │
        │ Cert versions + secrets │        │ Wi-Fi / VPN / device ID │
        │ Central distribution    │        │ User/device certs       │
        └────────────┬────────────┘        └─────────────────────────┘
                     │
        ┌────────────▼─────────────────────────────────────────────┐
        │ Event Grid + Functions / Automation / Logic Apps        │
        │ Near-expiry, new-version-created, redeploy workflows    │
        └────────────┬─────────────────────────────────────────────┘
                     │
      ┌──────────────▼──────────────┬───────────────┬───────────────┐
      │ Azure workloads             │ On-prem apps  │ Hybrid VMs     │
      │ App services / gateways     │ IIS / Nginx   │ Windows/Linux  │
      │ Pull or receive new cert    │ Rebind cert   │ Update store   │
      └─────────────────────────────┴───────────────┴───────────────┘
```

This separation keeps **trust issuance**, **endpoint issuance**, and **workload rotation** from becoming one monolithic PKI problem.

---

## Why This Is the Best Microsoft-Centric Design

### It Matches Microsoft's Current Product Strengths

- **Cloud PKI** is best for **modern managed endpoints**
- **AD CS/private PKI** is still required for many **legacy/on-prem AD-integrated scenarios**
- **Key Vault + Event Grid** is Microsoft's strongest pattern for **automated lifecycle handling and rotation orchestration**

### It Minimizes Blast Radius

Keeping the **root CA offline**, keeping issuing CAs scoped, and moving distribution/automation into Key Vault reduces the chance that one compromised server becomes "the place where every certificate lives."

### It Scales Operationally

The combination of **certificate versioning**, **events**, and **automation** scales much better than manual PFX export/import or per-server renewal runbooks. Microsoft explicitly calls out autorotation and event-driven handling as ways to reduce operational overhead and improve reliability.

---

## Opinionated Implementation Guidance

1. **Keep or build a hardened two-tier private PKI** with offline root + online issuing CA(s)
2. **Use Microsoft Cloud PKI for all Intune-managed endpoint certs** and use **BYOCA** if you need the same enterprise trust chain
3. **Move workload certificate distribution to Azure Key Vault** even if the actual certificate is still issued by AD CS
4. **Drive rotation with Event Grid + Azure Functions/Automation**, not manual server touch
5. **Use short-lived leaf certs where operationally possible** so rotation is routine, not a yearly emergency — Microsoft's autorotation guidance is built around regular lifecycle automation and near-expiry handling
6. **Treat domain controllers, NPS, and AD trust dependencies as a separate PKI lane** and do not try to force those entirely into Cloud PKI

---

## Bottom Line

| Component               | Recommendation                                                |
| ----------------------- | ------------------------------------------------------------- |
| Root of Trust           | Offline Root CA + limited private issuing CA(s)               |
| Endpoint Certificates   | Microsoft Cloud PKI for Intune-managed endpoints              |
| Workload Certificates   | Azure Key Vault as the certificate distribution/control plane |
| Rotation Orchestration  | Event Grid + Functions/Automation for mass rotation           |
| AD-Integrated Workloads | Keep on enterprise PKI, but shrink that scope over time       |

---

### Reference Links

| Topic                                            | Link                                                                                                                                                                                          |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Microsoft Cloud PKI for Intune                   | [learn.microsoft.com](https://learn.microsoft.com/en-us/intune/cloud-pki/)                                                                                                                    |
| Azure Key Vault Autorotation                     | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/key-vault/general/autorotation)                                                                                                 |
| Azure Key Vault Event Grid Overview              | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/key-vault/general/event-grid-overview)                                                                                          |
| AD CS PKI Design Considerations                  | [learn.microsoft.com](https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/pki-design-considerations)                                                                              |
| Windows Hello for Business Hybrid Cert Trust PKI | [learn.microsoft.com](https://learn.microsoft.com/en-us/windows/security/identity-protection/hello-for-business/deploy/hybrid-cert-trust-pki)                                                 |
| Key Vault Certificate Rotation Tutorial          | [learn.microsoft.com](https://learn.microsoft.com/en-us/azure/key-vault/certificates/tutorial-rotate-certificates)                                                                            |
| Event Grid Key Vault Event Schema                | [docs.azure.cn](https://docs.azure.cn/en-us/event-grid/event-schema-key-vault)                                                                                                                |
| AD CS Hardening and Secure Configuration         | [techcommunity.microsoft.com](https://techcommunity.microsoft.com/blog/coreinfrastructureandsecurityblog/secure-configuration-and-hardening-of-active-directory-certificate-services/4463240) |
