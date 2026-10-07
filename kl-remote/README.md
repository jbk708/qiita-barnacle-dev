# Hosting qiita-web on kl-remote

Serves the qiita-web SPA from kl-remote against the barnacle dev stack, which moves between nodes when it restarts.
Same shape as the mimo gateway: a 2-minute timer finds the node, an ssh forward follows it.

```
browser ─▶ cloudflared ─▶ oauth2-proxy :4185 ─▶ Caddy 127.0.0.1:8187 ─┬─ /api/* ─▶ 127.0.0.1:18080 ─▶ qiita-tunnel (ssh -J barnacle) ─▶ <node>:127.0.0.1:18080
                                                                └─ SPA build/
qiita-node.timer (2 min) ─▶ qiita-node.sh: newest running qiita-dev-stack job that is up and answers /healthz ─▶ tunnel-qiita.env, restart the tunnel
```

- `qiita-node.sh` only follows the stack. `stack/watch-stack.sh` on barnacle owns restarts, so two controllers never fight.
- The tunnel hops onto the stack's node and forwards to its loopback, so it works whether the control plane binds
  `127.0.0.1` or `0.0.0.0`. barnacle allows ssh into a node where you have a running job.
- No new ports open on the LAN: Caddy and the tunnel bind 127.0.0.1.
- The dev stack has no login (AuthRocket off), so users paste a personal token after the Google gate.

## Install (each step is a write on kl-remote: run it only with the owner's go-ahead)

1. A key of the stack owner's: kl-remote's existing `Host barnacle` is another user's identity, and only the job's owner
   may ssh into its node.
   ```bash
   ssh-keygen -t ed25519 -N '' -C 'kl-remote qiita-node' -f ~/.ssh/barnacle_jokirkland_ed25519
   cat ssh_config.snippet >> ~/.ssh/config
   ```
   Append the `.pub` to `~/.ssh/authorized_keys` on barnacle (shared home, so it covers the compute nodes too), then
   check `ssh barnacle-jk true` and `ssh <current node> true`.
2. Files:
   ```bash
   mkdir -p ~/qiita-node ~/.config/qiita-node
   cp qiita-node.sh ~/qiita-node/ && chmod +x ~/qiita-node/qiita-node.sh
   cp qiita-node.env.example ~/.config/qiita-node/qiita-node.env   # check LOCAL_PORT is free: ss -ltn
   cp systemd/qiita-node.{service,timer} systemd/qiita-tunnel.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   ~/qiita-node/qiita-node.sh            # first run writes tunnel-qiita.env and starts the tunnel
   systemctl --user enable --now qiita-node.timer
   systemctl --user enable qiita-tunnel.service
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18080/healthz   # expect 200
   ```
3. SPA, auto-deployed: `qiita-web-deploy.sh` + `qiita-web-deploy.{service,timer}` (every 5 min) build the latest
   `lucaspatel/Qiita` `feat/web-ui` into `~/qiita-web-dev/releases/<sha>` and swap `~/qiita-web-dev/current` atomically,
   keeping the last 3. The branch's code (vite config, npm deps) runs only in a throwaway `node:22-alpine` container
   (no capabilities, read-only root, source mounted read-only). A failed build leaves the live site alone and is not
   retried for that commit (`~/qiita-web-dev/failed/<sha>`). The branch has no lockfile, so deps float within
   `package.json` ranges. Roll back: `ln -sfn releases/<id> ~/qiita-web-dev/current`.
   Environment switch: upstream only reads `~/.qiita/config.toml` under `vite dev`, so the build goes through
   `vite.config.deploy.ts`, which bakes that file's environments (`qiita-web-config.toml`: dev = this stack, prod =
   qiita-miint) into the bundle; Caddy serves each `/_env/<name>/api`. A release id is `<sha>-<hash of config and
   wrapper>`, so editing the config redeploys on the next tick. Install both next to the script and the config at
   `~/.qiita/config.toml`.
4. Caddy: append `Caddyfile.snippet` to `~/Caddyfile`, `~/caddy validate --config ~/Caddyfile`, `~/caddy reload ...`.
5. Gate: `oauth2-proxy-qiita-dev.compose.yml` in `~/oauth2-proxy/qiita-dev/` (`.env`: the shared Google client's id and
   secret, plus its own `openssl rand -hex 16` cookie secret); `docker compose up -d`. Google login needs
   `https://qiita-dev.knight-lab-dev.org/oauth2/callback` among the OAuth client's redirect URIs.
6. Expose: ingress `qiita-dev.knight-lab-dev.org -> http://localhost:4185` above the catch-all in
   `~/.cloudflared/config.yml`, `cloudflared tunnel ingress validate`, `cloudflared tunnel route dns qiita-explore
   qiita-dev.knight-lab-dev.org`, restart `cloudflared.service`. Then `cloudflared tunnel info qiita-explore` must show
   one connector: a second one (a hand-started `cloudflared tunnel run`) keeps the old config and 404s the new hostname
   for part of the traffic.

Logs: `journalctl --user -u qiita-node -u qiita-tunnel -u qiita-web-deploy`.
Undo: `systemctl --user disable --now qiita-node.timer qiita-tunnel.service qiita-web-deploy.timer`, `docker compose down` in
`~/oauth2-proxy/qiita-dev`, remove the units, the Caddy block and the ingress rule (dated `.bak-*` copies exist).
