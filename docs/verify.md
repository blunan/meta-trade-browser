# Security and verification

## Pin a digest and check its signature

An optional, advanced step: pin a digest and check its signature.

A tag can move to another build; a digest (`sha256:…`) names exactly one. Every image this repository's CI builds is signed with cosign, keyless, by its GitHub Actions workflow. Only an image that passed the tests and the vulnerability scan is pushed, and it's signed before any tag points to it. To check one before you run it:

```sh
docker buildx imagetools inspect ghcr.io/blunan/metatrader-docker:20261019.1
cosign verify ghcr.io/blunan/metatrader-docker@sha256:<digest> \
  --certificate-identity https://github.com/blunan/metatrader-docker/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The first command prints the digest. Then pin it in `compose.yaml` (or `docker run`): `ghcr.io/blunan/metatrader-docker:20261019.1@sha256:<digest>`. Docker uses the digest, and the tag stays only as a reminder.

## Its package list and build record

Each image also carries a list of its packages (an SBOM) and a record of how it was built (its provenance):

```sh
docker buildx imagetools inspect ghcr.io/blunan/metatrader-docker:latest --format '{{ json .SBOM }}'
docker buildx imagetools inspect ghcr.io/blunan/metatrader-docker:latest --format '{{ json .Provenance }}'
```

## What the container connects to

For networks that filter outgoing traffic:

| When | Host | What for |
|---|---|---|
| First start | `msedge.sf.dl.delivery.mp.microsoft.com` | The WebView2 installer |
| First start | `www.microsoft.com` | Revocation lists, for the WebView2 installer's signature check |
| First start, then in the background | `config.edge.skype.com`, `msedge.api.cdp.microsoft.com`, `msedge.f.tlu.dl.delivery.mp.microsoft.com` | Edge Update, which installs WebView2 and keeps it current |
| First start | `download.mql5.com` | The MetaTrader installer, and the files it installs |
| First start | `crl3.digicert.com` | A revocation list, for the MetaTrader installer's signature check |
| First start | `content.finteza.com` | MetaQuotes' analytics service, contacted by the MetaTrader installer |
| From the first start on | `download.terminal.free` | LiveUpdate, MetaTrader's own updates |
| Once you log in | your broker's servers | Trading, and LiveUpdate through them |
| When you use them | MetaQuotes' MQL5 services | Market, Signals, Code Base and the like |

That's what a first start looked up, with MetaTrader idle afterwards. Your broker, and the features you use, add their own hosts.

## MetaTrader's AI-agent servers

MetaTrader and MetaEditor can run servers for AI agents (MCP) on the container's own loopback: MetaTrader on port 22346, and MetaEditor on 22345. They're protected only by an API key that MetaTrader keeps in `Config/assistant.ini`. In this image they're off at every start unless `MT_AI_AGENTS=true`; changing it takes a restart. With host networking, they would listen on the server's own loopback.
