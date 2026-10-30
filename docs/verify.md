# Security and verification

## Pin a digest and check its signature

Every published image is cryptographically signed keyless with Cosign via GitHub Actions. Only builds passing all automated tests and vulnerability scans are signed and tagged.

Inspect and verify an image:

```sh
docker buildx imagetools inspect ghcr.io/blunan/metatrader-docker:20261019.1
cosign verify ghcr.io/blunan/metatrader-docker@sha256:<digest> \
  --certificate-identity https://github.com/blunan/metatrader-docker/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Pin the verified digest in `compose.yaml` (or `docker run`): `ghcr.io/blunan/metatrader-docker:20261019.1@sha256:<digest>`.

## SBOM and build provenance

Inspect the Software Bill of Materials (SBOM) and SLSA build provenance:

```sh
docker buildx imagetools inspect ghcr.io/blunan/metatrader-docker:latest --format '{{ json .SBOM }}'
docker buildx imagetools inspect ghcr.io/blunan/metatrader-docker:latest --format '{{ json .Provenance }}'
```

## What the container connects to

For firewalls restricting outbound egress:

| Lifecycle | Endpoint | Purpose |
|---|---|---|
| Initial boot | `msedge.sf.dl.delivery.mp.microsoft.com` | Microsoft Edge WebView2 installer |
| Initial boot | `www.microsoft.com` | CRL revocation lists for Microsoft signature verification |
| Initial boot & background | `config.edge.skype.com`, `msedge.api.cdp.microsoft.com`, `msedge.f.tlu.dl.delivery.mp.microsoft.com` | Edge Update service |
| Initial boot | `download.mql5.com` | MetaTrader installer and binary components |
| Initial boot | `crl3.digicert.com` | DigiCert CRL for MetaQuotes signature verification |
| Initial boot | `content.finteza.com` | MetaQuotes installer telemetry endpoint |
| With `MT_PYTHON=true` | `www.python.org`, `www.microsoft.com` | Python installer and CRL endpoints |
| With `MT_PYTHON=true` | `pypi.org`, `files.pythonhosted.org` | PyPI package downloads (`MetaTrader5`, `numpy`) |
| Ongoing | `download.terminal.free` | MetaTrader LiveUpdate |
| Post-login | Broker access points | Market data, trade execution, broker LiveUpdate |
| Interactive use | MetaQuotes MQL5 services | Market, Signals, and Code Base |

## MetaTrader's AI-agent servers

MetaTrader and MetaEditor can run Model Context Protocol (MCP) servers on container loopback (MetaTrader: 22346, MetaEditor: 22345), protected by an API key stored in `Config/assistant.ini`. These servers are disabled by default and enabled only when `MT_AI_AGENTS=true`. With host networking, these ports bind directly to the server's loopback interface.
