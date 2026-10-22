# Verify the image

An optional, advanced step: pin a digest and check its signature.

A tag can move to another build; a digest (`sha256:…`) names exactly one. Every image this repository's CI builds is signed with cosign, keyless, by its GitHub Actions workflow. To check one before you run it:

```sh
docker buildx imagetools inspect ghcr.io/blunan/mt-browser:20261019
cosign verify ghcr.io/blunan/mt-browser@sha256:<digest> \
  --certificate-identity https://github.com/blunan/mt-browser/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The first command prints the digest. Then pin it in `compose.yaml` (or `docker run`): `ghcr.io/blunan/mt-browser:20261019@sha256:<digest>`. Docker uses the digest, and the tag stays only as a reminder.
