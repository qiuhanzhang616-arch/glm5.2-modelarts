# Security

- Never commit AK/SK, API keys, tokens, private keys, cookies, or downloaded
  credential files.
- Use a ModelArts IAM agency for SWR, OBS, SFS, LTS, and CES access.
- Keep model and script mounts read-only; isolate writable log and rendezvous
  directories per service and rollout.
- Pin the SWR image by digest and record the model revision and checksums.
- Do not expose vLLM backend ports directly to the Internet.
- Treat Mooncake metadata and KV-transfer networks as internal-only services.
- Revoke any secret that appears in logs, commits, or shell history.
